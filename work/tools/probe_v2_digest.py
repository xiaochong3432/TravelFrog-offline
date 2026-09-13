"""Find the exact v2 content-digest formula by brute-forcing variants against a
real apksigner-produced APK.

Usage: python probe_v2_digest.py <apk>
"""
import hashlib
import struct
import sys

MAGIC = b"APK Sig Block 42"
V2 = 0x7109871A
CHUNK = 1024 * 1024


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def lp(b, o):
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n


def stored_digest(d):
    eocd = d.rfind(b"PK\x05\x06")
    cd_offset = u32(d, eocd + 16)
    assert d[cd_offset - 16:cd_offset] == MAGIC
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
    signers_seq, _ = lp(v2, 0)
    signer, _ = lp(signers_seq, 0)
    sd, o1 = lp(signer, 0)
    dseq, _ = lp(sd, 0)
    entry, _ = lp(dseq, 0)
    algo = u32(entry, 0)
    dg, _ = lp(entry, 4)
    return dg, algo, blk_start, cd_offset, eocd


def chunk_hashes(data, prefix_len_byte=True, chunk=CHUNK):
    """Hash `data` into 1MB chunks. Returns list of per-chunk digests."""
    out = []
    for off in range(0, len(data), chunk):
        c = data[off:off + chunk]
        h = hashlib.sha256()
        if prefix_len_byte:
            h.update(b"\xa5")
        h.update(struct.pack("<I", len(c)))
        h.update(c)
        out.append(h.digest())
    return out


def main():
    path = sys.argv[1]
    d = open(path, "rb").read()
    stored, algo, blk_start, cd_offset, eocd = stored_digest(d)
    print(f"{path}")
    print(f"stored content digest: algo={algo:#06x} {stored.hex()}")
    print(f"blk_start={blk_start} cd_offset={cd_offset} eocd={eocd}")

    eocd_digest = bytearray(d[eocd:])
    struct.pack_into("<I", eocd_digest, 16, blk_start)
    segs = [d[:blk_start], d[cd_offset:cd_offset + u32(d, eocd + 12)], bytes(eocd_digest)]

    results = {}

    # Variant 1: continuous chunking across all 3 segments, outer hash of chunk hashes
    def continuous(prefix=True, outer=True, chunk=CHUNK):
        hashes = []
        buf = b""
        for s in segs:
            data = buf + s
            off = 0
            while len(data) - off >= chunk:
                c = data[off:off + chunk]
                h = hashlib.sha256()
                if prefix:
                    h.update(b"\xa5")
                h.update(struct.pack("<I", len(c)) + c)
                hashes.append(h.digest())
                off += chunk
            buf = data[off:]
        if buf:
            h = hashlib.sha256()
            if prefix:
                h.update(b"\xa5")
            h.update(struct.pack("<I", len(buf)) + buf)
            hashes.append(h.digest())
        joined = b"".join(hashes)
        return hashlib.sha256(joined).digest() if outer else joined

    results["continuous+prefix+outer"] = continuous(True, True)
    results["continuous-noprefix+outer"] = continuous(False, True)
    results["continuous+prefix-noouter"] = continuous(True, False)

    # Variant 2: per-segment hashing, then outer hash of the 3 segment digests
    per_seg = [hashlib.sha256(b"".join(chunk_hashes(s, True))).digest() for s in segs]
    results["persegment+concat"] = hashlib.sha256(b"".join(per_seg)).digest()
    results["persegment+concat-noprefix"] = hashlib.sha256(
        b"".join(hashlib.sha256(b"".join(chunk_hashes(s, False))).digest() for s in segs)).digest()

    # Variant 3: plain sha256 of each segment concatenated, outer hash
    results["plain3+outer"] = hashlib.sha256(
        b"".join(hashlib.sha256(s).digest() for s in segs)).digest()

    # Variant 4: chunk count sanity
    for name, val in results.items():
        mark = "  <<< MATCH" if val == stored else ""
        print(f"  {name:32s} {val.hex()[:40]}...{mark}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
