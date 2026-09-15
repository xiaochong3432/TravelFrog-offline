#!/usr/bin/env python3
"""Independently verify the v1 (JAR) signature of an APK.

Mirrors what Android's StrictJarVerifier / jarsigner -verify do:
  1. CERT.RSA -> PKCS#7, verify its signature over CERT.SF
  2. CERT.SF  -> SHA-256-Digest-Manifest must equal sha256(META-INF/MANIFEST.MF)
  3. for every entry: manifest digest must equal sha256(entry content)
  4. per-entry SF digests must match the manifest sections

Usage: python verify_apk_v1.py <apk>
"""
import base64, hashlib, io, re, sys, zipfile
from asn1crypto import cms

path = sys.argv[1]
z = zipfile.ZipFile(path)
names = z.namelist()
print(f"{path}: {len(names)} entries")

sig_files = [n for n in names if n.upper().startswith("META-INF/")
             and (n.upper().endswith(".SF") or n.upper().endswith(".RSA")
                  or n.upper().endswith(".DSA") or n.upper().endswith(".EC"))]
print("v1 signature files:", sig_files)
if not sig_files:
    print("RESULT: FAIL (no v1 signature)")
    sys.exit(1)

sf_name = [n for n in sig_files if n.upper().endswith(".SF")][0]
blk_name = [n for n in sig_files if not n.upper().endswith(".SF")][0]
sf_bytes = z.read(sf_name)
blk_bytes = z.read(blk_name)

# ---- 1. PKCS#7 over CERT.SF
ci = cms.ContentInfo.load(blk_bytes)
sd = ci["content"]
signer = sd["signer_infos"][0]
cert = sd["certificates"][0].chosen
sig = signer["signature"].native
print(f"\ncert subject : {cert.subject.human_friendly}")
print(f"sig algo     : {signer['signature_algorithm']['algorithm'].native}")

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography import x509 as cx509

pub = cx509.load_der_x509_certificate(cert.dump()).public_key()
try:
    pub.verify(sig, sf_bytes, padding.PKCS1v15(), hashes.SHA256())
    print("PKCS#7 signature over CERT.SF : OK")
except Exception as e:
    print(f"PKCS#7 signature over CERT.SF : FAILED ({e})")
    sys.exit(1)

# ---- 2. SF manifest digest
sf_text = sf_bytes.decode("utf8")


def split_sections(data):
    """Split a manifest/SF byte string into (main_raw, [(raw, text), ...])."""
    parts = data.split(b"\r\n\r\n")
    # a trailing empty part is just the final terminator
    if parts and parts[-1] == b"":
        parts = parts[:-1]
    main_raw = parts[0] + b"\r\n\r\n" if parts else b""
    rest = [(p + b"\r\n\r\n", p.decode("utf8", "replace")) for p in parts[1:]]
    return main_raw, rest


def parse_manifest(text):
    """Parse a JAR manifest/SF section body into {header: value}.

    Handles 72-byte line wrapping: a line starting with a single space is a
    continuation of the previous line (this is what java.util.jar.Manifest and
    Android's StrictJarManifest do).  The unfolded Name is returned under the
    key "__name__".
    """
    hdrs, last_key = {}, None
    for raw_line in text.split("\r\n"):
        if raw_line == "":
            break
        if raw_line.startswith(" "):
            if last_key:
                hdrs[last_key] += raw_line[1:]
            continue
        if ":" not in raw_line:
            continue
        k, v = raw_line.split(":", 1)
        v = v[1:] if v.startswith(" ") else v
        hdrs[k] = v
        last_key = k
    return hdrs


def parse_full(data):
    """Return (main_headers, {unfolded_name: headers}, {unfolded_name: raw})."""
    main_raw, rest = split_sections(data)
    main = parse_manifest(main_raw.decode("utf8", "replace"))
    entries, raws = {}, {}
    for raw, text in rest:
        hdrs = parse_manifest(text)
        name = hdrs.get("Name")
        if name is None:
            continue
        entries[name] = hdrs
        raws[name] = raw
    return main, entries, raws


sf_main, sf_entries, _ = parse_full(sf_bytes)
want = sf_main.get("SHA-256-Digest-Manifest")
manifest_bytes = z.read("META-INF/MANIFEST.MF")
got = base64.b64encode(hashlib.sha256(manifest_bytes).digest()).decode()
print(f"\nSHA-256-Digest-Manifest      : {'OK' if want == got else 'MISMATCH'}")
if want != got:
    print(f"  sf={want}\n  actual={got}")
    sys.exit(1)

# ---- 3. per-entry manifest digests
man_main, man_entries, man_raw = parse_full(manifest_bytes)
sections = {k: v["SHA-256-Digest"] for k, v in man_entries.items() if "SHA-256-Digest" in v}
print(f"manifest sections            : {len(sections)}")

missing = bad = ok = 0
for name in names:
    if name.upper().startswith("META-INF/") and (
            name.upper().endswith((".SF", ".RSA", ".DSA", ".EC"))
            or name.upper().endswith("MANIFEST.MF")):
        continue
    if name not in sections:
        missing += 1
        if missing <= 5:
            print(f"  UNSIGNED entry: {name}")
        continue
    actual = base64.b64encode(hashlib.sha256(z.read(name)).digest()).decode()
    if actual == sections[name]:
        ok += 1
    else:
        bad += 1
        if bad <= 5:
            print(f"  DIGEST MISMATCH: {name}")
print(f"entries verified             : {ok}   mismatched={bad}   unsigned={missing}")

# ---- 4. SF per-entry digests (over the raw manifest section bytes)
sf_bad = 0
checked = 0
for name, hdrs in sf_entries.items():
    if "SHA-256-Digest" not in hdrs:
        continue
    checked += 1
    raw = man_raw.get(name)
    if raw is None:
        sf_bad += 1
        continue
    actual = base64.b64encode(hashlib.sha256(raw).digest()).decode()
    if actual != hdrs["SHA-256-Digest"]:
        sf_bad += 1
print(f"SF per-entry digests checked : {checked}   mismatched={sf_bad}")

print("\nRESULT:", "PASS" if (bad == 0 and missing == 0 and sf_bad == 0) else "FAIL")
sys.exit(0 if (bad == 0 and missing == 0 and sf_bad == 0) else 1)
