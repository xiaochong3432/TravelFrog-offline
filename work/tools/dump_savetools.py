#!/usr/bin/env python3
"""Dump the shell's installSaveTools verbatim so it can be replaced wholesale."""
import io

P = r"H:\AI\frog\work\run\web\__probe.js"
t = io.open(P, encoding="utf-8").read()
i = t.find("    function installSaveTools()")
j = t.find("    /* --------------------------------------------------- main watchdog */")
assert i > 0 and j > i, (i, j)
io.open(r"H:\AI\frog\work\logs\savetools_src.txt", "w", encoding="utf-8").write(t[i:j])
print("start=%d end=%d len=%d" % (i, j, j - i))
print("installOfflineAds call sites:", t.count("installOfflineAds();"))
