#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""方案 A：把「他做的 V3 包」（TravelFrog-offline-V3.apk.1，2026-09-19 收到）里的
**小时级节奏 + 概率出门 + 开局行李**并入我们的引擎，并设为默认。

用户 2026-09-19 的决定：
  · 先做方案 A（只搬节奏与概率这一层，不搬家具工坊/礼物盒来访那套大系统）；
  · 动作间隔「按他的代码来」＝ 10 分钟（他口述的 45 分钟与代码不符，实测也是 10 分钟）；
  · 小时级节奏做**默认**（不是开关）；
  · 交付版本号 V3.6，versionCode 仍为 9。

他家这些值的出处（逐行核对过他引擎源码，同文件 work/build/his3/engine_live/index.js）：
  FROG_MOTION_SEC                     10 * 60
  TRAVEL_MIN_SEC / TRAVEL_MAX_SEC     120 * 60 / 510 * 60     (2–8.5 小时)
  TRAVEL_HARD_MAX_SEC                 72 * 60 * 60
  TRAVEL_IDLE_MIN / MAX               3 * 3600 / 5 * 3600
  TRAVEL_WAIT_UNPREPARED_MIN / MAX    3 * 3600 / 5 * 3600
  TRAVEL_DEPART_CHANCE                50
  DRIFT_RETURN_MIN / MAX              ORIG * 60（表里是分钟 10/20）
  STARTER_LUNCH/AMULET/TOOLS/SPECIALTY + preparationSeeded

我们这边**不需要**搬的：旅行槽位（他的 putTravelSlot/takeTravelSlot/normalizeTravelSlots）。
我们的 `packItem()` 已经等价实现（还多一层槽位类型校验），并有 3378 行的槽位清账。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')

