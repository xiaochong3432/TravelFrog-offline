#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""方案 B 收尾三项（并入「他做的 V3 包」）：

1) **手工品阶段时长**：他的口径是祈愿物 86 分钟/阶段、印章 129 分钟/阶段；我们原先是
   自设计的 90 秒/阶段。改成他的值作为默认，并留 env 回到短节奏。
2) **客人回礼增强**：他的回礼在原版公式之上做了四件事 —— 把三叶草夹到 50–300、
   额外按"是否喜欢"两档概率发【特产 / 博物馆门票 / 花种】、35% 概率追加抽奖券
   （上限 FRIEND_GIFTBOUNUS_TICKET_MAX=3）。我们的 `rollGuestGift` 只发三叶草/四叶草，
   而且邮件根本没收 `ticket` 字段，所以这块是真缺口。
3) **旅行中寄明信片**：他在**出发时**就把这趟奖励掷好（`travel.rewards`），于是能在行程的
   25–75% 处把一张**没收集过**的照片先寄回来（`deliverTravelPostcard` → `album_load_new`）。
   我们原先只在回家时结算，所以这一条要先补"出发时掷奖励 + 中段寄一张"。

**没有采纳的两处（如实标注）**：
  · 他的访客/客人在家节奏是 8–10 小时摇一次、停留 1 小时、冷却 0（我们是 60 秒摇一次、
    35% 概率、停留 30 分钟、冷却 300 秒）。他的节奏在离线版一个晚上可能一次都见不到客人，
    3.4 当年是**故意**把客人调活的，所以默认保留我们的；想照他的来：
    set FROG_GUEST_ROLL=30000 FROG_GUEST_CHANCE=50 FROG_GUEST_COOL=0 FROG_GUEST_STAY=3600。
  · 他的 `GUEST_FAREWELL_SEC = 20`（喂食后把停留截成 20 秒）会**推翻 3.4 的明确修复**
    （"喂食不再把剩余来访时间截成 20 秒"），属于回归，故不采纳。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')

