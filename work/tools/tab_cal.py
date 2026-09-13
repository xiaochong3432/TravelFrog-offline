#!/usr/bin/env python3
"""Tabulate a calendar sweep log written by cdp_drive (the JSON block after the
'in:' marker)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import json
import sys

path = sys.argv[1] if len(sys.argv) > 1 else str(PROJECT_ROOT) + "/work/logs/sw2.log"
t = io.open(path, encoding="utf-8", errors="replace").read()

start = t.find("=== in:")
start = t.find("\n", start) + 1
# the payload starts at the first '{' after the marker and ends at the last '}'
a = t.find("{", start)
# find the LAST brace before the '=== SUMMARY' marker (or EOF)
end = t.find("=== SUMMARY", a)
b = t.rfind("}", a, end if end > 0 else len(t))
d = json.loads(t[a:b + 1])

print("%-10s %-5s %-6s %-8s %-9s %-7s %-8s %s" %
      ("month", "maxD", "fWeek", "sched", "numWrong", "wkMism", "noIcon", "ring"))
for r in d.get("months", []):
    print("%04d-%02d    %-5s %-6s %-8s %-9s %-7s %-8s %s %s" %
          (r["y"], r["m"], r.get("maxDay"), r.get("firstWeek"), r.get("scheduled"),
           r.get("numberWrongCell"), r.get("weekdayMismatch"), r.get("daysWithoutIcon"),
           r.get("ringCorrect"), r.get("ringCell")))

print("\nBAD (%d):" % len(d.get("bad", [])))
for r in d.get("bad", []):
    print("  %04d-%02d fWeek=%s clientFWeek=%s maxDay=%s clientMaxDay=%s "
          "numWrong=%s wkMism=%s noIcon=%s ring=%s"
          % (r["y"], r["m"], r.get("firstWeek"), r.get("clientFirstWeek"),
             r.get("maxDay"), r.get("clientMaxDay"), r.get("numberWrongCell"),
             r.get("weekdayMismatch"), r.get("daysWithoutIcon"), r.get("ringCorrect")))
    for e in (r.get("examples") or [])[:3]:
        print("       day %s should be in cell %s but holds %s" % (e["d"], e["key"], e["got"]))
