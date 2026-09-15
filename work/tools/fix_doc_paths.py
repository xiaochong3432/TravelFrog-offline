#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rewrite absolute workspace paths in documentation into repo-relative ones.

    <old workspace root>/work/tools/x.py   ->  work/tools/x.py
    <old workspace root>                   ->  <仓库根>

Documents are prose, so a relative path (or the placeholder) reads better than a
machine-specific absolute path and keeps the docs valid on any checkout.

    python work/tools/fix_doc_paths.py            # dry run
    python work/tools/fix_doc_paths.py --apply
"""
import argparse
import io
import os
import re
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BACKUP = os.path.join(ROOT, 'work', 'portable-backup')

SCAN_DIRS = ['docs', os.path.join('work', 'notes'), os.path.join('work', 'repo-docs'),
             os.path.join('work', 'spec')]
SCAN_FILES = [os.path.join('work', 'run', 'README.md'),
              os.path.join('work', 'run', 'STATUS.md'),
              os.path.join('work', 'run', 'FEATURE_GAP.md')]

# a full path under the workspace root (separators may be / or \)
PATH_RX = re.compile(r'H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog((?:[\\/][^\s`"\'\)\],;]*)?)', re.I)


def rewrite(text):
    def repl(m):
        rest = (m.group(1) or '').replace('\\', '/').lstrip('/')
        return rest if rest else '<仓库根>'
    return PATH_RX.sub(repl, text)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    args = ap.parse_args()

    targets = []
    for d in SCAN_DIRS:
        p = os.path.join(ROOT, d)
        for dp, dn, fn in os.walk(p):
            dn[:] = [x for x in dn if x not in ('__pycache__', 'assets')]
            targets += [os.path.join(dp, f) for f in fn if f.endswith('.md')]
    targets += [os.path.join(ROOT, f) for f in SCAN_FILES]

    n = 0
    for p in sorted(set(targets)):
        if not os.path.isfile(p):
            continue
        text = io.open(p, encoding='utf8', errors='replace').read()
        new = rewrite(text)
        if new == text:
            continue
        rel = os.path.relpath(p, ROOT)
        cnt = len(PATH_RX.findall(text))
        if not args.apply:
            print('   %-60s %d path(s)' % (rel, cnt))
            n += 1
            continue
        dst = os.path.join(BACKUP, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.isfile(dst):
            shutil.copy2(p, dst)
        io.open(p, 'w', encoding='utf8', newline='').write(new)
        print('   %-60s %d path(s) rewritten' % (rel, cnt))
        n += 1
    print('%s %d files' % ('rewrote' if args.apply else 'would rewrite', n))
    return 0


if __name__ == '__main__':
    sys.exit(main())
