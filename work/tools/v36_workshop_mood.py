#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""方案 B-2：并入「他做的 V3 包」的**家具工坊**机制（心情/压力 + 自动换家具 + 自动开工）。

他的模型（逐行对照 work/build/his3/engine_live/index.js 2299-2380、3900-3970、2596-2690）：
  · 一个数值 `furniture.moodStress`，分档成客户端认识的 `Furniture.Mood`（1 很高兴 … 5 很生气）：
      0-2 → 1 / 3-7 → 2 / 8-17 → 3 / 18-26 → 4 / >=27 → 5
  · 客户端只在 mood==5 时把工作台画成"罢工"（main.min.js: serverData.mood==Furniture.Mood.very_angry
    → mainout_season*_gzt_strike_png），并且 `bench_lock` 会挡住工作台编辑。
  · 压力来源：换一件摆放中的家具 +1（FURNITURE_REPLACE_STRESS）
  · 安抚来源：一趟旅行回来 +5、手工品(祈愿物/印章)完成 +3、家具做成 +2
  · 自动换家具：每 8–12 小时检查一次，35% 概率把某件摆放中的家具换成**同类型**的另一件（已拥有）
  · 自动开工：他的口径是每 3 小时检查一次、35% 通过才开工

我们的实现有两处**如实标注的差异**（都是为了不引入"看着像 bug"的等待）：
  1) 我们的 tick 由外壳每 5 秒调一次（不是常驻定时器），所以"自动开工"的检查间隔默认 0（每拍查），
     概率仍是他的 35%；想完全照他的 3 小时节奏，设
     FROG_FURNITURE_AUTO_CRAFT_MIN_SEC=10800 / _MAX_SEC=10800 即可。
  2) 摆好图纸+材料的**手动路径**仍然是立刻开工（我们 V3.5 的既有行为，也是玩家预期）；
     自动开工只在"材料齐了但没开工"时补一脚，两条路都不互相覆盖。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')

