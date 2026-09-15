#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
d = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js", "rb").read().decode("utf8", "replace")
for k in ["client_load_events", "sendReadNote", "update", "numsPageItem", "deleteAllAdsPicture",
          "getFirstNewPictureInfo", "onComplete", "init", "updateData", "getErrorInfo",
          "setPictureID", "on_l_picture_change", "commitProperties", "setData", "album_delete",
          "album_save_new", "album_recover", "travel_read_note", "item_load_items"]:
    hits = [m.start() for m in re.finditer(r"prototype\." + re.escape(k) + r"\s*=", d)]
    print("%-24s %s" % (k, hits))
