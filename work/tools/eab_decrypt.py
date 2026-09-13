#!/usr/bin/env python3
"""Decrypt and extract the client's `config.eab` bundle.

Why this exists
---------------
The game's data tables (Item, shopData, Specialty, Collection, Prize, Character,
Shop, GiftData, lotteryData, furnitureShopData) are not loose files: the resource
manifest lists them as `eab_asset` entries whose url is `config_eab`. And
config.eab is NOT a plain bundle -- its magic ends in 0x1b instead of 0x1a, which
is why earlier notes called it "encrypted / unreadable".

The client itself shows how to read it (its `eab.decode`):

    if (magic[6] == 0x1b) {
        e = xxtea.decrypt(fileBytes.subarray(8), Utils.simpleEncrypt("r]|lnf\\x80X\\x81U\\x82aq_r", 13));
        view = new DataView(e, 0, 4);
    } else {
        view = new DataView(fileBytes, 8, 4);
    }
    indexLen = view.getUint32(0, true);
    index    = JSON.parse(utf8(e[4 .. 4+indexLen]));
    payload  = e[4+indexLen ..];

Utils.simpleEncrypt(s, 13) shifts even-indexed chars down by 13 and odd-indexed
ones up by 13, which turns that key into "ejoysassetbundle". XXTEA uses the
standard delta 0x9E3779B9 and stores the plaintext length in the final long.

Usage: python eab_decrypt.py [--probe]
"""
import json
import os
import struct
import sys

ROOT = r"H:\AI\frog"
BUNDLE = os.path.join(ROOT, r"work\run\web\resource\China\eab\config.eab")
OUTDIR = os.path.join(ROOT, "work", "run", "engine", "data", "tables")
COMBINED = os.path.join(ROOT, "work", "run", "engine", "data", "gamedata.json")

MAGIC_PLAIN = b"\x89EAB\r\n\x1a\n"
MAGIC_CRYPT = b"\x89EAB\r\n\x1b\n"

# from the client: Utils.simpleEncrypt("r]|lnf\x80X\x81U\x82aq_r", 13)
KEY_LITERAL = "r]|lnf\u0080X\u0081U\u0082aq_r"

TABLE_FILES = {
    "Item_json": "Item",
    "shopData_json": "shopData",
    "furnitureShopData_json": "furnitureShopData",
    "Specialty_json": "Specialty",
    "Collection_json": "Collection",
    "Prize_json": "Prize",
    "Character_json": "Character",
    "Shop_json": "Shop",
    "GiftData_json": "GiftData",
    "lotteryData_json": "lotteryData",
}


def simple_encrypt(s, shift=13):
    """Utils.simpleEncrypt: even index -shift, odd index +shift (mod 0x10000)."""
    out = []
    for i, ch in enumerate(s):
        c = ord(ch)
        c = c - shift if i % 2 == 0 else c + shift
        out.append(chr(c & 0xFFFF))
    return "".join(out)


def _to_longs(data):
    """Bytes -> little-endian u32 list (zero padded to a multiple of 4)."""
    if len(data) % 4:
        data = data + b"\x00" * (4 - len(data) % 4)
    return list(struct.unpack(f"<{len(data) // 4}I", data))


def _to_bytes(longs, include_length):
    if include_length:
        # Mirrors the client's long2str: the plaintext length lives in the LAST
        # long, and is only valid within [(n_longs-1)*4 - 3, (n_longs-1)*4].
        n = longs[-1]
        maxlen = (len(longs) - 1) * 4
        if n < maxlen - 3 or n > maxlen:
            raise ValueError(f"implausible plaintext length {n} (max {maxlen})")
    else:
        n = len(longs) * 4
    raw = struct.pack(f"<{len(longs)}I", *longs)
    return raw[:n]


