#!/usr/bin/env python3
"""Split the 243 protocol commands by 'response required' and feature group."""
import re, collections

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
data = open(JS, "rb").read().decode("utf8", "replace")
ENTRY = re.compile(r'([A-Za-z_][A-Za-z0-9_]{2,40})\s*:\s*\[\[([^\]]*)\]\s*,\s*!(0|1)\s*\]')

rows = []
for m in ENTRY.finditer(data):
    ps = re.findall(r'"([^"]*)"', m.group(2))
    rows.append((m.group(1), ps, m.group(3) == "0"))

req = [r for r in rows if r[2]]
opt = [r for r in rows if not r[2]]
print(f"total={len(rows)}  response-required(!0)={len(req)}  fire-and-forget(!1)={len(opt)}")

grp = collections.defaultdict(lambda: [0, 0])
for n, ps, r in rows:
    g = n.split("_")[0]
    grp[g][0 if r else 1] += 1

print(f"\n{'group':<14}{'required':>9}{'fire&forget':>13}{'total':>7}")
for g, (a, b) in sorted(grp.items(), key=lambda kv: -(kv[1][0] + kv[1][1])):
    print(f"{g:<14}{a:>9}{b:>13}{a+b:>7}")

CORE = ["hall", "client", "clover", "item", "travel", "album", "guest", "furniture",
        "shop", "mail", "task", "story", "tutorial", "lottery", "pray"]
print("\n--- CORE-ish commands requiring a response ---")
for n, ps, r in req:
    if n.split("_")[0] in CORE:
        print(f"   {n:<34}({','.join(ps)})")