MARK = 'V36-HOURS-EXTRAS'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[extras] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[extras] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[extras] 已并入过（%s），跳过' % MARK)
        return 0

    # ------------------------------------------------ 1. 花种奖池（他用的同一来源）
    src = sub_once(
        src,
        'const GIFTBOX_VISIT_RETURN_ITEMS = [12, 14].concat(SPECIALTY_IDS)\n'
        '  .filter((id, i, a) => ITEM_BY_ID.has(id) && a.indexOf(id) === i);',
        'const GIFTBOX_VISIT_RETURN_ITEMS = [12, 14].concat(SPECIALTY_IDS)\n'
        '  .filter((id, i, a) => ITEM_BY_ID.has(id) && a.indexOf(id) === i);\n'
        '\n'
        '/* %s 【并入他的 V3】客人回礼的额外奖池 —— 他用的是同一份数据：\n'
        '   SEED_IDS（GiftData 5003 = 花种）与 TV_MUSEUM_TICKETS（门票 1017..1021）。 */\n'
        'const GUEST_FLOWER_REWARD_IDS = SEED_IDS.filter((id) => ITEM_BY_ID.has(id));' % MARK,
        'flower reward pool')

    # ------------------------------------------------ 2. 手工品阶段时长（他的口径）
    src = sub_once(
        src,
        'const CRAFT_STAGE_SEC = 90;          // one stage per 90 s, OURS',
        'const CRAFT_STAGE_SEC = 90;          // one stage per 90 s, OURS\n'
        '/* 【并入他的 V3】手工品的阶段时长按他的口径：祈愿物 86 分钟/阶段、印章 129 分钟/阶段\n'
        '   （他注释里写明这是他的设定）。想回到我们原来的短节奏：\n'
        '   FROG_CRAFT_WISH_STAGE_SEC=90 FROG_CRAFT_STAMP_STAGE_SEC=90。 */\n'
        "const CRAFT_WISH_STAGE_SEC = Number(process.env.FROG_CRAFT_WISH_STAGE_SEC || 86 * 60);\n"
        "const CRAFT_STAMP_STAGE_SEC = Number(process.env.FROG_CRAFT_STAMP_STAGE_SEC || 129 * 60);",
        'craft stage constants')

    for old, new, label in (
        ('      make_time: t + CRAFT_STAGE_SEC,\n      u_id: c.seq,\n      materialPaid: true,\n    });\n'
         '    changed = true;\n  }\n'
         '  if (canCraft && atHome && stampIds.length && !c.stamps.some((s) => s.state < 3)',
         '      make_time: t + CRAFT_WISH_STAGE_SEC,\n      u_id: c.seq,\n      materialPaid: true,\n    });\n'
         '    changed = true;\n  }\n'
         '  if (canCraft && atHome && stampIds.length && !c.stamps.some((s) => s.state < 3)',
         'wish create stage'),
        ('      w.make_time = t + CRAFT_STAGE_SEC;',
         '      w.make_time = t + CRAFT_WISH_STAGE_SEC;',
         'wish advance stage'),
        ('      time: t + CRAFT_STAGE_SEC,\n      u_id: c.seq,',
         '      time: t + CRAFT_STAMP_STAGE_SEC,\n      u_id: c.seq,',
         'stamp create stage'),
        ('    s.time = Number(s.state) >= CRAFT_STAMP_MAX ? t : t + CRAFT_STAGE_SEC;',
         '    s.time = Number(s.state) >= CRAFT_STAMP_MAX ? t : t + CRAFT_STAMP_STAGE_SEC;',
         'stamp advance stage'),
    ):
        src = sub_once(src, old, new, label)

    # ------------------------------------------- 3. 客人停留时长可用 env（他的 3600）
    src = sub_once(
        src,
        'const GUEST_STAY_SEC = 1800;',
        '/* 【并入他的 V3 的可选项】他是 3600（1 小时）；我们默认保留 3.4 的 30 分钟，\n'
        '   想照他的来：FROG_GUEST_STAY=3600。 */\n'
        "const GUEST_STAY_SEC = Number(process.env.FROG_GUEST_STAY || 1800);",
        'guest stay env')

    # ------------------------------------------------------------ 4. 客人回礼增强
    src = sub_once(
        src,
        '    let clover = 0;\n'
        '    const giftItems = [];\n'
        '    if (got === \'four_leaf\') {\n'
        '      giftItems.push({ item_id: FOUR_LEAF_CLOVER_ID, count: 1 });\n'
        '    } else {',
        '    let clover = 0;\n'
        '    let ticket = 0;\n'
        '    const giftItems = [];\n'
        '    if (got === \'four_leaf\') {\n'
        '      giftItems.push({ item_id: FOUR_LEAF_CLOVER_ID, count: 1 });\n'
        '    } else {',
        'guest gift ticket var')

    src = sub_once(
        src,
        '      clover = Math.max(1, clover + Number(DEF(\'FRIEND_GIFTBOUNUS_CLOVER\', 0)));\n'
        '    }\n'
        '    return { got, clover, items: giftItems, feeling, rare };\n'
        '  }',
        '      clover = Math.max(1, clover + Number(DEF(\'FRIEND_GIFTBOUNUS_CLOVER\', 0)));\n'
        '      /* 【并入他的 V3】把三叶草夹进他的 50–300（可用 env 改）。 */\n'
        '      const cloMin = Number(process.env.FROG_GUEST_CLOVER_MIN || 50);\n'
        '      const cloMax = Math.max(cloMin, Number(process.env.FROG_GUEST_CLOVER_MAX || 300));\n'
        '      clover = Math.max(cloMin, Math.min(cloMax, Math.floor(clover)));\n'
        '    }\n'
        '    /* 【并入他的 V3】回礼不只有三叶草：特产 / 博物馆门票 / 花种按"是否喜欢"两档概率发。 */\n'
        '    const maybeGiftItem = (pct, pool) => {\n'
        '      if (!Array.isArray(pool) || !pool.length) return;\n'
        '      if (Math.random() * 100 >= pct) return;\n'
        '      giftItems.push({ item_id: Number(pool[randInt(0, pool.length - 1)]), count: 1 });\n'
        '    };\n'
        '    maybeGiftItem(rare ? 45 : 18, SPECIALTY_IDS);\n'
        '    maybeGiftItem(rare ? 28 : 8, TV_MUSEUM_TICKETS);\n'
        '    maybeGiftItem(rare ? 35 : 12, GUEST_FLOWER_REWARD_IDS);\n'
        '    /* 额外抽奖券：他的 35%% 概率，最多 FRIEND_GIFTBOUNUS_TICKET_MAX(3) 张。 */\n'
        '    const maxBonusTickets = Number(DEF(\'FRIEND_GIFTBOUNUS_TICKET_MAX\', 3));\n'
        '    if ((Number(state.guestBonusTickets) || 0) < maxBonusTickets\n'
        '        && Math.random() * 100 < Number(process.env.FROG_GUEST_BONUS_TICKET_CHANCE || 35)) {\n'
        '      ticket += Number(DEF(\'FRIEND_GIFTBOUNUS_TICKET\', 1));\n'
        '      state.guestBonusTickets = (Number(state.guestBonusTickets) || 0) + 1;\n'
        '    }\n'
        '    return { got, clover, ticket, items: giftItems, feeling, rare };\n'
        '  }',
        'guest gift extras')

    # 邮件要把券也带上（以前 makeMail 只收 clover/items）
    src = sub_once(
        src,
        "        senderCharaId: g.id, clover: g.pendingGift.clover,\n"
        "        items: g.pendingGift.items || [],",
        "        senderCharaId: g.id, clover: g.pendingGift.clover,\n"
        "        ticket: g.pendingGift.ticket || 0,\n"
        "        items: g.pendingGift.items || [],",
        'guest mail ticket')

    # ------------------------------------------- 5. 旅行中寄明信片：旧的"没见过"的照片
    src = sub_once(
        src,
        'function advanceCraft(t) {\n'
        '  const c = state.craft || (state.craft = { wishes: [], stamps: [], pending: [], seq: 0 });',
        '/** 【并入他的 V3】从这趟奖励的照片里挑出"一张都还没拥有过"的那些（用于旅行中先寄回来）。 */\n'
        'function freshPostcardIds(pictures) {\n'
        '  const owned = ownedPictureIds();\n'
        '  const out = [];\n'
        '  const add = (raw) => {\n'
        '    const pic = Number(raw && typeof raw === \'object\' ? raw.pic_id : raw);\n'
        '    if (!Number.isFinite(pic) || pic < 0) return;\n'
        '    if (owned.has(pic) || out.indexOf(pic) !== -1) return;\n'
        '    out.push(pic);\n'
        '    owned.add(pic);\n'
        '  };\n'
        '  (Array.isArray(pictures) ? pictures : []).forEach(add);\n'
        '  return out;\n'
        '}\n'
        '\n'
        'function advanceCraft(t) {\n'
        '  const c = state.craft || (state.craft = { wishes: [], stamps: [], pending: [], seq: 0 });',
        'freshPostcardIds')

    # 出发：先掷这趟奖励 + 定下寄件时刻
    src = sub_once(
        src,
        '    state.travel.returnAt = t + Math.min(Math.max(20, window), TRAVEL_HARD_MAX_SEC);\n'
        '    state.travel.nextDepartAt = 0;',
        '    state.travel.returnAt = t + Math.min(Math.max(20, window), TRAVEL_HARD_MAX_SEC);\n'
        '    state.travel.nextDepartAt = 0;\n'
        '    /* 【并入他的 V3】他在这时就掷好整趟奖励，所以才能"旅行中先寄一张照片回家"。\n'
        '       我们原先只在回家时掷，故先补这一步；回家时优先用这里掷好的结果。 */\n'
        '    state.travel.rewards = rollTripRewards(state.travel.plan);\n'
        '    const freshPics = freshPostcardIds((state.travel.rewards && state.travel.rewards.pictures) || []);\n'
        '    state.travel.postcardPics = freshPics;\n'
        '    state.travel.postcardSent = !freshPics.length;\n'
        '    if (freshPics.length) {\n'
        '      const dur = Math.max(20, state.travel.returnAt - state.travel.departAt);\n'
        '      const earliest = state.travel.departAt + Math.max(10, Math.floor(dur * 0.25));\n'
        '      const latest = state.travel.departAt + Math.max(10, Math.floor(dur * 0.75));\n'
        '      state.travel.postcardAt = randInt(earliest, Math.max(earliest, latest));\n'
        '    } else {\n'
        '      state.travel.postcardAt = 0;\n'
        '    }',
        'depart pre-roll rewards + postcardAt')

    # 回家：用掷好的奖励；清掉寄件状态；不要重复发中段寄过的那几张
    src = sub_once(
        src,
        '    const plan = state.travel.plan || null;\n'
        '    const r = rollTripRewards(plan);',
        '    const plan = state.travel.plan || null;\n'
        '    /* 【并入他的 V3】奖励在出发时已经掷好；老档（本次之前的行程）没有这个字段，\n'
        '       就按老办法在回家时掷，行为与 V3.5 一致。 */\n'
        '    const r = state.travel.rewards || rollTripRewards(plan);\n'
        '    const deliveredMidTrip = (state.travel.postcardPics || []).slice();',
        'returnFrog use stored rewards')

    src = sub_once(
        src,
        '      state.pictureSeq = (state.pictureSeq || 0) + 1;\n'
        '      state.albumPending.push({ id: state.pictureSeq, pic_id: pic, read: 0, new: 1 });\n'
        '    }',
        '      /* 旅行中已经先寄回来的那几张不再重复入待收（同一趟只给一份）。 */\n'
        '      if (deliveredMidTrip.indexOf(Number(pic)) !== -1 && state.travel.postcardSent) continue;\n'
        '      state.pictureSeq = (state.pictureSeq || 0) + 1;\n'
        '      state.albumPending.push({ id: state.pictureSeq, pic_id: pic, read: 0, new: 1 });\n'
        '    }',
        'returnFrog skip mid-trip pics')

    src = sub_once(
        src,
        '    state.travel.departAt = 0;\n'
        '    state.travel.returnAt = 0;\n'
        '    state.travel.plan = null;',
        '    state.travel.departAt = 0;\n'
        '    state.travel.returnAt = 0;\n'
        '    state.travel.plan = null;\n'
        '    state.travel.rewards = null;\n'
        '    state.travel.postcardAt = 0;\n'
        '    state.travel.postcardPics = [];\n'
        '    state.travel.postcardSent = false;',
        'returnFrog clear postcard fields')

    # 中段寄件 + tick 挂点
    src = sub_once(
        src,
        '  function returnFrog(ctx, t) {',
        '  /* 【并入他的 V3】旅行中先寄一张：把这趟里"还没拥有过"的照片先入待收并推\n'
        '     album_load_new（客户端会弹"收到新照片"）。*/ \n'
        '  function deliverTravelPostcard(ctx) {\n'
        '    const pics = (state.travel && state.travel.postcardPics) || [];\n'
        '    if (!pics.length || state.travel.postcardSent) return false;\n'
        '    state.travel.postcardSent = true;\n'
        '    const added = queuePostcardPictures(pics);\n'
        '    save();\n'
        '    if (added > 0) ctx.push(\'album_load_new\', handlers.album_load_new());\n'
        '    return added > 0;\n'
        '  }\n'
        '\n'
        '  function returnFrog(ctx, t) {',
        'deliverTravelPostcard')

    src = sub_once(
        src,
        '    } else if (t >= state.travel.returnAt) {\n'
        '      returnFrog(ctx, t);\n'
        '    }',
        '    } else {\n'
        '      /* 【并入他的 V3】行程中段先把一张新照片寄回来。 */\n'
        '      if (state.travel.postcardAt && !state.travel.postcardSent\n'
        '          && t >= state.travel.postcardAt) {\n'
        '        deliverTravelPostcard(ctx);\n'
        '      }\n'
        '      if (t >= state.travel.returnAt) {\n'
        '        returnFrog(ctx, t);\n'
        '      }\n'
        '    }',
        'tick postcard delivery')

    write(ENGINE, src)
    print('[extras] 引擎已改：手工品阶段时长(86/129 分钟) + 客人回礼增强 + 旅行中寄明信片（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
