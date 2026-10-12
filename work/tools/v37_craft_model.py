#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 制作模型（一）：27 个 type 的基材表 + 风格特殊材料（并入「他做的 3.3」）

他的 `craftMaterialsFor`：
    base = CRAFT_BASE_MATERIALS_BY_TYPE[type]      // 27 个 type 各自的基准材料
    special = CRAFT_SPECIAL_BY_STYLE[style]        // 风格 -> 一件特殊材料
    两者任一缺失 -> 返回 null（= 这件不可做）

**为什么不能照搬**（实测数据）：
  · 他的 `CRAFT_SPECIAL_BY_STYLE` 只覆盖 style **2–11**；
  · 我们合并的官方 1088 表里，很多 type 的最高风格是 **14 / 101**（例如 type 1 的 2301 是 style 14）；
  · 照搬 -> 这些件"没有 special -> null -> 不可做"，直接推翻本仓库自己的用例
    `craft: 每种可做 type 都能由一件图纸打出来（27 种全通）`；
  · 他还要求特殊材料**摆在工作台的选择位上**（`bench[bp.specialSlot] === item_id`）才算数，
    而我们的台面模型里没有"选择位"这一层（我们只有 0–4 工具位 / 5–9 物品位）。

因此本轮的落地是"他的基材表 + 特殊材料作为**配方里的额外材料**"：
  · `CRAFT_BASE_MATERIALS_BY_TYPE` 有登记 -> 用他的基准材料，并在该风格有 special 时**追加一件**；
  · 他的表里没登记的 type -> 退回我们原来的 style/默认配方（保证 27 种都能做）；
  · 特殊材料从**家里库存**扣（不是必须摆台面），其余照旧；
  · "手工品只在做手工动作时计时"（他的 `work_left`/`workClockAt`）留到下一轮单独做。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-CRAFT-MODEL'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[craft] 锚点没找到：%s\n%s' % (label, old[:220]))
    if n > 1:
        raise SystemExit('[craft] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


CONSTS = """/* __MARK__ ============ 制作模型：27 个 type 的基材表（他的复原表） ============ */

/* 每个家具 type 的基准材料（他按官方指南复原的那张表）。 */
const CRAFT_BASE_MATERIALS_BY_TYPE = {
  1: [{ item_id: 10003, count: 4 }, { item_id: 10007, count: 1 }],
  2: [{ item_id: 10003, count: 4 }, { item_id: 10007, count: 1 }],
  3: [{ item_id: 10001, count: 2 }, { item_id: 10002, count: 2 }, { item_id: 10004, count: 1 }, { item_id: 10007, count: 1 }],
  4: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10004, count: 1 }],
  5: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10006, count: 2 }],
  6: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10005, count: 1 }, { item_id: 10007, count: 1 }],
  7: [{ item_id: 10005, count: 3 }],
  8: [{ item_id: 10005, count: 1 }, { item_id: 10006, count: 1 }, { item_id: 10007, count: 2 }],
  9: [{ item_id: 10001, count: 2 }, { item_id: 10002, count: 1 }, { item_id: 10004, count: 1 }, { item_id: 10005, count: 2 }],
  10: [{ item_id: 10003, count: 3 }, { item_id: 10004, count: 1 }],
  11: [{ item_id: 10006, count: 3 }, { item_id: 10007, count: 1 }],
  12: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10007, count: 2 }],
  13: [{ item_id: 10004, count: 1 }, { item_id: 10005, count: 1 }, { item_id: 10006, count: 2 }],
  14: [{ item_id: 10001, count: 2 }, { item_id: 10002, count: 2 }, { item_id: 10005, count: 1 }],
  15: [{ item_id: 10003, count: 2 }, { item_id: 10006, count: 2 }],
  16: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10006, count: 1 }, { item_id: 10007, count: 1 }],
  17: [{ item_id: 10001, count: 3 }, { item_id: 10007, count: 1 }],
  18: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 2 }],
  19: [{ item_id: 10004, count: 2 }, { item_id: 10005, count: 2 }],
  20: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10003, count: 2 }],
  21: [{ item_id: 10003, count: 2 }],
  22: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10007, count: 1 }],
  23: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10004, count: 1 }],
  24: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10005, count: 2 }, { item_id: 10006, count: 2 }],
  25: [{ item_id: 10007, count: 2 }],
  26: [{ item_id: 10001, count: 2 }, { item_id: 10002, count: 2 }, { item_id: 10004, count: 2 }],
  27: [{ item_id: 10001, count: 1 }, { item_id: 10002, count: 1 }, { item_id: 10003, count: 1 },
       { item_id: 10004, count: 1 }, { item_id: 10005, count: 1 }, { item_id: 10006, count: 1 }],
};

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[craft] 已并入过（%s），跳过' % MARK)
        return 0

    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   CONSTS + '/* ---------------------------------------------------------------- engine */',
                   'module block')

    src = sub_once(
        src,
        '  function craftMaterialsFor(furnitureId) {\n'
        '    const def = FURNITURE_BY_ID.get(Number(furnitureId));\n'
        '    if (!def) return null;\n'
        '    const byStyle = CRAFT_MATERIALS_BY_STYLE[Number(def.style)];\n'
        '    return (byStyle || CRAFT_DEFAULT_MATERIALS).map((m) => ({ item_id: m.item_id, count: m.count }));\n'
        '  }',
        '  /* 【并入他 3.3】配方改成"按 type 的基准材料 + 该风格的特殊材料"。\n'
        '     说明：他的原版要求特殊材料**摆在工作台选择位**上，而且 style 没有登记就直接不可做；\n'
        '     我们这边台面没有"选择位"这一层，而且官方 1088 表里很多 type 的最高风格是 14/101\n'
        '     （他的 special 表只到 11），照搬会让这些件不可做。所以这里：\n'
        '       · 他的表里登记了该 type -> 用他的基材，并在该风格有 special 时追加一件；\n'
        '       · 没登记 -> 退回我们原来的 style/默认配方（保证 27 种都能做）。 */\n'
        '  function craftMaterialsFor(furnitureId) {\n'
        '    const def = FURNITURE_BY_ID.get(Number(furnitureId));\n'
        '    if (!def) return null;\n'
        '    const base = CRAFT_BASE_MATERIALS_BY_TYPE[Number(def.type)];\n'
        '    if (Array.isArray(base) && base.length) {\n'
        '      const mats = base.map((m) => ({ item_id: Number(m.item_id), count: Number(m.count) }));\n'
        '      const special = CRAFT_SPECIAL_BY_STYLE[Number(def.style)];\n'
        '      if (special) mats.push({ item_id: Number(special), count: 1 });\n'
        '      return mats;\n'
        '    }\n'
        '    const byStyle = CRAFT_MATERIALS_BY_STYLE[Number(def.style)];\n'
        '    return (byStyle || CRAFT_DEFAULT_MATERIALS).map((m) => ({ item_id: m.item_id, count: m.count }));\n'
        '  }',
        'craftMaterialsFor')

    write(ENGINE, src)
    print('[craft] 引擎已改：按 type 的基材表 + 风格特殊材料（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
