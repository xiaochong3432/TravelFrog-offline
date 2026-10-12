#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 系统 4：按日期/季节的天气 + 节气日 + 月历奖励 + 季节性彩蛋（并入「他做的 3.3」）

他的做法（源码与调用点都核对过）：
  1. **天气按日期与季节决定**（`seasonForMonth` + `WEATHER_BY_SEASON` + `weatherForDate`）：
     每季一张加权候选表（雪只在冬天、霜只在秋冬），同一天所有人看到同一种天气、重启不重掷。
     我们原来是 `(年*372+月*31+日)%9+1`，会出现"夏天飘雪"。
  2. **节气日**（`SOLAR_TERM_DAY_COEFFICIENTS` 24 项 + `solarTermDay`）——他的"节气商店"要用（下一批）。
  3. **月历奖励**（`CALENDAR_MONTH_REWARDS` 31 项，真实 ItemDB id，每天都有能画的图标）；
     我们的 `calendar_load` 原来把已领的日子也发出去（重启会重新长红点），而且奖励一律 30 三叶草。
  4. **季节性彩蛋**（`seasonalMealEgg`/`rotationEgg`/`setFrogEgg`/`eggPayload`）：吃饭出粽子/西瓜，
     5–10 月扇子动作 10% 出彩蛋，夏天夜里加萤火虫；我们的 `easteregg_load` 之前写死 `{egg_list: []}`。

结构（他的引擎也是这个布局）：
  · 纯函数（天气/节气/本地日键）放**模块级**，并加入 `module.exports`（便于单测与外壳复用）；
  · 依赖 state 的部分（月历载荷/发奖/彩蛋）放在 `createEngine` 内。

存档兼容：只新增 `frog.eggId`（老档补 0）；`calendar.claimedSt/claimedLucky` 本来就在默认值里。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-CALENDAR-EGGS'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[cal] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[cal] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


MODULE_BLOCK = """/* __MARK__ ============ 天气（按日期与季节）/ 节气日 / 本地日键（纯函数，模块级） ============ */

/* 5–10 月在家里"扇扇子"动作出彩蛋的概率（他的口径，可用 env 改）。 */
const FROG_FAN_ACTION_CHANCE = Math.min(100, Math.max(0,
  Number(process.env.FROG_FAN_ACTION_CHANCE || 10)));

/* 24 节气的经验系数（他给的复原表）：
   节气日 = floor(年份后两位 * 0.2422 + 系数) - floor((年份后两位 - 1) / 4)。 */
const SOLAR_TERM_DAY_COEFFICIENTS = [
  5.4055, 20.12, 3.87, 18.73, 5.63, 20.646,
  4.81, 20.1, 5.52, 21.04, 5.678, 21.37,
  7.108, 22.83, 7.5, 23.13, 7.646, 23.042,
  8.318, 23.438, 7.438, 22.36, 7.18, 21.94,
];

function solarTermDay(year, termIndex) {
  const yearInCentury = Number(year) % 100;
  const coefficient = SOLAR_TERM_DAY_COEFFICIENTS[termIndex];
  if (!Number.isFinite(yearInCentury) || coefficient === undefined) return 0;
  return Math.floor(yearInCentury * 0.2422 + coefficient)
    - Math.floor((yearInCentury - 1) / 4);
}

function seasonForMonth(month) {
  if (month >= 3 && month <= 5) return 1;
  if (month >= 6 && month <= 8) return 2;
  if (month >= 9 && month <= 11) return 3;
  return 4;
}

/* 每个季节的天气候选（重复项就是权重）。雪(8/9)只在冬天，霜(6)只在秋冬。 */
const WEATHER_BY_SEASON = {
  1: [1, 1, 2, 2, 2, 3, 3, 4, 5, 7],
  2: [1, 1, 1, 2, 2, 3, 3, 3, 4, 5, 7],
  3: [1, 1, 2, 2, 2, 3, 3, 4, 5, 6, 7],
  4: [1, 1, 2, 2, 5, 6, 6, 7, 8, 8, 9],
};

function weatherForDate(year, month, day) {
  const season = seasonForMonth(month);
  const candidates = WEATHER_BY_SEASON[season];
  const dayIndex = Math.floor(Date.UTC(year, month - 1, day) / 86400000);
  return { season, weather: candidates[dayIndex % candidates.length] };
}

/* 本地日期键 YYYYMMDD（他的商店补货/货架与幸运日都按天归档用它）。 */
function localDayKeyAt(at) {
  const d = new Date(Number(at) * 1000);
  return d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();
}

""".replace('__MARK__', MARK)

