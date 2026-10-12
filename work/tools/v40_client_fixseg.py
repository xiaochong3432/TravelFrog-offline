#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把客户端里被我"半个编辑"改坏的片段，整段换成他客户端里的原文。

目前已知坏点：HandCraftModel.prototype.req_compose（三元表达式丢了 `:[]`，留下 `;`）。
做法：从他客户端里抽 `req_compose=function(...)` 到 `__reflect(HandCraftModel` 之间的整段，
     替换我们客户端里对应的一段。抽/换都要求唯一命中。
然后跑 node --check 确认语法。
"""
import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CLIENT = os.path.join(ROOT, 'work', 'build', 'v4_client', 'main.min.js')
HIS = os.path.join(ROOT, 'work', 'build', 'x33', 'new', 'main.min.js')

START = 't.prototype.req_compose=function('
END = '__reflect(HandCraftModel'


def slice_between(text, start, end):
    i = text.find(start)
    if i < 0:
        return None
    j = text.find(end, i)
    if j < 0:
        return None
    return i, j, text[i:j]


def main():
    raw = io.open(CLIENT, encoding='utf-8', newline='').read()
    eol = '\r\n' if '\r\n' in raw else '\n'
    text = raw.replace('\r\n', '\n')
    his = io.open(HIS, encoding='utf-8', errors='replace').read().replace('\r\n', '\n')

    ours_seg = slice_between(text, START, END)
    his_seg = slice_between(his, START, END)
    if not ours_seg or not his_seg:
        print('** 抽不到 req_compose 段（我们 %s / 他 %s）' % (bool(ours_seg), bool(his_seg)))
        return 1
    oi, oj, oseg = ours_seg
    _, _, hseg = his_seg
    if oseg == hseg:
        print('req_compose 已经与他一致')
    else:
        text = text[:oi] + hseg + text[oj:]
        io.open(CLIENT, 'w', encoding='utf-8', newline='').write(text.replace('\n', eol))
        print('已用他的 req_compose 原文替换（%d -> %d 字符）' % (len(oseg), len(hseg)))

    r = subprocess.run(['node', '--check', CLIENT], capture_output=True, text=True, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        err = ((r.stderr or '') + (r.stdout or '')).split('\n')
        print('** node --check 仍失败:', [l for l in err if 'Error' in l][:2])
        return 1
    print('node --check 通过 ✔（客户端语法正确）')
    return 0


if __name__ == '__main__':
    sys.exit(main())
