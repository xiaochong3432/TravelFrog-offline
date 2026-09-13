#!/usr/bin/env python3
import re
d = open(r"H:\AI\frog\work\base\assets\game\js\main.min.js", "rb").read().decode("utf8", "replace")
for k in ["client_load_events", "sendReadNote", "update", "numsPageItem", "deleteAllAdsPicture",
          "getFirstNewPictureInfo", "onComplete", "init", "updateData", "getErrorInfo",
          "setPictureID", "on_l_picture_change", "commitProperties", "setData", "album_delete",
          "album_save_new", "album_recover", "travel_read_note", "item_load_items"]:
    hits = [m.start() for m in re.finditer(r"prototype\." + re.escape(k) + r"\s*=", d)]
    print("%-24s %s" % (k, hits))