def xxtea_decrypt(data, key, y_starts_at_v0=False):
    """XXTEA decrypt, mirroring the client's implementation exactly.

    The minified decrypt does not initialise `y`, so on the very first round it
    reads as 0 (JS coerces undefined to 0). Both readings are offered because the
    caller can tell which is right: only the correct one yields a JSON index.
    """
    v = _to_longs(data)
    k = _to_longs(key)
    if len(v) < 2 or not k:
        raise ValueError("data/key too short")
    n = len(v) - 1
    delta = 0x9E3779B9
    q = 6 + 52 // (n + 1)
    total = (q * delta) & 0xFFFFFFFF
    y = v[0] if y_starts_at_v0 else 0
    z = v[n]
    while total != 0:
        e = (total >> 2) & 3
        for p in range(n, 0, -1):
            z = v[p - 1]
            mx = ((((z >> 5) ^ (y << 2)) & 0xFFFFFFFF)
                  + (((y >> 3) ^ (z << 4)) & 0xFFFFFFFF)) & 0xFFFFFFFF
            mx = (mx ^ (((total ^ y) + (k[(p & 3) ^ e] ^ z)) & 0xFFFFFFFF)) & 0xFFFFFFFF
            v[p] = (v[p] - mx) & 0xFFFFFFFF
            y = v[p]
        z = v[n]
        mx = ((((z >> 5) ^ (y << 2)) & 0xFFFFFFFF)
              + (((y >> 3) ^ (z << 4)) & 0xFFFFFFFF)) & 0xFFFFFFFF
        mx = (mx ^ (((total ^ y) + (k[(0 & 3) ^ e] ^ z)) & 0xFFFFFFFF)) & 0xFFFFFFFF
        v[0] = (v[0] - mx) & 0xFFFFFFFF
        y = v[0]
        total = (total - delta) & 0xFFFFFFFF
    return _to_bytes(v, True)


def open_bundle(path):
    """Return (index_manifest, payload_bytes) for either eab variant."""
    d = open(path, "rb").read()
    magic = d[:8]
    if magic == MAGIC_PLAIN:
        plain = d[8:]
    elif magic == MAGIC_CRYPT:
        key = simple_encrypt(KEY_LITERAL, 13).encode("utf-8")
        last = None
        for y0 in (False, True):
            try:
                body = xxtea_decrypt(d[8:], key, y_starts_at_v0=y0)
            except Exception as ex:
                last = f"y0={y0}: {ex}"
                continue
            try:
                idxlen = struct.unpack_from("<I", body, 0)[0]
                man = json.loads(body[4:4 + idxlen].decode("utf-8"))
                return man, body[4 + idxlen:], f"xxtea (y_init={'v0' if y0 else '0'})"
            except Exception as ex:
                last = f"y0={y0}: {ex}"
        raise SystemExit(f"xxtea decryption failed for both readings; last: {last}")
    else:
        raise SystemExit(f"unknown eab magic {magic!r}")


def main():
    probe = "--probe" in sys.argv
    print(f"bundle: {BUNDLE} ({os.path.getsize(BUNDLE):,} bytes)")
    man, payload, how = open_bundle(BUNDLE)
    print(f"decoded via : {how}")
    print(f"index entry : {len(man)}")
    names = [e.get("n") for e in man]
    print("names       :", names[:14])
    if probe:
        return 0

    if not os.path.isdir(OUTDIR):
        os.makedirs(OUTDIR, exist_ok=True)
    got, nonjson, pos = {}, [], 0
    for e in man:
        name = e.get("n", "")
        size = e.get("s", 0)
        chunk = payload[pos:pos + size]
        pos += size
        if not name.endswith("_json"):
            if size:
                nonjson.append((name, size))
            continue
        key = name[:-len("_json")]          # Item_json -> Item
        try:
            got[key] = json.loads(chunk.decode("utf-8"))
        except Exception as ex:
            print(f"  !! {name}: {ex}")

    total = 0
    for name, obj in sorted(got.items()):
        n = len(obj) if isinstance(obj, (list, dict)) else "?"
        with open(os.path.join(OUTDIR, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1)
        total += os.path.getsize(os.path.join(OUTDIR, name + ".json"))
        print(f"  wrote {name:22s} n={n:<6} ")

    print(f"\n{len(got)} JSON tables, {total:,} bytes -> {OUTDIR}")
    if nonjson:
        print(f"({len(nonjson)} non-JSON entries skipped, e.g. {nonjson[:4]})")

    combined = {"tables": got}
    items = got.get("Item")
    if isinstance(items, list):
        # keep the flat list the engine already consumed, but enriched: the shop
        # needs names and prices, and they are already sitting in this table.
        combined["items"] = [{"id": it.get("id"), "type": it.get("type"),
                              "sub_type": it.get("sub_type", ""),
                              "name": it.get("name", ""),
                              "price": it.get("price", 0),
                              "spend": it.get("spend", 0)} for it in items]
    with open(COMBINED, "w", encoding="utf-8") as f:
        json.dump(combined, f, ensure_ascii=False, indent=1)
    print(f"wrote {COMBINED} ({os.path.getsize(COMBINED):,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
