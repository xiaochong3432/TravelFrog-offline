# -*- coding: utf-8 -*-
"""Swap the (mis-escaped) browser-resolver block in the CDP tools for the correct
one kept in work/tools/_browser_resolver.js.inc.

Why an include file: the replacement contains double backslashes and a regex, and
writing it through several layers of escaping is how it got broken the first time.
The .inc file holds the exact bytes.

    python work/tools/_repair_browser_block.py
"""
import glob
import io
import os

HERE = os.path.dirname(os.path.abspath(__file__))
INC = os.path.join(HERE, '_browser_resolver.js.inc')
FILES = ['cdp_drive.js', 'cdp_console.js', 'cdp_probe.js', 'cdp_shot.js',
         'save_persist_test.js', 'save_restart_test.js']
START = '/* 浏览器可执行文件'
END = '})();'

block = io.open(INC, encoding='utf-8').read().rstrip('\n')
changed = 0
for name in FILES:
    p = os.path.join(HERE, name)
    text = io.open(p, encoding='utf-8').read()
    i = text.find(START)
    if i < 0:
        i = text.find('const EDGE = (function')
    if i < 0:
        print('  no resolver block: %s' % name)
        continue
    j = text.find(END, i)
    if j < 0:
        print('  no end marker: %s' % name)
        continue
    j += len(END)
    new = text[:i] + block + text[j:]
    if new == text:
        print('  already correct: %s' % name)
        continue
    io.open(p, 'w', encoding='utf-8', newline='').write(new)
    print('  fixed: %s' % name)
    changed += 1
print('files changed:', changed)
