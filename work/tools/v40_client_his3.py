#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把他的客户端改动应用到我们客户端（用 -U0 --minimal 的小段；纯插入用基线行号锚点）。

不碰任何 O(n^2) 算法。每段都校验唯一性，全部算完再写文件。
用法：python work/tools/v40_client_his3.py [--check]
"""
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLIENT = os.path.join(ROOT, 'work', 'build', 'v4_client', 'main.min.js')
DIFF = os.environ.get('FROG_CLIENT_DIFF') or os.path.join(ROOT, 'work', 'logs', 'his_client_u0.diff')
BASE = os.path.join(ROOT, 'work', 'build', 'upstream34', 'client_main.min.js')


def parse(path):
    hunks, cur = [], None
    for line in io.open(path, encoding='utf-8', errors='replace').read().split('\n'):
        if line.startswith('@@'):
            if cur:
                hunks.append(cur)
            m = re.match(r'@@ -(\d+)(?:,(\d+))? \+\d+(?:,(\d+))? @@', line)
            cur = {'a': int(m.group(1)) if m else 0,
                   'alen': int(m.group(2)) if m and m.group(2) is not None else 1,
                   'minus': [], 'plus': []}
            continue
        if cur is None or line[:3] in ('---', '+++') or line.startswith('diff ') or line.startswith('index '):
            continue
        if line.startswith('-'):
            cur['minus'].append(line[1:])
        elif line.startswith('+'):
            cur['plus'].append(line[1:])
    if cur:
        hunks.append(cur)
    return hunks


def main():
    check = '--check' in sys.argv
    raw = io.open(CLIENT, encoding='utf-8', newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    text = raw.replace('\r\n', '\n')
    base_lines = io.open(BASE, encoding='utf-8', errors='replace').read().replace('\r\n', '\n').split('\n')
    hunks = parse(DIFF)
    ok = skip = bad = 0
    problems = []
    for i, h in enumerate(hunks, 1):
        old = '\n'.join(h['minus'])
        new = '\n'.join(h['plus'])
        if old:
            n_old, n_new = text.count(old), text.count(new)
            if n_old == 1:
                if not check:
                    text = text.replace(old, new, 1)
                ok += 1
            elif n_old == 0 and n_new >= 1:
                skip += 1
            else:
                bad += 1
                problems.append((i, 'old x%d new x%d' % (n_old, n_new), old[:100], new[:100]))
        else:
            # 纯插入：用基线第 a 行做锚点，插到它后面
            anchor = base_lines[h['a'] - 1] if 1 <= h['a'] <= len(base_lines) else ''
            if not anchor:
                bad += 1
                problems.append((i, 'pure-insert 无锚点', '', new[:100]))
                continue
            if new and new in text:
                skip += 1
                continue
            n_anchor = text.count(anchor)
            if n_anchor == 1:
                if not check:
                    text = text.replace(anchor, anchor + '\n' + new, 1)
                ok += 1
            else:
                bad += 1
                problems.append((i, '纯插入锚点 x%d' % n_anchor, anchor[:100], new[:100]))
    print('段数 %d：应用 %d / 已是 %d / 需人工 %d' % (len(hunks), ok, skip, bad))
    for i, why, o, n in problems:
        print('  #%d %s\n      old: %s\n      new: %s' % (i, why, o.replace('\n', '\\n'), n.replace('\n', '\\n')))
    if not check and ok:
        io.open(CLIENT, 'w', encoding='utf-8', newline='').write(text.replace('\n', eol))
        print('已写回客户端 %d B' % os.path.getsize(CLIENT))
    return 0


if __name__ == '__main__':
    sys.exit(main())
