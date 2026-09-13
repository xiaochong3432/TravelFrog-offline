#!/usr/bin/env python3
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 3），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[3]
import re
d = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js", "rb").read().decode("utf8", "replace")

targets = ["var ItemModel=function", "var BagTable=function", "var DeskTable=function",
           "var PlayerBag=function", "var AlbumView=function", "var GiftBoxAlbumView=function",
           "var TravelNoteView=function", "var TravelNoteItem=function", "var TravelModel=function",
           "var GiftBoxModel=function", "var TravelNoteModel=function", "var Result", "var AlbumPicture=function",
           "var PictureRecover=function", "var PictureModal=function", "var PictureItemRender=function",
           "var PostcardListItem=function", "var TravelDropView=function", "var TravelDropController=function",
           "var AlbumController=function", "var GiftBoxController=function", "var ItemModel",
           "var MainOutController=function"]
for t in targets:
    hits = [m.start() for m in re.finditer(re.escape(t), d)]
    print("%-34s %s" % (t, hits[:4]))

print()
for m in re.finditer(r"prototype\.(addHouseItem|consumeHouseItem|doAddHouseItem|renderItem|updateRedot|checkPictureInfoPage|album_load|album_load_all|album_load_by_id_list|album_load_new|album_load_recover|album_save_new|album_delete|album_delete_new|album_recover|travel_load_gift|travel_load_note|travel_read_note|gift_to_album|gift_to_bag|delete_album|putPicturesToGiftBox|recoverPictureInfo|deleteNewPictureInfo|saveNewPictureInfo|deletePictureInfo|requestAlbum|requestPagePictures|createPage|updateAlbum)", d):
    print("%-28s @%d" % (m.group(1), m.start()))
