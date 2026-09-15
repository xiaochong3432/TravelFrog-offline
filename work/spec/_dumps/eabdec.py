#!/usr/bin/env python3
"""Decrypt an EAB bundle (client's `eab.decode` logic) and dump its JSON index.

Client reference (main.min.js):
  eab.decode(data):
    magic = 89 45 41 42 0d 0a 1a 0a ; encMagic = ... 1b 0a
    if data[6] == 0x1b:
        plain = xxtea.decrypt(data[8:], Utils.simpleEncrypt("r]|lnf\x80X\x81U\x82aq_r", 13))
        view start = 0
    else:
        plain = data ; view start = 8
    idxLen = u32le at view start
    index  = JSON.parse(plain[4 : 4+idxLen])
    payloads = plain[4+idxLen :]

Utils.simpleEncrypt(s, t=13): even index -> c-t, odd index -> c+t  (char codes)
xxtea key = the char codes of the transformed string, as bytes.
"""
import json, struct, sys, os

MAGIC = bytes([137, 69, 65, 66, 13, 10, 26, 10])
ENCMAGIC6 = 27
DELTA = 0x9E3779B9
MASK = 0xFFFFFFFF


def simple_encrypt(s, t=13):
    out = []
    for i, ch in enumerate(s):
        c = ord(ch)
        out.append(chr(c - t if i % 2 == 0 else c + t))
    return "".join(out)


def str_to_bytes(s):
    return bytes(ord(c) & 0xFF for c in s)


def bytes_to_words(data):
    """Client xxtea `i(e, false)`: LITTLE-endian u32 words, zero padded to a word boundary."""
    if len(data) & 3:
        data = data + b"\x00" * (4 - (len(data) & 3))
    return list(struct.unpack("<%dI" % (len(data) // 4), data))


def words_to_bytes(v):
    return struct.pack("<%dI" % len(v), *v)


def pad_key(key_bytes):
    """Client xxtea `r(e)`: key shorter than 16 bytes is zero-padded to 16."""
    if len(key_bytes) < 16:
        key_bytes = key_bytes + b"\x00" * (16 - len(key_bytes))
    return key_bytes


def mx(sum_, y, z, p, e, k):
    # (z>>>5 ^ y<<2) + (y>>>3 ^ z<<4)  ^  (sum^y) + (k[3&p ^ e] ^ z)
    return (((z >> 5) ^ ((y << 2) & MASK)) + ((y >> 3) ^ ((z << 4) & MASK))
            ^ ((sum_ ^ y) + (k[(3 & p) ^ e] ^ z))) & MASK


def xxtea_decrypt(data, key):
    """Exact port of the client's xxtea.decrypt (little-endian, in-place decrypt)."""
    if not data:
        return None
    v = bytes_to_words(data)
    k = bytes_to_words(pad_key(key))
    if len(v) < 2 or not k:
        return None
    n = len(v) - 1
    z = v[n]
    y = v[0]
    sum_ = (6 + 52 // len(v)) * DELTA & MASK
    while sum_ != 0:
        e = (sum_ >> 2) & 3
        for p in range(n, 0, -1):
            z = v[p - 1]
            y = (v[p] - mx(sum_, y, z, p, e, k)) & MASK
            v[p] = y
        z = v[n]
        y = (v[0] - mx(sum_, y, z, 0, e, k)) & MASK
        v[0] = y
        sum_ = (sum_ - DELTA) & MASK
    raw = words_to_bytes(v)
    # `t(v, true)`: the last word is the original byte length
    m = v[-1]
    total = len(v) * 4 - 4
    if m < total - 3 or m > total:
        return None
    return raw[:m]


def decode(path):
    raw = open(path, "rb").read()
    if raw[:8] != MAGIC:
        if raw[:6] != MAGIC[:6] or raw[6] != ENCMAGIC6 or raw[7] != 10:
            raise ValueError("not an eab: %r" % raw[:8])
    if raw[6] == ENCMAGIC6:
        key = str_to_bytes(simple_encrypt("r]|lnf\x80X\x81U\x82aq_r", 13))
        plain = xxtea_decrypt(raw[8:], key)
        base = 0
    else:
        plain = raw
        base = 8
    idxlen = struct.unpack_from("<I", plain, base)[0]
    index = json.loads(plain[base + 4: base + 4 + idxlen].decode("utf8"))
    data_off = base + 4 + idxlen
    return plain, index, data_off


if __name__ == "__main__":
    p = sys.argv[1]
    plain, index, off = decode(p)
    print("%s: %d bytes -> %d plain bytes, %d entries, data at %d"
          % (os.path.basename(p), os.path.getsize(p), len(plain), len(index), off))
    pos = off
    for e in index:
        s = e.get("s", 0)
        print("   %-40s off=%-9d size=%-9d type=%s" % (e["n"], pos, s, e.get("t")))
        pos += s
    if len(sys.argv) > 2:
        want = sys.argv[2]
        pos = off
        for e in index:
            s = e.get("s", 0)
            if e["n"] == want:
                blob = plain[pos:pos + s]
                out = sys.argv[3] if len(sys.argv) > 3 else "eab_" + want.replace("/", "_")
                open(out, "wb").write(blob)
                print("wrote %s (%d bytes)" % (out, len(blob)))
                print(blob[:300].decode("utf8", "replace"))
                break
            pos += s
        else:
            print("no entry named", want)