MARK = 'V36-WORKSHOP-MOOD'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[workshop] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[workshop] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[workshop] 已并入过（%s），跳过' % MARK)
        return 0

    # ------------------------------------------------------------ 1. 常量
    src = sub_once(
        src,
        'const GIFTBOX_VISIT_RETURN_ITEMS = [12, 14].concat(SPECIALTY_IDS)\n'
        '  .filter((id, i, a) => ITEM_BY_ID.has(id) && a.indexOf(id) === i);',
        'const GIFTBOX_VISIT_RETURN_ITEMS = [12, 14].concat(SPECIALTY_IDS)\n'
        '  .filter((id, i, a) => ITEM_BY_ID.has(id) && a.indexOf(id) === i);\n'
        '\n'
        '/* %s 【并入他的 V3】家具工坊：心情/压力 + 自动换家具 + 自动开工。\n'
        '   他注释里写明：客户端只保留了 mood/bench_lock 的**显示**逻辑，原始阈值在服务端，\n'
        '   所以这几个数是他的【离线复原】值，全部可用环境变量覆盖。 */\n'
        "const envNum = (name, fallback, minValue) => {\n"
        '  const raw = process.env[name];\n'
        '  const v = Number(raw);\n'
        '  return Number.isFinite(v) ? Math.max(Number(minValue) || 0, v) : fallback;\n'
        '};\n'
        'const FURNITURE_MOOD = { VERY_HAPPY: 1, HAPPY: 2, CALM: 3, ANGRY: 4, VERY_ANGRY: 5 };\n'
        "const FURNITURE_MESS_STRESS = envNum('FROG_FURNITURE_MESS_STRESS', 27, 1);\n"
        "const FURNITURE_REPLACE_STRESS = envNum('FROG_FURNITURE_REPLACE_STRESS', 1, 1);\n"
        "const FURNITURE_TRIP_RELIEF = envNum('FROG_FURNITURE_TRIP_RELIEF', 5, 1);\n"
        "const FURNITURE_HANDCRAFT_RELIEF = envNum('FROG_FURNITURE_HANDCRAFT_RELIEF', 3, 1);\n"
        "const FURNITURE_CRAFT_RELIEF = envNum('FROG_FURNITURE_CRAFT_RELIEF', 2, 1);\n"
        "const FURNITURE_AUTO_REPLACE_MIN_SEC = envNum('FROG_FURNITURE_AUTO_REPLACE_MIN_SEC', 8 * 3600, 60);\n"
        "const FURNITURE_AUTO_REPLACE_MAX_SEC = envNum('FROG_FURNITURE_AUTO_REPLACE_MAX_SEC', 12 * 3600, 60);\n"
        "const FURNITURE_AUTO_REPLACE_CHANCE = envNum('FROG_FURNITURE_AUTO_REPLACE_CHANCE', 35, 0);\n"
        '/* 见文件头"差异 1"：默认每拍检查，概率仍 35%%；设成 10800 就是他的 3 小时。 */\n'
        "const FURNITURE_AUTO_CRAFT_MIN_SEC = envNum('FROG_FURNITURE_AUTO_CRAFT_MIN_SEC', 0, 0);\n"
        "const FURNITURE_AUTO_CRAFT_MAX_SEC = envNum('FROG_FURNITURE_AUTO_CRAFT_MAX_SEC', 0, 0);\n"
        "const FURNITURE_AUTO_CRAFT_CHANCE = envNum('FROG_FURNITURE_AUTO_CRAFT_CHANCE', 35, 0);" % MARK,
        'workshop constants')

    # ------------------------------------------------- 2. defaultState 字段
    src = sub_once(
        src,
        '      replaceFur: [],       // replace_fur: furniture TYPEs being rotated out',
        '      replaceFur: [],       // replace_fur: furniture TYPEs being rotated out\n'
        '      /* 【并入他的 V3】心情：换家具会涨压力，旅行/手工会降；>=27 时工作台"乱掉" */\n'
        '      mood: FURNITURE_MOOD.CALM,\n'
        '      moodStress: 0,\n'
        '      moodRecoverTrips: 0,\n'
        '      moodRecoverCrafts: 0,\n'
        '      nextAutoCraftAt: 0,   // 自动开工的下一次检查时间\n'
        '      nextAutoReplaceAt: 0, // 自动换家具的下一次检查时间\n'
        '      autoReplaceCount: 0,\n'
        '      autoReplaceLastAt: 0,',
        'defaultState furniture mood fields')

    # --------------------------------------- 3. 模块级心情/自动换家具逻辑
    src = sub_once(
        src,
        'function advanceCraft(t) {\n'
        '  const c = state.craft || (state.craft = { wishes: [], stamps: [], pending: [], seq: 0 });',
        '/* ==========================================================================\n'
        '   %s 家具工坊：心情与压力（并入他的 V3）\n'
        '   这些函数放在模块级，是因为手工品结算（advanceCraft）也要用到安抚。\n'
        '   ========================================================================== */\n'
        'function normalizeFurnitureMood() {\n'
        '  if (!state.furniture) state.furniture = defaultState().furniture;\n'
        '  const stress = Math.max(0, Number(state.furniture.moodStress) || 0);\n'
        '  state.furniture.moodStress = stress;\n'
        '  state.furniture.mood = stress >= FURNITURE_MESS_STRESS ? FURNITURE_MOOD.VERY_ANGRY\n'
        '    : stress >= 18 ? FURNITURE_MOOD.ANGRY\n'
        '    : stress >= 8 ? FURNITURE_MOOD.CALM\n'
        '    : stress >= 3 ? FURNITURE_MOOD.HAPPY\n'
        '    : FURNITURE_MOOD.VERY_HAPPY;\n'
        '  return state.furniture.mood;\n'
        '}\n'
        '\n'
        'function furnitureMood() {\n'
        '  return normalizeFurnitureMood();\n'
        '}\n'
        '\n'
        '/** 心情差到工作台乱掉：客户端此时画的是"罢工"图，也不接受工作台编辑。 */\n'
        'function furnitureMoodBlocked() {\n'
        '  return normalizeFurnitureMood() === FURNITURE_MOOD.VERY_ANGRY;\n'
        '}\n'
        '\n'
        'function stressFurnitureMood(n) {\n'
        '  if (!state.furniture) return;\n'
        '  state.furniture.moodStress = Math.max(0, (Number(state.furniture.moodStress) || 0) + Number(n || 0));\n'
        '  normalizeFurnitureMood();\n'
        '}\n'
        '\n'
        'function sootheFurnitureMood(n, kind) {\n'
        '  if (!state.furniture) return false;\n'
        '  const before = furnitureMoodBlocked();\n'
        '  state.furniture.moodStress = Math.max(0, (Number(state.furniture.moodStress) || 0) - Number(n || 0));\n'
        "  if (kind === 'trip') state.furniture.moodRecoverTrips = (Number(state.furniture.moodRecoverTrips) || 0) + 1;\n"
        "  if (kind === 'craft') state.furniture.moodRecoverCrafts = (Number(state.furniture.moodRecoverCrafts) || 0) + 1;\n"
        '  normalizeFurnitureMood();\n'
        '  return before && !furnitureMoodBlocked();\n'
        '}\n'
        '\n'
        'function furnitureNameOf(furnitureId) {\n'
        '  const def = FURNITURE_BY_ID.get(Number(furnitureId));\n'
        '  return def && def.name ? String(def.name) : String(furnitureId);\n'
        '}\n'
        '\n'
        'function scheduleNextFurnitureAutoReplace(t) {\n'
        '  const minSec = Math.max(60, Number(FURNITURE_AUTO_REPLACE_MIN_SEC) || 1800);\n'
        '  const maxSec = Math.max(minSec, Number(FURNITURE_AUTO_REPLACE_MAX_SEC) || minSec);\n'
        '  state.furniture.nextAutoReplaceAt = Number(t || nowSec()) + randInt(minSec, maxSec);\n'
        '}\n'
        '\n'
        'function scheduleNextFurnitureAutoCraft(t) {\n'
        '  const minSec = Math.max(0, Number(FURNITURE_AUTO_CRAFT_MIN_SEC) || 0);\n'
        '  const maxSec = Math.max(minSec, Number(FURNITURE_AUTO_CRAFT_MAX_SEC) || minSec);\n'
        '  state.furniture.nextAutoCraftAt = Number(t || nowSec()) + (maxSec > 0 ? randInt(minSec, maxSec) : 0);\n'
        '}\n'
        '\n'
        '/** 摆放中的家具 -> 可替换成的**同类型**其他款式（已拥有、且不是当前这件）。 */\n'
        'function autoFurnitureReplaceCandidates() {\n'
        '  const ownedByType = new Map();\n'
        '  for (const id of state.furniture.owned || []) {\n'
        '    const fid = Number(id);\n'
        '    const def = FURNITURE_BY_ID.get(fid);\n'
        '    if (!def) continue;\n'
        '    const type = Number(def.type);\n'
        '    if (!ownedByType.has(type)) ownedByType.set(type, []);\n'
        '    ownedByType.get(type).push(fid);\n'
        '  }\n'
        '  const out = [];\n'
        '  for (const placed of state.furniture.placed || []) {\n'
        '    const type = Number(placed && placed.type);\n'
        '    const current = Number(placed && placed.id);\n'
        '    const choices = (ownedByType.get(type) || [])\n'
        '      .filter((id) => id > 0 && id !== current)\n'
        '      .sort((a, b) => a - b);\n'
        '    if (choices.length) out.push({ type, current, choices });\n'
        '  }\n'
        '  return out;\n'
        '}\n'
        '\n'
        'function autoReplaceOneFurniture(t, forced) {\n'
        '  if (!forced) {\n'
        "    if (state.frog && state.frog.status !== 0) return { changed: false, reason: '蛙蛙不在家' };\n"
        "    if (state.furniture.craft) return { changed: false, reason: '蛙蛙正在做家具' };\n"
        "    if (furnitureMoodBlocked()) return { changed: false, reason: '工作台乱了，蛙蛙没有心情换家具' };\n"
        '  }\n'
        '  const candidates = autoFurnitureReplaceCandidates();\n'
        "  if (!candidates.length) return { changed: false, reason: '没有可替换的同类型家具款式' };\n"
        '  const pick = candidates[randInt(0, candidates.length - 1)];\n'
        '  const nextId = pick.choices[randInt(0, pick.choices.length - 1)];\n'
        '  state.furniture.placed = (state.furniture.placed || []).filter((p) => Number(p.type) !== pick.type);\n'
        '  state.furniture.placed.push({ type: pick.type, id: nextId });\n'
        '  if ((state.furniture.replaceFur || []).indexOf(pick.type) === -1) {\n'
        '    state.furniture.replaceFur.push(pick.type);\n'
        '  }\n'
        '  state.furniture.autoReplaceCount = (Number(state.furniture.autoReplaceCount) || 0) + 1;\n'
        '  state.furniture.autoReplaceLastAt = Number(t || nowSec());\n'
        '  return {\n'
        '    changed: true,\n'
        '    type: pick.type,\n'
        '    from: pick.current,\n'
        '    to: nextId,\n'
        '    fromName: furnitureNameOf(pick.current),\n'
        '    toName: furnitureNameOf(nextId),\n'
        '  };\n'
        '}\n'
        '\n'
        '/** 旧档补齐心情字段（缺字段的档从 0 压力、平静开始）。 */\n'
        'function normalizeFurnitureAutoFields() {\n'
        '  const F = state.furniture;\n'
        '  if (!F) return false;\n'
        '  let changed = false;\n'
        '  for (const [k, v] of [["moodStress", 0], ["moodRecoverTrips", 0], ["moodRecoverCrafts", 0],\n'
        '    ["nextAutoCraftAt", 0], ["nextAutoReplaceAt", 0], ["autoReplaceCount", 0], ["autoReplaceLastAt", 0]]) {\n'
        '    if (!Number.isFinite(Number(F[k]))) { F[k] = v; changed = true; }\n'
        '  }\n'
        '  normalizeFurnitureMood();\n'
        '  return changed;\n'
        '}\n'
        '\n'
        'function advanceCraft(t) {\n'
        '  const c = state.craft || (state.craft = { wishes: [], stamps: [], pending: [], seq: 0 });' % MARK,
        'module-level mood functions')

    # ------------------------------------------------ 4. 压力：换家具 +1
    src = sub_once(
        src,
        '      state.furniture.placed.push({ type, id });\n'
        '      if (state.furniture.replaceFur.indexOf(type) === -1) {\n'
        '        state.furniture.replaceFur.push(type);\n'
        '      }\n'
        '      save();\n'
        '      return { code: 0 };',
        '      state.furniture.placed.push({ type, id });\n'
        '      if (state.furniture.replaceFur.indexOf(type) === -1) {\n'
        '        state.furniture.replaceFur.push(type);\n'
        '      }\n'
        '      /* 【并入他的 V3】换一件家具 = 一次压力（他把这个数设成 1）。 */\n'
        '      stressFurnitureMood(FURNITURE_REPLACE_STRESS);\n'
        '      save();\n'
        '      return { code: 0 };',
        'replace_fur stress')

    # --------------------------------------- 5. 安抚：家具做成 + 手工完成 + 旅行
    src = sub_once(
        src,
        '    if (state.furniture.owned.indexOf(fid) === -1) state.furniture.owned.push(fid);\n'
        '    save();\n'
        '    const ev = makeEvent(EV_FURNITURE_FINISH, [fid, craft.drawing || 0]);',
        '    if (state.furniture.owned.indexOf(fid) === -1) state.furniture.owned.push(fid);\n'
        '    /* 【并入他的 V3】做出一件家具 = 安抚一次。 */\n'
        '    sootheFurnitureMood(FURNITURE_CRAFT_RELIEF, \'craft\');\n'
        '    save();\n'
        '    const ev = makeEvent(EV_FURNITURE_FINISH, [fid, craft.drawing || 0]);',
        'craftTick relief')

    src = sub_once(
        src,
        '      w.make_time = t;                       // finished now\n'
        '      stampWish(w, t);                       // + the seal and the DATE the card shows',
        '      w.make_time = t;                       // finished now\n'
        '      stampWish(w, t);                       // + the seal and the DATE the card shows\n'
        '      /* 【并入他的 V3】手工品(祈愿物)完成 = 安抚一次。 */\n'
        "      sootheFurnitureMood(FURNITURE_HANDCRAFT_RELIEF, 'craft');",
        'wish relief')

    src = sub_once(
        src,
        '    s.state = Number(s.state) + 1;\n'
        '    s.time = Number(s.state) >= CRAFT_STAMP_MAX ? t : t + CRAFT_STAGE_SEC;\n'
        '    changed = true;',
        '    s.state = Number(s.state) + 1;\n'
        '    s.time = Number(s.state) >= CRAFT_STAMP_MAX ? t : t + CRAFT_STAGE_SEC;\n'
        '    /* 【并入他的 V3】印章做完也算一次手工安抚。 */\n'
        '    if (Number(s.state) >= CRAFT_STAMP_MAX) {\n'
        "      sootheFurnitureMood(FURNITURE_HANDCRAFT_RELIEF, 'craft');\n"
        '    }\n'
        '    changed = true;',
        'stamp relief')

    src = sub_once(
        src,
        '    const flower = rollDecoration();\n'
        '    // ...and a story for a travel partner (see rollStory)\n'
        '    const story = rollStory();',
        '    const flower = rollDecoration();\n'
        '    // ...and a story for a travel partner (see rollStory)\n'
        '    const story = rollStory();\n'
        '    /* 【并入他的 V3】一趟旅行回来 = 最大的那次安抚（他把这个数设成 5）。 */\n'
        "    const moodRecovered = sootheFurnitureMood(FURNITURE_TRIP_RELIEF, 'trip');",
        'trip relief')

    # ------------------------------------------------- 6. 载荷：mood / bench_lock
    src = sub_once(
        src,
        '        mood: 0,\n'
        '        bench_lock: state.furniture.benchLock ? 1 : 0,',
        '        /* 【并入他的 V3】mood 以前恒为 0；客户端只在 ==5(very_angry) 时把工作台画成\n'
        '           "罢工"，bench_lock 也要把"心情太差"算进去（工作台此时不接受编辑）。 */\n'
        '        mood: furnitureMood(),\n'
        '        bench_lock: (state.furniture.benchLock\n'
        '          || (!state.furniture.craft && furnitureMoodBlocked())) ? 1 : 0,',
        'payload mood')

    # ------------------------------------------- 7. tick：自动换家具 + 自动开工
    src = sub_once(
        src,
        '    /* 工作台制作到点结算（离线也算：finishAt 是绝对时间，开机后第一拍就会结算） */\n'
        '    craftTick(ctx, t);',
        '    /* 工作台制作到点结算（离线也算：finishAt 是绝对时间，开机后第一拍就会结算） */\n'
        '    craftTick(ctx, t);\n'
        '    /* 【并入他的 V3】蛙蛙自己换家具：每 8–12 小时检查一次、35% 才动手。 */\n'
        '    maybeAutoReplaceFurniture(ctx, t);\n'
        '    /* 【并入他的 V3】材料齐了却还没开工时，按 35% 概率自己开工\n'
        '       （检查间隔默认每拍；设 FROG_FURNITURE_AUTO_CRAFT_MIN_SEC=10800 就是他的 3 小时）。 */\n'
        '    autoCraftCheck(ctx, t);',
        'tick auto furniture')

    # ------------------------------------------------------ 8. 自动逻辑胶水
    src = sub_once(
        src,
        '  /** 台面上出现图纸、且材料够 -> 开始制作（锁住工作台，材料当场扣掉）。\n'
        '   *  返回 true 表示这一拍真的开工了。 */\n'
        '  function maybeStartCraft() {',
        '  /* 【并入他的 V3】自动换家具 / 自动开工的引擎侧胶水（要 ctx 推送，所以放在这里）。 */\n'
        '  function maybeAutoReplaceFurniture(ctx, t) {\n'
        '    let changed = false;\n'
        '    if (!Number(state.furniture.nextAutoReplaceAt)) {\n'
        '      scheduleNextFurnitureAutoReplace(t);\n'
        '      changed = true;\n'
        '    }\n'
        '    if (t < Number(state.furniture.nextAutoReplaceAt)) {\n'
        '      if (changed) save();\n'
        '      return false;\n'
        '    }\n'
        '    scheduleNextFurnitureAutoReplace(t);\n'
        '    changed = true;\n'
        '    const chance = Math.max(0, Math.min(100, Number(FURNITURE_AUTO_REPLACE_CHANCE) || 0));\n'
        '    if (Math.random() * 100 >= chance) {\n'
        '      save();\n'
        '      return false;\n'
        '    }\n'
        '    const result = autoReplaceOneFurniture(t, false);\n'
        '    if (result.changed) {\n'
        '      save();\n'
        '      ctx.push(\'furniture_load_furniture\', handlers.furniture_load_furniture({}));\n'
        '      /* 客户端 MainOutController 收到 FurniturePut(22) 会提示"小屋好像发生了一点变化" */\n'
        '      ctx.push(\'notify_new_event\', { event: makeEvent(TIMER_EVENT.FurniturePut, []) });\n'
        '      return true;\n'
        '    }\n'
        '    if (changed) save();\n'
        '    return false;\n'
        '  }\n'
        '\n'
        '  function autoCraftCheck(ctx, t) {\n'
        '    if (state.furniture.craft) return false;\n'
        '    if (!Number(state.furniture.nextAutoCraftAt)) {\n'
        '      scheduleNextFurnitureAutoCraft(t);\n'
        '      save();\n'
        '    }\n'
        '    if (t < Number(state.furniture.nextAutoCraftAt)) return false;\n'
        '    scheduleNextFurnitureAutoCraft(t);\n'
        '    if (furnitureMoodBlocked()) { save(); return false; }\n'
        '    const chance = Math.max(0, Math.min(100, Number(FURNITURE_AUTO_CRAFT_CHANCE) || 0));\n'
        '    if (Math.random() * 100 >= chance) { save(); return false; }\n'
        '    if (!maybeStartCraft()) { save(); return false; }\n'
        '    ctx.push(\'furniture_load_furniture\', handlers.furniture_load_furniture({}));\n'
        '    ctx.push(\'item_load_items\', handlers.item_load_items());\n'
        '    ctx.push(\'client_load_role\', rolePayload());\n'
        '    return true;\n'
        '  }\n'
        '\n'
        '  /** 台面上出现图纸、且材料够 -> 开始制作（锁住工作台，材料当场扣掉）。\n'
        '   *  返回 true 表示这一拍真的开工了。 */\n'
        '  function maybeStartCraft() {',
        'auto glue')

    # ------------------------------------------------------------ 9. gm 命令
    src = sub_once(
        src,
        "    'craft_finish - 立刻完成当前制作',",
        "    'craft_finish - 立刻完成当前制作',\n"
        "    'furniture_mood - 看家具心情/压力（>=27 时工作台乱掉、暂停新制作）',\n"
        "    'furniture_auto - 看自动换家具/自动开工的排期（furniture_auto force 立刻换一件）',",
        'gm help lines')

    src = sub_once(
        src,
        "      case 'craft_finish': {",
        "      case 'furniture_mood': {\n"
        "        const names = { 1: '很高兴', 2: '开心', 3: '平静', 4: '生气', 5: '非常生气/工作台乱' };\n"
        "        const mood = normalizeFurnitureMood();\n"
        "        return ok('家具心情：' + (names[mood] || mood)\n"
        "          + '；压力=' + (Number(state.furniture.moodStress) || 0) + '/' + FURNITURE_MESS_STRESS\n"
        "          + '；工作台=' + (furnitureMoodBlocked() ? '乱了，暂停新制作' : '正常')\n"
        "          + '；旅行安抚 ' + (Number(state.furniture.moodRecoverTrips) || 0) + ' 次'\n"
        "          + '、手工安抚 ' + (Number(state.furniture.moodRecoverCrafts) || 0) + ' 次');\n"
        "      }\n"
        "\n"
        "      case 'furniture_auto': {\n"
        "        const force = (parts[0] || '').toLowerCase() === 'force';\n"
        "        const now = nowSec();\n"
        "        if (force) {\n"
        "          const r = autoReplaceOneFurniture(now, true);\n"
        "          save(); refresh();\n"
        "          return r.changed\n"
        "            ? ok('已换：' + r.fromName + ' → ' + r.toName + '（类型 ' + r.type + '）')\n"
        "            : bad('没换：' + r.reason);\n"
        "        }\n"
        "        const cands = autoFurnitureReplaceCandidates();\n"
        "        const left = (k, v) => (Number(v) > now ? Math.round((Number(v) - now) / 60) + ' 分钟后' : '现在');\n"
        "        return ok('自动开工：' + left('craft', state.furniture.nextAutoCraftAt)\n"
        "          + '检查一次，概率 ' + FURNITURE_AUTO_CRAFT_CHANCE + '%'\n"
        "          + '（默认每拍查；设 FROG_FURNITURE_AUTO_CRAFT_MIN_SEC=10800 就是他的 3 小时）'\n"
        "          + '；自动换家具：' + left('replace', state.furniture.nextAutoReplaceAt)\n"
        "          + '检查一次，概率 ' + FURNITURE_AUTO_REPLACE_CHANCE + '%'\n"
        "          + '；已换 ' + (Number(state.furniture.autoReplaceCount) || 0) + ' 次'\n"
        "          + '；可换的类型 ' + cands.length + ' 个');\n"
        "      }\n"
        "\n"
        "      case 'craft_finish': {",
        'gm furniture_mood/auto cases')

    # ------------------------------------------- 10b. 心情差时不开新活（两条路都挡）
    # 他的设计：mood==5 时工作台"乱掉"，暂停新制作（客户端也把工作台画成罢工、锁住编辑）。
    # 手动路径（摆好图纸+材料就开工）与自动路径都要挡，否则玩家会发现"明明罢工了还在做"。
    src = sub_once(
        src,
        '  function maybeStartCraft() {\n'
        '    if (state.furniture.craft) return false;\n'
        '    const info = craftMissing();',
        '  function maybeStartCraft() {\n'
        '    if (state.furniture.craft) return false;\n'
        '    /* 【并入他的 V3】心情太差（>=27，工作台乱了）时不开新活。 */\n'
        '    if (furnitureMoodBlocked()) return false;\n'
        '    const info = craftMissing();',
        'maybeStartCraft mood gate')

    src = sub_once(
        src,
        "    return maybeStartCraft() ? { ok: true } : { ok: false, reason: '材料没凑齐（不该发生，请报我）' };",
        '    if (furnitureMoodBlocked()) {\n'
        "      return { ok: false, reason: '蛙蛙心情太差（工作台乱了）：先让它旅行回家或做件手工恢复' };\n"
        '    }\n'
        "    return maybeStartCraft() ? { ok: true } : { ok: false, reason: '材料没凑齐（不该发生，请报我）' };",
        'startCraftFor mood reason')

    # ------------------------------------------------- 11. 旧档字段补齐
    src = sub_once(
        src,
        "    if (normalizeGiftBox()) graft.push('giftBox');",
        "    if (normalizeGiftBox()) graft.push('giftBox');\n"
        "    if (normalizeFurnitureAutoFields()) graft.push('furnitureMood');",
        'graft furniture mood')

    write(ENGINE, src)
    print('[workshop] 引擎已改：家具心情/压力 + 自动换家具 + 自动开工（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
