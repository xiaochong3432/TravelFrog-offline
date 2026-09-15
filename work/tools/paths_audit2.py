#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Second-pass audit: exactly which files hardcode the workspace root, in what
shape, plus every other local absolute path (URLs excluded).

    python work/tools/paths_audit2.py [root]      -> writes work/paths_report.txt
"""
import io
import os
import re
import sys
import collections

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'work', 'paths_report.txt')

TEXT_EXT = ('.py', '.js', '.mjs', '.ps1', '.cs', '.java', '.cmd', '.bat', '.md', '.txt')
SKIP_DIRS = {'.git', '__pycache__', 'resource', 'node_modules', 'shots', 'build',
             'jdk', 'jre', 'bt', 'plat', 'adb', 'cdn', 'jp_apk', 'logs', 'raw',
             'extracted', 'full', 'base', 'merge-backup', 'probe', 'spec',
             'jsdiff', 'compare-eab', 'compare-res', 'from-their-apk', 'conv',
             'Travel-Frog-Offline-Version', '.apksig_research', '_research'}
SKIP_PREFIX = ('dist/TravelFrog-PC', 'git-repo/')

URL_RX = re.compile(r'(?:https?|ftp|file|ws|wss)://')
# a literal that names the workspace root, in any escaping style
ROOT_RX = re.compile(r'H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog', re.I)
DRIVE_RX = re.compile(r'[A-Za-z]:[\\/][^\s"\'`\)\],;|]*')

shapes = collections.Counter()
root_files = []
other = collections.defaultdict(list)
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for f in fn:
        if not f.endswith(TEXT_EXT):
            continue
        p = os.path.join(dp, f)
        rel = os.path.relpath(p, ROOT).replace(os.sep, '/')
        if rel.startswith(SKIP_PREFIX):
            continue
        try:
            text = io.open(p, encoding='utf8', errors='replace').read()
        except OSError:
            continue
        n = len(ROOT_RX.findall(text))
        if n:
            root_files.append((rel, n))
            for line in text.split('\n'):
                if not ROOT_RX.search(line):
                    continue
                m = re.search(r'[rbfuRBFU]{0,3}["\']', line)
                styles = set(re.findall(r'(?<![\w.])[rbfuRBFU]{0,3}["\']', line))
                shapes[','.join(sorted(styles)) or '(none)'] += 1
        for m in DRIVE_RX.finditer(text):
            s = m.group(0)
            if ROOT_RX.search(s) or URL_RX.search(text[max(0, m.start() - 12):m.end()]):
                continue
            if len(s) < 4:
                continue
            other[rel].append(s)

with io.open(OUT, 'w', encoding='utf8') as fh:
    fh.write('== files hardcoding the workspace root: %d, occurrences %d\n'
             % (len(root_files), sum(n for _, n in root_files)))
    for rel, n in sorted(root_files):
        fh.write('   %-58s %d\n' % (rel, n))
    fh.write('\n== literal styles seen on those lines\n')
    for k, v in shapes.most_common():
        fh.write('   %-24s %d\n' % (k, v))
    fh.write('\n== other local absolute paths (URLs excluded)\n')
    for rel in sorted(other):
        uniq = sorted(set(other[rel]))
        fh.write('   %s\n' % rel)
        for u in uniq[:8]:
            fh.write('        %s\n' % u)
print('wrote %s' % OUT)
print('files with root literal: %d ; files with other absolute paths: %d'
      % (len(root_files), len(other)))
