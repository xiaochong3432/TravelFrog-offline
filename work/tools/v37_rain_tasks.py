#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 系统 9：雨天客人彩蛋 + 任务计数 + 绘本（友情邀约）出行节奏（并入「他做的 3.3」）

三件事（源码逐段核对）：
  1. **雨天客人**：客人到达时若天气是雨（`weather` 3/4），该客人有 **30%** 概率带上"雨天装扮"
     彩蛋（0/1/2 号客人 -> 彩蛋 103/104/102），彩蛋会跟着 `easteregg_load` 下发
     （`eggPayload` 上一轮已经并进来了，这里补上"什么时候挂上去"）。
  2. **任务计数**：`taskCounters`（按任务 id 计数）+ `taskCounter/addTaskCounter/completeTaskCounter`；
     他的月历奖励领完会给任务 407 记一次（`completeTaskCounter(407)`）。同时补 `taskTiers` 存档位。
  3. **绘本出行节奏**：`DRAWING_TRIP_MIN/MAX_SEC = 4–8 小时`、`DRAWING_HOME_REST_SEC = 1 小时`、
     `DRAWING_CHECK_COOLDOWN_SEC = 8 小时`。我们的实现里"被邀约的伙伴出门"只有 60 秒，
     这里换成他的小时级节奏；**邀约概率仍然是我们这条线用户指定的 75%**（`DRAWING_CHANCE`）。

存档兼容：新增 `taskCounters`/`taskTiers` 两个顶层字段（老档补默认）。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-RAIN-TASKS'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[rain] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[rain] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


MODULE_BLOCK = """/* __MARK__ ============ 雨天客人彩蛋 / 绘本出行节奏 ============ */

/* 客人到达时若在下雨，这位客人有 30% 概率带上雨天装扮彩蛋（0/1/2 号 -> 103/104/102）。 */
const RAIN_GUEST_CHANCE = 0.30;
const RAIN_GUEST_EGG = { 0: 103, 1: 104, 2: 102 };

/* 绘本（友情邀约）的出行节奏 —— 他的口径：伙伴出门 4–8 小时、回来在家歇 1 小时、
   每隔 8 小时才重新看一次邀约条件。邀约**概率**仍是我们这条线用户指定的 75%。 */
const DRAWING_CHECK_COOLDOWN_SEC = Number(process.env.FROG_DRAWING_ROLL || 8 * 60 * 60);
const DRAWING_HOME_REST_SEC = Number(process.env.FROG_DRAWING_REST || 60 * 60);
const DRAWING_TRIP_MIN_SEC = Number(process.env.FROG_DRAWING_TRIP_MIN || 4 * 60 * 60);
const DRAWING_TRIP_MAX_SEC = Math.max(DRAWING_TRIP_MIN_SEC,
  Number(process.env.FROG_DRAWING_TRIP_MAX || 8 * 60 * 60));

""".replace('__MARK__', MARK)

