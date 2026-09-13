#!/usr/bin/env python3
"""Dump the exact chars of the eab XXTEA key literal."""
import re
JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

i = d.index("Utils.simpleEncrypt(")
seg = d[i:i + 120]
print("raw repr:", repr(seg[:80]))
m = re.search(r'simpleEncrypt\("([^"]*)",\s*(\d+)\)', d[i:i + 200])
print("match:", m)
lit = m.group(1)
print("len", len(lit), "codes", [ord(c) for c in lit])
