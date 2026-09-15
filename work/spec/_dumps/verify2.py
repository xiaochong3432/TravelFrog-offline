#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
d = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js", "rb").read().decode("utf8", "replace")

strict = ["album_load", "album_load_all", "album_load_by_id_list", "album_load_new",
          "album_load_recover", "album_save_new", "album_delete", "album_delete_new",
          "album_recover", "travel_load_gift", "travel_load_note", "travel_read_note",
          "gift_to_album", "gift_to_bag", "delete_album", "item_load_items", "update",
          "selectGroupChange", "on_RecoverBtn", "deletePicture", "putPictureToGiftBox",
          "setBagData", "setDeskData", "updatePic", "onItemTap", "on_popBtn", "on_deleteBtn"]
for k in strict:
    hits = [m.start() for m in re.finditer(r"prototype\." + re.escape(k) + r"\s*=", d)]
    print("%-26s %s" % (k, hits))

print()
# enclosing class name for each renderItem / key offsets
classes = [(m.start(), m.group(1)) for m in re.finditer(r"var\s+([A-Za-z0-9_$]+)\s*=\s*function", d)]
def enc(off):
    prev = None
    for s, n in classes:
        if s < off:
            prev = (s, n)
        else:
            break
    return prev
for off in [431561, 435619, 549327, 1028064, 1104839, 475612, 475838, 477439, 485000]:
    print(off, enc(off))
