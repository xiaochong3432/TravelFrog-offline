#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 系统 8：花盆的肥力速度 + 花瓶生命周期与自动更换（并入「他做的 3.3」）

他这部分的两件事（源码逐段核对）：
  1. **花盆**：`plantRandomFlowerpot(t)` —— 访客离开时种花，且肥料星级 < 1 就不种；
     每株的 `stageSec = PLANT_STAGE_SEC / 星级`（土越肥长得越快，1–3 星封顶）。
  2. **花瓶/庭院装饰的生命周期**（`decorationFlowerRule` + `refreshDecoration`）：
     野草 2 天（第 1 天转形态）、蜡梅 5 天（3 天转形态）、栽培花 6 天（5 天转形态）、
     其余 7 天不变形态；到期自动撤下。以及 `maybeAutoChangeVaseFlower`：
     每 24 小时掷一次、35% 概率换成另一件**已拥有**的装饰（换下来的退回库存）。

本补丁的取舍（写在这里免得误读）：
  · 花盆"空位自动种"是**上游 3.4 的行为**（客户端根本没有种植命令，空着就永远是空的），
    这条保留；他的"访客离开才种、星级不足不种"作为**额外触发**接上（收获之后访客来访就能补种）。
  · 采纳他的**星级决定生长速度**，所以上一轮并进来的土壤肥力真的影响花盆了。
  · 花瓶生命周期与 24 小时自动更换按他的实现。

存档兼容：`decoration` 只加 `startedAt` / `nextAutoChangeAt` / `autoChangeCount` / `autoChangeLastAt`
四个字段（老档补默认）；`hasList`/`putId`/`status` 语义不变。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-FLOWER-VASE'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[flower] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[flower] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


MODULE_BLOCK = """/* __MARK__ ============ 花盆生长速度 / 花瓶生命周期与自动更换 ============ */

const DAY_SEC = 24 * 60 * 60;

/* 野草类装饰（会长出来又枯掉的那几种）。 */
const WILD_GRASS_DECORATIONS = new Set([1001, 1002, 1003, 1004, 1005]);
const CULTIVATED_DECORATION_MIN = 10011;
const CULTIVATED_DECORATION_MAX = 10063;

/* 花瓶自动更换：每 24 小时掷一次，35% 概率换成别的已拥有装饰（他的口径，可用 env 改）。 */
const VASE_AUTO_CHANGE_SECONDS = Math.max(60,
  Number(process.env.FROG_VASE_AUTO_CHANGE_SECONDS || 24 * 60 * 60));
const VASE_AUTO_CHANGE_CHANCE = Math.min(100, Math.max(0,
  Number(process.env.FROG_VASE_AUTO_CHANGE_CHANCE || 35)));

""".replace('__MARK__', MARK)

