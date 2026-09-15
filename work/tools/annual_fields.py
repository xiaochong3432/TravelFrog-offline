#!/usr/bin/env python3
"""List every payload field the annual-review pages read.

Also reports whether an animation/review asset declares a hardcoded year, so the
"2022" the player sees can be traced to art or to data.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os
import re

JS = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"

with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()

start = s.find("AnnualReviewViewControl=function")
end = s.find("AchieveItemView=function", start)
region = s[start:end]
print("annual-review region: %d..%d (%d chars)\n" % (start, end, len(region)))

# payload reads are on the page data object, named `t` in ChatPage/FinishPage
fields = {}
for m in re.finditer(r"\bt\.([A-Za-z_][A-Za-z0-9_]*)", region):
    fields[m.group(1)] = fields.get(m.group(1), 0) + 1
skip = {"data", "length", "push", "addEventListener", "enabled", "onNext", "start",
        "scroller", "list", "chats", "showChats", "pageGroup", "btnClose", "close",
        "dispatchEventWith", "parent", "addChild", "removeChild", "x", "y", "width",
        "height", "visible", "name", "source", "text", "valign", "algin", "skinName",
        "currentState", "validateProperties", "numChildren", "getChildAt", "stage",
        "canTap", "on_tap", "addChildAt", "setChildIndex", "once", "call", "Tween",
        "getTimer", "touchBeginPoint", "lastNextTime", "curPageIndex", "isMoving"}
payload = sorted(k for k in fields if k not in skip)
print("payload fields read by the review pages (%d):" % len(payload))
for k in payload:
    print("   %-22s x%d" % (k, fields[k]))

# is a literal 4-digit year anywhere in the region?
years = re.findall(r"(?<![0-9])(19|20)\d{2}(?![0-9])", region)
print("\n4-digit years found in the region: %s" % (years or "NONE"))

# and in the theme file?
THEME = str(PROJECT_ROOT) + "/work/run/web/js/default.thm.js"
with open(THEME, encoding="utf-8", errors="replace") as fh:
    th = fh.read()
i = th.find("AnnualReviewStartPageSkin.exml")
seg = th[i:i + 6000]
print("years in the StartPage skin: %s" % (re.findall(r"(?<![0-9])(?:19|20)\d{2}(?![0-9])", seg) or "NONE"))
