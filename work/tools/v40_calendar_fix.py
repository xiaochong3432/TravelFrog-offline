#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V4.0：把我们旧版的 ensureCalendarMonth 换成他 3.3 的原文（月奖励归一化 + rewardVersion）。

实测差异：
  我们 1,261 字符（缺 CALENDAR_MONTH_REWARDS 归一化、缺 CALENDAR_REWARD_VERSION 写入）
  他   1,681 字符
后果：并存了他客户端的 st_days 门槛后，新档里 state.calendar.st 不是按固定月奖表生成的，
      客户端拿到的 st_days 与他那版不一致 -> 月历奖励行为不对。
调用点两边一致（calendar_load / calendar_get_st_reward / calendar_get_luck_reward），
所以**只换函数体 + 补常量**即可。
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
HIS_PATH = os.path.join(ROOT, 'work', 'build', 'x33', 'live', 'index.js')
MARK = 'V40-CALENDAR-FIX'
HIS = io.open(HIS_PATH, encoding='utf-8', errors='replace').read()


def body_of(src, name, indent='  '):
    m = re.search(r"^%sfunction %s\s*\(" % (indent, re.escape(name)), src, re.M)
    if not m:
        return None
    i = src.find('{', m.end())
    d, j = 0, i
    while j < len(src):
        if src[j] == '{':
            d += 1
        elif src[j] == '}':
            d -= 1
            if d == 0:
                break
        j += 1
    return src[m.start():j + 1]


def const_of(src, name):
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
    return src[m.start():i].strip()


def names(src):
    s = set(re.findall(r'\bfunction\s+([A-Za-z_$][\w$]*)', src))
    s |= set(re.findall(r'\b(?:const|let|var)\s+([A-Za-z_$][\w$]*)', src))
    return s


def main():
    src = io.open(ENGINE, encoding='utf-8', newline='').read()
    if MARK in src:
        print('[calfix] 已修过，跳过')
        return 0
    his_body = body_of(HIS, 'ensureCalendarMonth')
    our_body = body_of(src, 'ensureCalendarMonth')
    if not his_body or not our_body:
        raise SystemExit('[calfix] 找不到 ensureCalendarMonth')
    if his_body == our_body:
        print('[calfix] 已经一致，跳过')
        return 0

    # 依赖检查：他函数体里用到、我们没有的名字
    used = set(re.findall(r'\b([A-Za-z_$][\w$]*)\b', his_body))
    ours = names(src)
    BUILTIN = set('state save nowSec randInt Number String Boolean Math Object Array JSON Date Map Set console process undefined null true false NaN isNaN parseInt parseFloat Error Promise ctx'.split())
    missing = sorted(n for n in used if n not in BUILTIN and n not in ours
                     and re.search(r'\b(?:function|const|let|var)\s+%s\b' % re.escape(n), HIS))
    print('[calfix] 他函数体缺失依赖:', missing or '无')

    # ① 换函数体
    src = src.replace(our_body, his_body, 1)
    # ② 补常量
    added = []
    for c in missing:
        # 只认模块级常量：名字全大写，且定义不引用 state（否则是别人函数里的局部变量）
        if not re.match(r'^[A-Z][A-Z0-9_]*$', c):
            print('[calfix] 跳过局部变量: %s' % c)
            continue
        t = const_of(HIS, c)
        if t and 'state.' in t:
            print('[calfix] 跳过引用 state 的定义: %s' % c)
            continue
        if t and not re.search(r'^[ \t]*const %s\s*=' % re.escape(c), src, re.M):
            anchor = '/* ---------------------------------------------------------------- engine */'
            src = src.replace(anchor, '/* %s 常量（抄他 3.3） */\n%s\n\n%s' % (MARK, t, anchor), 1)
            added.append(c)
    io.open(ENGINE, 'w', encoding='utf-8', newline='').write(src)
    print('[calfix] 已换成他的 ensureCalendarMonth（%d -> %d 字符），补常量 %s'
          % (len(our_body), len(his_body), added or '无'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
