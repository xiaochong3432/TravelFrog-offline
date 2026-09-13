#!/usr/bin/env python3
import re
JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for k in ["pushNewPictureIDs", "getErrorInfo", "newPictureIDs", "for_ads", "visted_pic",
          "has_ads", "is_share", "notify_redmsg", "redmsg"]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s (%d) %s" % (k, len(hits), hits[:14]))
    for h in hits[:5]:
        print("     @%d %s" % (h, d[max(0, h - 200):h + 200]))
