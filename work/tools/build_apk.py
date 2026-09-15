#!/usr/bin/env python3
"""=========================================================================
   NOT THE SHIPPING BUILDER -- DO NOT USE THIS TO PRODUCE dist/.
   =========================================================================

This repacks the ORIGINAL OPPO channel APK (base.apk): it keeps that app's
native shell, its Application class, its channel SDKs and its native libraries,
and only swaps assets/game/**. The result INSTALLS and then SITS ON THE CHANNEL
LOGIN SCREEN FOREVER ("移动服务 / 登录中"), because the channel initialisation it
runs can never succeed -- the service closed on 2026-12-08 and channel auth is
long gone. That is exactly the symptom a player reported after this script was
(mistakenly) used for a release build.

Use it only to study or inspect a repack. The shipping APK comes from:

    python tools/build_wrapper_apk.py
    python tools/sign_apk.py --in work/build/wrapper/TravelFrog-wrapper-unsigned.apk \\
                             --out dist/TravelFrog-offline.apk

build_wrapper_apk.py builds a CLEAN WebView shell (package com.frog.offline)
containing only AndroidManifest.xml, resources.arsc, res/**, classes.dex and
assets/game/** -- no channel machinery at all. tools/apk_identity.py now asserts
that shape, so a repack of base.apk cannot be shipped by accident again.

   =========================================================================

Repack base.apk with the offline build and sign it (APK Signature Scheme v2).

Why not a normal toolchain: this machine has no JDK and no Android SDK, so there
is no apksigner/zipalign. Everything here is done by hand:

  * the zip is rewritten preserving each entry's original compression method and
    4-byte data alignment (the source APK was zipaligned; STORED entries must
    stay aligned)
  * assets/game/** is replaced by the patched offline build
  * an APK Signing Block (v2, RSA PKCS#1 v1.5 / SHA-256) is inserted before the
    central directory, and the EOCD central-directory offset is patched

targetSdkVersion is 30, so Android 11+ requires v2 - a v1-only rebuild would be
refused at install time. v1 files are dropped (they would be invalid anyway once
the key changes).

Usage:
  python build_apk.py --out out.apk [--web <dir>] [--key <pem>] [--apk base.apk]
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse, base64, datetime, hashlib, io, os, struct, sys, time, zlib, zipfile

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import padding, rsa
    from cryptography.x509.oid import NameOID
    HAVE_CRYPTO = True
except ImportError:
    HAVE_CRYPTO = False

ALIGN = 4
V2_BLOCK_ID = 0x7109871A
SIG_ALGO_RSA_PKCS1_SHA256 = 0x0103

# files that exist in the working tree but must not ship
EXCLUDE_SUFFIX = (".clean", ".orig", ".bak")
EXCLUDE_NAMES = {"__captest.html"}


def log(*a):
    print(*a, flush=True)


# --------------------------------------------------------------------- zip

class Entry:
    __slots__ = ("name", "data", "method", "date_time", "external_attr",
                 "create_system", "comment", "is_dir")

    def __init__(self, name, data, method, date_time, external_attr,
                 create_system, comment=b"", is_dir=False):
        self.name = name
        self.data = data
        self.method = method
        self.date_time = date_time
        self.external_attr = external_attr
        self.create_system = create_system
        self.comment = comment
        self.is_dir = is_dir


def dos_time(dt):
    """(time, date) DOS fields from a time.struct_time / tuple."""
    y, mo, d, h, mi, s = dt[0], dt[1], dt[2], dt[3], dt[4], dt[5]
    if y < 1980:
        y = 1980
    return ((h << 11) | (mi << 5) | (s // 2), ((y - 1980) << 9) | (mo << 5) | d)


def read_entries(apk_path):
    out = []
    z = zipfile.ZipFile(apk_path)
    for i in z.infolist():
        data = b"" if i.is_dir() else z.read(i.filename)
        out.append(Entry(i.filename, data, i.compress_type, i.date_time,
                         i.external_attr, i.create_system, i.comment, i.is_dir()))
    z.close()
    return out


def raw_deflate(data, level=9):
    """ZIP stores raw deflate, NOT a zlib-wrapped stream (wbits=-15)."""
    co = zlib.compressobj(level, zlib.DEFLATED, -15)
    return co.compress(data) + co.flush()


def write_zip(entries, out_path):
    """Write entries as a zip with aligned STORED data. Returns (cd_offset, cd_size,
    eocd_offset) so the caller can build the signing block."""
    buf = io.BytesIO()
    central = []

    for e in entries:
        name_b = e.name.encode("utf8")
        if e.method == 8 and not e.is_dir:
            comp = raw_deflate(e.data, 9)
            method = 8
        else:
            comp = e.data
            method = 0
        crc = zlib.crc32(e.data) & 0xFFFFFFFF
        csize = len(comp)
        usize = len(e.data)

        local_off = buf.tell()
        extra = b""
        if method == 0:
            # keep the payload 4-byte aligned using an Android-style padding field
            base = local_off + 30 + len(name_b)
            if base % ALIGN:
                pad = ALIGN - (base % ALIGN)
            else:
                pad = 0
            total = 4 + pad                      # field header (4) + padding
            if (base + total) % ALIGN:           # field header itself breaks alignment
                pad += ALIGN - ((base + 4) % ALIGN)
                total = 4 + pad
            extra = struct.pack("<HH", 0xD935, pad) + b"\x00" * pad

        t, d = dos_time(e.date_time)
        buf.write(struct.pack(
            "<IHHHHHIIIHH", 0x04034B50, 20, 0x0800, method, t, d,
            crc, csize, usize, len(name_b), len(extra)))
        buf.write(name_b)
        buf.write(extra)
        buf.write(comp)
        assert buf.tell() - csize == local_off + 30 + len(name_b) + len(extra)

        central.append((e, name_b, method, t, d, crc, csize, usize, local_off, extra))

    cd_offset = buf.tell()
    for (e, name_b, method, t, d, crc, csize, usize, local_off, extra) in central:
        buf.write(struct.pack(
            "<IHHHHHHIIIHHHHHII", 0x02014B50, 20, 20, 0x0800, method, t, d,
            crc, csize, usize, len(name_b), len(extra), len(e.comment),
            0, 0, e.external_attr, local_off))
        buf.write(name_b)
        buf.write(extra)
        buf.write(e.comment)
    cd_size = buf.tell() - cd_offset

    eocd_offset = buf.tell()
    buf.write(struct.pack("<IHHHHIIH", 0x06054B50, 0, 0,
                          len(central), len(central), cd_size, cd_offset, 0))

    data = buf.getvalue()
    with open(out_path, "wb") as f:
        f.write(data)
    return data, cd_offset, cd_size, eocd_offset


# ------------------------------------------------------------------ crypto

# -------------------------------------------------------------------- v1

def _manifest_line(out, key, value):
    """Write one manifest header, wrapping at 70 bytes (continuation = ' ')."""
    line = (key + ": " + value).encode("utf8")
    first = True
    while line:
        take = 70 if first else 69
        chunk, line = line[:take], line[take:]
        out.write(chunk + b"\r\n" if first else b" " + chunk + b"\r\n")
        first = False


def _is_sig_file(name):
    u = name.upper()
    if not u.startswith("META-INF/"):
        return False
    base = u[len("META-INF/"):]
    return (base == "MANIFEST.MF" or base.endswith(".SF") or base.endswith(".RSA")
            or base.endswith(".DSA") or base.endswith(".EC")
            or base.startswith("SIG-"))


def build_v1_entries(entries, key, cert):
    """Produce MANIFEST.MF / CERT.SF / CERT.RSA (JAR signing, SHA-256).

    Some installers only look at the v1 signature - without it they report
    "package lacks a developer certificate" even when v2 is present.
    """
    from asn1crypto import cms, algos
    from asn1crypto import x509 as ax509

    # 1) MANIFEST.MF - digest every entry that is not a signature file
    man = io.BytesIO()
    man.write(b"Manifest-Version: 1.0\r\n")
    man.write(b"Created-By: 1.0 (FrogOffline)\r\n")
    man.write(b"\r\n")
    sections = {}
    for e in entries:
        if _is_sig_file(e.name):
            continue
        digest = base64.b64encode(hashlib.sha256(e.data).digest()).decode("ascii")
        sec = io.BytesIO()
        _manifest_line(sec, "Name", e.name)
        _manifest_line(sec, "SHA-256-Digest", digest)
        sec.write(b"\r\n")
        sections[e.name] = sec.getvalue()
        man.write(sections[e.name])
    manifest_bytes = man.getvalue()

    # 2) CERT.SF - digest of the whole manifest plus each section
    sf = io.BytesIO()
    sf.write(b"Signature-Version: 1.0\r\n")
    sf.write(b"Created-By: 1.0 (FrogOffline)\r\n")
    _manifest_line(sf, "SHA-256-Digest-Manifest",
                   base64.b64encode(hashlib.sha256(manifest_bytes).digest()).decode("ascii"))
    sf.write(b"\r\n")
    for name, sec in sections.items():
        _manifest_line(sf, "Name", name)
        _manifest_line(sf, "SHA-256-Digest",
                       base64.b64encode(hashlib.sha256(sec).digest()).decode("ascii"))
        sf.write(b"\r\n")
    sf_bytes = sf.getvalue()

    # 3) CERT.RSA - detached PKCS#7 SignedData over CERT.SF
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    cert_asn1 = ax509.Certificate.load(cert_der)
    signature = key.sign(sf_bytes, padding.PKCS1v15(), hashes.SHA256())

    signed_data = cms.SignedData({
        "version": "v1",
        "digest_algorithms": [algos.DigestAlgorithm({"algorithm": "sha256"})],
        "encap_content_info": {"content_type": "data"},
        "certificates": [cert_asn1],
        "signer_infos": [cms.SignerInfo({
            "version": "v1",
            "sid": cms.SignerIdentifier({
                "issuer_and_serial_number": cms.IssuerAndSerialNumber({
                    "issuer": cert_asn1.issuer,
                    "serial_number": cert_asn1.serial_number,
                }),
            }),
            "digest_algorithm": algos.DigestAlgorithm({"algorithm": "sha256"}),
            "signature_algorithm": algos.SignedDigestAlgorithm({"algorithm": "sha256_rsa"}),
            "signature": signature,
        })],
    })
    pkcs7 = cms.ContentInfo({"content_type": "signed_data", "content": signed_data}).dump()

    now = time.localtime()
    return [
        Entry("META-INF/MANIFEST.MF", manifest_bytes, 8, now, 0, 0),
        Entry("META-INF/CERT.SF", sf_bytes, 8, now, 0, 0),
        Entry("META-INF/CERT.RSA", pkcs7, 8, now, 0, 0),
    ]


def make_key_and_cert(key_pem=None):
    if key_pem and os.path.exists(key_pem):
        key = serialization.load_pem_private_key(open(key_pem, "rb").read(), password=None)
        log(f"  loaded key: {key_pem}")
    else:
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        if key_pem:
            with open(key_pem, "wb") as f:
                f.write(key.private_bytes(
                    serialization.Encoding.PEM,
                    serialization.PrivateFormat.PKCS8,
                    serialization.NoEncryption()))
            log(f"  generated key -> {key_pem}")

    subject = issuer = x509.Name([
        x509.NameAttribute(NameOID.COMMON_NAME, "FrogOffline"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Offline Preservation Build"),
    ])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder()
            .subject_name(subject).issuer_name(issuer)
            .public_key(key.public_key())
            .serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(days=1))
            .not_valid_after(now + datetime.timedelta(days=3650))
            .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
            .sign(key, hashes.SHA256()))
    return key, cert


def lp(b):
    return struct.pack("<I", len(b)) + b


def build_v2_block(signed_data, signature, spki, cert_der):
    """Assemble the APK Signing Block containing the v2 signer."""
    # signed data = digests | certificates | additional attributes
    digests_seq = b""
    for dg in signed_data["digests"]:
        digests_seq += struct.pack("<I", SIG_ALGO_RSA_PKCS1_SHA256) + lp(dg)
    signed_data_bytes = (lp(digests_seq) + lp(lp(cert_der)) + lp(b""))

    signatures_seq = struct.pack("<I", SIG_ALGO_RSA_PKCS1_SHA256) + lp(signature)
    signer = lp(signed_data_bytes) + lp(signatures_seq) + lp(spki)
    value = lp(signer)                      # signers sequence

    pair = struct.pack("<Q", 4 + len(value)) + struct.pack("<I", V2_BLOCK_ID) + value
    return struct.pack("<Q", len(pair)) + pair + struct.pack("<Q", len(pair))


def sign_apk(raw, cd_offset, cd_size, eocd_offset, key, cert):
    """Insert the v2 signing block and return the finished APK bytes."""
    entries_bytes = raw[:cd_offset]
    cd_bytes = raw[cd_offset:cd_offset + cd_size]
    eocd_bytes = raw[eocd_offset:]

    # The EOCD hashed for the signature must point at the signing block start.
    eocd_for_digest = bytearray(eocd_bytes)
    struct.pack_into("<I", eocd_for_digest, 16, cd_offset)

    digests = [hashlib.sha256(entries_bytes).digest(),
               hashlib.sha256(cd_bytes).digest(),
               hashlib.sha256(bytes(eocd_for_digest)).digest()]

    digests_seq = b""
    for dg in digests:
        digests_seq += struct.pack("<I", SIG_ALGO_RSA_PKCS1_SHA256) + lp(dg)
    cert_der = cert.public_bytes(serialization.Encoding.DER)
    signed_data_bytes = lp(digests_seq) + lp(lp(cert_der)) + lp(b"")

    signature = key.sign(signed_data_bytes, padding.PKCS1v15(), hashes.SHA256())
    spki = key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo)

    block = build_v2_block({"digests": digests}, signature, spki, cert_der)
    log(f"  signing block: {len(block)} bytes, signature {len(signature)} bytes")

    new_cd_offset = cd_offset + len(block)
    eocd_out = bytearray(eocd_bytes)
    struct.pack_into("<I", eocd_out, 16, new_cd_offset)
    return entries_bytes + block + cd_bytes + bytes(eocd_out), digests, signed_data_bytes, signature, spki


def verify(apk_bytes, key, signed_data_bytes, signature):
    key.public_key().verify(signature, signed_data_bytes,
                            padding.PKCS1v15(), hashes.SHA256())


# -------------------------------------------------------------------- main

def collect_web(webroot):
    """Map web/** to assets/game/** entries."""
    out = {}
    for dp, dns, fns in os.walk(webroot):
        for fn in fns:
            full = os.path.join(dp, fn)
            rel = os.path.relpath(full, webroot).replace("\\", "/")
            if fn in EXCLUDE_NAMES or rel.endswith(EXCLUDE_SUFFIX):
                continue
            with open(full, "rb") as f:
                out["assets/game/" + rel] = f.read()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apk", default=str(PROJECT_ROOT) + "/base.apk")
    ap.add_argument("--web", default=str(PROJECT_ROOT) + "/work/run/web")
    ap.add_argument("--out", default=str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk")
    ap.add_argument("--key", default=str(PROJECT_ROOT) + "/dist/offline-signing-key.pem")
    ap.add_argument("--sign-legacy-builtin", action="store_true",
                    help="DANGER: use the old hand-rolled signer. It produces APKs "
                         "that Android REJECTS. Only for studying the bug. "
                         "Default (off) emits an unsigned APK for sign_apk.py.")
    args = ap.parse_args()

    if not HAVE_CRYPTO:
        log("ERROR: need `cryptography` to sign. Install with:")
        log("  python -m pip install --index-url https://pypi.org/simple cryptography")
        return 1

    os.makedirs(os.path.dirname(args.out), exist_ok=True)

    log("[1/6] reading base.apk")
    entries = read_entries(args.apk)
    log(f"  {len(entries)} entries")

    log("[2/6] replacing assets/game/** with the offline build")
    old = [e for e in entries if e.name.startswith("assets/game/")]
    kept = [e for e in entries
            if not e.name.startswith("assets/game/")
            and not _is_sig_file(e.name)]
    log(f"  dropping {len(old)} original game files, "
        f"keeping {len(kept)} others (old signature files removed)")

    web = collect_web(args.web)
    log(f"  adding {len(web)} files from {args.web}")

    # reuse the original compression method where we know it, else deflate
    orig_method = {e.name: e.method for e in old}
    now = time.localtime()
    for name, data in sorted(web.items()):
        method = orig_method.get(name, 8)
        kept.append(Entry(name, data, method, now, 0, 0))

    if args.sign_legacy_builtin:
        log("")
        log("  !! WARNING: --sign-legacy-builtin uses the BROKEN hand-rolled signer.")
        log("  !! Android rejects its output: the v2 signing block lacks the")
        log("  !! 'APK Sig Block 42' magic, and v1 uses SHA-256withRSA which")
        log("  !! minSdkVersion=16 does not support. Use sign_apk.py instead.")
        log("")
        log("[3/6] signing v1 (JAR: MANIFEST.MF / CERT.SF / CERT.RSA)")
        key, cert = make_key_and_cert(args.key)
        v1_entries = build_v1_entries(kept, key, cert)
        for e in v1_entries:
            log(f"  {e.name:<26} {len(e.data):>10,} bytes")
        kept.extend(v1_entries)
    else:
        log("[3/6] emitting an UNSIGNED apk; sign_apk.py does zipalign + apksigner")

    log("[4/6] writing zip (preserving alignment)")
    data, cd_offset, cd_size, eocd_offset = write_zip(kept, args.out + ".tmp")
    log(f"  raw zip {len(data)} bytes, cd@{cd_offset} size={cd_size}")

    if not args.sign_legacy_builtin:
        os.replace(args.out + ".tmp", args.out)
    else:
        log("[5/6] signing v2 (APK Signature Scheme, RSA PKCS#1 v1.5 / SHA-256)")
        signed, digests, signed_data_bytes, signature, spki = sign_apk(
            data, cd_offset, cd_size, eocd_offset, key, cert)

        verify(signed, key, signed_data_bytes, signature)
        log("  v2 signature verifies against the generated key")

        with open(args.out, "wb") as f:
            f.write(signed)
        os.remove(args.out + ".tmp")

    log("[6/6] sanity-checking the result")
    z = zipfile.ZipFile(args.out)
    infos = z.infolist()
    log(f"  zip entries: {len(infos)}")
    bad = []
    for i in infos:
        try:
            z.read(i.filename)
        except Exception as ex:
            bad.append((i.filename, str(ex)))
            if len(bad) >= 8:
                break
    if bad:
        log(f"  !! {len(bad)} entr(ies) failed to read back:")
        for n, e in bad:
            log(f"     {n}: {e}")
    else:
        log("  all entries read back OK")
    names = set(z.namelist())
    for probe in ("assets/game/index.html", "assets/game/__offline-engine.js",
                  "assets/game/__probe.js", "assets/game/js/main.min.js",
                  "assets/game/resource/China/config/gameConfig.json"):
        log(f"    {'OK ' if probe in names else 'MISSING'} {probe}")
    log(f"  size: {os.path.getsize(args.out)/1048576:.1f} MB -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
