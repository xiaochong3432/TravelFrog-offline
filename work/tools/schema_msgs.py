#!/usr/bin/env python3
"""Extract the game's Chinese diagnostic strings -> schema documentation.

Messages like: "服务端的协议 client_load_role 中的 frog 属性不存在，检查协议配置是否被修改"
literally document the required response fields per protocol command.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
raw = open(JS, "rb").read()
out = []

# all UTF-8 Chinese string literals
seen = set()
for m in re.finditer(rb'"([^"\\\n]{2,300})"', raw):
    b = m.group(1)
    if not any(c >= 0x80 for c in b):
        continue
    try:
        s = b.decode("utf8")
    except UnicodeDecodeError:
        continue
    if re.search(r"[\u4e00-\u9fff]", s) and s not in seen:
        seen.add(s)
        out.append((m.start(), s))

with open(str(PROJECT_ROOT) + "/work/chinese_strings.txt", "w", encoding="utf8") as f:
    f.write(f"# {len(out)} unique Chinese string literals from main.min.js\n\n")
    for off, s in sorted(out):
        f.write(f"[{off}] {s}\n")

# schema documentation messages
proto = [(o, s) for o, s in out if ("\u534f\u8bae" in s and ("\u5c5e\u6027" in s or "\u6709\u6548\u6570\u636e" in s or "\u4e0d\u5b58\u5728" in s))]
print(f"schema-documenting messages: {len(proto)}\n")
for o, s in sorted(proto):
    print(f"  [{o}] {s}")

print("\nwritten: work/chinese_strings.txt")
