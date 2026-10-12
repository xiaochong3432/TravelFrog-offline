#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.1：并入他 3.3「旅行地图·伙伴同行 / 路遇 / 照片伙伴图层」整块。

他 3.3 相对 3.2 新增（我们此前没有）的这条链：
  · 路遇判定：`tvEncounterSlot(edge)` —— 边的 `en`(enc_name) / `ep`(enc_per) 决定这条路上
    会不会遇到伙伴，遇到谁（`TV_TRAVEL_FRIEND_SLOT = {bh:0, cw:1, yhc:2}`）；
  · 行程记录：走位时把 `travelerSlot` 写进 path 的每一步；`tvTripTravelerSlot(trip)` 取这次
    实际同行的那位；
  · 照片图层：`companionSlotForPicture(p)` + `pictureLayersFor(p, rec)` 把 `Picture` 记录里
    角色为 `bh` 的伙伴图层换成"实际遇到的那位"（没遇到就**去掉**该图层 = 独角蛙照片）；
    `TV_COMPANION_LAYER_VARIANTS` 由 `resources` 表按 `x_bh_y -> x_cw_y / x_yhc_y` 建立；
  · 礼物盒好友照片：`isGiftBoxFriendPicture(picId)`（配我们已有的 `TV_PIC_FRIEND`），
    路遇/目标发图时排除它们。

