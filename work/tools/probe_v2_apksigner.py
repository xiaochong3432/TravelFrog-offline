"""Ground-truth probe: parse a real apksigner v2 block and test digest formulas.

Determines authoritatively:
  * where the APK Signing Block starts / ends (spec layout)
  * which pair IDs are present
  * the content-digest algorithm ID stored in `signed data`
  * whether the stored section digests are PLAIN or CHUNKED (0xa5-prefixed)

Usage: python probe_v2_apksigner.py <apk>
"""
import hashlib
import struct
import sys

MAGIC = b"APK Sig Block 42"
V2_ID = 0x7109871A
V3_ID = 0xF05368C0
V31_ID = 0x1B93AD61
VERITY_PADDING_ID = 0x42726577

NAMES = {V2_ID: "v2", V3_ID: "v3", V31_ID: "v3.1", VERITY_PADDING_ID: "verity-padding"}

CONTENT_DIGEST = {
    1: "CHUNKED_SHA256",
    2: "CHUNKED_SHA512",
    3: "VERITY_CHUNKED_SHA256",
    4: "SHA256",
}

CHUNK = 1024 * 1024


def find_eocd(d):
    i = d.rfind(b"PK\x05\x06")
    return i


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0]


def u64(b, o):
    return struct.unpack_from("<Q", b, o)[0]


def lp(b, o):
    n = u32(b, o)
    return b[o + 4:o + 4 + n], o + 4 + n


def plain_sha256(data):
    return hashlib.sha256(data).digest()


def chunked_sha256(data):
    h = hashlib.sha256()
    for off in range(0, len(data), CHUNK):
        c = data[off:off + CHUNK]
        h.update(b"\xa5")
        h.update(struct.pack("<I", len(c)))
        h.update(c)
    return h.digest()


def main():
    path = sys.argv[1]
    d = open(path, "rb").read()
    eocd = find_eocd(d)
    cd_size = u32(d, eocd + 12)
    cd_offset = u32(d, eocd + 16)
    print(f"{path}: {len(d)} bytes")
    print(f"EOCD@{eocd} cd_offset={cd_offset} cd_size={cd_size}")

    if d[cd_offset:cd_offset + 4] != b"PK\x01\x02":
        print("  !! cd_offset does not point at a central directory")
        return 1

    # SPEC layout: [u64 S][pairs][u64 S][magic 16], immediately before the CD.
    magic = d[cd_offset - 16:cd_offset]
    print(f"magic at cd_offset-16: {magic!r}  match={magic == MAGIC}")
    if magic != MAGIC:
        print("  => NO well-formed APK Signing Block: Android sees an unsigned/v1-only APK")
        return 1

    tail_s = u64(d, cd_offset - 24)
    blk_start = cd_offset - 8 - tail_s
    head_s = u64(d, blk_start)
    print(f"signing block: blk_start={blk_start} total={cd_offset - blk_start} "
          f"head_S={head_s} tail_S={tail_s} consistent={head_s == tail_s}")

    # pairs live between the leading size and the trailing size
    body = d[blk_start + 8:cd_offset - 24]
    o = 0
    pairs = []
    while o < len(body):
        plen = u64(body, o)
        pid = u32(body, o + 8)
        val = body[o + 12:o + 8 + plen]
        pairs.append((pid, val))
        print(f"  pair id={pid:#010x} ({NAMES.get(pid, '?')}) value_len={plen - 4}")
        o += 8 + plen

    v2 = next((v for i, v in pairs if i == V2_ID), None)
    if v2 is None:
        print("  no v2 block")
        return 1

    # v2 value = lp(signers_sequence); each element of the sequence = lp(signer)
    signers_seq, _ = lp(v2, 0)
    signer, _ = lp(signers_seq, 0)
    print(f"\nv2 block value={len(v2)}B signers_seq={len(signers_seq)}B signer={len(signer)}B")

    signed_data, o2 = lp(signer, 0)
    signatures_raw, o2 = lp(signer, o2)
    pubkey, o2 = lp(signer, o2)
    print(f"signer consumed {o2}/{len(signer)} bytes (must be equal)")

    digests_raw, o3 = lp(signed_data, 0)
    certs_raw, o3 = lp(signed_data, o3)
    attrs, o3 = lp(signed_data, o3)
    print(f"\nv2 signed data: digests_seq={len(digests_raw)}B certs={len(certs_raw)}B "
          f"attrs={len(attrs)}B pubkey={len(pubkey)}B")

    stored = []
    p = 0
    while p < len(digests_raw):
        entry, p = lp(digests_raw, p)        # each digest entry is length-prefixed
        algo = u32(entry, 0)
        dg, _ = lp(entry, 4)
        stored.append((algo, dg))
        print(f"  content digest algo={algo:#06x} ({CONTENT_DIGEST.get(algo, '?')}) len={len(dg)}")

    sig_entry, _ = lp(signatures_raw, 0)
    sig_algo = u32(sig_entry, 0)
    sig, _ = lp(sig_entry, 4)
    print(f"  signature algo={sig_algo:#06x} sig_len={len(sig)}")

    # ---- THE decisive experiment: which formula reproduces the stored digests?
    eocd_for_digest = bytearray(d[eocd:])
    struct.pack_into("<I", eocd_for_digest, 16, blk_start)
    sections = [d[:blk_start], d[cd_offset:cd_offset + cd_size], bytes(eocd_for_digest)]

    print("\nsection digest formulas (stored vs plain vs chunked):")
    for i, sec in enumerate(sections):
        pl = plain_sha256(sec)
        ch = chunked_sha256(sec)
        print(f"  section {i+1} ({len(sec)} bytes):")
        for algo, dg in stored:
            tag = "PLAIN" if dg == pl else ("CHUNKED" if dg == ch else "NEITHER")
            print(f"    algo={algo}: {tag}   stored={dg.hex()[:24]}... "
                  f"plain={pl.hex()[:24]}... chunked={ch.hex()[:24]}...")
    return 0


if __name__ == "__main__":
    sys.exit(main())