INNER_BLOCK = """  /* __MARK__ ================= 月历奖励与季节性彩蛋（依赖 state，放在引擎内） ================= */

  /* 月历每天的奖励表（他的复原表；用真实 ItemDB id，保证每个格子都能画出图标）。 */
  const CALENDAR_MONTH_REWARDS = [
    { item_id: ITEM_CLOVER_RES, num: 30 }, { item_id: 101, num: 1 },
    { item_id: 1104, num: 1 }, { item_id: 3000, num: 1 },
    { item_id: 1201, num: 1 }, { item_id: 5101, num: 1 },
    { item_id: ITEM_TICKET_RES, num: 1 }, { item_id: 3002, num: 1 },
    { item_id: 102, num: 1 }, { item_id: 1103, num: 1 },
    { item_id: ITEM_CLOVER_RES, num: 50 }, { item_id: 3004, num: 1 },
    { item_id: 1104, num: 1 }, { item_id: ITEM_TICKET_RES, num: 1 },
    { item_id: 1201, num: 1 }, { item_id: 3012, num: 1 },
    { item_id: 101, num: 1 }, { item_id: ITEM_CLOVER_RES, num: 30 },
    { item_id: 5101, num: 1 }, { item_id: 3014, num: 1 },
    { item_id: ITEM_TICKET_RES, num: 1 }, { item_id: 1104, num: 1 },
    { item_id: ITEM_CLOVER_RES, num: 60 }, { item_id: 3017, num: 1 },
    { item_id: 1103, num: 1 }, { item_id: 102, num: 1 },
    { item_id: 1201, num: 1 }, { item_id: ITEM_TICKET_RES, num: 1 },
    { item_id: ITEM_CLOVER_RES, num: 80 }, { item_id: 3008, num: 1 },
    { item_id: 1104, num: 1 },
  ];

  function calendarTaskPayload() {
    return (state.calendar.taskList || []).slice(0, 3).map((row, i) => ({
      id: Number(row && row.id) || i + 1,
      pro: Number(row && row.pro) || 0,
      complete: 1,
    }));
  }

  /** 月历奖励统一在这里发：三叶草 / 抽奖券 / 普通物品（他的做法）。 */
  function grantCalendarReward(ctx, itemId, count) {
    const id = Number(itemId);
    const n = Math.max(1, Number(count) || 1);
    if (id === ITEM_CLOVER_RES) {
      state.clover += n;
      ctx.push('clover_update', { clover: state.clover });
      return;
    }
    if (id === ITEM_TICKET_RES) {
      state.ticket += n;
      ctx.push('item_update_ticket', { ticket: state.ticket });
      return;
    }
    const have = addHouseItem(id, n);
    pushItemUpdate(ctx, id, have);
  }

  /** 吃饭时的彩蛋：5/15–6 月是粽子季(4)，5–10 月有西瓜(5)，其余 10% 出(2)。 */
  function seasonalMealEgg(t) {
    const d = new Date(Number(t) * 1000);
    const month = d.getMonth() + 1;
    const zongziSeason = (month === 5 && d.getDate() >= 15) || month === 6;
    if (zongziSeason && Math.random() < 0.5) return 4;
    if (month >= 5 && month <= 10 && Math.random() < 0.5) return 5;
    if (Math.random() < 0.1) return 2;
    return 0;
  }

  /** 每次换动作时决定彩蛋：吃饭走季节款，5–10 月的其他动作按 10% 出扇子彩蛋(3)。 */
  function rotationEgg(motion, t) {
    if (Number(motion) === Number(FROGMOTIONNUM.eat)) return seasonalMealEgg(t);
    const month = new Date(Number(t) * 1000).getMonth() + 1;
    return month >= 5 && month <= 10
      && Math.random() * 100 < FROG_FAN_ACTION_CHANCE ? 3 : 0;
  }

  function setFrogEgg(id) {
    const next = Number(id) || 0;
    if (Number(state.frog.eggId) === next) return false;
    state.frog.eggId = next;
    const momentByEgg = {
      1: 'egg_1_dress', 2: 'egg_2_eat', 3: 'egg_3_cook',
      4: 'zongzi', 5: 'egg_5_chixigua',
    };
    if (next && momentByEgg[next]) momentTrigger(2, momentByEgg[next]);
    return true;
  }

  /** `easteregg_load` 的载荷：当前彩蛋 + 雨天访客彩蛋 + 夏天夜里的萤火虫(201)。 */
  function eggPayload() {
    const eggs = [];
    const add = (id) => { if (id && eggs.indexOf(id) === -1) eggs.push(id); };
    add(Number(state.frog.eggId));
    if (state.guest && state.guest.rainEgg) add(Number(state.guest.rainEgg));
    if (seasonNow() === 2 && hoursTypeNow() >= 3) add(201);
    return { egg_list: eggs };
  }

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[cal] 已并入过（%s），跳过' % MARK)
        return 0

    # ------------------------------------------------- 模块级纯函数
    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   MODULE_BLOCK + '/* ---------------------------------------------------------------- engine */',
                   'module block')

    # ------------------------------------------------- 引擎内：月历 + 彩蛋
    src = sub_once(src, '  function seasonNow() {', INNER_BLOCK + '  function seasonNow() {',
                   'inner block')

    # ------------------------------------------------- 天气/季节改用这套
    src = sub_once(
        src,
        '  function weatherNow() {\n'
        '    const d = new Date(nowSec() * 1000);\n'
        '    return ((d.getFullYear() * 372 + (d.getMonth() + 1) * 31 + d.getDate()) % 9) + 1;\n'
        '  }',
        '  /* 【并入他 3.3】天气改成"按日期 + 季节"决定：同一天恒定、季节里只出应季天气。 */\n'
        '  function weatherNow() {\n'
        '    const d = new Date(nowSec() * 1000);\n'
        '    return weatherForDate(d.getFullYear(), d.getMonth() + 1, d.getDate()).weather;\n'
        '  }',
        'weatherNow')

    src = sub_once(
        src,
        '  function seasonNow() {\n'
        '    const m = new Date(nowSec() * 1000).getMonth() + 1;\n'
        '    if (m >= 3 && m <= 5) return 1;        // spring\n'
        '    if (m >= 6 && m <= 8) return 2;        // summer\n'
        '    if (m >= 9 && m <= 11) return 3;       // autumn\n'
        '    return 4;                              // winter\n'
        '  }',
        '  function seasonNow() {\n'
        '    return seasonForMonth(new Date(nowSec() * 1000).getMonth() + 1);\n'
        '  }',
        'seasonNow')

    # ------------------------------------------------- 彩蛋存档位
    src = sub_once(
        src,
        "      status: 0, motion: 0, icon: 0, picShow: 0, todayStep: 0, taobaoData: null,",
        "      status: 0, motion: 0, icon: 0, picShow: 0, todayStep: 0, taobaoData: null,\n"
        "      /* 【并入他 3.3】季节彩蛋 id（0 = 无）。 */\n"
        "      eggId: 0,",
        'frog eggId')

    # ------------------------------------------------- 载荷
    src = sub_once(
        src,
        '    easteregg_load: () => ({ egg_list: [] }),',
        '    /* 【并入他 3.3】彩蛋载荷不再写死空列表：当前彩蛋 / 雨天访客彩蛋 / 夏天夜里萤火虫。 */\n'
        '    easteregg_load: () => eggPayload(),',
        'easteregg_load')

    src = sub_once(
        src,
        '      return {\n'
        '        new_flag: flags,\n'
        '        task_list: state.calendar.taskList.slice(0, 3),\n'
        '        lucky_days: state.calendar.lucky,\n'
        '        st_days: state.calendar.st,\n'
        '      };',
        '      /* 【并入他 3.3】已领的日子不再下发（否则重启会重新长出红点），\n'
        '         每天的奖励套用他的月历表（真实 ItemDB id），并回传已领清单。 */\n'
        '      const claimedSt = new Set(state.calendar.claimedSt || []);\n'
        '      const claimedLucky = new Set(state.calendar.claimedLucky || []);\n'
        '      const stDays = (state.calendar.st || [])\n'
        '        .filter((row) => !claimedSt.has(row.day))\n'
        '        .map((row) => {\n'
        '          const d = Number(row.day);\n'
        '          const fixed = CALENDAR_MONTH_REWARDS[d - 1];\n'
        '          return fixed ? { day: d, item_id: fixed.item_id, num: fixed.num } : row;\n'
        '        });\n'
        '      const luckyDays = (state.calendar.lucky || []).filter((row) => !claimedLucky.has(row.day));\n'
        '      return {\n'
        '        new_flag: flags,\n'
        '        task_list: calendarTaskPayload(),\n'
        '        lucky_days: luckyDays,\n'
        '        st_days: stDays,\n'
        '        claimed_st_days: [...claimedSt],\n'
        '        claimed_lucky_days: [...claimedLucky],\n'
        '      };',
        'calendar_load payload')

    src = sub_once(
        src,
        "      const today = curDayOfMonth();\n"
        "      if (!state.calendar.st.some((e) => e.day === today)) return { code: -1 };\n"
        "      if (state.calendar.claimedSt.indexOf(today) !== -1) return { code: 0 };\n"
        "      state.calendar.claimedSt.push(today);\n"
        "      state.clover += CALENDAR_ST_CLOVER;\n"
        "      save();\n"
        "      ctx.push('clover_update', { clover: state.clover });\n"
        "      return { code: 0 };",
        "      const today = curDayOfMonth();\n"
        "      const row = state.calendar.st.find((e) => e.day === today);\n"
        "      if (!row) return { code: -1 };\n"
        "      if (state.calendar.claimedSt.indexOf(today) !== -1) return { code: 0 };\n"
        "      state.calendar.claimedSt.push(today);\n"
        "      /* 【并入他 3.3】按当天的月历奖励发（原来一律 30 三叶草）。 */\n"
        "      const fixed = CALENDAR_MONTH_REWARDS[today - 1] || row;\n"
        "      const rewardId = Number(fixed.item_id) || ITEM_CLOVER_RES;\n"
        "      const rewardCount = Math.max(1, Number(fixed.num) || 1);\n"
        "      grantCalendarReward(ctx, rewardId, rewardCount);\n"
        "      save();\n"
        "      return { code: 0, item_id: rewardId, count: rewardCount };",
        'calendar_get_st_reward')

    src = sub_once(
        src,
        "      if (!state.calendar.lucky.some((e) => e.day === today)) return { code: -1 };\n"
        "      if (state.calendar.claimedLucky.indexOf(today) !== -1) return { code: 0 };\n"
        "      state.calendar.claimedLucky.push(today);\n"
        "      state.ticket += CALENDAR_LUCKY_TICKETS;\n"
        "      save();\n"
        "      ctx.push('item_update_ticket', { ticket: state.ticket });\n"
        "      return { code: 0 };",
        "      const row = state.calendar.lucky.find((e) => e.day === today);\n"
        "      if (!row) return { code: -1 };\n"
        "      if (state.calendar.claimedLucky.indexOf(today) !== -1) return { code: 0 };\n"
        "      state.calendar.claimedLucky.push(today);\n"
        "      /* 【并入他 3.3】幸运日同样按行里的奖励发。 */\n"
        "      const rewardId = Number(row.reward_item_id || row.item_id) || ITEM_TICKET_RES;\n"
        "      const rewardCount = Math.max(1, Number(row.num) || CALENDAR_LUCKY_TICKETS);\n"
        "      grantCalendarReward(ctx, rewardId, rewardCount);\n"
        "      save();\n"
        "      return { code: 0, item_id: rewardId, count: rewardCount };",
        'calendar_get_luck_reward')

    # ------------------------------------------------- 动作刷新时决定彩蛋
    src = sub_once(
        src,
        '    else if (mode === \'craft\') state.frog.motion = 5 + state.frog.motionStep % 5;\n'
        '    state.frog.motionNextAt = t + FROG_MOTION_SEC;',
        '    else if (mode === \'craft\') state.frog.motion = 5 + state.frog.motionStep % 5;\n'
        '    /* 【并入他 3.3】每换一个动作就重掷季节彩蛋（睡觉时清掉）。 */\n'
        '    setFrogEgg(sleeping ? 0 : rotationEgg(state.frog.motion, t));\n'
        '    state.frog.motionNextAt = t + FROG_MOTION_SEC;',
        'refreshFrogMotion egg')

    # 出门时清掉彩蛋
    src = sub_once(
        src,
        '    state.travel.waitingForBag = false;\n'
        '    // Provisions are decided (and consumed) at DEPARTURE: the stray-or-not outcome',
        '    state.travel.waitingForBag = false;\n'
        '    setFrogEgg(0);        // 【并入他 3.3】出门就不带家里的彩蛋了\n'
        '    // Provisions are decided (and consumed) at DEPARTURE: the stray-or-not outcome',
        'departFrog egg reset')

    # tick 里天气一变就重推彩蛋载荷
    src = sub_once(
        src,
        "    if (refreshWeather()) ctx.push('weather_load', weatherPayload());\n"
        "    if (refreshFrogMotion(t)) ctx.push('client_load_role', rolePayload());",
        "    if (refreshWeather()) {\n"
        "      ctx.push('weather_load', weatherPayload());\n"
        "      /* 【并入他 3.3】天气/季节变了，院子的彩蛋也要跟着换。 */\n"
        "      ctx.push('easteregg_load', eggPayload());\n"
        "    }\n"
        "    if (refreshFrogMotion(t)) {\n"
        "      ctx.push('easteregg_load', eggPayload());\n"
        "      ctx.push('client_load_role', rolePayload());\n"
        "    }",
        'tick egg pushes')

    # ------------------------------------------------- 模块级导出（他的引擎也导出 weatherForDate）
    src = sub_once(
        src,
        'module.exports = { createEngine, canon, toWire, nowSec, defaultState, makeClovers, CLOVER_SLOTS };',
        'module.exports = {\n'
        '  createEngine, canon, toWire, nowSec, defaultState, makeClovers, CLOVER_SLOTS,\n'
        '  /* 【并入他 3.3】他的引擎也导出 weatherForDate；这里连节气日与本地日键一起导出。 */\n'
        '  weatherForDate, solarTermDay, localDayKeyAt,\n'
        '};',
        'exports')

    write(ENGINE, src)
    print('[cal] 引擎已改：按日期/季节的天气 + 节气日 + 月历奖励表 + 季节性彩蛋（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
