#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0 统一（修正版）：把"我们仍用自己的取值/字段"的地方按他 3.3 统一。

修正点：
  1. VISITOR_FOOD_MAX 引用 VISITOR_FOOD_IDS —— 原位替换会 TDZ，改成插到 VISITOR_FOOD_IDS 声明之后
  2. 载荷替换**必须生效**（替换后校验，失败就报错而不是静默跳过）
  3. furniture_load_pocket / furniture_load_compost 用"整段键定位"的方式换
"""
import io
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = ROOT + 'work/build/v4_engine/index.js'
HIS_PATH = ROOT + 'work/build/x33/live/index.js'
MARK = 'V40-UNIFY-HIS'
HIS = io.open(HIS_PATH, encoding='utf-8', errors='replace').read()

FLIP = ['GUEST_CHANCE', 'GUEST_COOL_SEC', 'GUEST_STAY_SEC', 'GUEST_ROLL_MIN_SEC',
        'GUEST_ROLL_MAX_SEC', 'PLANT_STAGE_SEC', 'DRIFT_RETURN_MIN', 'DRIFT_RETURN_MAX',
        'DRAWING_TRIP_MAX_SEC', 'FURNITURE_AUTO_REPLACE_MAX_SEC', 'FURNITURE_TOOL_MOTION',
        'TIMER_EVENT']
LATE = ['VISITOR_FOOD_MAX']            # 要插到依赖之后
# pray_load_grays 不换：他的载荷要配他的手工状态机，我们的状态机没并 -> 换了就错位。
PAYLOADS = ['furniture_load_pocket', 'furniture_load_compost']


def span_const(src, name):
    m = re.search(r"^[ \t]*const %s\s*=" % re.escape(name), src, re.M)
    if not m:
        return None
    i = m.end()
    d = 0
    while i < len(src):
        c = src[i]
        if c in '([{':
            d += 1
        elif c in ')]}':
            d -= 1
        elif c == ';' and d <= 0:
            i += 1
            break
        i += 1
    return m.start(), i, src[m.start():i]


def span_handler(src, key, indent='    '):
    m = re.search(r"^%s%s:\s*" % (indent, re.escape(key)), src, re.M)
    if not m:
        return None
    i = m.end()
    while i < len(src) and src[i] not in '{(':
        i += 1
    opener, closer = src[i], ('}' if src[i] == '{' else ')')
    d, j = 0, i
    while j < len(src):
        if src[j] == opener:
            d += 1
        elif src[j] == closer:
            d -= 1
            if d == 0:
                break
        j += 1
    return m.start(), j + 1, src[m.start():j + 1]


def his_defaults():
    js = ('const m=require(%s);const e=m.createEngine({savePath:%s,verbose:false});e.tick();'
          'const s=e.exportSave();console.log(JSON.stringify({q:s.drawingQueued,r:s.drawingRestUntil,'
          'lw:(s.cooking||{}).lastWeek,td:(s.cooking||{}).taskDay,cs:((s.furniture||{}).compost||{}).state}));'
          % (json.dumps(HIS_PATH), json.dumps(ROOT + 'work/logs/_d2.json')))
    r = subprocess.run(['node', '-e', js], capture_output=True, text=True, encoding='utf-8', errors='replace')
    return json.loads(r.stdout)


def main():
    src = io.open(ENGINE, encoding='utf-8', newline='').read()
    if MARK in src:
        print('[unify] 已统一过，跳过')
        return 0
    done, failed = [], []

    for c in FLIP:
        h, o = span_const(HIS, c), span_const(src, c)
        if not h or not o:
            failed.append(c)
            continue
        if h[2] == o[2]:
            continue
        src = src[:o[0]] + h[2] + src[o[1]:]
        done.append('const ' + c)

    for c in LATE:
        h = span_const(HIS, c)
        dep = span_const(src, 'VISITOR_FOOD_IDS')
        o = span_const(src, c)
        if not h or not o or not dep:
            failed.append(c)
            continue
        if h[2] == o[2]:
            continue
        # 先删掉原位，再插到依赖之后
        src = src[:o[0]] + src[o[1]:]
        dep = span_const(src, 'VISITOR_FOOD_IDS')     # 重新定位（前面的删除会移位）
        src = src[:dep[1]] + '\n  ' + h[2] + src[dep[1]:]
        done.append('const %s（移到 VISITOR_FOOD_IDS 之后）' % c)

    for key in PAYLOADS:
        h, o = span_handler(HIS, key), span_handler(src, key)
        if not h or not o:
            failed.append(key)
            continue
        if h[2] == o[2]:
            continue
        before = src
        src = src[:o[0]] + h[2] + src[o[1]:]
        if src == before:
            failed.append(key + '(替换未生效)')
        else:
            done.append('handler ' + key)

    d = his_defaults()
    ensure = (
        "  /* %s 【抄他 3.3】他进度模型的字段：顶层原始值会被启动包装掉，在 tick 里按他的默认补齐。 */\n"
        "  if (state.drawingQueued === undefined || typeof state.drawingQueued === 'object') "
        "state.drawingQueued = %s;\n"
        "  if (state.drawingRestUntil === undefined || typeof state.drawingRestUntil === 'object') "
        "state.drawingRestUntil = %s;\n"
        "  if (state.cooking) {\n"
        "    if (state.cooking.lastWeek === undefined) state.cooking.lastWeek = %s;\n"
        "    if (state.cooking.taskDay === undefined) state.cooking.taskDay = %s;\n"
        "  }\n"
        "  if (state.craft && state.craft.workClockAt === undefined) state.craft.workClockAt = 0;\n"
        "  if (state.furniture && state.furniture.compost "
        "&& state.furniture.compost.state === undefined) state.furniture.compost.state = %s;\n"
    ) % (MARK, json.dumps(d.get('q', False)), json.dumps(d.get('r', 0)),
         json.dumps(d.get('lw', 0)), json.dumps(d.get('td', '')), json.dumps(d.get('cs', 0)))
    anchor = '  function tickGuest(ctx, t) {'
    if anchor in src:
        src = src.replace(anchor, ensure + '\n' + anchor, 1)
        done.append('tick 补字段')
    else:
        failed.append('tick 锚点')

    io.open(ENGINE, 'w', encoding='utf-8', newline='').write(src)
    print('[unify] 统一 %d 项：%s' % (len(done), done))
    if failed:
        print('[unify] ** 未完成：%s' % failed)
    return 0


if __name__ == '__main__':
    sys.exit(main())
