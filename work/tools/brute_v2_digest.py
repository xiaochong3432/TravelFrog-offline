"""Wide brute-force search for the v2 content-digest formula.

Reads the stored digest out of a real apksigner-signed APK and tries many
candidate formulas, printing any that reproduce it byte-exactly.

Usage: python brute_v2_digest.py <apk>
"""
import hashlib
import itertools
import struct
import sys

MAGIC = b"APK Sig Block 42"
V2 = 0x7109871A
MB = 1024 * 1024


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def lp(b, o):
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n


def read_stored(d):
    eocd = d.rfind(b"PK\x05\x06")
    cd_size = u32(d, eocd + 12)
    cd_offset = u32(d, eocd + 16)
    assert d[cd_offset - 16:cd_offset] == MAGIC, "no well-formed signing block"
    S = u64(d, cd_offset - 24)
    blk_start = cd_offset - 8 - S
    body = d[blk_start + 8:cd_offset - 24]
    o, v2 = 0, None
    while o < len(body):
        plen = u64(body, o)
        pid = u32(body, o + 8)
        if pid == V2:
            v2 = body[o + 12:o + 8 + plen]
        o += 8 + plen
    seq, _ = lp(v2, 0)
    signer, _ = lp(seq, 0)
    sd, _ = lp(signer, 0)
    dseq, _ = lp(sd, 0)
    entry, _ = lp(dseq, 0)
    algo = u32(entry, 0)
    dg, _ = lp(entry, 4)
    return dg, algo, blk_start, cd_offset, cd_size, eocd


PREFIXES = {
    "a5+len_le": lambda n: b"\xa5" + struct.pack("<I", n),
    "len_le+a5": lambda n: struct.pack("<I", n) + b"\xa5",
    "a5+len_be": lambda n: b"\xa5" + struct.pack(">I", n),
    "a5only": lambda n: b"\xa5",
    "len_le": lambda n: struct.pack("<I", n),
    "none": lambda n: b"",
}


def chunk_digests(data, pf, chunk):
    out = []
    for off in range(0, len(data), chunk):
        c = data[off:off + chunk]
        out.append(hashlib.sha256(pf(len(c)) + c).digest())
    return out


def main():
    path = sys.argv[1]
    d = open(path, "rb").read()
    stored, algo, blk_start, cd_offset, cd_size, eocd = read_stored(d)
    print(f"{path}")
    print(f"stored: algo={algo:#06x} digest={stored.hex()}")

    eocd_mod = bytearray(d[eocd:])
    struct.pack_into("<I", eocd_mod, 16, blk_start)
    eocd_variants = {
        "eocd_rewritten": bytes(eocd_mod),
        "eocd_raw": d[eocd:],
    }
    s1 = d[:blk_start]
    s2 = d[cd_offset:cd_offset + cd_size]
    print(f"sections: s1={len(s1)} s2={len(s2)} s3={len(d[eocd:])}")

    hits = []
    for pfname, pf in PREFIXES.items():
        for chunk in (MB, 1 << 16):
            for eocdname, s3 in eocd_variants.items():
                segs = [s1, s2, s3]
                key = f"{pfname}/chunk={chunk}/{eocdname}"
                # --- boundary handling
                # continuous: one stream, chunk boundaries do not reset
                cont = []
                buf = b""
                for s in segs:
                    data = buf + s
                    off = 0
                    while len(data) - off >= chunk:
                        c = data[off:off + chunk]
                        cont.append(hashlib.sha256(pf(len(c)) + c).digest())
                        off += chunk
                    buf = data[off:]
                if buf:
                    cont.append(hashlib.sha256(pf(len(buf)) + buf).digest())

                # flush: each segment chunked independently from offset 0
                flush = []
                per_seg = []
                for s in segs:
                    cd_ = chunk_digests(s, pf, chunk)
                    flush.extend(cd_)
                    per_seg.append(hashlib.sha256(b"".join(cd_)).digest())

                cands = {
                    "cont->sha256(join)": hashlib.sha256(b"".join(cont)).digest(),
                    "cont->join(no outer)": b"".join(cont),
                    "flush->sha256(join)": hashlib.sha256(b"".join(flush)).digest(),
                    "flush->join(no outer)": b"".join(flush),
                    "perseg->sha256(join)": hashlib.sha256(b"".join(per_seg)).digest(),
                    "perseg->join(no outer)": b"".join(per_seg),
                    "sha256(concat raw)": hashlib.sha256(s1 + s2 + s3).digest(),
                    "sha256(sha256 each)": hashlib.sha256(
                        b"".join(hashlib.sha256(x).digest() for x in segs)).digest(),
                }
                for cname, val in cands.items():
                    if val == stored:
                        hits.append(f"{key} :: {cname}")
                        print(f"  *** MATCH: {key} :: {cname}")
    if not hits:
        print("\nno match found")
    else:
        print(f"\n{len(hits)} match(es)")
    return 0 if hits else 1


if __name__ == "__main__":
    sys.exit(main())
