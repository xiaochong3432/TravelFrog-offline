#!/usr/bin/env python3
"""Find the announcement service's gameId inside the ORIGINAL apk.

The client builds it as `https://<gameId>-launcher.ejoy.com/ann/v2/ticket/...`, and the
value is injected by the native shell (`jsInvokeLua("gangplank","autoconfig",["",gameId])`),
so it is not in the H5 bundle. Scanning the apk's own text should reveal it -- and if that
host still resolves, the official activity/公告 data (including the album's 地图 URL) may
still be fetchable before the shut-down.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import re
import zipfile

APK = str(PROJECT_ROOT) + "/base.apk"
NEEDLES = [b"launcher.ejoy.com", b"-launcher", b"gameId", b"game_id", b"lxqw", b"lingxi"]
out = io.StringIO()

zf = zipfile.ZipFile(APK)
names = zf.namelist()
out.write("apk entries: %d\n" % len(names))
hits = {}
for n in names:
    if n.startswith("assets/game/"):
        continue
    try:
        data = zf.read(n)
    except Exception:
        continue
    for nd in NEEDLES:
        for m in re.finditer(re.escape(nd), data):
            a = max(0, m.start() - 60)
            snippet = data[a:m.start() + 120]
            txt = "".join(chr(c) if 32 <= c < 127 else "." for c in snippet)
            hits.setdefault(nd.decode(), []).append((n, txt))
out.write("entries with hits: %d\n\n" % len(hits))
for nd in NEEDLES:
    k = nd.decode()
    rows = hits.get(k, [])
    out.write("=== %s : %d hits\n" % (k, len(rows)))
    seen = set()
    for n, txt in rows[:14]:
        if (n, txt) in seen:
            continue
        seen.add((n, txt))
        out.write("  %-46s %s\n" % (n, txt))
    out.write("\n")

sys_out = io.open(str(PROJECT_ROOT) + "/work/logs/apk_gameid.txt", "w", encoding="utf-8")
sys_out.write(out.getvalue())
print("wrote logs/apk_gameid.txt")
