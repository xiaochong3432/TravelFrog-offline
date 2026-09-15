#!/usr/bin/env python3
"""The game JS stores some Chinese strings as GBK. Extract & search them."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re, json

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
raw = open(JS, "rb").read()

hits = []
for m in re.finditer(rb'"([^"\\\n]{2,160})"', raw):
    b = m.group(1)
    if not any(c >= 0x80 for c in b):
        continue
    for enc in ("gbk", "utf8"):
        try:
            s = b.decode(enc)
        except UnicodeDecodeError:
            continue
        if re.search(r"[\u4e00-\u9fff]", s):
            hits.append((m.start(), enc, s))
        break

print(f"Chinese string literals: {len(hits)}\n")

KEYWORDS = ["\u5355\u673a", "\u79bb\u7ebf", "\u65ad\u7f51", "\u7f51\u7edc",
            "\u670d\u52a1\u5668", "\u767b\u5f55", "\u5931\u8d25", "\u91cd\u8fde",
            "\u8bf7\u68c0\u67e5", "\u94fe\u63a5"]

for kw in KEYWORDS:
    found = [(o, e, s) for o, e, s in hits if kw in s]
    print(f"===== {kw} ({len(found)}) =====")
    for o, e, s in found[:30]:
        print(f"  [{o}|{e}] {s}")
    if not found:
        print("  (none)")

# locate the localized string table
vj = json.load(open(str(PROJECT_ROOT) + "/work/base/assets/game/version.json", encoding="utf8"))
print("\n===== resource files matching zh / lang / words =====")
for k in vj:
    kl = k.lower()
    if "zh" in kl or "lang" in kl or "words" in kl or kl.endswith(".json") and "China/" in k and "/images/" not in kl:
        print("   ", k)