MARK = 'V36-PACING'          # 幂等标记：出现过就说明本步已应用


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[pacing] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[pacing] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[pacing] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 头部说明表
    src = sub_once(
        src,
        '   | travel length       | TRAVEL_TIME_MIN = 60               | 90-240 s        |\n'
        '   | stray (放浪) return | FROG_DRIFTRETURNTIME 10 / MAX 20   | same            |\n'
        '   | frog rest           | FROG_RESTTIME 400 / MAX 900        | 20-45 s         |\n'
        '   | standby wait        | FROG_STANDBY_WAIT_MIN = 60         | 20-45 s         |\n',
        '   | travel length       | TRAVEL_TIME_MIN = 60 (min)         | 2-8.5 h         |\n'
        '   | stray (放浪) return | FROG_DRIFTRETURNTIME 10 / MAX 20   | same (min)      |\n'
        '   | frog at-home action | (no table)                         | 10 min          |\n'
        '   | standby wait        | FROG_STANDBY_WAIT_MIN = 60 (min)   | 3-5 h           |\n',
        'header table (pacing rows)')

    # ------------------------------------------------------------ 节奏常量（默认值）
    src = sub_once(
        src,
        "const TRAVEL_MIN_SEC = pace('FROG_TRAVEL_MIN', 12 * 60, ORIG.travelTimeMin * 60);",
        '/* %s 【自设计·并入他的 V3，2026-09-19】小时级节奏设为**默认**（不再是开关）：\n'
        '   一趟 2–8.5 小时，与他的 FROG_TRAVEL_MIN/MAX 默认值一致。\n'
        '   FROG_FAITHFUL=1 仍是原版口径（60 分钟起、6 倍上限），env 仍可覆盖。 */\n'
        "const TRAVEL_MIN_SEC = pace('FROG_TRAVEL_MIN', 120 * 60, ORIG.travelTimeMin * 60);" % MARK,
        'TRAVEL_MIN_SEC')

    src = sub_once(
        src,
        "const TRAVEL_MAX_SEC = pace('FROG_TRAVEL_MAX', 40 * 60, ORIG.travelTimeMin * 60 * 6);",
        "const TRAVEL_MAX_SEC = pace('FROG_TRAVEL_MAX', 510 * 60, ORIG.travelTimeMin * 60 * 6);\n"
        '/* 便当 HP 加成与门票缩短之后再压一道硬上限：任何一趟都不超过 72 小时（他的设定）。 */\n'
        'const TRAVEL_HARD_MAX_SEC = 72 * 60 * 60;',
        'TRAVEL_MAX_SEC + HARD_MAX')

    src = sub_once(
        src,
        '// How long the frog waits at home before heading out again.\n'
        "const TRAVEL_IDLE_MIN = pace('FROG_IDLE_MIN', 2 * 60, ORIG.standbyWaitMin);\n"
        "const TRAVEL_IDLE_MAX = pace('FROG_IDLE_MAX', 6 * 60, ORIG.restTick);",
        '// How long the frog waits at home before rolling to head out again (3-5 h).\n'
        "const TRAVEL_IDLE_MIN = pace('FROG_IDLE_MIN', 3 * 3600, ORIG.standbyWaitMin);\n"
        "const TRAVEL_IDLE_MAX = pace('FROG_IDLE_MAX', 5 * 3600, ORIG.restTick);\n"
        '/* 到点只掷一次骰：50% 才真的出门（他的 TRAVEL_DEPART_CHANCE）。掷不中就按下面的\n'
        '   间隔重新排下一次检查；中了就走，哪怕背包是空的 —— 那一趟按放浪（短窗口）结算。 */\n'
        "const TRAVEL_DEPART_CHANCE = Number(process.env.FROG_TRAVEL_CHANCE || 50);",
        'TRAVEL_IDLE_* + DEPART_CHANCE')

    src = sub_once(
        src,
        '/* 没准备就不出门 (OUR rule, see the file header note): while the bag is empty the frog\n'
        '   stays home, and it re-checks on this interval instead of leaving. */\n'
        "const TRAVEL_WAIT_UNPREPARED_MIN = pace('FROG_WAIT_MIN', 3 * 60, ORIG.standbyWaitMin);\n"
        "const TRAVEL_WAIT_UNPREPARED_MAX = pace('FROG_WAIT_MAX', 8 * 60, ORIG.restTick);",
        '/* 掷骰没中时下一次检查的间隔（3–5 小时）。空背包也能出门，所以这不再等于\n'
        '   "没准备就不出门"的等待，只是下一次掷骰的间隔。 */\n'
        "const TRAVEL_WAIT_UNPREPARED_MIN = pace('FROG_WAIT_MIN', 3 * 3600, ORIG.standbyWaitMin);\n"
        "const TRAVEL_WAIT_UNPREPARED_MAX = pace('FROG_WAIT_MAX', 5 * 3600, ORIG.restTick);",
        'TRAVEL_WAIT_UNPREPARED_*')

    src = sub_once(
        src,
        'const DRIFT_RETURN_MIN = Number(process.env.FROG_DRIFT_MIN || ORIG.driftReturn);\n'
        'const DRIFT_RETURN_MAX = Number(process.env.FROG_DRIFT_MAX || ORIG.driftReturnMax);',
        '/* 表里这两项是**分钟**（10 / 20），引擎存的是秒，所以要 ×60 —— 他的口径。\n'
        '   以前按秒用，一趟放浪只有 10–20 秒。 */\n'
        'const DRIFT_RETURN_MIN = Number(process.env.FROG_DRIFT_MIN || (ORIG.driftReturn * 60));\n'
        'const DRIFT_RETURN_MAX = Number(process.env.FROG_DRIFT_MAX || (ORIG.driftReturnMax * 60));',
        'DRIFT_RETURN_* ×60')

    # ------------------------------------------------------------------ 动作间隔
    src = sub_once(
        src,
        '  const FROG_MOTION_SEC = Number(process.env.FROG_MOTION_SEC || 45);',
        '  /* 【并入他的 V3】在家动作每 10 分钟换一次（他口述是"45 分钟"，但他代码与实测\n'
        '     都是 10 分钟 = 600 s；用户 2026-09-19 定：按他代码来）。 */\n'
        '  const FROG_MOTION_SEC = Number(process.env.FROG_MOTION_SEC || 10 * 60);',
        'FROG_MOTION_SEC')

    # ------------------------------------------------------- 开局行李：模块级常量
    src = sub_once(
        src,
        'const ITEM_TYPE_TOOLS = 2;',
        'const ITEM_TYPE_TOOLS = 2;\n'
        '\n'
        '/* 【自设计·并入他的 V3，2026-09-19】开局行李（他的 STARTER_* 口径）。\n'
        '   小时级节奏下"没便当就只能放浪"，所以开局补一套能真的出门的东西：\n'
        '   便当（绘本食物 + 前三样便当）各 3、护身符各 1、工具各 1、特产各 2。 */\n'
        "const DRAWING_FOOD_IDS = ['value2', 'value3', 'value4']\n"
        '  .map((k) => String((((((gamedata.tables || {}).drawingCommonData || {}).food) || {})[k]\n'
        "    || [])[0] || '').split(',')[1])\n"
        '  .map((v) => Number(v))\n'
        '  .filter((v) => Number.isFinite(v));\n'
        'const STARTER_LUNCH_IDS = Array.from(new Set(DRAWING_FOOD_IDS.concat(gamedata.items\n'
        '  .filter((i) => Number(i.type) === ITEM_TYPE_LUNCHBOX && Number(i.id) > 0)\n'
        '  .slice(0, 3).map((i) => Number(i.id)))));\n'
        'const STARTER_AMULET_IDS = gamedata.items\n'
        '  .filter((i) => Number(i.type) === ITEM_TYPE_AMULET && Number(i.id) > 0)\n'
        '  .slice(0, 2).map((i) => Number(i.id));\n'
        'const STARTER_TOOL_IDS = gamedata.items\n'
        '  .filter((i) => Number(i.type) === ITEM_TYPE_TOOLS && Number(i.id) > 0)\n'
        '  .slice(0, 3).map((i) => Number(i.id));\n'
        'const STARTER_SPECIALTY_IDS = SPECIALTY_IDS.slice(0, 8);',
        'STARTER_* constants')

    # ------------------------------------------------- 开局行李：播种函数 + 调用点
    src = sub_once(
        src,
        '  /* ---- the one call site: after V3.1\'s own slot repair, before anything reads the state --- */\n'
        '  try {\n'
        '    const graft = [];',
        '  /* 【并入他的 V3，2026-09-19】开局行李：只在第一次（preparationSeeded 之前）补，\n'
        '     之后完全不动。判定口径照他的：便当/特产看"家里有没有这一类"，护身符/工具看\n'
        '     "总共有没有"（背包/桌子上也算）。 */\n'
        '  function seedPreparationInventory() {\n'
        '    if (state.items.preparationSeeded) return false;\n'
        '    const top = (ids, count) => {\n'
        '      for (const raw of ids) {\n'
        '        const id = Number(raw);\n'
        '        if (!ITEM_BY_ID.has(id) || getHouseOnlyItemCount(id) > 0) continue;\n'
        '        addHouseItem(id, count);\n'
        '      }\n'
        '    };\n'
        '    const haveType = (type) => gamedata.items.some((it) => Number(it.type) === type\n'
        '      && getHaveItem(Number(it.id)) > 0);\n'
        '    const houseType = (type) => gamedata.items.some((it) => Number(it.type) === type\n'
        '      && getHouseOnlyItemCount(Number(it.id)) > 0);\n'
        '    if (!houseType(ITEM_TYPE_LUNCHBOX)) top(STARTER_LUNCH_IDS, 3);\n'
        '    if (!haveType(ITEM_TYPE_AMULET)) top(STARTER_AMULET_IDS, 1);\n'
        '    if (!haveType(ITEM_TYPE_TOOLS)) top(STARTER_TOOL_IDS, 1);\n'
        '    if (!houseType(ITEM_TYPE_SPECIALTY)) top(STARTER_SPECIALTY_IDS, 2);\n'
        '    state.items.preparationSeeded = true;\n'
        '    return true;\n'
        '  }\n'
        '\n'
        '  /* ---- the one call site: after V3.1\'s own slot repair, before anything reads the state --- */\n'
        '  try {\n'
        '    const graft = [];',
        'seedPreparationInventory()')

    src = sub_once(
        src,
        "    if (migrateTripSpecialtysToHouse()) graft.push('specialtys');\n"
        "    if (debitPackedSlotsOnce()) graft.push('slotDebit');",
        "    if (migrateTripSpecialtysToHouse()) graft.push('specialtys');\n"
        "    if (seedPreparationInventory()) graft.push('prepSeeded');\n"
        "    if (debitPackedSlotsOnce()) graft.push('slotDebit');",
        'graft call site')

    # ---------------------------------------------------------- tripPrepared 口径
    src = sub_once(
        src,
        '  function tripPrepared() {\n'
        '    return isType(state.items.bag[0], ITEM_TYPE_LUNCHBOX)\n'
        '      || state.items.desk.slice(0, 2).some(id => isType(id, ITEM_TYPE_LUNCHBOX));\n'
        '  }',
        '  /* 【并入他的 V3】口径改成他的：背包里有**任何**东西就算准备好；桌子上放着\n'
        '     便当/护身符/工具也算。它现在只决定 waiting_for_bag 这个提示，不再决定能不能\n'
        '     出门（能不能走看 tick() 里那次 50% 掷骰，空背包走的是放浪）。 */\n'
        '  function tripPrepared() {\n'
        '    if ((state.items.bag || []).some((id) => id !== -1 && id !== null && id !== undefined)) {\n'
        '      return true;\n'
        '    }\n'
        '    return (state.items.desk || []).some((id) => isType(id, ITEM_TYPE_LUNCHBOX)\n'
        '      || isType(id, ITEM_TYPE_AMULET) || isType(id, ITEM_TYPE_TOOLS));\n'
        '  }',
        'tripPrepared')

    # ------------------------------------------------- departFrog：去掉门槛 + 硬上限
    src = sub_once(
        src,
        '  function departFrog(ctx, t) {\n'
        '    if (!tripPrepared()) return null;',
        '  function departFrog(ctx, t) {\n'
        '    /* 【并入他的 V3】不再要求"先准备"：掷骰中了就能走；没便当的那一趟按放浪\n'
        '       结算（DRIFT 短窗口，不带照片/特产回来）。 */',
        'departFrog gate')

    src = sub_once(
        src,
        'state.travel.returnAt = t + Math.max(20, window);',
        'state.travel.returnAt = t + Math.min(Math.max(20, window), TRAVEL_HARD_MAX_SEC);',
        'departFrog hard cap')

    # ------------------------------------------------------------- tick 概率出门
    src = sub_once(
        src,
        '        // No food, no departure; tools and amulets alone cannot start a trip.\n'
        '        if (tripPrepared()) {\n'
        '          departFrog(ctx, t);\n'
        '        } else {\n'
        '          state.travel.waitingForBag = true;\n'
        '          state.travel.nextDepartAt = t\n'
        '            + randInt(TRAVEL_WAIT_UNPREPARED_MIN, TRAVEL_WAIT_UNPREPARED_MAX);\n'
        '          save();\n'
        '        }',
        '        /* 【并入他的 V3，2026-09-19】到点掷一次骰：50% 才真的出门。\n'
        '           掷中就走（背包空着也走，那趟是放浪）；没掷中就把下一次检查推到 3–5 小时后。 */\n'
        '        const departChance = Math.max(0, Math.min(100, Number(TRAVEL_DEPART_CHANCE) || 0));\n'
        '        const departRoll = Math.random() * 100;\n'
        '        if (departRoll < departChance) {\n'
        '          departFrog(ctx, t);\n'
        '        } else {\n'
        '          state.travel.waitingForBag = !tripPrepared();\n'
        '          state.travel.nextDepartAt = t\n'
        '            + randInt(TRAVEL_WAIT_UNPREPARED_MIN, TRAVEL_WAIT_UNPREPARED_MAX);\n'
        '          state.travel.lastDepartRoll = departRoll;\n'
        '          state.travel.lastDepartRollAt = t;\n'
        '          save();\n'
        '        }',
        'tick depart roll')

    # -------------------------------------------------- 登录时也补一次开局行李
    src = sub_once(
        src,
        '      ensureTutorialMails();',
        '      ensureTutorialMails();\n'
        '      seedPreparationInventory();   /* 开局行李（并入他的 V3）：登录时兜一次底 */',
        'hall_enter_game seeding')

    write(ENGINE, src)
    print('[pacing] 引擎已改：小时级节奏 + 50%% 概率出门 + 10 分钟动作 + 开局行李（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
