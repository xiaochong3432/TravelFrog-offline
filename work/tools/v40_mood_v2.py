#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0：并入他的「家具心情 v2 + 工坊检查」——函数体从他的引擎**原样抽取**，再照他的调用点接线。

抄（原样抽取）：
  常量：FURNITURE_ANGER_CHANCE / ANGER_MIN_CHANGES / ANGER_MAX_CHANGES / MESS_STRESS /
        TRIP_RELIEF / HANDCRAFT_RELIEF / CRAFT_RELIEF / AUTO_REPLACE_RELIEF /
        CRAFT_CHECK_SECONDS / CRAFT_START_CHANCE
  函数：recordFurnitureChange / skipFurnitureCraftChecksUntil / rollFurnitureCraftCheck /
        processFurnitureCraftChecks / advanceFurnitureCraft

接线（照他的位置）：
  · 换家具：我们原来 `stressFurnitureMood(FURNITURE_REPLACE_STRESS);`  -> 他的 `recordFurnitureChange();`
    （他的这个函数内部就会加同样的压力，另外加上"3–6 次换家具、75% 概率强制乱掉"）
  · tick：我们原来 `autoCraftCheck(ctx, t);` -> 他的 `if (processFurnitureCraftChecks(t, ctx)) save();`
    （3 小时一次检查 + 35% 开工；我们自己的 autoCraftCheck 保留在文件里但不再调用）
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
HIS_PATH = os.path.join(ROOT, 'work', 'build', 'x33', 'live', 'index.js')
MARK = 'V40-MOOD-V2'

HIS = io.open(HIS_PATH, encoding='utf-8', errors='replace').read()

CONSTS = ['FURNITURE_ANGER_CHANCE', 'FURNITURE_ANGER_MIN_CHANGES', 'FURNITURE_ANGER_MAX_CHANGES',
          'FURNITURE_MESS_STRESS', 'FURNITURE_TRIP_RELIEF', 'FURNITURE_HANDCRAFT_RELIEF',
          'FURNITURE_CRAFT_RELIEF', 'FURNITURE_AUTO_REPLACE_RELIEF',
          'FURNITURE_CRAFT_CHECK_SECONDS', 'FURNITURE_CRAFT_START_CHANCE']
FUNCS = ['recordFurnitureChange', 'skipFurnitureCraftChecksUntil', 'rollFurnitureCraftCheck',
         'processFurnitureCraftChecks', 'advanceFurnitureCraft']


def pull_const(name):
    """抽 `const X = ...;`（多行也行），遇到第一处行尾分号结束。"""
    m = re.search(r"^[ \t]*const %s\s*=" % re.escape(name), HIS, re.M)
    if not m:
        return None
    i = m.end()
    depth = 0
    while i < len(HIS):
        ch = HIS[i]
        if ch in '([{':
            depth += 1
        elif ch in ')]}':
            depth -= 1
        elif ch == ';' and depth <= 0:
            i += 1
            break
        i += 1
    return HIS[m.start():i].strip()


def pull_func(name):
    m = re.search(r"^[ \t]*function %s\s*\(" % re.escape(name), HIS, re.M)
    if not m:
        return None
    i = HIS.find('{', m.end())
    depth, j = 0, i
    while j < len(HIS):
        if HIS[j] == '{':
            depth += 1
        elif HIS[j] == '}':
            depth -= 1
            if depth == 0:
                break
        j += 1
    return HIS[m.start():j + 1]


def main():
    src = io.open(ENGINE, encoding='utf-8', newline='').read()
    if MARK in src:
        print('[mood2] 已并入过（%s），跳过' % MARK)
        return 0

    consts, funcs, missing = [], [], []
    for c in CONSTS:
        t = pull_const(c)
        if t:
            # 已经有同名常量的（如 FURNITURE_MESS_STRESS）就跳过
            if re.search(r"^[ \t]*const %s\s*=" % c, src, re.M):
                continue
            consts.append(t)
        else:
            missing.append('const ' + c)
    for f in FUNCS:
        t = pull_func(f)
        if t:
            funcs.append(t)
        else:
            missing.append('func ' + f)

    # 常量放到模块级常量区
    anchor_c = '/* ---------------------------------------------------------------- engine */'
    if consts and anchor_c in src:
        src = src.replace(anchor_c,
                          '/* %s 常量（抄他 3.3） */\n%s\n\n%s' % (MARK, '\n'.join(consts), anchor_c), 1)

    # 函数放进 createEngine 内部
    anchor_f = '  function tickGuest(ctx, t) {'
    if funcs and anchor_f in src:
        block = '\n'.join('  /* 【抄他 3.3】%s */\n%s\n' % (f, t) for f, t in zip(FUNCS, funcs))
        src = src.replace(anchor_f, block + '\n' + anchor_f, 1)
    elif funcs:
        raise SystemExit('[mood2] 找不到 tickGuest 锚点，函数放不进去')

    # 接线①：换家具 -> recordFurnitureChange()
    old1 = 'stressFurnitureMood(FURNITURE_REPLACE_STRESS);'
    if src.count(old1) >= 1:
        src = src.replace(old1, 'recordFurnitureChange();   /* 抄他 3.3：换家具记一次（含强制乱掉判定） */', 1)
        print('[mood2] 接线① 换家具 -> recordFurnitureChange（%d 处候选）' % src.count(old1))
    else:
        missing.append('接线①（换家具）')

    # 接线②：tick -> processFurnitureCraftChecks
    old2 = '    autoCraftCheck(ctx, t);'
    if old2 in src:
        src = src.replace(old2,
                          '    /* 抄他 3.3：工坊改成"每 3 小时检查一次 + 35% 开工"（我们原来的每拍检查不再调用）。 */\n'
                          '    if (processFurnitureCraftChecks(t, ctx)) save();', 1)
        print('[mood2] 接线② tick -> processFurnitureCraftChecks')
    else:
        missing.append('接线②（tick）')

    io.open(ENGINE, 'w', encoding='utf-8', newline='').write(src)
    print('[mood2] 常量 +%d，函数 +%d；未取到：%s' % (len(consts), len(funcs), missing or '无'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