INNER_BLOCK = """  /* __MARK__ ================= 任务计数（依赖 state） ================= */

  /** 某个任务计数当前值（没有就是 0）。 */
  function taskCounter(id) {
    return Math.max(0, Number((state.taskCounters || {})[String(id)]) || 0);
  }

  function addTaskCounter(id, amount) {
    const n = Math.max(0, Number(amount) || 0);
    if (!n) return;
    if (!state.taskCounters || typeof state.taskCounters !== 'object') state.taskCounters = {};
    state.taskCounters[String(id)] = taskCounter(id) + n;
  }

  /** 记"这件事发生过一次"（计数不足 1 才记，避免重复累加）。 */
  function completeTaskCounter(id) {
    if (taskCounter(id) < 1) addTaskCounter(id, 1);
  }

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[rain] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 常量
    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   MODULE_BLOCK + '/* ---------------------------------------------------------------- engine */',
                   'module block')

    # ---------------------------------------------------------------- 存档位
    src = sub_once(
        src,
        '    tasks: [],\n    taskList: [],',
        '    tasks: [],\n    taskList: [],\n'
        '    /* %s 【并入他 3.3】任务计数（按任务 id）/ 任务档位。 */\n'
        '    taskCounters: {},\n'
        '    taskTiers: {},\n' % MARK,
        'task state')

    # ---------------------------------------------------------------- 任务计数函数
    src = sub_once(src, '  function tickGuest(ctx, t) {', INNER_BLOCK + '  function tickGuest(ctx, t) {',
                   'task counters')

    # ---------------------------------------------------------------- 雨天客人彩蛋
    src = sub_once(
        src,
        '    state.guest = pickGuest();\n'
        '    state.guestVisits = (state.guestVisits || 0) + 1;',
        '    state.guest = pickGuest();\n'
        '    /* %s 【并入他 3.3】下雨天来的客人有 30%% 概率带"雨天装扮"彩蛋。 */\n'
        '    {\n'
        '      const wx = Number((state.weather || {}).weather) || 0;\n'
        '      const isRain = wx === 3 || wx === 4;\n'
        '      const guestId = Number(state.guest && state.guest.id);\n'
        '      if (isRain && RAIN_GUEST_EGG[guestId] && Math.random() < RAIN_GUEST_CHANCE) {\n'
        '        state.guest.rainEgg = RAIN_GUEST_EGG[guestId];\n'
        '      }\n'
        '    }\n'
        '    state.guestVisits = (state.guestVisits || 0) + 1;' % MARK,
        'rain guest egg')

    # ---------------------------------------------------------------- 月历奖励记任务 407
    src = sub_once(
        src,
        "      const fixed = CALENDAR_MONTH_REWARDS[today - 1] || row;\n"
        "      const rewardId = Number(fixed.item_id) || ITEM_CLOVER_RES;\n"
        "      const rewardCount = Math.max(1, Number(fixed.num) || 1);\n"
        "      grantCalendarReward(ctx, rewardId, rewardCount);\n"
        "      save();",
        "      const fixed = CALENDAR_MONTH_REWARDS[today - 1] || row;\n"
        "      const rewardId = Number(fixed.item_id) || ITEM_CLOVER_RES;\n"
        "      const rewardCount = Math.max(1, Number(fixed.num) || 1);\n"
        "      grantCalendarReward(ctx, rewardId, rewardCount);\n"
        "      /* 【并入他 3.3】领「当日奖励」= 任务 407 记一次（他的写法，只有 st 奖励记）。 */\n"
        "      completeTaskCounter(407);\n"
        "      save();",
        'calendar task 407')

    # 状态归零那段会把冷却清掉，这里改成"保留冷却/没有就补一个 8 小时"
    src = sub_once(
        src,
        '      state.drawingReturnAt = 0;\n'
        '      state.drawingNextRollAt = 0;\n'
        '    }',
        '      state.drawingReturnAt = 0;\n'
        '      /* 【并入他 3.3】回来后的 8 小时冷却由出行分支设置，这里别清零。 */\n'
        '      if (!Number(state.drawingNextRollAt)) {\n'
        '        state.drawingNextRollAt = t + DRAWING_CHECK_COOLDOWN_SEC;\n'
        '      }\n'
        '    }',
        'drawing reset keeps cooldown')

    # ---------------------------------------------------------------- 绘本出行节奏
    # 接受邀约、进入"出行"状态时把回程时间设成小时级（他 4–8 小时；我们原来是 +60 秒）
    src = sub_once(
        src,
        '        d.state = 4; // visit\n'
        '        state.drawingReturnAt += 60;',
        '        d.state = 4; // visit\n'
        '        /* 【并入他 3.3】被邀约的伙伴出门 4–8 小时（原来是 60 秒）。 */\n'
        '        state.drawingReturnAt = t + randInt(DRAWING_TRIP_MIN_SEC, DRAWING_TRIP_MAX_SEC);',
        'drawing accept trip')
    # 出行结束：回家歇一小时，再按他的 8 小时冷却重新看邀约条件
    src = sub_once(
        src,
        '    if (d.state === 4) {\n'
        '      if (!state.drawingReturnAt) { state.drawingReturnAt = t + 60; changed = true; }\n'
        '      if (t >= state.drawingReturnAt) { d.state = 0; changed = true; }\n'
        '    }',
        '    if (d.state === 4) {\n'
        '      if (!state.drawingReturnAt) {\n'
        '        state.drawingReturnAt = t + randInt(DRAWING_TRIP_MIN_SEC, DRAWING_TRIP_MAX_SEC);\n'
        '        changed = true;\n'
        '      }\n'
        '      if (t >= state.drawingReturnAt) {\n'
        '        d.state = 0;\n'
        '        /* 【并入他 3.3】回来先在家歇一小时，之后每 8 小时才重新看一次邀约条件。 */\n'
        '        state.drawingRestUntil = t + DRAWING_HOME_REST_SEC;\n'
        '        state.drawingNextRollAt = t + DRAWING_CHECK_COOLDOWN_SEC;\n'
        '        changed = true;\n'
        '      }\n'
        '    }',
        'drawing trip hours')

    write(ENGINE, src)
    print('[rain] 引擎已改：雨天客人彩蛋 + 任务计数(含 407) + 绘本 4–8 小时出行（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
