#!/usr/bin/env python3
"""Is the archived CDN payload a full build or an incremental patch?

patch.json carries __base_version__ / __prev_version__ / __dist_dir__, which looks
like a DIFF descriptor. That distinction decides whether the content our APK lacks
(the 2025-11 探秘东山岛 event) could still be fetched from the CDN.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import os
import re
import sys

ROOT = str(PROJECT_ROOT)
CDN = os.path.join(ROOT, "work", "cdn")
out = io.StringIO()


def say(s=""):
    out.write(s + "\n")


j = json.load(open(os.path.join(CDN, "patch.json"), encoding="utf-8"))
meta = {k: v for k, v in j.items() if k.startswith("__")}
say("=== patch.json metadata ===")
for k, v in meta.items():
    say("  %-20s %s" % (k, v))
files = {k: v for k, v in j.items() if not k.startswith("__")}
say("  file entries: %d" % len(files))
say("  sample entries:")
for k in list(files)[:6]:
    say("     %-40s %s" % (k, str(files[k])[:160]))

say()
say("=== are the v1021 files full sources or diffs? ===")
for rel in ["js/main.min.js", "js/default.thm.js", "index.html"]:
    p = os.path.join(CDN, "v1021", rel)
    if not os.path.isfile(p):
        say("  %-24s MISSING" % rel)
        continue
    b = open(p, "rb").read()
    head = b[:120].decode("utf-8", "replace").replace("\n", "\\n")
    say("  %-24s %8d bytes  head=%s" % (rel, len(b), head[:100]))

say()
say("=== so: which ProtocolList does v1021 really carry? ===")


def protolist(path):
    if not os.path.isfile(path):
        return None
    s = io.open(path, encoding="utf-8", errors="replace").read()
    i = s.find("ProtocolList")
    if i < 0:
        return None
    # the table is one big object literal; grab a wide window and pull the keys
    seg = s[i:i + 120000]
    return set(re.findall(r"([a-z][a-z0-9_]{2,})\s*:\s*\[\[", seg))


po = protolist(os.path.join(ROOT, "work", "run", "web", "js", "main.min.js"))
pn = protolist(os.path.join(CDN, "v1021", "js", "main.min.js"))
say("  ours  : %d commands" % (len(po or [])))
say("  v1021 : %d commands" % (len(pn or [])))
if po and pn:
    say("  only in v1021: %s" % (", ".join(sorted(pn - po)) or "NONE"))
    say("  only in ours : %s" % (", ".join(sorted(po - pn)) or "NONE"))

say()
say("=== index.html: what does the archived v1021 page load? ===")
ih = os.path.join(CDN, "v1021", "index.html")
if os.path.isfile(ih):
    t = io.open(ih, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r'(src|href)\s*=\s*"([^"]+)"', t):
        say("  %s = %s" % (m.group(1), m.group(2)))
    say("  mentions launcherv2: %s" % ("launcherv2" in t))
    say("  mentions hotfix    : %s" % ("hotfix" in t))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "patch_kind.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote work/logs/patch_kind.txt")
