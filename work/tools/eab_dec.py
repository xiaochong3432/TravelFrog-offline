#!/usr/bin/env python3
"""Decrypt an encrypted Egret .eab bundle exactly like the client does.

Ported from main.min.js:
  * xxtea module  (chars ~227200-231600)     - standard XXTEA, key = UTF-8 bytes
  * Utils.simpleEncrypt(k, 13)               - even index: -13, odd index: +13
  * eab.decode()  (chars ~231700-232500)     - magic 89 45 41 42 0d 0a 1b 0a => xxtea

Usage:
  py eab_dec.py list   <bundle>              # print the JSON index entries
  py eab_dec.py get    <bundle> <name> <out> # write one entry payload
"""
import json, struct, sys

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
DELTA = 0x9E3779B9
MASK = 0xFFFFFFFF


def _mx(sum_, y, z, p, e, key):
    a = (((z >> 5) ^ ((y << 2) & MASK)) + ((y >> 3) ^ ((z << 4) & MASK))) & MASK
    b = ((sum_ ^ y) + (key[(p & 3) ^ e] ^ z)) & MASK
    return (a ^ b) & MASK


def _bytes_to_words(data, include_len):
    n = len(data)
    words = n >> 2
    if n & 3:
        words += 1
    out = [0] * (words + 1 if include_len else words)
    if include_len:
        out[words] = n
    for i in range(n):
        out[i >> 2] = (out[i >> 2] | (data[i] << ((i & 3) << 3))) & MASK
    return out


def _words_to_bytes(words, include_len):
    n = len(words) << 2
    if include_len:
        ln = words[len(words) - 1]
        n -= 4
        if ln < n - 3 or ln > n:
            return None
        n = ln
    return bytes((words[i >> 2] >> ((i & 3) << 3)) & 0xFF for i in range(n))


def _fix_key(k):
    return k if len(k) >= 16 else k + b"\0" * (16 - len(k))


def xxtea_decrypt(data, key):
    key = _fix_key(key)
    v = _bytes_to_words(data, False)
    k = _bytes_to_words(key, False)
    n = len(v)
    if n < 2:
        return data
    y = v[0]
    q = 6 + 52 // n
    sum_ = (q * DELTA) & MASK
    while sum_ != 0:
        e = (sum_ >> 2) & 3
        for p in range(n - 1, 0, -1):
            z = v[p - 1]
            v[p] = (v[p] - _mx(sum_, y, z, p, e, k)) & MASK
            y = v[p]
        z = v[n - 1]
        v[0] = (v[0] - _mx(sum_, y, z, 0, e, k)) & MASK
        y = v[0]
        sum_ = (sum_ - DELTA) & MASK
    return _words_to_bytes(v, True)


def simple_encrypt(s, delta=13):
    out = []
    for i, ch in enumerate(s):
        c = ord(ch)
        out.append(chr(c - delta if i % 2 == 0 else c + delta))
    return "".join(out)


def client_key():
    d = open(JS, "rb").read().decode("utf8", "replace")
    marker = 'Utils.simpleEncrypt("'
    i = d.index(marker) + len(marker)
    j = d.index('"', i)
    raw = d[i:j]
    return raw, simple_encrypt(raw, 13).encode("utf8")


PLAIN_MAGIC = bytes([137, 69, 65, 66, 13, 10, 26, 10])
CRYPT_MAGIC = bytes([137, 69, 65, 66, 13, 10, 27, 10])


def decode(path):
    d = open(path, "rb").read()
    assert d[:8] in (PLAIN_MAGIC, CRYPT_MAGIC), "not an eab: " + repr(d[:8])
    if d[:8] == CRYPT_MAGIC:
        raw, key = client_key()
        out = xxtea_decrypt(d[8:], key)
        print(f"  key literal={raw!r} decrypted={len(out)} bytes")
    else:
        out = d[8:]
    (idxlen,) = struct.unpack_from("<I", out, 0)
    idx = json.loads(out[4:4 + idxlen].decode("utf8"))
    payload = out[4 + idxlen:]
    entries = {}
    pos = 0
    for e in idx:
        entries[e["n"]] = (pos, e.get("s", 0), e)
        pos += e.get("s", 0)
    return entries, payload


def main():
    mode = sys.argv[1]
    entries, payload = decode(sys.argv[2])
    print(f"{len(entries)} entries, payload {len(payload)} bytes")
    if mode == "list":
        pat = sys.argv[3] if len(sys.argv) > 3 else ""
        for n, (o, s, e) in entries.items():
            if pat.lower() in n.lower():
                print(f"  {n:<46} off={o:<8} size={s:<8} type={e.get('t')}")
        return
    name, out = sys.argv[3], sys.argv[4]
    o, s, e = entries[name]
    blob = payload[o:o + s]
    open(out, "wb").write(blob)
    print(f"wrote {out} ({s} bytes)")


if __name__ == "__main__":
    main()
