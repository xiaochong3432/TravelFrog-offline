#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0：把我们**故意保留 V3.6 做法**的地方，默认翻成「他 3.3 的做法」。

对应《V37-三方对照》§四 那张表，一共 9 条，这里翻 7 条行为项 + 1 条可选项：
  1. 商店营业窗口      常开            -> 他的 12:00 后到 / 21:00 走（FROG_SHOP_WINDOW=always 回退）
  2. 售罄行            留在货架(num=0) -> 他的：售罄就不列（FROG_SHOP_KEEP_SOLD_OUT=1 回退）
  3. 自动开工          抽中即开工      -> 他的：排队 + 等蛙蛙拿起对应工具的动作（FROG_CRAFT_QUEUE=0 回退）
  4. 手工品计时        阶段墙钟        -> 他的：只有蛙蛙在做手工时才推进（FROG_WISH_WORKCLOCK=0 回退）
  5. 手工品工具/材料   要工具+1 材料   -> 他的：不要（FROG_HANDCRAFT_GATE=1 回退）
  6. 堆肥发酵          统一 5 分钟     -> 他的：20001–3 立即、20004–6 三天（FROG_COMPOST_SEC=300 回退）
  7. 友情邀约概率      75%【你指定过】 -> 他的 20%（FROG_DRAWING_CHANCE=75 回退）
  8. 风格特殊材料缺失  退回默认配方    -> 他的"不可做"，但**默认不启用**（FROG_CRAFT_STRICT_SPECIAL=1 才启用）
       理由：实测我们合并的官方 1088 表里**每个 type 的目标件都是 style 14**，
       他的 special 表只到 style 11 —— 启用即 27/27 全部不可做（v37_craft_model_test.js 有断言）。
  9. 商店补行          改客户端数据    -> 保持（与他的"改客户端代码"目标一致：让两行能买），不涉及玩家可感行为。

