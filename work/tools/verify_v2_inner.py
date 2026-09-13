"""Decisive structural test: does the v2 RSA signature verify over our parsed
`signed data` bytes?  If yes, our field slicing is byte-exact.

Usage: python verify_v2_inner.py <apk>
"""
import hashlib
import struct
import sys

from cryptography import x509 as cx509
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

MAGIC = b"APK Sig Block 42"
V2 = 0x7109871A


def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]
def lp(b, o):
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n


path = sys.argv[1]
d = open(path, "rb").read()
eocd = d.rfind(b"PK\x05\x06")
cd_offset = u32(d, eocd + 16)
S = u64(d, cd_offset - 24)
blk_start = cd_offset - 8 - S
body = d[blk_start + 8:cd_offset - 24]
o, v2 = 0, None
while o < len(body):
    plen = u64(body, o)
    if u32(body, o + 8) == V2:
        v2 = body[o + 12:o + 8 + plen]
    o += 8 + plen

seq, _ = lp(v2, 0)
signer, _ = lp(seq, 0)
sd, q = lp(signer, 0)
sigs, q = lp(signer, q)
pk, q = lp(signer, q)
sd_full = signer[0:q - len(pk) - 4 - 0]  # not used

# signatures content
sc, _ = lp(sigs, 0)
sig_algo = u32(sc, 0)
sig, _ = lp(sc, 4)

# cert
certs, _ = lp(sd, 0)
c, _ = lp(certs, 0)
cert = cx509.load_der_x509_certificate(c)
pub = cert.public_key()

print(f"signer={len(signer)} signed_data={len(sd)} signatures={len(sigs)} pubkey={len(pk)}")
print(f"sig_algo={sig_algo:#06x} sig_len={len(sig)}")
print(f"pubkey matches cert pubkey: "
      f"{pub.public_bytes(__import__('cryptography').hazmat.primitives.serialization.Encoding.DER, __import__('cryptography').hazmat.primitives.serialization.PublicFormat.SubjectPublicKeyInfo) == pk}")

for name, blob in [("signed_data slice (953B)", sd),
                   ("signed_data + 4 zero bytes", sd + b"\x00" * 4),
                   ("signer[0:957] (sd with its length prefix)", signer[0:q - len(pk) - 4])]:
    try:
        pub.verify(sig, blob, padding.PKCS1v15(), hashes.SHA256())
        print(f"  VERIFY OK   : {name} ({len(blob)} bytes)")
    except Exception as e:
        print(f"  verify fail : {name} ({len(blob)} bytes) {type(e).__name__}")

# also report how much of sd is 'accounted'
a, o1 = lp(sd, 0)
b, o2 = lp(sd, o1)
cc, o3 = lp(sd, o2)
print(f"signed_data fields: digests={len(a)} certs={len(b)} attrs={len(cc)}; "
      f"consumed={o3}/{len(sd)} leftover={len(sd) - o3} bytes = {sd[o3:].hex()}")
