#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Payload check for the 足迹地图 work: the shipped APK must carry the offline page,
its data file, and the shell hook that reveals the album's 地图 button."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import sys
import zipfile

APK = str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk"
OUT = str(PROJECT_ROOT) + "/work/logs/check_map_payload.txt"

NEED = {
    "assets/game/map.html": ["蛙蛙的旅行地图", "不使用任何行政区划界线"],
    "assets/game/map_data.json": ["museumProvinces"],
    "assets/game/__probe.js": ["openMapOverlay", "getAnnInfo", "TravelMapController",
                               "MAP_PAGE"],
    "assets/game/__offline-engine.js": ["acquireProvinces"],
}

out = io.open(OUT, "w", encoding="utf-8")
z = zipfile.ZipFile(APK)
names = set(z.namelist())
out.write("apk: %s (%d entries)\n" % (APK, len(names)))
bad = 0
for path, needles in NEED.items():
    if path not in names:
        out.write("  MISSING  %s\n" % path)
        bad += 1
        continue
    raw = z.read(path)
    text = raw.decode("utf-8", "replace")
    miss = [n for n in needles if n not in text]
    if miss:
        out.write("  NO MARK  %s (%d bytes) missing %r\n" % (path, len(raw), miss))
        bad += 1
    else:
        out.write("  ok       %s (%d bytes) marks %r\n" % (path, len(raw), needles))

# the province data must actually be the game's own 33 provinces
data = json.loads(z.read("assets/game/map_data.json").decode("utf-8"))
out.write("\nprovinces: %d, museums: %d, flower arts: %d\n"
          % (len(data["provinces"]), len(data["museumProvinces"]),
             sum(1 for p in data["provinces"] if p["flower"])))
if len(data["provinces"]) != 33:
    out.write("  BAD: expected 33 provinces\n")
    bad += 1

# the flower art the page points at must be in the APK
missing_art = [p["flower"] for p in data["provinces"]
               if p["flower"] and not any(n.endswith("flower/" + p["flower"]) for n in names)]
out.write("flower art present: %d/%d\n"
          % (len(data["provinces"]) - len(missing_art), len(data["provinces"])))
if missing_art:
    out.write("  MISSING ART: %r\n" % missing_art)
    bad += 1

out.write("\nRESULT: %s\n" % ("OK" if bad == 0 else "FAIL (%d)" % bad))
out.close()
print("wrote logs/check_map_payload.txt -> %s" % ("OK" if bad == 0 else "FAIL"))
sys.exit(0 if bad == 0 else 1)