versionCode 保持 10（与 V3.7 相同），versionName 用 4.0。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V40-PREFER-HIS'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_all(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[v40] 锚点没找到：%s\n%s' % (label, old[:200]))
    print('[v40]   %s：替换 %d 处' % (label, n))
    return text.replace(old, new)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[v40] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[v40] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[v40] 已翻过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 开关常量
    src = sub_once(
        src,
        "const DRAWING_CHANCE = Number(process.env.FROG_DRAWING_CHANCE || 75);",
        '/* %s 【V4.0】默认改用他的邀约概率 20%%（我们 V3.6/V3.7 是 75%%）。\n'
        '   想回到 75%%：FROG_DRAWING_CHANCE=75。 */\n'
        'const DRAWING_CHANCE = Number(process.env.FROG_DRAWING_CHANCE || 20);' % MARK,
        'drawing chance')

    src = sub_once(
        src,
        "const WISH_WORKCLOCK = String(process.env.FROG_WISH_WORKCLOCK || '') === '1';",
        '/* %s 【V4.0】默认启用他的工作时钟（只有蛙蛙在做手工时才推进）。\n'
        '   想回到 V3.7 的阶段墙钟：FROG_WISH_WORKCLOCK=0。 */\n'
        "const WISH_WORKCLOCK = String(process.env.FROG_WISH_WORKCLOCK || '1') !== '0';\n"
        '/* %s 他的手工品不需要工具/材料；我们 V3.7 的门槛作为可选项保留。 */\n'
        "const HANDCRAFT_GATE = String(process.env.FROG_HANDCRAFT_GATE || '') === '1';\n"
        '/* %s 他的"风格没有特殊材料就不可做"。默认关：官方 1088 表里目标件都是 style 14，\n'
        '   启用会让 27 种全部不可做（见 v37_craft_model_test.js 的断言）。 */\n'
        "const CRAFT_STRICT_SPECIAL = String(process.env.FROG_CRAFT_STRICT_SPECIAL || '') === '1';" % (MARK, MARK, MARK),
        'workclock + gate + strict')

    src = sub_once(
        src,
        "const FROG_CRAFT_QUEUE = String(process.env.FROG_CRAFT_QUEUE || '') === '1';",
        '/* %s 【V4.0】默认启用他的排队开工（等蛙蛙拿起对应工具的动作才开工）。\n'
        '   想回到 V3.7 的"抽中即开工"：FROG_CRAFT_QUEUE=0。 */\n'
        "const FROG_CRAFT_QUEUE = String(process.env.FROG_CRAFT_QUEUE || '1') !== '0';" % MARK,
        'craft queue')

    # ---------------------------------------------------------------- 商店：窗口 + 售罄
    src = sub_once(
        src,
        "    if (String(process.env.FROG_SHOP_WINDOW || '') === 'faithful') {",
        '    /* %s 【V4.0】默认改用他的营业窗口（12:00 后到、21:00 走）。\n'
        "       想恢复 V3.7 的常开：FROG_SHOP_WINDOW=always。 */\n"
        "    if (String(process.env.FROG_SHOP_WINDOW || 'faithful') !== 'always') {" % MARK,
        'shop window')

    src = sub_once(
        src,
        '      const num = Math.max(0, Math.min(limitLeft, stockLeft));',
        '      const num = Math.max(0, Math.min(limitLeft, stockLeft));\n'
        '      /* %s 【V4.0】他的实现是售罄就从货架上拿掉；\n'
        '         想恢复 V3.7/上游 3.4 的"卖完了看得见"：FROG_SHOP_KEEP_SOLD_OUT=1。 */\n'
        "      if (!SHOP_KEEP_SOLD_OUT && num <= 0) continue;" % MARK,
        'sold out')

    src = sub_once(
        src,
        'const MERCHANT_DAILY_OFFER_COUNT = 8;',
        'const MERCHANT_DAILY_OFFER_COUNT = 8;\n'
        '/* %s 售罄行是否还列出来（V4.0 默认不列，与他的实现一致）。 */\n'
        "const SHOP_KEEP_SOLD_OUT = String(process.env.FROG_SHOP_KEEP_SOLD_OUT || '') === '1';" % MARK,
        'keep sold out const')

    # ---------------------------------------------------------------- 手工品门槛
    src = sub_once(
        src,
        '    if (WISH_WORKCLOCK && !doingHandcraft) continue;\n'
        '    if (!canCraft || w.state > 3 || !reserveMaterial(w, HANDCRAFT_MATERIAL_ID) || t < w.make_time) continue;',
        '    if (WISH_WORKCLOCK && !doingHandcraft) continue;\n'
        '    /* %s 【V4.0】他的手工品不再要工具/材料；我们的门槛走 FROG_HANDCRAFT_GATE=1。 */\n'
        '    if (w.state > 3 || t < w.make_time) continue;\n'
        '    if (HANDCRAFT_GATE && (!canCraft || !reserveMaterial(w, HANDCRAFT_MATERIAL_ID))) continue;' % MARK,
        'handcraft gate')

    # ---------------------------------------------------------------- 堆肥：按他的每件时长
    src = sub_once(
        src,
        'const COMPOST_DURATION_SEC = 5 * 60;',
        'const COMPOST_DURATION_SEC = 5 * 60;   // 我们 V3.6/V3.7 的统一时长（回退值）\n'
        '/* %s 【V4.0】默认改用他的发酵时长：20001–3 立即（0 秒）、20004–6 三天。\n'
        '   想回到统一的 5 分钟：FROG_COMPOST_SEC=300。 */\n'
        'const COMPOST_HIS_RULES = new Map([[20001, 0], [20002, 0], [20003, 0],\n'
        '  [20004, 3 * 86400], [20005, 3 * 86400], [20006, 3 * 86400]]);\n'
        'const COMPOST_FLAT_SEC = process.env.FROG_COMPOST_SEC !== undefined\n'
        '  ? Math.max(0, Number(process.env.FROG_COMPOST_SEC) || 0) : null;' % MARK,
        'compost consts')

    src = sub_once(
        src,
        '  function refreshCompost(t) {',
        '  /** 他的发酵时长：20004–6 三天，其余立即；FROG_COMPOST_SEC 可强制统一时长。 */\n'
        '  function compostDurationFor(itemId) {\n'
        '    if (COMPOST_FLAT_SEC !== null) return COMPOST_FLAT_SEC;\n'
        '    const id = Number(itemId);\n'
        '    return COMPOST_HIS_RULES.has(id) ? Number(COMPOST_HIS_RULES.get(id)) : COMPOST_DURATION_SEC;\n'
        '  }\n\n'
        '  function refreshCompost(t) {',
        'compostDurationFor')

    src = sub_once(
        src,
        '        && [COMPOST_DURATION_SEC, 3 * 60 * 60].includes(job.finishAt - job.startedAt))) {',
        '        && [compostDurationFor(job.itemId), COMPOST_DURATION_SEC, 3 * 60 * 60]\n'
        '          .includes(job.finishAt - job.startedAt))) {',
        'compost validate')

    src = sub_once(
        src,
        '    c.job = {index, itemId: c.boxes[index - 1], startedAt: cursor, finishAt: cursor + COMPOST_DURATION_SEC};',
        '    c.job = {index, itemId: c.boxes[index - 1], startedAt: cursor,\n'
        '      finishAt: cursor + compostDurationFor(c.boxes[index - 1])};',
        'compost job create')

    # ---------------------------------------------------------------- 排队模式防卡死
    # ① 排队也算"制作中"，否则蛙蛙永远拿不到工具动作
    src = sub_once(
        src,
        "    const mode = sleeping ? 'sleep' : state.furniture.craft ? 'craft' : 'awake';",
        "    /* %s 【V4.0】排队的活也算制作中：不然蛙蛙永远进不了 craft 模式、\n"
        "       也就永远拿不到工具动作，tryStartQueuedCraft 的门槛永远不成立（实测卡死）。 */\n"
        "    const mode = sleeping ? 'sleep'\n"
        "      : (state.furniture.craft || state.furniture.craftQueued) ? 'craft' : 'awake';" % MARK,
        'queued counts as craft mode')

    # ② 需要的工具不在台面上就别排队
    src = sub_once(
        src,
        '  /** 这件东西需要哪些工具（口袋/不倒翁用各自的，其余按家具 type）。 */',
        '  /** %s 排队模式的安全阀：需要的工具不在台面上就别排队（否则等不到工具动作）。\n'
        '      我们的家具制作不强制工具，所以这种活应当直接开工。 */\n'
        '  function canQueueCraft(bp) {\n'
        '    if (!bp) return false;\n'
        '    const tools = furnitureCraftTools(Number(bp.furnitureId), bp.kind);\n'
        '    return Array.isArray(tools) && tools.length > 0\n'
        '      && craftMissingToolsFor(tools).length === 0;\n'
        '  }\n\n'
        '  /** 这件东西需要哪些工具（口袋/不倒翁用各自的，其余按家具 type）。 */' % MARK,
        'canQueueCraft helper')

    src = sub_once(
        src,
        '    if (FROG_CRAFT_QUEUE) {\n'
        '      const bp = benchBlueprint();\n'
        '      if (!bp) { save(); return false; }',
        '    if (FROG_CRAFT_QUEUE && canQueueCraft(benchBlueprint())) {\n'
        '      const bp = benchBlueprint();\n'
        '      if (!bp) { save(); return false; }',
        'auto craft queue guarded')

    src = sub_once(
        src,
        '      if (FROG_CRAFT_QUEUE) {\n'
        '        /* 【并入他 3.3 的可选项】排队模式：放上台面也先排队，等蛙蛙拿起对应工具的动作。 */\n'
        '        const qbp = extraBp || benchBlueprint();',
        '      if (FROG_CRAFT_QUEUE && canQueueCraft(extraBp || benchBlueprint())) {\n'
        '        /* 【并入他 3.3 的可选项】排队模式：放上台面也先排队，等蛙蛙拿起对应工具的动作。 */\n'
        '        const qbp = extraBp || benchBlueprint();',
        'putin bench queue guarded')

    # ---------------------------------------------------------------- 配方算不出来 = 不可做
    src = sub_all(
        src,
        '    const mats = craftMaterialsFor(bp.furnitureId) || [];',
        '    /* %s 【V4.0】他的模型里「算不出配方」就是不可做；原来的 `|| []`\n' % MARK
        + '       会把严格模式算出来的 null 当成「不缺材料」，于是 craft 能起来但材料列表是空的。 */\n'
        + '    const mats = craftMaterialsFor(bp.furnitureId);\n'
        + '    if (!mats) return null;',
        'recipe null = uncraftable')

    # ---------------------------------------------------------------- 严格特殊材料（可选）
    src = sub_once(
        src,
        '  function craftMaterialsFor(furnitureId) {\n'
        '    const def = FURNITURE_BY_ID.get(Number(furnitureId));\n'
        '    if (!def) return null;',
        '  function craftMaterialsFor(furnitureId) {\n'
        '    const def = FURNITURE_BY_ID.get(Number(furnitureId));\n'
        '    if (!def) return null;\n'
        '    /* %s 【V4.0 可选】他的原版规则：风格没有登记特殊材料 -> 这件不可做。\n'
        '       默认关（官方 1088 表里目标件都是 style 14，启用会让 27 种全不可做）。 */\n'
        '    if (CRAFT_STRICT_SPECIAL && !CRAFT_SPECIAL_BY_STYLE[Number(def.style)]) return null;' % MARK,
        'strict special')

    write(ENGINE, src)
    print('[v40] 已把 7 项默认翻成他的做法（+1 项可选项默认关）（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
