#!/usr/bin/env python3
"""Pull the exact eab decryption key + the simpleEncrypt function out of the client.

The client decrypts the `\\x89EAB\\r\\n\\x1b\\n` variant of .eab with

    xxtea.decrypt(bytes_after_magic, Utils.simpleEncrypt("<key>", 13))

so reproducing it needs (a) the key string byte-exactly (it contains non-ASCII
characters a console dump mangles) and (b) the body of Utils.simpleEncrypt, which
the minifier exported as `k`.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
raw = open(JS, "rb").read()

out = open(str(PROJECT_ROOT) + "/work/build/eab_key.txt", "w", encoding="utf-8")

# ---- 1. the key literal, byte exact
m = re.search(rb"simpleEncrypt\((\"[\s\S]{1,80}?\"),13\)", raw)
if not m:
    out.write("key literal not found\n")
else:
    lit = m.group(1)
    out.write("raw literal bytes:\n")
    out.write(f"  {lit!r}\n")
    inner = lit[1:-1]
    out.write(f"inner bytes : {inner!r}\n")
    out.write(f"inner hex   : {inner.hex(' ')}\n")
    out.write(f"inner len   : {len(inner)}\n")
    try:
        out.write(f"as utf-8    : {inner.decode('utf-8')!r}\n")
    except UnicodeDecodeError as e:
        out.write(f"as utf-8    : FAILED ({e})\n")
    # the client's Utf8ArrayToStr decodes %-escaping? check for backslash escapes
    out.write(f"has backslash escapes: {b'\\\\' in inner}\n")

# ---- 2. Utils.simpleEncrypt = k  ->  function k(...)
m2 = re.search(rb"function k\(([^)]*)\)\{", raw)
if not m2:
    out.write("\nfunction k( not found\n")
else:
    start = m2.start()
    # brace-balanced walk
    depth = 0
    i = m2.end() - 1
    while i < len(raw):
        c = raw[i:i + 1]
        if c == b"{":
            depth += 1
        elif c == b"}":
            depth -= 1
            if depth == 0:
                break
        i += 1
    body = raw[start:i + 1]
    out.write(f"\nfunction k body ({len(body)} bytes):\n")
    out.write(body.decode("utf-8", "replace"))
    out.write("\n")

# ---- 3. the xxtea module, to confirm delta / block handling
m3 = re.search(rb"2654435769", raw)
out.write(f"\ndelta constant 2654435769 present: {bool(m3)}\n")
if m3:
    lo = max(0, m3.start() - 1200)
    out.write(raw[lo:m3.start() + 200].decode("utf-8", "replace"))
    out.write("\n")

out.close()
print("written")
