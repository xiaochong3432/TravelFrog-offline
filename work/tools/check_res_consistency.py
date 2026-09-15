#!/usr/bin/env python3
"""Is our shipped resource tree self-consistent?

The APK may ship a resource manifest that references files it does not contain
(those arrived via hotfix). Check that, because it decides whether the archived
CDN resources are actually needed.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os, re, collections

WEB = str(PROJECT_ROOT) + "/work/run/web"
RES = os.path.join(WEB, "resource", "China", "default.res.json")

d = json.load(open(RES, encoding="utf8"))
resources = d.get("resources", [])
print(f"local default.res.json: {len(resources)} resources, {len(d.get('groups', []))} groups")

missing = []
for r in resources:
    url = r.get("url")
    if not url:
        continue
    # eab_asset entries point at a bundle, not a file
    if r.get("type") == "eab_asset":
        continue
    p = os.path.join(WEB, "resource", "China", url.replace("/", os.sep))
    if not os.path.isfile(p):
        missing.append((r.get("name"), url))

print(f"\nresources whose file is ABSENT from the APK tree: {len(missing)}")
by = collections.Counter("/".join(u.split("/")[:-1]) for _, u in missing)
for k, v in by.most_common(15):
    print(f"   {v:5d}  {k}")
print("\nsample:")
for n, u in missing[:12]:
    print(f"   {n:<40} {u}")

# do the names overlap with the 226 CDN-only files?
patch = json.load(open(str(PROJECT_ROOT) + "/work/cdn/patch.json", encoding="utf8"))
cdn_only = {p for p in patch if not p.startswith("__")
            and not os.path.isfile(os.path.join(WEB, p.replace("/", os.sep)))}
cdn_basenames = {os.path.basename(p) for p in cdn_only}
overlap = [n for n, _ in missing if n in cdn_basenames]
print(f"\nCDN-only files: {len(cdn_only)}")
print(f"missing-resource names that the CDN supplies: {len(overlap)}")
for n in overlap[:10]:
    print("   ", n)
