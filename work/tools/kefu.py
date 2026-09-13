#!/usr/bin/env python3
"""Which skin owns a given literal string, and what the customer-service button
does under the Test channel?"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os
import re

THEME = str(PROJECT_ROOT) + "/work/run/web/js/default.thm.js"
JS = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"

with open(THEME, encoding="utf-8", errors="replace") as fh:
    th = fh.read()
with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

# class -> skin path
path_of = {}
for m in re.finditer(r"generateEUI\.paths\['([^']+)'\]\s*=\s*(?:window\.)?(\$?[A-Za-z0-9_$]+)", th):
    path_of[m.group(2)] = m.group(1)


def class_at(off):
    decls = list(re.finditer(r"window\.(\$?[A-Za-z0-9_$]+)\s*=\s*\(function", th[:off]))
    return decls[-1].group(1) if decls else None


for needle in ["客服系统正在接入", "1051431084", "btn_service", "Kefu", "kefu"]:
    print("=" * 18, needle)
    hits = list(re.finditer(re.escape(needle), th))
    print("   theme hits: %d" % len(hits))
    for m in hits[:4]:
        cls = class_at(m.start())
        print("     THM @%d cls=%s skin=%s" % (m.start(), cls, path_of.get(cls, '?')))
    hits2 = list(re.finditer(re.escape(needle), s))
    print("   bundle hits: %d" % len(hits2))
    for m in hits2[:4]:
        a, b = max(0, m.start() - 260), min(len(s), m.end() + 200)
        print("     JS  @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
    print()
