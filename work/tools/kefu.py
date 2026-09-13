#!/usr/bin/env python3
"""Which skin owns a given literal string, and what the customer-service button
does under the Test channel?"""
import os
import re

THEME = r"H:\AI\frog\work\run\web\js\default.thm.js"
JS = r"H:\AI\frog\work\run\web\js\main.min.js"

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
