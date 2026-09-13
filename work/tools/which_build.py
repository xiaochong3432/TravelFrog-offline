#!/usr/bin/env python3
"""Which client build is actually fuller: v1001 (APK) or v1021 (CDN hotfix)?"""
import re

V1 = r"H:\AI\frog\work\run\web\js\main.min.js"
V1T = r"H:\AI\frog\work\run\web\js\default.thm.js"
V2 = r"H:\AI\frog\work\cdn\v1021\js\main.min.js"
V2T = r"H:\AI\frog\work\cdn\v1021\js\default.thm.js"

v1 = open(V1, "rb").read()
v1t = open(V1T, "rb").read()
v2 = open(V2, "rb").read()
v2t = open(V2T, "rb").read()

print(f"main.min.js    v1001={len(v1):>10,}   v1021={len(v2):>10,}")
print(f"default.thm.js v1001={len(v1t):>10,}   v1021={len(v2t):>10,}")
print()

FEATURES = [b"springcard", b"partycake", b"museumday", b"greetcard", b"capsule",
            b"lottery", b"wishingpool", b"animpicture", b"encyclopedia", b"koto",
            b"weather", b"clover", b"MainOutController", b"checkGuide"]
print(f"{'symbol':<24}{'v1001':>9}{'v1021':>9}")
for f in FEATURES:
    print(f"  {f.decode():<22}{v1.count(f):>9}{v2.count(f):>9}")

def skins(b):
    return len(set(re.findall(rb"[\w/]+\.exml", b)))

print()
print("distinct .exml skin refs:  main  v1001=%d  v1021=%d" % (skins(v1), skins(v2)))
print("distinct .exml skin refs:  theme v1001=%d  v1021=%d" % (skins(v1t), skins(v2t)))

print()
print("year / event markers in main.min.js:")
for m in [b"2023", b"2024", b"2025", b"2026", b"zhongqiu", b"xinnian", b"chunjie"]:
    print(f"  {m.decode():<12} v1001={v1.count(m):>6}   v1021={v2.count(m):>6}")

print()
# does v1021 reference assets that only exist in the CDN payload?
for probe in [b"PictureData", b"TravelData", b"MainData", b"FurnitureData"]:
    print(f"  {probe.decode():<16} v1001={v1.count(probe):>6}   v1021={v2.count(probe):>6}")
