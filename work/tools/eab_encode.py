#!/usr/bin/env python3
"""Encode `.eab` bundles -- the inverse of eab_decrypt.py.

WHY THIS EXISTS: eab_decrypt.py can READ config.eab, but merging content into it
(patch ② of the reference-port plan) needs to WRITE one back. The gate for touching
a file the retail client must load is simple and non-negotiable:

    decode -> re-encode  must reproduce the ORIGINAL BYTES EXACTLY

If that round-trip is not byte-identical, we do not touch the client's bundle.

Container layout (verified against our own config.eab, see eab_facts.py):
    magic  = 89 45 41 42 0d 0a 1b 0a        (the CRYPT variant: byte 6 == 0x1b)
    body   = XXTEA( plaintext )             with key "ejoyassetbundle"
    plain  = <u32 LE index_len> <index JSON utf-8> <blobs concatenated in order>
    index  = [{"n":name,"f":source-path,"s":size,"t":"json"}, ...]
    XXTEA  = standard xxtea.js: data longs + ONE trailing length word inside the
             ciphertext, i.e. ciphertext_longs = data_longs + 1 and the decoder's
             long2str bound is [(n-1)*4-3, (n-1)*4].

Usage:
    python eab_encode.py --roundtrip <bundle.eab>        # prove byte-identity
"""
import argparse
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eab_decrypt as E  # noqa: E402  (reuse the proven decoder + key derivation)

MAGIC = E.MAGIC_CRYPT


def _to_longs(data):
    """Bytes -> little-endian u32 list, zero padded to a multiple of 4."""
    if len(data) % 4:
        data = data + b"\x00" * (4 - len(data) % 4)
    return list(struct.unpack(f"<{len(data) // 4}I", data))


def xxtea_encrypt(data, key):
    """Encrypt so that `eab_decrypt.xxtea_decrypt` (y_init=v[0]) returns `data` exactly.

    NOT the textbook xxtea.js encrypt. The client's decrypt is the canonical loop
    EXCEPT that it starts with `y = v[0]` instead of `y = 0` (that is why
    eab_decrypt's `y_starts_at_v0=True` reading is the one that yields JSON for both
    config.eab bundles). Its inverse therefore differs in exactly one place: the
    inner step p == n must use `y = v[0]` (the wrap-restored value) rather than the
    canonical `y = v[n]`.

    Derivation: our decoder runs, per round with `total`:
        for p = n..1:  z = v[p-1];  v[p] -= mx(y, z, p);  y = v[p]
        z = v[n];      v[0] -= mx(y, z, 0);               y = v[0]
    Undoing a round means replaying those operations newest-first and recomputing
    mx from the array as it stands (each operand still holds the value it had at
    execution time):
        v[0] += mx(v[1], v[n], 0)                 # also recovers y for this round
        for p = 1..n: v[p] += mx(v[p+1] or v[0], v[p-1], p)
    Validated by D(E(x)) == x on random inputs and by D(E(original)) == original.
    """
    v = _to_longs(data)
    v.append(len(data))
    k = _to_longs(key)
    if len(v) < 2 or not k:
        raise ValueError("data/key too short")
    n = len(v) - 1
    delta = 0x9E3779B9
    q = 6 + 52 // (n + 1)

    def mx(y, z, p, e, total):
        m = ((((z >> 5) ^ (y << 2)) & 0xFFFFFFFF)
             + (((y >> 3) ^ (z << 4)) & 0xFFFFFFFF)) & 0xFFFFFFFF
        return (m ^ (((total ^ y) + (k[(p & 3) ^ e] ^ z)) & 0xFFFFFFFF)) & 0xFFFFFFFF

    for r in range(1, q + 1):
        total = (r * delta) & 0xFFFFFFFF          # our decoder ends at delta, starts at q*delta
        e = (total >> 2) & 3
        v[0] = (v[0] + mx(v[1], v[n], 0, e, total)) & 0xFFFFFFFF
        y_round = v[0]                            # == the y our decoder entered this round with
        for p in range(1, n + 1):
            y = v[p + 1] if p < n else y_round
            v[p] = (v[p] + mx(y, v[p - 1], p, e, total)) & 0xFFFFFFFF
    return struct.pack(f"<{len(v)}I", *v)


def selfcheck(rounds=120):
    """D(E(x)) == x on random inputs of assorted lengths -- the property that matters."""
    import random
    rnd = random.Random(20260912)
    bad = []
    for _ in range(rounds):
        length = rnd.choice([1, 2, 3, 4, 5, 7, 8, 15, 16, 17, 63, 64, 65, 1000, 4093])
        data = bytes(rnd.randrange(256) for _ in range(length))
        try:
            enc = xxtea_encrypt(data, key_bytes())
            dec = E.xxtea_decrypt(enc, key_bytes(), y_starts_at_v0=True)
        except Exception as ex:  # noqa: BLE001
            bad.append((length, f"raised {ex}"))
            continue
        if dec != data:
            bad.append((length, f"decoded {len(dec)} bytes, expected {length}"))
    return bad


def key_bytes():
    return E.simple_encrypt(E.KEY_LITERAL, 13).encode("utf-8")


def load_entries(path):
    """Return (entries_in_order, blobs_in_order) from a bundle."""
    man, payload, _ = E.open_bundle(path)
    blobs, pos = [], 0
    for e in man:
        size = e.get("s", 0)
        blobs.append(payload[pos:pos + size])
        pos += size
    return man, blobs


def build(entries, blobs):
    """entries: list of dicts (kept in ORDER, keys n/f/s/t); blobs: matching payloads."""
    if len(entries) != len(blobs):
        raise ValueError("entries/blobs length mismatch")
    norm = []
    for e, b in zip(entries, blobs):
        row = {"n": e["n"], "f": e.get("f", ""), "s": len(b), "t": e.get("t", "json")}
        norm.append(row)
    index_text = json.dumps(norm, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    plain = struct.pack("<I", len(index_text)) + index_text + b"".join(blobs)
    return MAGIC + xxtea_encrypt(plain, key_bytes())


def roundtrip(path):
    original = open(path, "rb").read()
    entries, blobs = load_entries(path)
    rebuilt = build(entries, blobs)
    same = rebuilt == original
    print(f"{os.path.basename(path)}: original {len(original)} bytes, rebuilt {len(rebuilt)} bytes")
    if same:
        print("  ROUND-TRIP: byte-identical  <-- encoder proven")
        return True
    diff = next((i for i in range(min(len(original), len(rebuilt))) if original[i] != rebuilt[i]), None)
    print(f"  ROUND-TRIP: DIFFERS (first differing byte at {diff})")
    if diff is not None:
        print(f"    original: {original[diff:diff + 24].hex()}")
        print(f"    rebuilt : {rebuilt[diff:diff + 24].hex()}")
    return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--roundtrip", metavar="BUNDLE", help="decode then re-encode, compare bytes")
    ap.add_argument("--selfcheck", action="store_true", help="D(E(x)) == x on random inputs")
    args = ap.parse_args()
    ok = True
    if args.selfcheck:
        bad = selfcheck()
        if bad:
            ok = False
            print(f"SELFCHECK FAILED on {len(bad)} inputs, e.g. {bad[:5]}")
        else:
            print("SELFCHECK: D(E(x)) == x for every random input  <-- encoder/decoder are a pair")
    if args.roundtrip:
        ok = roundtrip(args.roundtrip) and ok
    if not (args.selfcheck or args.roundtrip):
        ap.print_help()
        return
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
