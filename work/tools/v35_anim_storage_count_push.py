#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.5：动态照片界面的「照片存储开启物」数量不跟着变，要重启才更新。

根因：展示页那行字是
    this.lbItem.text = "持有" + (ItemModel.getHouseItemCount(9002) + data.item_num) + "个"
（AnimPictureShowPage.updatePic()，客户端 main.min.js 里逐字核对过），所以只要引擎改了 9002 的
持有数就必须主动推给客户端。而动态照片这条线上有三个地方会改它：
  · animpicture_use_item   扣显影液 —— 我们早前已经补了 item_load_items ✔
  · animpicture_open_album 扣 1 个「照片存储开启物」—— **没推** ❌
  · animpicture_get_item   一页做完，把 item_num 个存储券真正入屋 —— **没推** ❌
后两处只有等下次登录（客户端重新请求 item_load_items）才刷新，也就是玩家看到的"重启后才对"。

修法：两处都按 use_item 的写法补推 item_load_items（全量）+ item_update（单项增量，
客户端按它与自己当前数量的差值增减，重复推送不会翻倍）。
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parents[2]
ENGINE = ROOT / "work/build/v4_engine/index.js"

eng = ENGINE.read_bytes().decode("utf-8")
MARK = "存储券的持有数必须主动推给客户端"
if MARK in eng:
    print("引擎里已经有这两处推送，跳过")
    sys.exit(0)

PUSH = """      /* 存储券的持有数必须主动推给客户端：展示页那行「持有 N 个」是
         `ItemModel.getHouseItemCount(9002) + data.item_num`，引擎改了 9002 而不推，
         界面就一直显示旧数字，只有重启（重新请求 item_load_items）才更新
         —— 2026-09-19 玩家反馈。item_load_items 是全量、item_update 是单项增量，
         客户端 item_update 按"与当前数量的差值"增减，所以两个一起推不会翻倍。 */
      try { ctx.push('item_load_items', handlers.item_load_items()); } catch (e) { /* 推送失败不影响本步 */ }
      ctx.push('item_update', { item: { item_id: ANIM_STORAGE_ITEM, count: getHaveItem(ANIM_STORAGE_ITEM) } });
"""

edits = [
    ("animpicture_open_album 扣券后推送",
     """      while (page.pictures.length < page.putNum) page.pictures.push({ id: 0, pic_id: 0, layers: [] });
      save();
      return { code: 0 };""",
     """      while (page.pictures.length < page.putNum) page.pictures.push({ id: 0, pic_id: 0, layers: [] });
      save();
""" + PUSH + """      return { code: 0 };"""),
    ("animpicture_get_item 入屋后推送",
     """        A.collected = (A.collected || 0) + A.itemNum;
        A.itemNum = 0;
        save();
      }
      return { code: 0 };""",
     """        A.collected = (A.collected || 0) + A.itemNum;
        A.itemNum = 0;
        save();
""" + PUSH + """      }
      return { code: 0 };"""),
]

for name, old, new in edits:
    n = eng.count(old)
    if n != 1:
        sys.exit("引擎锚点【%s】出现 %d 次" % (name, n))
    eng = eng.replace(old, new, 1)
    print("引擎已改：", name)

ENGINE.write_text(eng, encoding="utf-8", newline="")
print("写出 %s（%d 行）" % (ENGINE.relative_to(ROOT), len(eng.split("\n"))))
