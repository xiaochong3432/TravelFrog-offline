#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 -U0 diff 里还没应用的那几段，拆成最小编辑后逐条应用。

关键点：
  · SequenceMatcher 用**默认 autojunk=True**（96KB 的段也秒回；之前卡住是因为 autojunk=False）
  · 每条编辑都带上下文，要求在我们客户端里**恰好命中一次**才算数
  · 纯插入段（before 为空）：拿**他文件里插入点前面 120 字符**当锚点，在我们客户端里找它，
    找到就插在它后面（找不到就报出来，不猜）
"""
import difflib
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLIENT = os.path.join(ROOT, 'work', 'build', 'v4_client', 'main.min.js')
DIFF = os.environ.get('FROG_CLIENT_DIFF') or os.path.join(ROOT, 'work', 'logs', 'his_client_u0.diff')
HIS = os.path.join(ROOT, 'work', 'build', 'x33', 'new', 'main.min.js')
CTX = 70


def parse(path):
    hunks, cur = [], None
    for line in io.open(path, encoding='utf-8', errors='replace').read().split('\n'):
        if line.startswith('@@'):
            if cur:
                hunks.append(cur)
            cur = {'minus': [], 'plus': []}
            continue
        if cur is None or line[:3] in ('---', '+++') or line.startswith('diff ') or line.startswith('index '):
            continue
        if line.startswith('-'):
            cur['minus'].append(line[1:])
        elif line.startswith('+'):
            cur['plus'].append(line[1:])
    if cur:
        hunks.append(cur)
    return [('\n'.join(h['minus']), '\n'.join(h['plus'])) for h in hunks]


def edits_of(before, after):
    """最小编辑（带上下文）。"""
    if not before:
        return [('', after)]
    sm = difflib.SequenceMatcher(None, before, after)   # autojunk=True（快）
    out = []
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            continue
        pre = before[max(0, i1 - CTX):i1]
        post = before[i2:i2 + CTX]
        out.append((pre + before[i1:i2] + post, pre + after[j1:j2] + post))
    return out


def main():
    check = '--check' in sys.argv
    raw = io.open(CLIENT, encoding='utf-8', newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    text = raw.replace('\r\n', '\n')
    his = io.open(HIS, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')
    hunks = parse(DIFF)
    done = skipped = 0
    problems = []
    for hi, (before, after) in enumerate(hunks, 1):
        # 整段能命中就整段
        if before and text.count(before) == 1:
            if not check:
                text = text.replace(before, after, 1)
            done += 1
            continue
        if before and text.count(before) == 0 and after and text.count(after) >= 1:
            skipped += 1
            continue
        for old, new in edits_of(before, after):
            if old == '':
                # 纯插入：用他文件里插入点前 120 字符做锚点
                k = his.find(new)
                if k < 0:
                    problems.append((hi, '在他文件里都找不到插入内容', new[:90]))
                    continue
                anchor = his[max(0, k - 120):k]
                if text.count(anchor) == 1:
                    if not check:
                        text = text.replace(anchor, anchor + new, 1)
                    done += 1
                else:
                    problems.append((hi, '插入锚点命中 %d 次' % text.count(anchor), anchor[-90:]))
                continue
            if old == new:
                continue
            n_old, n_new = text.count(old), text.count(new)
            if n_old == 1:
                if not check:
                    text = text.replace(old, new, 1)
                done += 1
            elif n_old == 0 and n_new >= 1:
                skipped += 1
            else:
                problems.append((hi, 'old 命中 %d 次' % n_old, old[:120]))
    print('应用 %d 条最小编辑；已是 %d；待人工 %d' % (done, skipped, len(problems)))
    for hi, why, snip in problems:
        print('  #%d %s: %s' % (hi, why, snip.replace('\n', '\\n')))
    if not check and done:
        io.open(CLIENT, 'w', encoding='utf-8', newline='').write(text.replace('\n', eol))
        print('已写回客户端 %d B' % os.path.getsize(CLIENT))
    return 0


if __name__ == '__main__':
    sys.exit(main())
