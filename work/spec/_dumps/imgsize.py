#!/usr/bin/env python3
"""Check sizes of the base picture images + look up a few item ids."""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import json, os, struct, io, collections

ROOT = str(PROJECT_ROOT) + "/work/run/web/resource/China/images"
B = str(PROJECT_ROOT) + "/work/spec/_dumps/tables/%s.json"
out = io.open(str(PROJECT_ROOT) + "/work/spec/_dumps/imgsize.txt", "w", encoding="utf8")


def png_size(p):
    with open(p, "rb") as f:
        h = f.read(24)
    if h[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", h[16:24])


res = json.load(open(B % "resources", encoding="utf8"))
sizes = collections.Counter()
byid = {}
for k, v in res.items():
    p = os.path.join(ROOT, v.replace("/", os.sep) + ".png")
    if os.path.exists(p):
        s = png_size(p)
        byid[k] = (v, s)
        sizes[s] += 1
out.write("### resource id -> (path, size) histogram of unique sizes\n")
out.write("%s\n" % sizes.most_common(15))
for k in ["0", "1", "2", "3", "5", "100", "200"]:
    out.write("  %s -> %s\n" % (k, byid.get(k)))

pic = json.load(open(B % "Picture", encoding="utf8"))
names = collections.Counter()
for e in pic:
    for n in e["backImage"] + e["frontImage"]:
        names[n] += 1
out.write("\n### distinct backImage/frontImage names: %d\n" % len(names))
out.write("%s\n" % names.most_common(30))

# name -> resource ids
idx = collections.defaultdict(list)
for k, v in res.items():
    idx[v.split("/")[-1]].append((int(k), v))
out.write("\n### name -> resIds for the top names\n")
for n, c in names.most_common(25):
    out.write("  %-24s x%-3d -> %s\n" % (n, c, idx.get(n, [])[:6]))

item = json.load(open(B % "Item", encoding="utf8"))
byid2 = {e["id"]: e for e in item}
out.write("\n### item lookups\n")
for i in [2066, 3014, 0, 1, 2, 1000, 2000, 3000]:
    e = byid2.get(i)
    out.write("  %s -> %s\n" % (i, json.dumps(e, ensure_ascii=False) if e else None))
out.write("\nitem ids by type:\n")
byt = collections.defaultdict(list)
for e in item:
    byt[e.get("type")].append(e["id"])
for t in sorted(byt, key=lambda x: (x is None, x)):
    out.write("  type %-3s (%3d): %s\n" % (t, len(byt[t]), byt[t][:25]))
out.close()
print("ok")
