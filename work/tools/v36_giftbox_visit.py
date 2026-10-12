#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""方案 B-1：并入「他做的 V3 包」的**礼物盒来访**（gift-box visit）。

玩家把明信片/特产放进礼物盒后，青蛙出发时有 50% 概率带走 1–3 件（`GIFTBOX_VISIT_CHANCE` /
`_MAX_SEND`）；回来时由一位**旅行伙伴**（PictureTag 里带 `_TRAVELER_ID` 标记的那三池之一）
寄来「拜访回礼」邮件：50–300 三叶草、35% 概率 1–2 张抽奖券、65% 概率一份礼物
（草莓汁/苹果汁/任一种特产），外加 1–2 张**该伙伴系列、优先你没收集过**的明信片。

为什么可以纯引擎侧做：这套东西全部走**已有协议** —— 拿走时推 `travel_load_gift`，
回来时推 `notify_new_mail` + `mail_load`；我们引擎的邮件结构（`makeMail`）本来就有
`pictures` 字段，客户端 `checkMailItemType` 也是拿 `e.pictures.length` 判红点的，
所以数据通路不需要改客户端。（他的客户端里那份 23 KB overlay 只是把这张邮件换成他自绘的
卡片，属于外观选项，本次不并。）

出处（逐行对照他引擎 work/build/his3/engine_live/index.js）：TV_PIC_FRIEND 索引 250-271、
常量 1079-1088、takeGiftBoxVisitGifts 2817-2852、rollGiftBoxVisitReply 2854-2893、
出发时取走 4610-4611/4657、回来时发信 4748-4765/4794-4797。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')

