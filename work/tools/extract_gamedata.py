#!/usr/bin/env python3
"""Reassemble the client DB dump from the probe log into engine data files."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os, re, json, collections

LOG = str(PROJECT_ROOT) + "/work/run/logs/client.log"
OUTDIR = str(PROJECT_ROOT) + "/work/run/engine/data"

txt = open(LOG, encoding="utf8", errors="replace").read()

def collect(tag, labelled=True):
    """Concatenate the payloads of [tag] lines in order, keyed by prefix label."""
    buckets = collections.OrderedDict()
    if labelled:
        for m in re.finditer(re.escape(tag) + r" ([A-Za-z]+):([^\n]*)", txt):
            buckets.setdefault(m.group(1), []).append(m.group(2))
    else:
        buckets["all"] = re.findall(re.escape(tag) + r" ([^\n]*)", txt)
    return {k: "".join(v) for k, v in buckets.items()}

lists = collect("[dbd]")
print("list buckets:", {k: len(v) for k, v in lists.items()})

items = collect("[dbitemd]", labelled=False)
item_rows = "".join(items.values())
print("item row chars:", len(item_rows))

os.makedirs(OUTDIR, exist_ok=True)

data = {}
for name, s in lists.items():
    ids = [int(x) for x in s.split(",") if x.strip().isdigit()]
    data[name] = ids
    print(f"  {name}: {len(ids)} ids")

rows = []
for r in item_rows.split(";"):
    if not r.strip():
        continue
    p = r.split("|")
    if len(p) == 3 and p[0].strip().isdigit():
        rows.append({"id": int(p[0]), "type": int(p[1]) if p[1].strip().lstrip("-").isdigit() else p[1],
                     "sub_type": int(p[2]) if p[2].strip().lstrip("-").isdigit() else p[2]})
print(f"  item rows: {len(rows)}")

by_type = collections.Counter(r["type"] for r in rows)
print("  items by type:", dict(by_type.most_common()))

json.dump({"tables": data, "items": rows},
          open(os.path.join(OUTDIR, "gamedata.json"), "w", encoding="utf8"),
          ensure_ascii=False, indent=1)
print("wrote", os.path.join(OUTDIR, "gamedata.json"))
