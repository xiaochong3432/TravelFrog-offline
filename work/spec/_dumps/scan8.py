#!/usr/bin/env python3
import re
JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for k in ["backImage", "frontImage", "frogPose", "travelerPose", "PictureDB", "ResourcesDB", "getPicturePath", "formatPathImage"]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s (%d) %s" % (k, len(hits), hits[:12]))
    for h in hits[:3]:
        print("     @%d %s" % (h, d[max(0, h - 200):h + 200]))
