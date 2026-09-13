#!/usr/bin/env python3
"""Compare the v1001 (APK) and v1021 (CDN) client builds for offline compatibility.

Checks:
  * protocol command sets (our engine implements against v1001's table)
  * whether our patch anchors still exist in v1021
  * whether offline-critical symbols are present
"""
import re, json, os

V1001 = r"H:\AI\frog\work\run\web\js\main.min.js"
V1001_CLEAN = r"H:\AI\frog\work\run\web\js\main.min.js.clean"
V1021 = r"H:\AI\frog\work\cdn\v1021\js\main.min.js"

ENTRY = re.compile(r'([A-Za-z_][A-Za-z0-9_]{2,40})\s*:\s*\[\[([^\]]*)\]\s*,\s*!(0|1)\s*\]')


def protocol_of(path):
    d = open(path, "rb").read().decode("utf8", "replace")
    i = d.find("protocolList={")
    if i < 0:
        return None, d
    start = d.index("{", i)
    depth = 0
    for j in range(start, len(d)):
        if d[j] == "{":
            depth += 1
        elif d[j] == "}":
            depth -= 1
            if depth == 0:
                break
    raw = d[start:j + 1]
    names = set()
    for m in ENTRY.finditer(raw):
        names.add(m.group(1))
    return names, d


p1, d1 = protocol_of(V1001)
p2, d2 = protocol_of(V1021)
print(f"protocol commands: v1001={len(p1 or [])}  v1021={len(p2 or [])}")

if p1 and p2:
    only1 = sorted(p1 - p2)
    only2 = sorted(p2 - p1)
    print(f"  shared            : {len(p1 & p2)}")
    print(f"  only in v1001     : {len(only1)} {only1[:12]}")
    print(f"  only in v1021     : {len(only2)} {only2[:12]}")

print("\n--- patch anchors / offline-critical symbols ---")
checks = {
    "season clamp anchor (we patch this)":
        'getSeasonKey=function(){return this.data.season+""+this.data.hours_type}',
    "enterGame gate (must stay intact)":
        "this.loadComplete&&NetworkControl.getInstance().isSyncComplete()&&GameConfig.activate&&",
    "core.Socket seam":
        "__reflect(i.prototype,\"core.Socket\")",
    "SocketManage.createSocketByUrl":
        "createSocketByUrl=function",
    "MainOutView checkGuide":
        "checkGuide=function",
    "GameConfig.activate":
        "GameConfig.activate",
    "showGM red square hook":
        "GameConfig.showGM",
}
for label, needle in checks.items():
    print(f"  {label:<38} v1001={'YES' if needle in d1 else 'no ':<4} "
          f"v1021={'YES' if needle in d2 else 'no '}")

print("\n--- key protocol messages our engine pushes ---")
for cmd in ["client_load_role", "weather_load", "clover_load_clovers", "item_load_items",
            "notify_new_event", "clover_update", "travel_load_gift", "client_gm",
            "hall_gen_token", "hall_enter_game", "item_load_shop_info"]:
    print(f"  {cmd:<24} v1001={'YES' if cmd in d1 else 'no ':<4} v1021={'YES' if cmd in d2 else 'no '}")

# also: does v1021 still carry the __reflect names we rely on?
print("\n--- GUID/loader symbols ---")
for sym in ["MainOutController", "WebLoadingController", "GuideNamedView", "Tabikaeru.DataManager"]:
    print(f"  {sym:<26} v1001={'YES' if sym in d1 else 'no ':<4} v1021={'YES' if sym in d2 else 'no '}")
