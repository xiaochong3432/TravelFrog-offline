#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compare two JavaScript files ignoring comments and blank lines.

Used to answer "is the older copy missing any real code, or does it only differ in
wording?" — the V3 handover and our own tree carry two revisions of __probe.js.

    python work/tools/js_code_diff.py <a.js> <b.js>
"""
import io
import re
import sys


def strip_js(text):
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == '/*':
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
            continue
        if two == '//':
            j = text.find('\n', i)
            i = n if j < 0 else j
            continue
        if c in '"\'':
            quote = c
            out.append(c)
            i += 1
            while i < n:
                if text[i] == '\\':
                    out.append(text[i:i + 2])
                    i += 2
                    continue
                out.append(text[i])
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        out.append(c)
        i += 1
    code = ''.join(out)
    lines = [re.sub(r'\s+', ' ', l).strip() for l in code.split('\n')]
    return [l for l in lines if l]


def main():
    a, b = sys.argv[1], sys.argv[2]
    A = strip_js(io.open(a, encoding='utf8', errors='replace').read())
    B = strip_js(io.open(b, encoding='utf8', errors='replace').read())
    print('%s: %d 行代码' % (a, len(A)))
    print('%s: %d 行代码' % (b, len(B)))
    setA, setB = set(A), set(B)
    onlyA = [l for l in A if l not in setB]
    onlyB = [l for l in B if l not in setA]
    print('\n只在 A 里出现的代码行: %d' % len(onlyA))
    for l in onlyA[:20]:
        print('   A| ' + l[:120])
    print('\n只在 B 里出现的代码行: %d' % len(onlyB))
    for l in onlyB[:20]:
        print('   B| ' + l[:120])
    print('\n结论: ' + ('两者代码等价（只有注释/空白不同）'
                      if not onlyA and not onlyB else '存在真实代码差异，需要人工确认'))
    return 0 if not onlyA and not onlyB else 2


if __name__ == '__main__':
    sys.exit(main())