MARK = 'V36-GIFTBOX-VISIT'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[giftbox] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[giftbox] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[giftbox] 已并入过（%s），跳过' % MARK)
        return 0

    # ------------------------------------------------ 1. 伙伴明信片反查表
    src = sub_once(
        src,
        'const TV_TAG_PICS = {};\nconst TV_PIC_TAG = {};\n'
        '(function tvIndexPictures() {\n'
        '  const byName = {};\n'
        '  tvRows(\'Picture\').forEach((p) => { if (p && p.name !== undefined) byName[p.name] = p.id; });',
        'const TV_TAG_PICS = {};\nconst TV_PIC_TAG = {};\n'
        '/* %s PictureTag 的 picNames 里带 `_TRAVELER_ID` 标记的那些标签，属于某一位\n'
        '   旅行伙伴（0/1/2）；礼物盒来访的明信片要按伙伴分池挑，所以这里建反查表。\n'
        '   同时把 Picture 表的全部 id 收进一个 Set，用来过滤掉不在表里的 id。 */\n'
        'const TV_PIC_FRIEND = {};\nconst TV_PICTURE_IDS = new Set();\n'
        '(function tvIndexPictures() {\n'
        '  const byName = {};\n'
        '  tvRows(\'Picture\').forEach((p) => {\n'
        '    if (p && p.id !== undefined) TV_PICTURE_IDS.add(Number(p.id));\n'
        '    if (p && p.name !== undefined) byName[p.name] = p.id;\n'
        '  });' % MARK,
        'TV_PIC_FRIEND declaration')

    src = sub_once(
        src,
        '    TV_TAG_PICS[String(t.Tag)] = ids;\n'
        '    ids.forEach((id) => { TV_PIC_TAG[id] = String(t.Tag); });\n'
        '  });\n'
        '})();',
        '    TV_TAG_PICS[String(t.Tag)] = ids;\n'
        '    ids.forEach((id) => { TV_PIC_TAG[id] = String(t.Tag); });\n'
        '    const marker = (t.picNames || []).indexOf(\'_TRAVELER_ID\');\n'
        '    const friendId = marker >= 0 ? Number(t.picNames[marker + 1]) : -1;\n'
        '    if (friendId >= 0 && friendId <= 2) {\n'
        '      ids.forEach((id) => { TV_PIC_FRIEND[id] = friendId; });\n'
        '    }\n'
        '  });\n'
        '})();',
        'TV_PIC_FRIEND filling')

    # -------------------------------------------------------------- 2. 常量
    src = sub_once(
        src,
        'const STARTER_SPECIALTY_IDS = SPECIALTY_IDS.slice(0, 8);',
        'const STARTER_SPECIALTY_IDS = SPECIALTY_IDS.slice(0, 8);\n'
        '\n'
        '/* 【并入他的 V3】礼物盒来访：出发时有 %d%% 概率带走 1–3 件，回来由伙伴寄「拜访回礼」。 */\n'
        'const GIFTBOX_VISIT_CHANCE = Number(process.env.FROG_GIFTBOX_VISIT_CHANCE || 50);\n'
        'const GIFTBOX_VISIT_MAX_SEND = Number(process.env.FROG_GIFTBOX_VISIT_MAX_SEND || 3);\n'
        '/* 只有带 `_TRAVELER_ID` 标记、且确实在 Picture 表里的明信片才算"伙伴的明信片"，\n'
        '   这样伙伴的明信片组不会和别的青蛙/动物明信片混在一起。 */\n'
        'const GIFTBOX_VISIT_PICTURE_IDS = Object.keys(TV_PIC_FRIEND)\n'
        '  .map(Number)\n'
        '  .filter((id, i, a) => TV_PICTURE_IDS.has(id) && a.indexOf(id) === i);\n'
        '/* 回礼里的"东西"：两瓶饮料 + 任一种特产。 */\n'
        'const GIFTBOX_VISIT_RETURN_ITEMS = [12, 14].concat(SPECIALTY_IDS)\n'
        '  .filter((id, i, a) => ITEM_BY_ID.has(id) && a.indexOf(id) === i);' % 50,
        'visit constants')

    # ------------------------------------------------- 3. 三个函数 + 旧档归一化
    src = sub_once(
        src,
        '  function giftBoxPayload() {\n'
        '    return {\n'
        '      pictures: (state.giftBox.pictures || []).map(withLayers),\n'
        '      specialtys: (state.giftBox.specialtys || []).map((s) => ({\n'
        '        item_id: s.item_id, count: s.count,\n'
        '      })),\n'
        '    };\n'
        '  }',
        '  function giftBoxPayload() {\n'
        '    return {\n'
        '      pictures: (state.giftBox.pictures || []).map(withLayers),\n'
        '      specialtys: (state.giftBox.specialtys || []).map((s) => ({\n'
        '        item_id: s.item_id, count: s.count,\n'
        '      })),\n'
        '    };\n'
        '  }\n'
        '\n'
        '  /* ---- 礼物盒来访（并入他的 V3，2026-09-19）---------------------------------\n'
        '     旧档可能没有 giftBox（或只有一半），先补成两个数组再谈别的。 */\n'
        '  function normalizeGiftBox() {\n'
        '    if (!state.giftBox || typeof state.giftBox !== \'object\') {\n'
        '      state.giftBox = { pictures: [], specialtys: [] };\n'
        '      return true;\n'
        '    }\n'
        '    let changed = false;\n'
        '    if (!Array.isArray(state.giftBox.pictures)) { state.giftBox.pictures = []; changed = true; }\n'
        '    if (!Array.isArray(state.giftBox.specialtys)) { state.giftBox.specialtys = []; changed = true; }\n'
        '    state.giftBox.specialtys = state.giftBox.specialtys\n'
        '      .filter((s) => s && ITEM_BY_ID.has(Number(s.item_id)) && Number(s.count) > 0);\n'
        '    state.giftBox.pictures = state.giftBox.pictures\n'
        '      .filter((p) => p && TV_PICTURE_IDS.has(Number(p.pic_id)));\n'
        '    return changed;\n'
        '  }\n'
        '\n'
        '  function addGiftItem(list, itemId, count) {\n'
        '    const id = Number(itemId);\n'
        '    const n = Math.max(0, Number(count) || 0);\n'
        '    if (!(n > 0) || !ITEM_BY_ID.has(id)) return;\n'
        '    const row = list.find((x) => Number(x.item_id) === id);\n'
        '    if (row) row.count = Number(row.count) + n;\n'
        '    else list.push({ item_id: id, count: n });\n'
        '  }\n'
        '\n'
        '  /* 出发时从礼物盒里挑 1–3 件带走（明信片按张、特产按个）。返回 null = 这次不带。 */\n'
        '  function takeGiftBoxVisitGifts(t) {\n'
        '    const box = state.giftBox || { pictures: [], specialtys: [] };\n'
        '    if (!Array.isArray(box.pictures)) box.pictures = [];\n'
        '    if (!Array.isArray(box.specialtys)) box.specialtys = [];\n'
        '    const choices = [];\n'
        '    box.pictures.forEach((p, i) => { if (p) choices.push({ kind: \'picture\', index: i }); });\n'
        '    box.specialtys.forEach((s, i) => {\n'
        '      const count = Math.max(0, Number(s && s.count) || 0);\n'
        '      for (let n = 0; n < count; n++) choices.push({ kind: \'specialty\', index: i });\n'
        '    });\n'
        '    if (!choices.length) return null;\n'
        '    if (Math.random() * 100 >= GIFTBOX_VISIT_CHANCE) return null;\n'
        '    const max = Math.max(1, Math.min(Number(GIFTBOX_VISIT_MAX_SEND) || 3, choices.length));\n'
        '    const want = randInt(1, max);\n'
        '    const carried = { pictures: [], specialtys: [], at: Number(t || nowSec()) };\n'
        '    for (let n = 0; n < want && choices.length; n++) {\n'
        '      const pickAt = randInt(0, choices.length - 1);\n'
        '      const pick = choices.splice(pickAt, 1)[0];\n'
        '      if (pick.kind === \'picture\') {\n'
        '        const pic = box.pictures.splice(pick.index, 1)[0];\n'
        '        if (pic) carried.pictures.push(pic);\n'
        '        for (const c of choices) if (c.kind === \'picture\' && c.index > pick.index) c.index--;\n'
        '      } else {\n'
        '        const row = box.specialtys[pick.index];\n'
        '        if (row && Number(row.count) > 0) {\n'
        '          carried.specialtys.push({ item_id: Number(row.item_id), count: 1 });\n'
        '          row.count = Number(row.count) - 1;\n'
        '          if (row.count <= 0) {\n'
        '            box.specialtys.splice(pick.index, 1);\n'
        '            for (const c of choices) if (c.kind === \'specialty\' && c.index > pick.index) c.index--;\n'
        '          }\n'
        '        }\n'
        '      }\n'
        '    }\n'
        '    return (carried.pictures.length || carried.specialtys.length) ? carried : null;\n'
        '  }\n'
        '\n'
        '  /* 回来时的回礼：一位伙伴 + 三叶草 + 可能抽奖券 + 可能礼物 + 1–2 张该伙伴的明信片\n'
        '     （优先给还没收集过的）。 */\n'
        '  function rollGiftBoxVisitReply(carried) {\n'
        '    if (!carried) return null;\n'
        '    const pics = Array.isArray(carried.pictures) ? carried.pictures : [];\n'
        '    const specs = Array.isArray(carried.specialtys) ? carried.specialtys : [];\n'
        '    if (!pics.length && !specs.length) return null;\n'
        '    const sent = pics.length + specs.length;\n'
        '    const owned = ownedPictureIds();\n'
        '    const friendPools = { 0: [], 1: [], 2: [] };\n'
        '    GIFTBOX_VISIT_PICTURE_IDS.forEach((id) => {\n'
        '      const friend = TV_PIC_FRIEND[Number(id)];\n'
        '      if (friendPools[friend]) friendPools[friend].push(id);\n'
        '    });\n'
        '    const freshFriends = Object.keys(friendPools)\n'
        '      .filter((friend) => friendPools[friend].some((id) => !owned.has(Number(id))));\n'
        '    const friendId = Number(freshFriends.length\n'
        '      ? freshFriends[randInt(0, freshFriends.length - 1)]\n'
        '      : randInt(0, 2));\n'
        '    const friendPool = friendPools[friendId] || [];\n'
        '    const freshVisitPics = friendPool.filter((id) => !owned.has(Number(id)));\n'
        '    const pool = freshVisitPics.length ? freshVisitPics : friendPool;\n'
        '    const pictures = [];\n'
        '    const wantPics = Math.min(pool.length, sent >= 2 && Math.random() < 0.45 ? 2 : 1);\n'
        '    while (pictures.length < wantPics && pool.length) {\n'
        '      const id = pool[randInt(0, pool.length - 1)];\n'
        '      if (pictures.indexOf(id) === -1) pictures.push(id);\n'
        '      else break;\n'
        '    }\n'
        '    const items = [];\n'
        '    if (GIFTBOX_VISIT_RETURN_ITEMS.length && Math.random() < 0.65) {\n'
        '      addGiftItem(items, GIFTBOX_VISIT_RETURN_ITEMS[randInt(0, GIFTBOX_VISIT_RETURN_ITEMS.length - 1)], 1);\n'
        '    }\n'
        '    if (!pictures.length && !items.length && GIFTBOX_VISIT_RETURN_ITEMS.length) {\n'
        '      addGiftItem(items, GIFTBOX_VISIT_RETURN_ITEMS[randInt(0, GIFTBOX_VISIT_RETURN_ITEMS.length - 1)], 1);\n'
        '    }\n'
        '    return {\n'
        '      friendId,\n'
        '      clover: randInt(50, 300),\n'
        '      ticket: Math.random() < 0.35 ? randInt(1, 2) : 0,\n'
        '      items,\n'
        '      pictures,\n'
        '    };\n'
        '  }',
        'gift-box visit functions')

    # ------------------------------------------------------------ 4. 出发时取走
    src = sub_once(
        src,
        '    state.travel.plan = provisionTrip();',
        '    state.travel.plan = provisionTrip();\n'
        '    /* 【并入他的 V3】礼物盒来访：带着礼物出门，回来由伙伴寄回礼。 */\n'
        '    const visitGifts = takeGiftBoxVisitGifts(t);\n'
        '    if (visitGifts) state.travel.plan.giftBoxVisit = visitGifts;',
        'departFrog take gifts')

    src = sub_once(
        src,
        '    ctx.push(\'client_load_role\', rolePayload());\n'
        '    ctx.push(\'item_load_items\', handlers.item_load_items());\n'
        '    ctx.push(\'notify_new_event\', { event: ev });\n'
        '    return ev;\n'
        '  }\n'
        '\n'
        '  function returnFrog(ctx, t) {',
        '    ctx.push(\'client_load_role\', rolePayload());\n'
        '    ctx.push(\'item_load_items\', handlers.item_load_items());\n'
        '    /* 礼物盒被拿走了几件，客户端那份列表要跟着变。 */\n'
        '    if (visitGifts) ctx.push(\'travel_load_gift\', giftBoxPayload());\n'
        '    ctx.push(\'notify_new_event\', { event: ev });\n'
        '    return ev;\n'
        '  }\n'
        '\n'
        '  function returnFrog(ctx, t) {',
        'departFrog gift push')

    # ------------------------------------------------------------ 5. 回来时回礼
    src = sub_once(
        src,
        '    // ...and a story for a travel partner (see rollStory)\n'
        '    const story = rollStory();',
        '    // ...and a story for a travel partner (see rollStory)\n'
        '    const story = rollStory();\n'
        '    /* 【并入他的 V3】礼物盒来访的回礼：由一位旅行伙伴寄来（明信片 + 三叶草 + 可能有券/礼物）。 */\n'
        '    const giftBoxVisitReply = rollGiftBoxVisitReply(plan && plan.giftBoxVisit);\n'
        '    let giftBoxVisitMail = null;\n'
        '    if (giftBoxVisitReply) {\n'
        '      giftBoxVisitMail = makeMail({\n'
        '        type: 3,\n'
        '        title: \'拜访回礼\',\n'
        '        message: \'旅友寄来了回礼。\',\n'
        '        senderCharaId: giftBoxVisitReply.friendId,\n'
        '        clover: giftBoxVisitReply.clover,\n'
        '        ticket: giftBoxVisitReply.ticket,\n'
        '        items: giftBoxVisitReply.items,\n'
        '        pictures: giftBoxVisitReply.pictures,\n'
        '      });\n'
        '      state.mails.push(giftBoxVisitMail);\n'
        '      trimMails();\n'
        '    }',
        'returnFrog visit mail')

    src = sub_once(
        src,
        '    ctx.push(\'travel_load_gift\', giftBoxPayload());\n'
        '    ctx.push(\'notify_new_event\', { event: ev });\n'
        '    /* A new 旅行笔记 does not pop anything: evt_type=15 only makes the client',
        '    ctx.push(\'travel_load_gift\', giftBoxPayload());\n'
        '    ctx.push(\'notify_new_event\', { event: ev });\n'
        '    if (giftBoxVisitMail) {\n'
        '      ctx.push(\'notify_new_mail\', { mail: giftBoxVisitMail });\n'
        '      ctx.push(\'mail_load\', state.mails);\n'
        '    }\n'
        '    /* A new 旅行笔记 does not pop anything: evt_type=15 only makes the client',
        'returnFrog visit pushes')

    # ------------------------------------------------------------ 6. 旧档归一化挂载点
    src = sub_once(
        src,
        "    if (migrateTripSpecialtysToHouse()) graft.push('specialtys');",
        "    if (migrateTripSpecialtysToHouse()) graft.push('specialtys');\n"
        "    if (normalizeGiftBox()) graft.push('giftBox');",
        'graft normalizeGiftBox')

    # ------------------------------------------------- 7. 待收明信片的两个桶
    # 客户端有两个待收桶（albumPending / albumPendingVisit，后者经 album_load_new.visted_pic
    # 下发）。`album_save_new` 只查前一个的话，探访得来的明信片永远存不进相册（回 76）。
    src = sub_once(
        src,
        '    album_save_new: (d) => {\n'
        '      const id = Number(d && d.id);\n'
        '      const pend = state.albumPending || [];\n'
        '      const i = pend.findIndex((p) => p.id === id);\n'
        '      if (i === -1) return { code: 76 };   // 76 = 删除错误的新照片id',
        '    album_save_new: (d) => {\n'
        '      const id = Number(d && d.id);\n'
        '      /* 【并入他的 V3】待收照片有**两个**桶：albumPending 与 albumPendingVisit\n'
        '         （探访礼物的明信片走后者，客户端用 album_load_new.visted_pic 收）。\n'
        '         只查前者会让探访明信片永远存不进相册（回 76 = 错误的新照片 id）。 */\n'
        '      let pend = state.albumPending || [];\n'
        '      let i = pend.findIndex((p) => p.id === id);\n'
        '      if (i === -1) {\n'
        '        pend = state.albumPendingVisit || [];\n'
        '        i = pend.findIndex((p) => p.id === id);\n'
        '      }\n'
        '      if (i === -1) return { code: 76 };   // 76 = 删除错误的新照片id',
        'album_save_new two buckets')

    # ------------------------------------------- 8. 入桶 helper（邮件礼物明信片）
    src = sub_once(
        src,
        '  function addGiftItem(list, itemId, count) {',
        '  /* 【并入他的 V3】把邮件/礼物带来的明信片放进待收桶。探访来源走 albumPendingVisit\n'
        '     （客户端在 album_load_new 的 visted_pic 里收，而且领奖后不会立刻再弹一次\n'
        '     "保存照片"）；其余走普通待收桶。已经拥有过的同款不再重复发。 */\n'
        '  function queuePostcardPictures(pictures, opts) {\n'
        '    if (!Array.isArray(state.albumPending)) state.albumPending = [];\n'
        '    if (!Array.isArray(state.albumPendingVisit)) state.albumPendingVisit = [];\n'
        '    const visit = !!(opts && opts.visit);\n'
        '    const sender = opts && opts.sender != null ? Number(opts.sender) : -1;\n'
        '    const owned = ownedPictureIds();\n'
        '    const ids = (Array.isArray(pictures) ? pictures : [])\n'
        '      .map((p) => Number(p && typeof p === \'object\' ? p.pic_id : p))\n'
        '      .filter((id) => Number.isFinite(id) && id >= 0 && !!pictureLayers[String(id)]);\n'
        '    let added = 0;\n'
        '    for (const pic of ids) {\n'
        '      if (owned.has(pic)) continue;\n'
        '      state.pictureSeq = (state.pictureSeq || 0) + 1;\n'
        '      const row = { id: state.pictureSeq, pic_id: pic, read: 0, new: 1 };\n'
        '      if (visit) row.visit = true;\n'
        '      if (sender >= 0) row.sender = sender;\n'
        '      (visit ? state.albumPendingVisit : state.albumPending).push(row);\n'
        '      owned.add(pic);\n'
        '      added += 1;\n'
        '    }\n'
        '    return added;\n'
        '  }\n'
        '\n'
        '  function addGiftItem(list, itemId, count) {',
        'queuePostcardPictures')

    # ------------------------------------- 9. openMail 要兑现邮件里的明信片
    src = sub_once(
        src,
        '    for (const it of (mail.items || [])) {\n'
        '      const itemId = Number(it.item_id);\n'
        '      const count = addHouseItem(itemId, Number(it.count) || 1);\n'
        '      pushItemUpdate(ctx, itemId, count);\n'
        '    }\n'
        '    state.mails.splice(i, 1);\n'
        '    save();\n'
        '    ctx.push(\'mail_load\', state.mails);\n'
        '    return true;',
        '    for (const it of (mail.items || [])) {\n'
        '      const itemId = Number(it.item_id);\n'
        '      const count = addHouseItem(itemId, Number(it.count) || 1);\n'
        '      pushItemUpdate(ctx, itemId, count);\n'
        '    }\n'
        '    /* 【并入他的 V3】邮件里的明信片以前**被吞掉**（这里只发三叶草/券/扭蛋/物品）。\n'
        '       现在按来源入待收桶：标题是「拜访回礼」的走探访桶（客户端用 visted_pic 收，\n'
        '       领奖后不再多弹一次"保存照片"），其余走普通待收桶并推 album_load_new。 */\n'
        '    const visitMail = String(mail.title || \'\') === \'拜访回礼\';\n'
        '    const addedPictures = queuePostcardPictures(mail.pictures || [], {\n'
        '      visit: visitMail,\n'
        '      sender: visitMail ? Number(mail.senderCharaId) : -1,\n'
        '    });\n'
        '    state.mails.splice(i, 1);\n'
        '    save();\n'
        '    if (addedPictures > 0 && !visitMail) ctx.push(\'album_load_new\', handlers.album_load_new());\n'
        '    ctx.push(\'mail_load\', state.mails);\n'
        '    return true;',
        'openMail credits pictures')

    write(ENGINE, src)
    print('[giftbox] 引擎已改：礼物盒来访（取走 50%%/1-3 件 + 拜访回礼邮件）（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
