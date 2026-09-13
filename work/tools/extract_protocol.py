#!/usr/bin/env python3
"""Extract the embedded client/server protocol table from main.min.js.

Entries look like:  cmd_name:[["param1","param2"],!0]   where !0 = required-ish
"""
import re, json, sys, os, collections

path = sys.argv[1] if len(sys.argv) > 1 else r"H:\AI\frog\work\base\assets\game\js\main.min.js"
data = open(path, "rb").read().decode("utf8", "replace")

ENTRY = re.compile(r'([A-Za-z_][A-Za-z0-9_]{2,40})\s*:\s*\[\[([^\]]*)\]\s*,\s*!(0|1)\s*\]')

rows = []
for m in ENTRY.finditer(data):
    name, params, req = m.group(1), m.group(2), m.group(3)
    ps = re.findall(r'"([^"]*)"', params)
    rows.append((name, ps, req == "0", m.start()))

print(f"protocol entries parsed: {len(rows)}")
# contiguity: find the largest cluster (the real table)
starts = [r[3] for r in rows]
cluster, best, cur = [], [], [rows[0]] if rows else []
for a, b in zip(rows, rows[1:]):
    if b[3] - a[3] < 400:
        cur.append(b)
    else:
        if len(cur) > len(best):
            best = cur
        cur = [b]
if len(cur) > len(best):
    best = cur

print(f"largest contiguous cluster: {len(best)} entries  "
      f"(offset {best[0][3]}..{best[-1][3]})")

with open(r"H:\AI\frog\work\protocol_table.txt", "w", encoding="utf8") as f:
    for name, ps, req, off in best:
        f.write(f"{name}\t{','.join(ps)}\t{'REQ' if req else 'opt'}\t{off}\n")
    f.write("\n--- all parsed entries ---\n")
    for name, ps, req, off in rows:
        f.write(f"{name}\t{','.join(ps)}\t{'REQ' if req else 'opt'}\t{off}\n")

# group by prefix
grp = collections.Counter(n.split("_")[0] for n, _, _, _ in best)
print("\ngroups:", dict(grp.most_common()))
print("\nsample:")
for name, ps, req, off in best[:25]:
    print(f"  {name}({','.join(ps)}) {'REQ' if req else 'opt'}")
print("  ...")
# raw text around table
s = max(0, best[0][3] - 300); e = min(len(data), best[-1][3] + 200)
open(r"H:\AI\frog\work\protocol_table_raw.txt", "w", encoding="utf8").write(data[s:e])
print("\nwrote work/protocol_table.txt and protocol_table_raw.txt")
