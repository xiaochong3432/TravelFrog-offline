#!/usr/bin/env python3
"""Independently verify a v2-signed APK (what apksigner/Android would check).

Parses the APK Signing Block, recomputes the content digests over the three
signed chunks, and verifies the RSA signature. This is a self-check: it proves
the file is structurally what Android expects, but it is NOT a substitute for
installing it on a real device.

Usage: python verify_apk.py <apk>
"""
import hashlib, struct, sys
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

V2_ID = 0x7109871A
ALGO = {0x0101: ("RSASSA-PSS", hashes.SHA256()),
        0x0102: ("RSASSA-PSS", hashes.SHA512()),
        0x0103: ("RSA-PKCS1", hashes.SHA256()),
        0x0104: ("RSA-PKCS1", hashes.SHA512()),
        0x0201: ("ECDSA", hashes.SHA256()),
        0x0202: ("ECDSA", hashes.SHA512()),
        0x0301: ("DSA", hashes.SHA256())}


def find_eocd(d):
    for i in range(len(d) - 22, max(0, len(d) - 22 - 65536), -1):
        if d[i:i + 4] == b"PK\x05\x06":
            return i
    raise SystemExit("no EOCD found")


class Reader:
    def __init__(self, b):
        self.b = b
        self.o = 0

    def u32(self):
        v = struct.unpack_from("<I", self.b, self.o)[0]
        self.o += 4
        return v

    def lp(self):
        n = self.u32()
        v = self.b[self.o:self.o + n]
        self.o += n
        return v


def main():
    path = sys.argv[1]
    d = open(path, "rb").read()
    print(f"{path}: {len(d)} bytes")

    eocd = find_eocd(d)
    cd_size, cd_offset = struct.unpack_from("<II", d, eocd + 12)
    print(f"EOCD@{eocd}  cd_offset={cd_offset} cd_size={cd_size}")

    if d[cd_offset:cd_offset + 4] != b"PK\x01\x02":
        print("  !! cd_offset does not point at a central directory")
        return 1

    # signing block = [u64 size][pairs][u64 size] sitting just before the CD
    blk_end = cd_offset
    (trailer,) = struct.unpack_from("<Q", d, blk_end - 8)
    blk_start = blk_end - trailer - 16
    (header,) = struct.unpack_from("<Q", d, blk_start)
    print(f"signing block: start={blk_start} size={trailer} (header={header})")
    if header != trailer:
        print("  !! signing block size mismatch")
        return 1
    if d[blk_start + 8 + trailer:blk_start + 8 + trailer + 8] != d[blk_start:blk_start + 8]:
        print("  !! signing block trailer mismatch")
        return 1

    body = d[blk_start + 8:blk_end - 8]
    o = 0
    v2 = None
    while o < len(body):
        (plen,) = struct.unpack_from("<Q", body, o)
        pid = struct.unpack_from("<I", body, o + 8)[0]
        val = body[o + 12:o + 8 + plen]
        print(f"  pair id={pid:#010x} len={plen - 4}")
        if pid == V2_ID:
            v2 = val
        o += 8 + plen
    if v2 is None:
        print("  !! no v2 signature block")
        return 1

    # signers
    r = Reader(v2)
    signers_raw = r.lp()
    sr = Reader(signers_raw)
    signed_data = sr.lp()
    signatures = sr.lp()
    pubkey = sr.lp()

    sd = Reader(signed_data)
    digests_raw = sd.lp()
    certs_raw = sd.lp()
    attrs = sd.lp()
    dr = Reader(digests_raw)
    digests = []
    while dr.o < len(dr.b):
        algo = dr.u32()
        digests.append((algo, dr.lp()))
    cr = Reader(certs_raw)
    cert_der = cr.lp()

    sgr = Reader(signatures)
    algo = sgr.u32()
    sig = sgr.lp()
    print(f"\nsigner: algo={algo:#06x} ({ALGO.get(algo, ('?', None))[0]}) "
          f"sig={len(sig)}B pubkey={len(pubkey)}B certs=1")
    print(f"digests in signed data: {len(digests)}")

    cert = x509.load_der_x509_certificate(cert_der)
    print(f"cert subject: {cert.subject.rfc4514_string()}")
    print(f"cert valid: {cert.not_valid_before_utc.date()} .. {cert.not_valid_after_utc.date()}")

    # recompute the three chunks exactly as Android does
    eocd_for_digest = bytearray(d[eocd:])
    struct.pack_into("<I", eocd_for_digest, 16, blk_start)
    chunks = [d[:blk_start],
              d[cd_offset:cd_offset + cd_size],
              bytes(eocd_for_digest)]

    ok = True
    for idx, (a, want) in enumerate(digests):
        got = hashlib.sha256(chunks[idx]).digest()
        same = got == want
        ok &= same
        print(f"  chunk{idx + 1}: {'OK' if same else 'MISMATCH'}  "
              f"sha256={got.hex()[:32]}...")

    name, h = ALGO[algo]
    pad = padding.PSS(mgf=padding.MGF1(h), salt_length=padding.PSS.MAX_LENGTH) \
        if name == "RSASSA-PSS" else padding.PKCS1v15()
    try:
        cert.public_key().verify(sig, signed_data, pad, h)
        print(f"\nsignature: OK ({name})")
    except Exception as e:
        ok = False
        print(f"\nsignature: FAILED ({name}): {e}")

    print("\nRESULT:", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
