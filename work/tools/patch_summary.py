#!/usr/bin/env python3
"""Summarize the CDN patch.json before archiving."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, collections, os

P = str(PROJECT_ROOT) + "/work/cdn/patch.json"
d = json.load(open(P, encoding="utf8"))

meta = {k: v for k, v in d.items() if k.startswith("__")}
files = {k: v for k, v in d.items() if not k.startswith("__")}

print("=== metadata ===")
for k, v in meta.items():
    print(f"  {k} = {v}")

total = sum(v["2"] for v in files.values())
print(f"\nfiles: {len(files)}   total listed size: {total:,} bytes ({total/1048576:.1f} MiB)")

bydir = collections.Counter()
szdir = collections.Counter()
for k, v in files.items():
    bydir[v["0"]] += 1
    szdir[v["0"]] += v["2"]
print(f"\n{'dist dir':<16}{'files':>8}{'MiB':>10}")
for k in sorted(bydir):
    print(f"{k:<16}{bydir[k]:>8}{szdir[k]/1048576:>10.2f}")

ext = collections.Counter()
szext = collections.Counter()
for k, v in files.items():
    e = os.path.splitext(k)[1].lower() or "(none)"
    ext[e] += 1
    szext[e] += v["2"]
print(f"\n{'ext':<12}{'files':>8}{'MiB':>10}")
for e, c in ext.most_common(20):
    print(f"{e:<12}{c:>8}{szext[e]/1048576:>10.2f}")

print("\n=== JS entries ===")
for k, v in sorted(files.items()):
    if k.endswith(".js") or k.endswith(".html") or k.endswith(".json") and "/" not in k:
        print(f"  {k:<28} dir={v['0']:<12} size={v['2']:>9,}  md5={v['1']}")

# free disk space
import shutil
u = shutil.disk_usage("H:\\")
print(f"\ndisk H: free {u.free/1073741824:.1f} GiB / total {u.total/1073741824:.1f} GiB")
