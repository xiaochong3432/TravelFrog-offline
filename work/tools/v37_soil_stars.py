#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 系统 1：土壤肥力星级（并入「他做的 3.3」）

他的做法（实测 + 源码）：
  · `FERTILIZER_RULES`：每个发酵物给点数 20001=10 / 20002=20 / 20003=30，
    20004–20006 同为 10/20/30 但"释放"要 3 天；发酵是**一次一个、排队结算**。
  · `SOIL_FERTILITY_MAX = 100`、每天 **−1**（`SOIL_FERTILITY_DECAY_PERIOD_SEC = 86400`）。
  · `SOIL_STAR_THRESHOLDS = [0, 20, 50, 80]` → 0/1/2/3 星，载荷里多送 `fertility_stars`。
  · `compost.state` 是显示态。

我们的做法：发酵**时长 5 分钟**是这条线用户明确指定的（`COMPOST_DURATION_SEC = 5 * 60`），
所以只取他的"点数 + 星级 + 每日衰减"，**不动时长**，也不改成他那种 0/3 天释放。
未登记的发酵物按 1 点算（保持我们原来的 +1 语义）。

存档兼容：只新增 `fertilityDecayAt` 与 `fertility_stars`（后者只在载荷里），
老档读入时把 `fertilityDecayAt` 补成"现在"（不追溯扣分）、`fertility` 夹到 [0,100]。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-SOIL-STARS'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[soil] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[soil] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[soil] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 常量
    src = sub_once(
        src,
        '// Temporary user-requested pacing: one reserved item per 5 minutes, fertility +1.\n'
        'const COMPOST_DURATION_SEC = 5 * 60;',
        '// Temporary user-requested pacing: one reserved item per 5 minutes, fertility +1.\n'
        'const COMPOST_DURATION_SEC = 5 * 60;\n'
        '/* %s 【并入他 3.3】土地肥力：点数 / 星级 / 每日衰减。\n'
        '   他那边每个发酵物的点数是 FERTILIZER_RULES（20001=10、20002=20、20003=30，\n'
        '   20004–20006 同为 10/20/30 但发酵要 3 天）。发酵**时长**保留我们这条线用户指定的\n'
        '   5 分钟，不采用他的 0/3 天。 */\n'
        'const SOIL_FERTILITY_MAX = 100;\n'
        'const SOIL_FERTILITY_DECAY_PERIOD_SEC = 86400;\n'
        'const SOIL_FERTILITY_DECAY_PER_PERIOD = 1;\n'
        'const SOIL_STAR_THRESHOLDS = [0, 20, 50, 80];      // 0/1/2/3 星\n'
        'const FERTILIZER_POINTS = new Map([[20001, 10], [20002, 20], [20003, 30],\n'
        '  [20004, 10], [20005, 20], [20006, 30]]);' % MARK,
        'compost constants')

    # ---------------------------------------------------------------- 默认存档位
    src = sub_once(
        src,
        "compost: { showIndex: 1, replaceIndex: 0, boxIndex: 0, boxes: [0, 0, 0, 0, 0, 0], list: [21000], job: null, fertility: 0 },",
        "compost: { showIndex: 1, replaceIndex: 0, boxIndex: 0, boxes: [0, 0, 0, 0, 0, 0], list: [21000], job: null, fertility: 0, fertilityDecayAt: 0 },",
        'default compost')

    # ---------------------------------------------------------------- 函数
    src = sub_once(
        src,
        '  function refreshCompost(t) {',
        '  /* 【并入他 3.3】星级：阈值 [0,20,50,80] → 0/1/2/3 星（客户端 pips 之外的真实星级）。 */\n'
        '  function soilStars(fertility) {\n'
        '    const value = Math.max(0, Number(fertility) || 0);\n'
        '    let stars = 0;\n'
        '    for (let i = 1; i < SOIL_STAR_THRESHOLDS.length; i += 1) {\n'
        '      if (value >= SOIL_STAR_THRESHOLDS[i]) stars = i;\n'
        '    }\n'
        '    return stars;\n'
        '  }\n'
        '\n'
        '  /* 一个发酵物完成时给多少肥力点（他的点数表；未登记的按 1 点，即我们原来的 +1）。 */\n'
        '  function compostPointsFor(id) {\n'
        '    const points = FERTILIZER_POINTS.get(Number(id));\n'
        '    return Number.isFinite(points) && points > 0 ? points : 1;\n'
        '  }\n'
        '\n'
        '  function refreshCompost(t) {',
        'soilStars + compostPointsFor')

    # 夹取 + 每日衰减
    src = sub_once(
        src,
        '    c.fertility = Number.isSafeInteger(c.fertility) && c.fertility >= 0 ? c.fertility : 0;',
        '    c.fertility = Number.isFinite(c.fertility) && c.fertility >= 0\n'
        '      ? Math.min(SOIL_FERTILITY_MAX, Math.floor(c.fertility)) : 0;\n'
        '    /* 【并入他 3.3】肥力每天 −1，离线期间同样补算；记在 fertilityDecayAt 上。 */\n'
        '    {\n'
        '      const at = Number(t) || nowSec();\n'
        '      const decayAt = Number(c.fertilityDecayAt);\n'
        '      if (!Number.isFinite(decayAt) || decayAt <= 0) {\n'
        '        c.fertilityDecayAt = at;\n'
        '      } else if (at > decayAt) {\n'
        '        const periods = Math.floor((at - decayAt) / SOIL_FERTILITY_DECAY_PERIOD_SEC);\n'
        '        if (periods > 0) {\n'
        '          c.fertility = Math.max(0,\n'
        '            c.fertility - periods * SOIL_FERTILITY_DECAY_PER_PERIOD);\n'
        '          c.fertilityDecayAt = decayAt + periods * SOIL_FERTILITY_DECAY_PERIOD_SEC;\n'
        '        }\n'
        '      }\n'
        '    }',
        'fertility clamp + decay')

    src = sub_once(
        src,
        '      c.fertility = Math.min(Number.MAX_SAFE_INTEGER, c.fertility + 1);',
        '      c.fertility = Math.min(SOIL_FERTILITY_MAX, c.fertility + compostPointsFor(c.job.itemId));',
        'fertility gain')

    # 载荷加星级
    src = sub_once(
        src,
        '      state: Math.min(4, 1 + c.fertility), fertility: c.fertility,',
        '      state: Math.min(4, 1 + c.fertility), fertility: c.fertility,\n'
        '      fertility_stars: soilStars(c.fertility),',
        'payload stars')

    # ---------------------------------------------------------------- 老档补齐
    src = sub_once(
        src,
        '      // Old saves started with no owned compost bin, making its entire UI invisible.\n'
        '      if (!Array.isArray(s.furniture.compost.list) || !s.furniture.compost.list.length) {\n'
        '        s.furniture.compost.list = [21000];\n'
        '        s.furniture.compost.showIndex = 1;\n'
        '      }',
        '      // Old saves started with no owned compost bin, making its entire UI invisible.\n'
        '      if (!Array.isArray(s.furniture.compost.list) || !s.furniture.compost.list.length) {\n'
        '        s.furniture.compost.list = [21000];\n'
        '        s.furniture.compost.showIndex = 1;\n'
        '      }\n'
        '      /* 【并入他 3.3】老档没有 fertilityDecayAt：从现在起算衰减（不追溯扣分）；\n'
        '         肥力值夹到 [0, SOIL_FERTILITY_MAX]。 */\n'
        '      if (!Number.isFinite(Number(s.furniture.compost.fertilityDecayAt))\n'
        '          || Number(s.furniture.compost.fertilityDecayAt) <= 0) {\n'
        '        s.furniture.compost.fertilityDecayAt = nowSec();\n'
        '      }\n'
        '      s.furniture.compost.fertility = Math.max(0, Math.min(SOIL_FERTILITY_MAX,\n'
        '        Math.floor(Number(s.furniture.compost.fertility) || 0)));',
        'old save backfill')

    write(ENGINE, src)
    print('[soil] 引擎已改：肥力点数(10/20/30) + 星级[0,20,50,80] + 每日 −1（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
