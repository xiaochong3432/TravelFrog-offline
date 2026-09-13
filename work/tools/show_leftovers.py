#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""List every line that still names the old workspace root, using the canonical
detector in _pathpat (no regex escaping pitfalls).

    python work/tools/show_leftovers.py [root]
"""
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _pathpat as pp  # noqa: E402

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'leftovers.txt')
OUT = os.path.abspath(OUT)

SKIP_DIRS = set(pp.SKIP_DIRS) | {'logs', 'raw', 'extracted', 'full', 'base',
                                 'merge-backup', 'jsdiff', 'compare-eab', 'compare-res',
                                 'from-their-apk', 'conv', 'Travel-Frog-Offline-Version',
                                 '.apksig_research', '_research', 'specdata'}
SKIP_PREFIX = ('dist/TravelFrog-PC', 'git-repo/')

rows = []
n_lines = 0
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for f in fn:
        if not f.endswith(pp.CODE_EXT + ('.txt', '.json')):
            continue
        p = os.path.join(dp, f)
        rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
        if rel.startswith(SKIP_PREFIX):
            continue
        text = io.open(p, encoding='utf8', errors='replace').read()
        hits = [(i, l.strip()) for i, l in enumerate(text.split('\n'), 1)
                if pp.has_root_marker(l)]
        if hits:
            rows.append((rel, hits))
            n_lines += len(hits)

with io.open(OUT, 'w', encoding='utf8') as fh:
    for rel, hits in rows:
        fh.write('\n%s  (%d)\n' % (rel, len(hits)))
        for i, l in hits[:10]:
            fh.write('   L%-5d %s\n' % (i, l[:150]))
    fh.write('\n== %d files, %d lines\n' % (len(rows), n_lines))

code_rows = [r for r in rows if r[0].endswith(('.py', '.js', '.mjs', '.ps1', '.cs', '.java'))]
print('wrote %s' % OUT)
print('%d files / %d lines ; of which CODE: %d files' % (len(rows), n_lines, len(code_rows)))
for rel, hits in code_rows[:20]:
    print('   %-56s %d' % (rel, len(hits)))
