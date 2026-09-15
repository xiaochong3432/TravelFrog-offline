"""Byte-account for every field of a v2 signer, reporting any leftovers."""
import struct, sys

MAGIC = b"APK Sig Block 42"
V2 = 0x7109871A


def u32(b, o): return struct.unpack_from("<I", b, o)[0]
def u64(b, o): return struct.unpack_from("<Q", b, o)[0]
def lp(b, o):
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n


def hx(b, per=32):
    for i in range(0, len(b), per):
        print(f"      {i:5d}: {b[i:i+per].hex(' ')}")


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
    pid = u32(body, o + 8)
    print(f"pair {pid:#010x}: total={8+plen} value={plen-4}")
    if pid == V2:
        v2 = body[o + 12:o + 8 + plen]
    o += 8 + plen
print("pairs region consumed:", o, "of", len(body))

seq, _ = lp(v2, 0)
print("\n--- signers sequence:", len(seq), "bytes")
p = 0
idx = 0
while p < len(seq):
    signer, p = lp(seq, p)
    print(f"  signer[{idx}] = {len(signer)} bytes")
    sd, q = lp(signer, 0)
    sg, q = lp(signer, q)
    pk, q = lp(signer, q)
    print(f"    signed_data={len(sd)} signatures={len(sg)} pubkey={len(pk)} "
          f"consumed={q}/{len(signer)}")
    print("    --- signed_data full hex ---")
    hx(sd)
    print("    --- signatures full hex ---")
    hx(sg)
    print("    --- pubkey full hex ---")
    hx(pk)
    idx += 1
