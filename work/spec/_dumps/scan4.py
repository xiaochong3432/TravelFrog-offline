#!/usr/bin/env python3
import re
JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")
for k in ["eab", "EAB", "eab_asset", "decrypt", "Decrypt", "xxtea", "XXTEA"]:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s (%d) %s" % (k, len(hits), hits[:20]))
