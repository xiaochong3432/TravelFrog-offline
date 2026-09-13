#!/usr/bin/env python3
import io
s = io.open(r"H:\AI\frog\work\spec\travel-album.md", encoding="utf8").read()
fence = chr(96) * 3
n = s.count(fence)
print("fences:", n, "balanced" if n % 2 == 0 else "UNBALANCED")
print("lines:", len(s.splitlines()))
for l in s.splitlines():
    if l.startswith("#"):
        print(l)
