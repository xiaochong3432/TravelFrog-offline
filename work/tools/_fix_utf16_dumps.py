#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""One-off: two archived dumps captured a PowerShell error message that quoted a
command line containing the old workspace root. Both files are UTF-16LE, which the
UTF-8-oriented scanners could not see. Rewrite the marker inside them (keeping the
encoding) instead of deleting them, because one of them is cited by work/spec.

Workspace-side cleanup; safe to re-run.
"""
import io
import os

BS = chr(92)
FS = chr(47)
MARKERS = ('H:' + BS + 'AI' + BS + 'frog', 'H:' + FS + 'AI' + FS + 'frog',
           'h:' + FS + 'ai' + FS + 'frog')
FILES = [r'work\out_config_idx.txt', r'work\spec\_dumps\se.out']

for rel in FILES:
    if not os.path.isfile(rel):
        print('missing: %s' % rel)
        continue
    raw = io.open(rel, 'rb').read()
    for enc in ('utf-16', 'utf-8-sig', 'utf-8'):
        try:
            text = raw.decode(enc)
        except UnicodeDecodeError:
            continue
        n = 0
        for m in MARKERS:
            n += text.count(m)
            text = text.replace(m, '<repo>')
        if n:
            io.open(rel, 'w', encoding=enc if enc != 'utf-8-sig' else 'utf-8',
                    newline='').write(text)
            print('%-34s %s: rewrote %d occurrence(s)' % (rel, enc, n))
        else:
            print('%-34s %s: nothing to rewrite' % (rel, enc))
        break
