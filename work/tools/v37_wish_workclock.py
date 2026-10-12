#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 收尾：手工品"要正在做手工才推进"（可选）+ SAVE_VERSION 升到 2

一、手工品的推进条件（并入他 3.3 的精神，做法上做了简化）
   他的 3.3 给手工品加了"工作时钟"：每个祈愿物记 `work_left`，只有蛙蛙**正在做手工**
   （`frog.motion == FrogMotionNum.make`）时才把这段时间扣掉，并且顺手去掉了我们这条线的
   "制作工具 + 每件 1 份材料"门槛。
   我们这边：
     · **保留**工具/材料门槛（那是 3.4 的资源经济，我们 V3.6 的文档也这么写）；
     · **保留**按阶段计时（86/129 分钟），只加上"到点时蛙蛙必须正在做手工"这一条，
       等价于他的"只有做手工的时间才算"，但不用维护 work_left/workClockAt，
       也不会因为离线追赶算出负值；
     · 默认**关**（我们 V3.6 的玩家说明写的是"86 分钟/阶段"的墙钟时间），
       想照他的节奏来：`FROG_WISH_WORKCLOCK=1`。

二、SAVE_VERSION 1 -> 2
   六条线的老档（我们 V3/V3.1/V3.3/V3.5/V3.6、他们 3.4、他的 3.2/3.3）写的都是 1，
   本版从 2 开始写；`> SAVE_VERSION` 的档（更新引擎写的）仍然只读不写。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-WISH-WORKCLOCK'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[wish] 锚点没找到：%s\n%s' % (label, old[:220]))
    if n > 1:
        raise SystemExit('[wish] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[wish] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 常量
    src = sub_once(
        src,
        'const COMPOST_DURATION_SEC = 5 * 60;',
        'const COMPOST_DURATION_SEC = 5 * 60;\n'
        '/* %s 【并入他 3.3 的可选项】手工品"要正在做手工才推进"：\n'
        '   他给手工品加了 work_left 工作时钟，只有蛙蛙正在做手工时才计时。\n'
        '   我们保留按阶段计时，只加上"到点时必须在做手工"这一条（等价、更简单）。\n'
        '   默认关（V3.6 的玩家说明写的是 86/129 分钟一阶段）；想照他的来设 1。 */\n'
        "const WISH_WORKCLOCK = String(process.env.FROG_WISH_WORKCLOCK || '') === '1';" % MARK,
        'workclock const')

    # ---------------------------------------------------------------- 推进条件
    src = sub_once(
        src,
        '  const atHome = !state.frog || state.frog.status === 0;\n'
        '  const canCraft = getHaveItem(HANDCRAFT_TOOL_ID) > 0;',
        '  const atHome = !state.frog || state.frog.status === 0;\n'
        '  const canCraft = getHaveItem(HANDCRAFT_TOOL_ID) > 0;\n'
        '  /* 【并入他 3.3 的可选项】蛙蛙此刻是不是正在做手工（FrogMotionNum.make = 3）。 */\n'
        '  const craftMotionNum = Number((defineData.maps && defineData.maps.FrogMotionNum || {}).make);\n'
        '  const doingHandcraft = atHome && Number(state.frog && state.frog.motion)\n'
        '    === (Number.isFinite(craftMotionNum) ? craftMotionNum : 3);',
        'doingHandcraft')

    src = sub_once(
        src,
        '    if (!canCraft || w.state > 3 || !reserveMaterial(w, HANDCRAFT_MATERIAL_ID) || t < w.make_time) continue;',
        '    /* 【并入他 3.3 的可选项】WISH_WORKCLOCK=1 时，到点还不够，得蛙蛙正在做手工。 */\n'
        '    if (WISH_WORKCLOCK && !doingHandcraft) continue;\n'
        '    if (!canCraft || w.state > 3 || !reserveMaterial(w, HANDCRAFT_MATERIAL_ID) || t < w.make_time) continue;',
        'wish gate')

    # ---------------------------------------------------------------- SAVE_VERSION 2
    src = sub_once(src, 'const SAVE_VERSION = 1;', 'const SAVE_VERSION = 2;', 'save version')
    # 老档（v1）读入后按版本迁移到 2（原来只补"缺失或 0"的情况，v1 会一直是 v1）；
    # 比本版更新的档（v3+）不动，仍然"只读不写"。
    src = sub_once(
        src,
        '  if (!(Number(s.saveVersion) >= 1)) s.saveVersion = SAVE_VERSION;',
        '  /* %s 老档按版本迁移：v1 -> v2（V3.7 会回填新字段）；比本版新的档不动。 */\n'
        '  if (Number(s.saveVersion) < SAVE_VERSION) s.saveVersion = SAVE_VERSION;' % MARK,
        'save version migrate')

    write(ENGINE, src)
    print('[wish] 引擎已改：WISH_WORKCLOCK 可选 + SAVE_VERSION=2（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