INNER_BLOCK = """  /* __MARK__ ================= 花盆与花瓶（依赖 state） ================= */

  /** 星级越高长得越快：`PLANT_STAGE_SEC / 星级`（1–3 星封顶，最少 60 秒）。 */
  function plantStageSeconds(stars) {
    const level = Math.max(1, Math.min(3, Number(stars) || 1));
    return Math.max(60, Math.round(PLANT_STAGE_SEC / level));
  }

  /** 花盆槽位形状（老档/损坏档补齐成 FLOWERPOT_SLOTS 个空槽）。 */
  function ensureFlowerpotSlots() {
    if (!Array.isArray(state.flowerpot.slots)
        || state.flowerpot.slots.length !== FLOWERPOT_SLOTS) {
      state.flowerpot.slots = [];
      for (let i = 0; i < FLOWERPOT_SLOTS; i++) {
        state.flowerpot.slots.push({ id: 0, stage: 0, plantedAt: 0 });
      }
      return true;
    }
    return false;
  }

  /** 他的触发：访客离开时种一株（土不够肥就空着）。空位随便挑、品种随便挑。 */
  function plantRandomFlowerpot(t) {
    refreshCompost(t);
    const compost = state.furniture.compost || {};
    ensureFlowerpotSlots();
    const empty = [];
    for (let i = 0; i < state.flowerpot.slots.length; i += 1) {
      if (!state.flowerpot.slots[i].id) empty.push(i);
    }
    const stars = soilStars(Number(compost.fertility) || 0);
    if (!empty.length || stars < 1 || !FLOWER_PLANTS.length) return false;
    const slotIndex = empty[randInt(0, empty.length - 1)];
    const plantId = Number(FLOWER_PLANTS[randInt(0, FLOWER_PLANTS.length - 1)]);
    const plantedAt = Number(t) || nowSec();
    state.flowerpot.slots[slotIndex] = {
      id: plantId,
      stage: 1,
      plantedAt,
      fertility: stars,
      stageSec: plantStageSeconds(stars),
      seededByGuest: true,
    };
    save();
    return true;
  }

  /** 一件装饰的生命周期：[总时长, 转形态的时刻]（null = 不变形态）。 */
  function decorationFlowerRule(id) {
    if (WILD_GRASS_DECORATIONS.has(Number(id))) {
      return { lifeSec: 2 * DAY_SEC, stage2Sec: 1 * DAY_SEC };
    }
    if (Number(id) === 100) {
      // 蜡梅：含苞三天，开花两天，总计五天。
      return { lifeSec: 5 * DAY_SEC, stage2Sec: 3 * DAY_SEC };
    }
    if (Number(id) >= CULTIVATED_DECORATION_MIN
      && Number(id) <= CULTIVATED_DECORATION_MAX) {
      // 角堇/葡风/风信子/鸢尾/郁金香/铃兰：美丽五天，枯萎一天。
      return { lifeSec: 6 * DAY_SEC, stage2Sec: 5 * DAY_SEC };
    }
    // 木槿、桂花、丁香、建兰、水仙：保持同一形态七天。
    return { lifeSec: 7 * DAY_SEC, stage2Sec: null };
  }

  /** 把某个装饰从库存里扣掉一件（撤下花瓶时用）。 */
  function removeDisplayedDecoration(id) {
    const list = state.decoration.hasList || [];
    const entry = list.find((d) => Number(d.id) === Number(id));
    if (!entry) return;
    entry.num = Math.max(0, Number(entry.num) - 1);
    if (entry.num <= 0) {
      state.decoration.hasList = list.filter((d) => d !== entry);
    }
  }

  function decorationPayload() {
    return {
      has_list: decorationInventory(),
      put_id: state.decoration.putId || 0,
      status: state.decoration.status || 0,
    };
  }

  /** 推进当前摆着的花：到第二形态改 status、到寿命就撤下（`startedAt` 是我们新加的字段，
      老档没有就按"现在开始"算，不会把老档的花直接判死）。 */
  function refreshDecoration(t, ctx) {
    const D = state.decoration;
    const putId = Number(D.putId) || 0;
    if (!putId) {
      if (D.status || D.startedAt) {
        D.status = 0;
        D.startedAt = 0;
        return true;
      }
      return false;
    }
    if (!DECORATIONS[String(putId)]) {
      D.putId = 0;
      D.status = 0;
      D.startedAt = 0;
      if (ctx) ctx.push('client_load_decorate', decorationPayload());
      return true;
    }
    const rule = decorationFlowerRule(putId);
    let startedAt = Number(D.startedAt) || 0;
    let changed = false;
    if (!startedAt) {
      /* 老档没有摆放时间：本来已经是第二形态的就按"刚好进第二形态"倒推，否则从现在开始。 */
      startedAt = Number(D.status) >= 2 && rule.stage2Sec ? t - rule.stage2Sec : t;
      D.startedAt = startedAt;
      changed = true;
    }
    const elapsed = Math.max(0, t - startedAt);
    if (elapsed >= rule.lifeSec) {
      removeDisplayedDecoration(putId);
      D.putId = 0;
      D.status = 0;
      D.startedAt = 0;
      if (ctx) ctx.push('client_load_decorate', decorationPayload());
      return true;
    }
    const nextStatus = rule.stage2Sec !== null && elapsed >= rule.stage2Sec ? 2 : 1;
    if (Number(D.status) !== nextStatus) {
      D.status = nextStatus;
      changed = true;
      if (ctx) ctx.push('client_load_decorate', decorationPayload());
    }
    return changed;
  }

  /** 每 24 小时掷一次：35% 概率把花瓶换成另一件已拥有的装饰（换下来的退回库存）。 */
  function maybeAutoChangeVaseFlower(at, ctx) {
    const D = state.decoration;
    if (!Number(D.nextAutoChangeAt)) {
      D.nextAutoChangeAt = Number(at) + VASE_AUTO_CHANGE_SECONDS;
      save();
      return false;
    }
    if (Number(at) < Number(D.nextAutoChangeAt)) return false;
    D.nextAutoChangeAt = Number(at) + VASE_AUTO_CHANGE_SECONDS;
    save();
    if (Math.random() * 100 >= VASE_AUTO_CHANGE_CHANCE) return false;
    if (state.frog.status !== 0 || !(Number(D.putId) > 0)) return false;

    const choices = decorationInventory().filter((row) => Number(row.id) !== Number(D.putId));
    if (!choices.length) return false;
    const nextId = Number(choices[randInt(0, choices.length - 1)].id);
    const item = DECORATION_ITEMS.get(nextId);
    const stored = (D.hasList || []).find((row) => Number(row.id) === nextId);
    if ((!stored || Number(stored.num) <= 0)
      && item && state.items.house.some((row) => Number(row.item_id) === item.id && row.count > 0)) {
      addHouseItem(item.id, -1);
      addDecoration(nextId, 1);
      pushItemUpdate(ctx, item.id, getHaveItem(item.id));
    }
    removeDisplayedDecoration(D.putId);
    D.putId = nextId;
    D.status = 1;
    D.startedAt = Number(at);
    D.autoChangeCount = (Number(D.autoChangeCount) || 0) + 1;
    D.autoChangeLastAt = Number(at);
    save();
    if (ctx) ctx.push('client_load_decorate', handlers.client_load_decorate());
    return true;
  }

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[flower] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 常量
    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   MODULE_BLOCK + '/* ---------------------------------------------------------------- engine */',
                   'module block')

    # ---------------------------------------------------------------- 默认存档位
    src = sub_once(
        src,
        'decoration: { hasList: [], putId: 0, status: 0 }',
        'decoration: {\n'
        '      hasList: [], putId: 0, status: 0,\n'
        '      /* %s 【并入他 3.3】摆放时间 / 下一次自动更换时间 / 已自动更换次数。 */\n'
        '      startedAt: 0, nextAutoChangeAt: 0, autoChangeCount: 0, autoChangeLastAt: 0,\n'
        '    }' % MARK,
        'decoration defaults')

    # ---------------------------------------------------------------- 引擎内函数
    src = sub_once(src, '  function refreshFlowerpot(t) {', INNER_BLOCK + '  function refreshFlowerpot(t) {',
                   'inner block')

    # ---------------------------------------------------------------- 花盆：星级决定速度
    src = sub_once(
        src,
        '    let changed = false;\n'
        '    for (const s of state.flowerpot.slots) {\n'
        '      if (!s.id) {\n'
        '        if (FLOWER_PLANTS.length) {\n'
        '          s.id = Number(FLOWER_PLANTS[randInt(0, FLOWER_PLANTS.length - 1)]);\n'
        '          s.stage = 1;\n'
        '          s.plantedAt = t;\n'
        '          changed = true;\n'
        '        }\n'
        '        continue;\n'
        '      }\n'
        '      const want = Math.min(3, 1 + Math.floor((t - (s.plantedAt || t)) / PLANT_STAGE_SEC));\n'
        '      if (want !== s.stage) { s.stage = want; changed = true; }\n'
        '    }',
        '    let changed = false;\n'
        '    /* 【并入他 3.3】生长速度由土地肥力的星级决定（1–3 星 -> 1/2/3 倍速）。 */\n'
        '    const stars = soilStars(Number((state.furniture.compost || {}).fertility) || 0);\n'
        '    const stageSec = plantStageSeconds(stars);\n'
        '    for (const s of state.flowerpot.slots) {\n'
        '      if (!s.id) {\n'
        '        if (FLOWER_PLANTS.length) {\n'
        '          s.id = Number(FLOWER_PLANTS[randInt(0, FLOWER_PLANTS.length - 1)]);\n'
        '          s.stage = 1;\n'
        '          s.plantedAt = t;\n'
        '          s.fertility = stars;\n'
        '          s.stageSec = stageSec;\n'
        '          changed = true;\n'
        '        }\n'
        '        continue;\n'
        '      }\n'
        '      const sec = Number(s.stageSec) || stageSec;\n'
        '      const want = Math.min(3, 1 + Math.floor((t - (s.plantedAt || t)) / sec));\n'
        '      if (want !== s.stage) { s.stage = want; changed = true; }\n'
        '    }',
        'flowerpot star speed')

    # ---------------------------------------------------------------- 载荷与 tick
    src = sub_once(
        src,
        '    client_load_decorate: () => ({\n'
        '      // Harvested flower items remain in the house until selected for the vase.\n'
        '      // Expose them with decoration IDs without copying/duplicating ownership.\n'
        '      has_list: decorationInventory(),\n'
        '      put_id: state.decoration.putId || 0,\n'
        '      status: state.decoration.status || 0,\n'
        '    }),',
        '    /* 【并入他 3.3】取载荷前先推进花期（到点转形态/枯萎撤下）。 */\n'
        '    client_load_decorate: () => {\n'
        '      if (refreshDecoration(nowSec())) save();\n'
        '      // Harvested flower items remain in the house until selected for the vase.\n'
        '      // Expose them with decoration IDs without copying/duplicating ownership.\n'
        '      return decorationPayload();\n'
        '    },',
        'client_load_decorate')

    src = sub_once(
        src,
        '    refreshClovers(t);\n',
        '    refreshClovers(t);\n'
        '    /* 【并入他 3.3】花期推进 + 花瓶每 24 小时可能自动换花。 */\n'
        '    if (refreshDecoration(t, ctx)) save();\n'
        '    if (maybeAutoChangeVaseFlower(t, ctx)) save();\n',
        'tick decoration')

    # ---------------------------------------------------------------- 访客离开时种花
    src = sub_once(
        src,
        '    state.guest = null;\n'
        '    state.guestBonusTickets = 0;',
        '    /* 【并入他 3.3】访客离开是"种花"的触发点之一（土不够肥就不种）。 */\n'
        '    plantRandomFlowerpot(t);\n'
        '    state.guest = null;\n'
        '    state.guestBonusTickets = 0;',
        'finishGuest planting')

    write(ENGINE, src)
    print('[flower] 引擎已改：星级决定生长速度 + 花期生命周期 + 花瓶 24 小时自动更换（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
