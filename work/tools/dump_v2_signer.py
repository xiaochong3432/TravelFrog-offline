"""Hexdump the v2 signer structures so the layout can be read by eye."""
import struct, sys

MAGIC = b"APK Sig Block 42"
V2 = 0x7109871A


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def lp(b, o):
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n


def hexs(b, n=64):
    return b[:n].hex(" ")


path = sys.argv[1]
d = open(path, "rb").read()
eocd = d.rfind(b"PK\x05\x06")
cd_offset = u32(d, eocd + 16)
assert d[cd_offset - 16:cd_offset] == MAGIC, "no signing block magic"
S = u64(d, cd_offset - 24)
blk_start = cd_offset - 8 - S
body = d[blk_start + 8:cd_offset - 24]
o = 0
v2 = None
while o < len(body):
    plen = u64(body, o)
    pid = u32(body, o + 8)
    val = body[o + 12:o + 8 + plen]
    if pid == V2:
        v2 = val
    o += 8 + plen
print("v2 value len:", len(v2))
print("  v2[0:32]      :", hexs(v2, 32))

signers_seq, _ = lp(v2, 0)
print("signers_seq len:", len(signers_seq))
print("  seq[0:32]     :", hexs(signers_seq, 32))

signer, _ = lp(signers_seq, 0)
print("signer len:", len(signer))
print("  signer[0:48]  :", hexs(signer, 48))

sd, o1 = lp(signer, 0)
sigs, o2 = lp(signer, o1)
pk, o3 = lp(signer, o2)
print(f"signed_data={len(sd)} (next {o1})")
print(f"signatures ={len(sigs)} (next {o2})")
print(f"pubkey     ={len(pk)} (next {o3}) end_of_signer={len(signer)}")
print("  signed_data[0:48]:", hexs(sd, 48))
print("  signatures[0:24] :", hexs(sigs, 24))
print("  pubkey[0:24]     :", hexs(pk, 24))

dig, o4 = lp(sd, 0)
certs, o5 = lp(sd, o4)
attrs, o6 = lp(sd, o5)
print(f"\nsigned_data fields: digests={len(dig)} (next {o4}) certs={len(certs)} (next {o5}) "
      f"attrs={len(attrs)} (next {o6}) sd_len={len(sd)}")
print("  digests hex:", dig.hex(" "))
print("  certs[0:24]:", hexs(certs, 24))

p = 0
while p < len(dig):
    algo = u32(dig, p)
    dg, np = lp(dig, p + 4)
    print(f"    digest entry: algo={algo} ({algo:#x}) len={len(dg)} -> next {np}")
    p = np
print("  signatures hex[0:16]:", hexs(sigs, 16))
print("  sig algo field:", hex(u32(sigs, 0)))
