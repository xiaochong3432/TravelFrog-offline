#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re, sys

JS = str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

pats = [
    'send("album_load_new"', 'send("album_load_recover"', 'send("album_load_all"',
    'send("album_load_by_id_list"', 'send("album_load"', 'send("travel_read_note"',
    'send("travel_load_note"', 'send("travel_load_gift"', 'send("album_save_new"',
    'send("album_delete"', 'send("album_delete_new"', 'send("album_recover"',
    'album_load_new', 'album_load_recover',
    'TravelEventType.updateNewAlbum', 'TravelEventType.updateRecover',
    'TravelEventType.addPicture', 'TravelEventType.updateAlbumContent',
    'TravelEventType.updateAlbum', 'TravelEventType.deletePicture',
    'updateRedot', 'TravelNoteEventType',
]
for k in pats:
    hits = [m.start() for m in re.finditer(re.escape(k), d)]
    print("== %s  (%d)" % (k, len(hits)))
    for h in hits[:14]:
        print("   [%d] %s" % (h, d[max(0, h-140):h+140]))
