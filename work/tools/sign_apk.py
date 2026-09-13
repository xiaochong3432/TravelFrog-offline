#!/usr/bin/env python3
"""Sign the repacked APK with the REAL Android `zipalign` + `apksigner`.

Why we stopped hand-rolling the signatures
------------------------------------------
Our pure-Python signer produced an APK that the real `apksigner verify` rejects:

  * v2: the APK Signing Block was written WITHOUT the trailing 16-byte
    "APK Sig Block 42" magic, so Android cannot even locate the block -> the APK
    is effectively v1-only, and Android 11+ rejects a v1-only APK that targets
    API 30+, which surfaces as vivo/OriginOS's
    "应用未安装：软件包似乎无效（安装包缺乏开发者证书）".
  * v2: the signer nesting was one level short (`value = lp(signer)` instead of
    `value = lp(lp(signer))`) and the content digests were plain rather than
    chunked.
  * v1: we signed the JAR with SHA-256withRSA, which is unsupported on the
    declared minSdkVersion=16 (needs API 18+) -- reported verbatim by apksigner:
    "JAR signature META-INF/CERT.RSA uses digest algorithm SHA-256 and signature
     algorithm SHA-256 with RSA which is not supported on API Level(s) 16-17".

Both verifiers I wrote shared the same wrong assumptions as my builder, so they
reported PASS on a broken APK.  The lesson: validate a container format against a
reference implementation, not against your own reimplementation of it.

Pipeline
--------
  1. zipalign -f -p 4     align uncompressed entries
  2. apksigner sign       v1 + v2, picking an algorithm valid for minSdkVersion
  3. apksigner verify     must print "Verifies"

Usage:
    python sign_apk.py --in <unsigned.apk> --out <signed.apk>
    python sign_apk.py --verify-only <apk>
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse
import datetime
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _toolchain  # noqa: E402

ROOT = str(PROJECT_ROOT)
JAVA = _toolchain.java()
ZIPALIGN = _toolchain.build_tool("zipalign")
APKSIGNER_JAR = _toolchain.apksigner_jar()
KEY_PEM = os.path.join(ROOT, "dist", "offline-signing-key.pem")
# apksigner (build-tools 34) wants the PKCS#8 private key as DER, not PEM:
# given the PEM it reports "Failed to load PKCS #8 encoded private key ...
# Not an RSA, EC, or DSA private key".
KEY_DER = os.path.join(ROOT, "dist", "offline-signing-key.pk8")
CERT_PEM = os.path.join(ROOT, "dist", "offline-signing-cert.pem")


def log(*a):
    print(*a, flush=True)


def run(cmd, **kw):
    log("  $ " + " ".join(str(c) for c in cmd))
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8", errors="replace", **kw)
    for stream in (p.stdout, p.stderr):
        if stream and stream.strip():
            for line in stream.rstrip().splitlines():
                log("    " + line)
    return p


def ensure_key_and_cert():
    """Load the existing key/cert pair, or create it once and persist it.

    The certificate must be STABLE across builds: Android identifies a signer by
    the certificate, so regenerating it would break upgrade-installs.
    """
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import rsa
    from cryptography.x509.oid import NameOID

    if os.path.exists(KEY_PEM):
        key = serialization.load_pem_private_key(open(KEY_PEM, "rb").read(), password=None)
        log(f"  loaded key  : {KEY_PEM}")
    else:
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        os.makedirs(os.path.dirname(KEY_PEM), exist_ok=True)
        with open(KEY_PEM, "wb") as f:
            f.write(key.private_bytes(serialization.Encoding.PEM,
                                      serialization.PrivateFormat.PKCS8,
                                      serialization.NoEncryption()))
        log(f"  generated key -> {KEY_PEM}")

    with open(KEY_DER, "wb") as f:
        f.write(key.private_bytes(serialization.Encoding.DER,
                                  serialization.PrivateFormat.PKCS8,
                                  serialization.NoEncryption()))
    log(f"  wrote PKCS#8 DER key -> {KEY_DER}")

    if os.path.exists(CERT_PEM):
        cert = x509.load_pem_x509_certificate(open(CERT_PEM, "rb").read())
        log(f"  loaded cert : {CERT_PEM}")
    else:
        name = x509.Name([
            x509.NameAttribute(NameOID.COMMON_NAME, "FrogOffline"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Offline Preservation Build"),
            x509.NameAttribute(NameOID.COUNTRY_NAME, "CN"),
        ])
        now = datetime.datetime.now(datetime.timezone.utc)
        cert = (x509.CertificateBuilder()
                .subject_name(name).issuer_name(name)
                .public_key(key.public_key())
                .serial_number(x509.random_serial_number())
                .not_valid_before(now - datetime.timedelta(days=3650))
                .not_valid_after(now + datetime.timedelta(days=3650))
                .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()),
                               critical=False)
                .sign(key, hashes.SHA256()))
        with open(CERT_PEM, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
        log(f"  generated cert -> {CERT_PEM}")
    return key, cert


def verify(apk, extra=()):
    log(f"\n[verify] {apk}")
    p = run([JAVA, "-jar", APKSIGNER_JAR, "verify", "--verbose", "--print-certs", *extra, apk])
    ok = "Verifies" in p.stdout and "DOES NOT VERIFY" not in p.stdout
    log(f"  => {'PASS' if ok else 'FAIL'}")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="src", default=os.path.join(ROOT, "dist", "TravelFrog-offline-unsigned.apk"))
    ap.add_argument("--out", dest="dst", default=os.path.join(ROOT, "dist", "TravelFrog-offline.apk"))
    ap.add_argument("--verify-only", default=None)
    args = ap.parse_args()

    missing = [(name, path) for name, path in
               (("java", JAVA), ("zipalign", ZIPALIGN), ("apksigner.jar", APKSIGNER_JAR))
               if not path or not os.path.exists(path)]
    if missing:
        log("ERROR: 签名工具链不完整，缺少：")
        for name, path in missing:
            log("   %-14s %s" % (name, path or "(未找到)"))
        log("")
        log("指向一个现成的 Android build-tools 与 JDK 即可（任选其一）：")
        log("   set ANDROID_HOME=<你的 Android SDK 根>   # zipalign 与 apksigner.jar 都从它找")
        log("   set JAVA_HOME=<你的 JDK 17>")
        log("   set FROG_ANDROID_BUILD_TOOLS=<含 zipalign 的目录>")
        return 1

    if args.verify_only:
        return 0 if verify(args.verify_only) else 1

    for f in (args.src,):
        if not os.path.exists(f):
            log(f"ERROR: missing {f}")
            return 1

    log("[1/3] key + certificate")
    ensure_key_and_cert()

    aligned = args.dst + ".aligned.apk"
    if os.path.exists(aligned):
        os.remove(aligned)

    log("\n[2/3] zipalign -f -p 4")
    p = run([ZIPALIGN, "-f", "-p", "4", args.src, aligned])
    if p.returncode != 0:
        log("  !! zipalign failed")
        return 1

    log("\n[3/3] apksigner sign")
    if os.path.exists(args.dst):
        os.remove(args.dst)
    p = run([JAVA, "-jar", APKSIGNER_JAR, "sign",
             "--key", KEY_DER, "--cert", CERT_PEM,
             "--v1-signing-enabled", "true",
             "--v2-signing-enabled", "true",
             "--v3-signing-enabled", "false",
             "--v4-signing-enabled", "false",
             "--out", args.dst, aligned])
    if p.returncode != 0:
        log("  !! apksigner sign failed")
        return 1
    os.remove(aligned)

    log(f"\n  size: {os.path.getsize(args.dst) / 1048576:.1f} MB -> {args.dst}")
    return 0 if verify(args.dst) else 1


if __name__ == "__main__":
    sys.exit(main())