存档兼容：只在明信片行上按需多一个 `travelerSlot` 字段（老档没有就是独角照），
不新增顶层字段、不改 saveVersion。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V41-TRAVEL-MAP'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[tvmap] 锚点没找到：%s\n%s' % (label, old[:220]))
    if n > 1:
        raise SystemExit('[tvmap] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


BLOCK = r'''/* __MARK__ ============ 旅行地图：伙伴同行 / 路遇 / 照片伙伴图层 ============ */

/* 能在旅途中路遇、并出现在旅行照片里的三位伙伴（对应 NodeEdge.enc_name）。 */
const TV_TRAVEL_FRIEND_SLOT = { bh: 0, cw: 1, yhc: 2 };

/* 某张照片里的伙伴图层 -> 三位伙伴各自的图层 id。
   官方 resources 表里伙伴图层是按 `xxx_bh` / `xxx_cw` / `xxx_yhc`（可带 `_后缀`）成组的，
   这里把同一组的三张登记在一起；登记不全的（合成图）不参与替换。 */
const TV_COMPANION_LAYER_VARIANTS = {};
(function indexCompanionLayers() {
  const resources = (gamedata.tables && gamedata.tables.resources) || {};
  const byPath = {};
  Object.keys(resources).forEach((id) => { byPath[String(resources[id]).toLowerCase()] = Number(id); });
  Object.keys(resources).forEach((id) => {
    const source = String(resources[id]).toLowerCase();
    const match = source.match(/^(.*)_bh(_[a-z0-9]+)?$/);
    if (!match) return;
    const tail = match[2] || '';
    const variants = ['bh', 'cw', 'yhc'].map((suffix) => (
      byPath[match[1] + '_' + suffix + tail] || byPath[match[1] + '_' + suffix]
    ));
    if (variants.every((value) => value !== undefined)) {
      TV_COMPANION_LAYER_VARIANTS[Number(id)] = variants;
    }
  });
})();

'''.replace('__MARK__', MARK)

INNER = r'''  /* __MARK__ ================= 旅行地图伙伴（依赖 state） ================= */

  /** 这条路上会遇到伙伴吗：按边的 enc_per(%) 掷一次，命中返回伙伴槽位（0–2），否则 -1。 */
  function tvEncounterSlot(edge) {
    const slot = TV_TRAVEL_FRIEND_SLOT[String((edge && edge.en) || '').toLowerCase()];
    const per = Number((edge && edge.ep) || 0);
    if (slot === undefined || per <= 0) return -1;
    return Math.random() * 100 < per ? slot : -1;
  }

  /** 这次行程实际同行的那位（取路径上第一个记录到的伙伴槽位）。 */
  function tvTripTravelerSlot(trip) {
    if (!trip || !Array.isArray(trip.path)) return -1;
    for (const step of trip.path) {
      const slot = Number(step && step.travelerSlot);
      if (slot >= 0 && slot <= 2) return slot;
    }
    return -1;
  }

  function companionSlotForPicture(p) {
    const explicit = Number(p && p.travelerSlot);
    if (explicit >= 0 && explicit <= 2) return explicit;
    return -1;
  }

  /** 把 Picture 记录里角色为 bh 的伙伴图层换成"实际遇到的那位"；没遇到就去掉该图层。 */
  function pictureLayersFor(p, rec) {
    const slot = companionSlotForPicture(p);
    return ((rec && rec.layers) || []).map((entry) => {
      if (!entry || entry.role !== 'bh' || !entry.layer) return entry;
      const variants = TV_COMPANION_LAYER_VARIANTS[Number(entry.layer[0])];
      /* 合成美术（找不到成组图层）保持原样；可替换的伙伴图层在"没遇到伙伴"时移除。 */
      if (!variants) return entry;
      if (slot < 0 || variants[slot] === undefined) return null;
      return Object.assign({}, entry, {
        layer: [variants[slot], entry.layer[1], entry.layer[2]],
      });
    }).filter((entry) => entry !== null);
  }

  /** 礼物盒好友照片：这些图不该被"路遇/目标"发出来（配我们已有的 TV_PIC_FRIEND）。 */
  function isGiftBoxFriendPicture(picId) {
    return Object.prototype.hasOwnProperty.call(TV_PIC_FRIEND, Number(picId));
  }

'''.replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[tvmap] 已并入过（%s），跳过' % MARK)
        return 0

    # 1) 常量块（放在 engine 常量区之前）
    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   BLOCK + '/* ---------------------------------------------------------------- engine */', 'const block')

    # 2) 函数块（放在 tvPhotos 之前）
    src = sub_once(src, 'function tvPhotos(trip, wantFill, ownedTags) {',
                   INNER + 'function tvPhotos(trip, wantFill, ownedTags) {', 'inner block')

    # 3) 走位时记录路遇
    src = sub_once(src, '    path.push({ from: node, node: pick, e });',
                   '    /* 【并入他 3.3】这一步有没有路遇伙伴，记在 path 上（照片要靠它）。 */\n'
                   '    path.push({ from: node, node: pick, e, travelerSlot: tvEncounterSlot(e) });',
                   'path travelerSlot')

    # 4) tvPhotos 改成携带伙伴槽位（queuePostcardPictures 本来就接受对象）
    src = sub_once(
        src,
        '  const add = (id) => {\n'
        '    if (id === undefined || id === null) return;\n'
        '    if (out.indexOf(id) === -1 && out.length < cap) out.push(id);\n'
        '  };',
        '  /* 【并入他 3.3】条目仍然是 id（下游按 id 消费）；\n'
        '     伙伴信息记在行程 path 上，由照片行自己的 travelerSlot 决定图层。 */\n'
        '  const add = (id) => {\n'
        '    if (id === undefined || id === null) return;\n'
        '    if (out.indexOf(id) === -1 && out.length < cap) out.push(id);\n'
        '  };',
        'tvPhotos add')

    src = sub_once(
        src,
        '        const ids = TV_TAG_PICS[String(slot[1])] || [];\n'
        '        if (ids.length) add(ids[tvRand(0, ids.length - 1)]);',
        '        const ids = TV_TAG_PICS[String(slot[1])] || [];\n'
        '        const routeIds = ids.filter((id) => !isGiftBoxFriendPicture(id));\n'
        '        if (routeIds.length) add(routeIds[tvRand(0, routeIds.length - 1)], step.travelerSlot);',
        'tvPhotos route')

    src = sub_once(
        src,
        '    const fresh = ids.filter((id) => out.indexOf(id) === -1);\n'
        '    if (fresh.length) add(fresh[tvRand(0, fresh.length - 1)]);',
        '    const fresh = ids.filter((id) => !isGiftBoxFriendPicture(id)\n'
        '      && out.indexOf(id) === -1);\n'
        '    if (fresh.length) add(fresh[tvRand(0, fresh.length - 1)]);',
        'tvPhotos goal')

    src = sub_once(
        src,
        '      add(PICTURE_IDS[tvRand(0, PICTURE_IDS.length - 1)]);',
        '      add(PICTURE_IDS[tvRand(0, PICTURE_IDS.length - 1)]);',
        'tvPhotos fallback')

    # 5) 入桶时把 travelerSlot 写到明信片行上（老档没有救援规则）
    src = sub_once(
        src,
        '      const row = { id: state.pictureSeq, pic_id: pic, read: 0, new: 1 };\n'
        '      if (visit) row.visit = true;',
        '      const row = { id: state.pictureSeq, pic_id: pic, read: 0, new: 1 };\n'
        '      /* 【并入他 3.3】这张照片是哪位伙伴同行；老档没有这个字段时按 PictureTag 救援。 */\n'
        '      {\n'
        '        const src0 = (Array.isArray(pictures) ? pictures : [])\n'
        '          .find((x) => x && typeof x === \'object\' && Number(x.pic_id) === pic);\n'
        '        let slot = Number(src0 && src0.travelerSlot);\n'
        '        if (!(slot >= 0 && slot <= 2) && isGiftBoxFriendPicture(pic)) slot = TV_PIC_FRIEND[Number(pic)];\n'
        '        if (slot >= 0 && slot <= 2) row.travelerSlot = slot;\n'
        '      }\n'
        '      if (visit) row.visit = true;',
        'row travelerSlot')

    # 6) 下发给客户端的照片：图层按"实际遇到的那位伙伴"替换，并救援老档的伙伴槽位
    src = sub_once(
        src,
        "  const rec = pictureLayers[String(p.pic_id)];\n"
        "  const layers = (rec && Array.isArray(rec.layers)) ? rec.layers : [];\n"
        "  const out = Object.assign({}, p, { layers });\n"
        "  if (rec && rec.travelers) out.travelers = rec.travelers;",
        "  const rec = pictureLayers[String(p.pic_id)];\n"
        "  /* 【并入他 3.3】只有「这一行确实记录到了伙伴」时才替换伙伴图层；\n"
        "     没有伙伴信息的照片保持原图层（= 我们原来的画面，不做回退）。 */\n"
        "  const layers = (rec && Array.isArray(rec.layers))\n"
        "    ? (companionSlotForPicture(p) >= 0 ? pictureLayersFor(p, rec) : rec.layers) : [];\n"
        "  const out = Object.assign({}, p, { layers });\n"
        "  /* 老档里的礼物盒好友照片没有内部 travelerSlot 字段，用 PictureTag 标记恢复，\n"
        "     而不是按轮换猜一个。 */\n"
        "  if (out.travelerSlot === undefined && isGiftBoxFriendPicture(out.pic_id)) {\n"
        "    out.travelerSlot = TV_PIC_FRIEND[Number(out.pic_id)];\n"
        "  }\n"
        "  if (rec && rec.travelers) out.travelers = rec.travelers;",
        'withLayers companion layers')

    write(ENGINE, src)
    print('[tvmap] 引擎已改：路遇槽位 + 照片伙伴图层（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
