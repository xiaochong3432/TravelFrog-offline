#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0：并入剩下的函数与协议（原样抽取 + 依赖检查）。

抄：
  函数：cookingPayload / cookingResetDailyTasks / capsuleFastTask / queuePartyResult /
        wishingPoolPayload / resetWishPoolIfExhausted / advanceFurnitureOffline /
        scheduledFurnitureMotion
  协议：compost / saw
  常量：他缺失的那些（FERTILIZER_RULES、三个迁移戳、COMPOSE_PIECE_CHANCE、
        GIFTBOX_VISIT_TAGS、GUEST_BONUS_TICKET_CHANCE、GUEST_CLOVER_MIN/MAX、FROG_MIRROR_PREP_SEC）

安全网：抽出来的每个函数都会做**依赖检查**——如果它用到、而我们引擎里根本没有的
        函数/常量，就跳过这个函数并打印（避免抄进来一调用就崩）。
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
HIS_PATH = os.path.join(ROOT, 'work', 'build', 'x33', 'live', 'index.js')
MARK = 'V40-REST'

HIS = io.open(HIS_PATH, encoding='utf-8', errors='replace').read()

FUNCS = ['cookingPayload', 'cookingResetDailyTasks', 'capsuleFastTask', 'queuePartyResult',
         'wishingPoolPayload', 'resetWishPoolIfExhausted', 'advanceFurnitureOffline',
         'scheduledFurnitureMotion']
CONSTS = ['FERTILIZER_RULES', 'CALENDAR_REWARD_VERSION', 'FLOWERPOT_STATE_VERSION',
          'TRAVEL_SCHEDULE_VERSION', 'COMPOSE_PIECE_CHANCE', 'GIFTBOX_VISIT_TAGS',
          'GUEST_BONUS_TICKET_CHANCE', 'GUEST_CLOVER_MIN', 'GUEST_CLOVER_MAX',
          'FROG_MIRROR_PREP_SEC']
HANDLERS = ['compost', 'saw']

# 引擎里天然存在的名字（不算依赖缺失）
BUILTIN = set('''state save nowSec randInt Number String Boolean Math Object Array JSON Date
Map Set console process require module exports define gamedata defineData handlers ctx
undefined null true false NaN Infinity isNaN parseInt parseFloat Error Promise'''.split())


def pull_const(name):
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


def pull_handler(name):
    """抽协议处理体：支持 `name: (d, ctx) => { ... }` 与 `=> ({ ... })` 两种写法。"""
    # 只认"处理函数"（箭头函数或 function），不认默认存档里的同名对象字段
    m = re.search(r"^[ \t]{4}%s:\s*(?:async\s*)?(?:\(|function\b)" % re.escape(name), HIS, re.M)
    if not m:
        return None
    i = m.end()
    i -= 1
    # 跳到第一个 { 或 (
    while i < len(HIS) and HIS[i] not in '{(':
        if HIS[i] == ',':
            return None
        i += 1
    if i >= len(HIS):
        return None
    opener = HIS[i]
    closer = '}' if opener == '{' else ')'
    depth, j = 0, i
    while j < len(HIS):
        if HIS[j] == opener:
            depth += 1
        elif HIS[j] == closer:
            depth -= 1
            if depth == 0:
                break
        j += 1
    body = HIS[m.start():j + 1]
    return body.rstrip().rstrip(',') + ','


def known_names(src):
    """这份引擎里声明的函数名与常量名。"""
    names = set(re.findall(r'\bfunction\s+([A-Za-z_$][\w$]*)', src))
    names |= set(re.findall(r'\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)', src))
    return names


def main():
    src = io.open(ENGINE, encoding='utf-8', newline='').read()
    if MARK in src:
        print('[rest] 已并入过（%s），跳过' % MARK)
        return 0
    his_names, our_names = known_names(HIS), known_names(src)

    consts, funcs, handlers, skipped = [], [], [], []
    for c in CONSTS:
        if re.search(r"^[ \t]*const %s\s*=" % c, src, re.M):
            continue
        t = pull_const(c)
        (consts.append(t) if t else skipped.append('const ' + c))

    for f in FUNCS:
        t = pull_func(f)
        if not t:
            skipped.append('func ' + f)
            continue
        # 依赖检查：函数体里用到的、他声明了而我们没有的名字
        used = set(re.findall(r'\b([A-Za-z_$][\w$]*)\s*\(', t)) | set(re.findall(r'\b([A-Z][A-Z0-9_]{2,})\b', t))
        missing = sorted(n for n in used
                         if n not in BUILTIN and n not in our_names and n in his_names and n != f)
        if missing and not all(any(m == cc for cc in [x.split()[1] for x in []]) for m in missing):
            # 允许缺失项里包含本次同批要补的常量
            allowed = set(CONSTS) | set(FUNCS)
            hard = [m for m in missing if m not in allowed]
            if hard:
                skipped.append('func %s（缺依赖 %s）' % (f, ','.join(hard)))
                continue
        funcs.append((f, t))

    for h in HANDLERS:
        t = pull_handler(h)
        (handlers.append((h, t)) if t else skipped.append('handler ' + h))

    if consts:
        src = src.replace('/* ---------------------------------------------------------------- engine */',
                          '/* %s 常量（抄他 3.3） */\n%s\n\n/* ---------------------------------------------------------------- engine */'
                          % (MARK, '\n'.join(consts)), 1)
    anchor_f = '  function tickGuest(ctx, t) {'
    if funcs and anchor_f in src:
        src = src.replace(anchor_f, ''.join('  /* 【抄他 3.3】%s */\n%s\n' % (f, t) for f, t in funcs) + '\n' + anchor_f, 1)
    anchor_h = '    task_load: () => {'
    if handlers and anchor_h in src:
        src = src.replace(anchor_h, ''.join('    /* 【抄他 3.3】%s 协议 */\n%s\n' % (h, t) for h, t in handlers) + anchor_h, 1)

    io.open(ENGINE, 'w', encoding='utf-8', newline='').write(src)
    print('[rest] 常量 +%d：%s' % (len(consts), [c.split()[1] for c in consts] if consts else '无'))
    print('[rest] 函数 +%d：%s' % (len(funcs), [f for f, _ in funcs]))
    print('[rest] 协议 +%d：%s' % (len(handlers), [h for h, _ in handlers]))
    print('[rest] 跳过：%s' % (skipped or '无'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
