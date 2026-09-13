# -*- coding: utf-8 -*-
"""Check that every repo-relative path mentioned in backticks in docs/ + README
actually exists. Keeps documentation from rotting after a refactor.

    python work/tools/check_doc_links.py <repo-root>
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else str(PROJECT_ROOT) + "/git-repo"
PREFIXES = ('work/', 'docs/', 'dist/', 'NOTICE.txt', 'README.md')
SKIP_SUFFIX = ('/', '.py', '.js', '.json', '.md', '.txt', '.exe', '.bat', '.cmd',
               '.ps1', '.pem', '.pk8', '.html', '.cs', '.java')

# Paths a document mentions on purpose while explaining that they are NOT part of
# the repository (client art, downloaded toolchains, reference material).
INTENTIONALLY_ABSENT = (
    'work/run/web/resource/',
    'work/jdk/',
    'work/jre/',
    'work/bt/',
    'work/plat/',
    'work/cdn/',
    'work/jp_apk/',
    'work/logs/',
    'base.apk',
    'jp.co.hit_point.tabikaeru.apk',
)

pat = re.compile(r'`([^`]+)`')

bad = []
total = 0
targets = [os.path.join(ROOT, 'README.md'), os.path.join(ROOT, 'NOTICE.txt')]
for dp, dn, fn in os.walk(os.path.join(ROOT, 'docs')):
    targets += [os.path.join(dp, f) for f in fn if f.endswith('.md')]

for p in targets:
    if not os.path.isfile(p):
        continue
    text = io.open(p, encoding='utf-8', errors='replace').read()
    for m in pat.finditer(text):
        ref = m.group(1).strip()
        if not ref.startswith(PREFIXES) or ' ' in ref:
            continue
        if ref.endswith('*') or '*' in ref:
            continue
        ref_path = ref.split('#')[0].rstrip('.,;:')
        if any(ref_path == p or ref_path.startswith(p) for p in INTENTIONALLY_ABSENT):
            continue          # documented as not-in-repo, not a broken link
        total += 1
        if not os.path.exists(os.path.join(ROOT, ref_path.replace('/', os.sep))):
            bad.append((os.path.relpath(p, ROOT), ref_path))

print('checked %d references' % total)
for rel, ref in bad:
    print('  MISSING  %-46s  (in %s)' % (ref, rel))
print('missing: %d' % len(bad))
