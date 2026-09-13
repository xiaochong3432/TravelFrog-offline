#!/usr/bin/env python3
"""Find the in-game help/settings menu and what its entries do.

Searches main.min.js (and the theme) for the labels and handlers behind 协议 /
联系客服 / 礼包码兑换, without passing CJK through the shell.
"""
import os
import re

JS = r"H:\AI\frog\work\run\web\js\main.min.js"
THEME = r"H:\AI\frog\work\run\web\js\default.thm.js"

with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()
with open(THEME, encoding="utf-8", errors="replace") as fh:
    th = fh.read()

for label in ["联系客服", "礼包码", "用户协议", "隐私", "客服"]:
    print("=" * 20, label)
    for m in list(re.finditer(re.escape(label), s))[:5]:
        a, b = max(0, m.start() - 320), min(len(s), m.end() + 200)
        print("  JS   @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
    for m in list(re.finditer(re.escape(label), th))[:5]:
        a, b = max(0, m.start() - 260), min(len(th), m.end() + 160)
        print("  THM  @%d ...%s..." % (m.start(), th[a:b].replace("\n", " ")))
    print()

print("=" * 20, "who opens CdkeyView / the customer-service button")
for pat in [r"CdkeyViewController", r"openKefu", r"open_custom_service", r"USER_ARGEEMENT_CONTENT_1"]:
    hits = list(re.finditer(pat, s))
    print("  %-26s %d hits" % (pat, len(hits)))
    for m in hits[:3]:
        a, b = max(0, m.start() - 260), min(len(s), m.end() + 200)
        print("     @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))

print()
print("=" * 20, "协议 content shape (is it HTML in the bundle, or a URL?)")
i = s.find("USER_ARGEEMENT_CONTENT_1")
if i > 0:
    j = s.find("USER_ARGEEMENT_CONTENT_3")
    k = s.find("}", j)
    print("  first 200 chars: %r" % s[i:i + 200])
    print("  total bundle HTML length for the three docs: %d chars" % ((j - i) if j > i else -1))
for pat in [r"USER_ARGEEMENT_CONTENT_1\s*[,)]", r"\.source\s*=\s*[^;]{0,40}ARGEEMENT"]:
    for m in list(re.finditer(pat, s))[:4]:
        a, b = max(0, m.start() - 300), min(len(s), m.end() + 200)
        print("  usage @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
