#!/usr/bin/env python3
"""Temporary diagnostic: make the offline enterGame path announce itself."""
import os, shutil

MAIN = r"H:\AI\frog\work\run\web\js\main.min.js"
d = open(MAIN, encoding="utf8").read()

OLD = 'true&&(Music.play("BGM_Default"'
NEW = '(window.console&&console.log("[offline] enterGame body reached"),true)&&(Music.play("BGM_Default"'

n = d.count(OLD)
print("occurrences of patched guard:", n)
if 'enterGame body reached' in d:
    print("diagnostic already present")
elif n:
    d = d.replace(OLD, NEW)
    open(MAIN, "w", encoding="utf8").write(d)
    print("diagnostic inserted")
else:
    # fall back: report what the enterGame definitions look like
    i = 0
    while True:
        i = d.find("prototype.enterGame=function", i + 1)
        if i < 0:
            break
        print("---", d[i:i + 260])
