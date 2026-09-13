#!/usr/bin/env python3
import re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

pats = [
    "loadPicture", "getPictureTexture", "picture_loader", "PictureRes",
    "layers", "pic_id", "CollectDB", "collect", "ItemType=",
    "TravelNoteDB", "note_list", "note_type",
]
for k in pats:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s  (%d)  %s" % (k, len(hits), hits[:22]))
