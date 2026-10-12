#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 系统 10：家具动作演出 + 排队开工（并入「他做的 3.3」）

他这部分的两件事（源码逐行核对过）：
  1. **"做家具"这个动作会换成具体工具动画**：`FURNITURE_TOOL_MOTION = {saw:5, brush:6,
     hammer:7, needle:8, knife:9}`（`FrogMotionNum.make` 本身是 3）。做东西时，
     按"这件家具需要的工具 ∩ 台面上有的工具"挑一个（按动作步数轮换），
     于是玩家能看到蛙蛙在锯/刷/锤/缝/刻，而不是一个笼统的"做"。
  2. **排队开工**：概率抽中后先 `craftQueued = 1`，等蛙蛙**真的拿起对应工具的动作**时
     才 `startCraftFromBench()` 开工（`tryStartQueuedCraft`），并且会把台面/物品载荷推给客户端。

本补丁的取舍：
  · 工具动画**直接采纳**（纯表现层，风险低，玩家可见）。
  · `CRAFT_TOOLS_BY_TYPE`（27 个 type 的工需求表）先作为常量并进来，**只用于动画**；
    真正"按 type 卡工具"属于他的「制作模型」大改，留到那一轮。
  · 排队开工：他的流程是"3 小时检查一次 → 排队 → 等动作"。我们 V3.6 的默认是
    "每拍 35% 抽中即开工"（文档里写明的玩家体验），所以**默认保持我们的**，
    想照他的来设 `FROG_CRAFT_QUEUE=1`（此时走他的排队 + 等动作逻辑）。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-FURNITURE-MOTION'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[motion] 锚点没找到：%s\n%s' % (label, old[:220]))
    if n > 1:
        raise SystemExit('[motion] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


MODULE_BLOCK = """/* __MARK__ ============ 做家具的工具动画 / 排队开工 ============ */

/* 做家具时的具体工具动画（FrogMotionNum.make = 3，工具动画是 5..9）。 */
const FURNITURE_TOOL_MOTION = { saw: 5, brush: 6, hammer: 7, needle: 8, knife: 9 };

/* 每个家具 type 需要哪些工具（他的 27 行表）。本轮只用于"演哪段工具动画"，
   真正的按 type 卡工具留到「制作模型」那一轮。 */
const CRAFT_TOOLS_BY_TYPE = {
  1: ['hammer'], 2: ['hammer'], 3: ['brush', 'saw', 'needle', 'hammer'],
  4: ['brush', 'saw', 'needle'], 5: ['brush', 'saw', 'knife'],
  6: ['brush', 'saw', 'hammer', 'knife'], 7: ['needle', 'knife'],
  8: ['knife', 'hammer'], 9: ['brush', 'saw', 'needle', 'knife'],
  10: ['needle', 'hammer'], 11: ['knife', 'hammer'],
  12: ['brush', 'saw', 'hammer'], 13: ['needle', 'knife'],
  14: ['brush', 'hammer', 'knife'], 15: ['knife', 'hammer'],
  16: ['brush', 'saw', 'hammer', 'knife'], 17: ['brush', 'hammer'],
  18: ['brush', 'saw'], 19: ['needle', 'knife'],
  20: ['brush', 'saw', 'hammer'], 21: ['hammer'],
  22: ['brush', 'saw', 'hammer'], 23: ['brush', 'saw', 'needle'],
  24: ['brush', 'saw', 'knife'], 25: ['needle', 'hammer'],
  26: ['brush', 'saw', 'needle'],
  27: ['brush', 'saw', 'needle', 'hammer', 'knife'],
};

/* 他的"排队开工"是可选流程（默认关，见文件头说明）。 */
const FROG_CRAFT_QUEUE = String(process.env.FROG_CRAFT_QUEUE || '') === '1';

""".replace('__MARK__', MARK)

INNER_BLOCK = """  /* __MARK__ ================= 工具动画与排队开工（依赖 state） ================= */

  /** 这件东西需要哪些工具（口袋/不倒翁用各自的，其余按家具 type）。 */
  function furnitureCraftTools(furnitureId, kind) {
    if (kind === 'tumbler') return TUMBLER_TOOLS;
    if (kind === 'pocket') return POCKET_TOOLS;
    const row = FURNITURE_BY_ID.get(Number(furnitureId));
    return CRAFT_TOOLS_BY_TYPE[Number(row && row.type)] || [];
  }

  /** "做"这个动作要演哪一段：按"需要的工具 ∩ 台面上有的工具"挑一个，按动作步数轮换。 */
  function furnitureActionMotion() {
    const craft = state.furniture.craft;
    const queued = !craft && state.furniture.craftQueued;
    if (!craft && !queued) return Number(FROGMOTIONNUM.make) || 0;
    const furnitureId = craft ? craft.furnitureId : state.furniture.craftQueuedFurnitureId;
    const bp = queued ? benchBlueprint(furnitureId, state.furniture.craftQueuedBenchSlot) : null;
    const kind = craft ? craft.kind : bp && bp.kind;
    const required = furnitureCraftTools(furnitureId, kind);
    const benchTools = (state.furniture.bench || []).slice(0, 5).map(Number);
    const available = required.filter((tool) => benchTools.some((id) =>
      (CRAFT_TOOL_VARIANTS[tool] || []).includes(id)));
    if (!available.length) {
      /* 台面上没有对应工具时的退化：
         · 他的做法是退回"做"这个通用动作（make = 3）；
         · 但我们这条线的家具制作**目前不强制工具**（工具门槛属于他的「制作模型」大改，
           留到那一轮），所以为了不出现"人在工作台却演读书动作"，这里退化成
           我们原来的工作台动作 5..9（有工具时仍然演具体工具动画）。 */
      return 5 + (Math.abs(Number(state.frog.motionStep) || 0) % 5);
    }
    const index = Math.abs(Number(state.frog.motionStep) || 0) % available.length;
    return FURNITURE_TOOL_MOTION[available[index]] || Number(FROGMOTIONNUM.make) || 0;
  }

  function furnitureToolMotion(motion) {
    return Object.values(FURNITURE_TOOL_MOTION).includes(Number(motion));
  }

  /** 排队的活：等蛙蛙进入"对应工具"的动作时才真的开工（他的做法）。 */
  function tryStartQueuedCraft(at, ctx) {
    if (!state.furniture.craftQueued || state.furniture.craft
      || state.frog.status !== 0
      || !furnitureToolMotion(state.frog.motion)
      || furnitureMoodBlocked()) return false;
    const queuedId = Number(state.furniture.craftQueuedFurnitureId) || 0;
    const bp = benchBlueprint(queuedId, state.furniture.craftQueuedBenchSlot);
    const furnitureId = Number(bp && bp.furnitureId) || queuedId;
    if (!bp || !furnitureId) return false;
    const required = furnitureCraftTools(furnitureId, bp && bp.kind);
    const motionTool = Object.keys(FURNITURE_TOOL_MOTION)
      .find((tool) => FURNITURE_TOOL_MOTION[tool] === Number(state.frog.motion));
    if (!motionTool || !required.includes(motionTool)) return false;
    if (!startCraftFromBench(at, state.furniture.craftQueuedFurnitureId,
      state.furniture.craftQueuedBenchSlot)) {
      /* 台面已经凑不齐了：取消排队，别卡着。 */
      state.furniture.craftQueued = 0;
      state.furniture.craftQueuedFurnitureId = 0;
      state.furniture.craftQueuedBenchSlot = -1;
      return false;
    }
    state.furniture.craftQueued = 0;
    state.furniture.craftQueuedFurnitureId = 0;
    state.furniture.craftQueuedBenchSlot = -1;
    if (ctx) {
      ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));
      ctx.push('item_load_items', handlers.item_load_items());
    }
    save();
    return true;
  }

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[motion] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 常量
    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   MODULE_BLOCK + '/* ---------------------------------------------------------------- engine */',
                   'module block')

    # ---------------------------------------------------------------- 存档位（排队相关的字段）
    src = sub_once(
        src,
        '      craft: null,          // 进行中的制作 {furnitureId, drawing, materials, startedAt, finishAt}',
        '      craft: null,          // 进行中的制作 {furnitureId, drawing, materials, startedAt, finishAt}\n'
        '      /* %s 【并入他 3.3】排队的活：等蛙蛙拿起对应工具的动作才开工。 */\n'
        '      craftQueued: 0,\n'
        '      craftQueuedFurnitureId: 0,\n'
        '      craftQueuedBenchSlot: -1,\n'
        '      nextCraftCheckAt: 0,' % MARK,
        'queue state')

    # ---------------------------------------------------------------- 引擎内函数
    src = sub_once(src, '  function autoCraftCheck(ctx, t) {', INNER_BLOCK + '  function autoCraftCheck(ctx, t) {',
                   'inner block')

    # ---------------------------------------------------------------- 做家具演工具动画
    src = sub_once(
        src,
        "    else if (mode === 'craft') state.frog.motion = 5 + state.frog.motionStep % 5;",
        '    /* 【并入他 3.3】做东西时按台面上的工具换成具体工具动画（锯/刷/锤/缝/刻）。 */\n'
        '    else if (mode === \'craft\') state.frog.motion = furnitureActionMotion();',
        'craft motion')

    # ---------------------------------------------------------------- 自动开工：可选排队
    src = sub_once(
        src,
        '    if (!maybeStartCraft()) { save(); return false; }\n'
        "    ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));\n"
        "    ctx.push('item_load_items', handlers.item_load_items());\n"
        "    ctx.push('client_load_role', rolePayload());\n"
        '    return true;',
        '    /* 【并入他 3.3 的可选项】FROG_CRAFT_QUEUE=1 时先排队，等蛙蛙拿起对应工具的动作再开工。 */\n'
        '    if (FROG_CRAFT_QUEUE) {\n'
        '      const bp = benchBlueprint();\n'
        '      if (!bp) { save(); return false; }\n'
        '      state.furniture.craftQueued = 1;\n'
        '      state.furniture.craftQueuedFurnitureId = Number(bp.furnitureId) || 0;\n'
        '      state.furniture.craftQueuedBenchSlot = craftRecipeSlot(bp);\n'
        '      save();\n'
        "      ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));\n"
        '      return true;\n'
        '    }\n'
        '    if (!maybeStartCraft()) { save(); return false; }\n'
        "    ctx.push('furniture_load_furniture', handlers.furniture_load_furniture({}));\n"
        "    ctx.push('item_load_items', handlers.item_load_items());\n"
        "    ctx.push('client_load_role', rolePayload());\n"
        '    return true;',
        'auto craft queue')

    # ---------------------------------------------------------------- 台面放入也走排队（queue 模式）
    src = sub_once(
        src,
        '      const extraBp = benchPocketTumblerBlueprint();\n'
        '      const started = extraBp\n'
        '        ? startCraftFromBench(nowSec(), extraBp.furnitureId, craftRecipeSlot(extraBp))\n'
        '        : maybeStartCraft();',
        '      const extraBp = benchPocketTumblerBlueprint();\n'
        '      let started = false;\n'
        '      if (FROG_CRAFT_QUEUE) {\n'
        '        /* 【并入他 3.3 的可选项】排队模式：放上台面也先排队，等蛙蛙拿起对应工具的动作。 */\n'
        '        const qbp = extraBp || benchBlueprint();\n'
        '        if (qbp) {\n'
        '          state.furniture.craftQueued = 1;\n'
        '          state.furniture.craftQueuedFurnitureId = Number(qbp.furnitureId) || 0;\n'
        '          state.furniture.craftQueuedBenchSlot = craftRecipeSlot(qbp);\n'
        '        }\n'
        '      } else if (extraBp) {\n'
        '        started = startCraftFromBench(nowSec(), extraBp.furnitureId, craftRecipeSlot(extraBp));\n'
        '      } else {\n'
        '        started = maybeStartCraft();\n'
        '      }',
        'putin bench queue')

    # ---------------------------------------------------------------- tick：动作刷新后尝试开工
    src = sub_once(
        src,
        "    if (refreshFrogMotion(t)) {\n"
        "      ctx.push('easteregg_load', eggPayload());\n"
        "      ctx.push('client_load_role', rolePayload());\n"
        "    }",
        "    if (refreshFrogMotion(t)) {\n"
        "      ctx.push('easteregg_load', eggPayload());\n"
        "      ctx.push('client_load_role', rolePayload());\n"
        "    }\n"
        "    /* 【并入他 3.3】排队的活：趁刚才换了动作，看看是不是该开工了。 */\n"
        "    tryStartQueuedCraft(t, ctx);",
        'tick queued craft')

    write(ENGINE, src)
    print('[motion] 引擎已改：工具动画 + 排队开工（可选）（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
