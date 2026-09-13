# -*- coding: utf-8 -*-
"""Scan a tree for wording that should not appear in a public repository:
references to a chat/assistant process rather than to the project itself.

Read-only. Prints file:line:excerpt grouped by file."""
import io
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else r'H:\AI\frog\git-repo'

PATTERNS = [
    '对话', '子代理', '本对话', '另一个对话', '你报', '我报', '用户说', '你说',
    'DSH', 'deepseek', 'DeepSeek', 'Claude', 'GPT', 'assistant 说',
    '本轮我', '这一轮我', '我写了', '我改', '请你', '你的截图',
]
# files whose matches are known-benign (game data / vendored code)
SKIP_DIRS = {'resource', '_dumps', '__pycache__'}
SKIP_FILES = {'main.min.js', 'default.thm.js', 'gamedata.json', 'version.json',
              'zh-CN.json', 'egret.min.js', 'eui.min.js', 'game.min.js'}

rx = re.compile('|'.join(re.escape(p) for p in PATTERNS))
total = 0
out = io.open(os.path.join(os.path.dirname(ROOT.rstrip('\\')), 'work', 'wording_report.txt'),
              'w', encoding='utf8') if os.path.isdir(ROOT) else None
for dp, dn, fn in os.walk(ROOT):
    dn[:] = [d for d in dn if d not in SKIP_DIRS]
    for f in fn:
        if f in SKIP_FILES or f.endswith(('.png', '.jpg', '.mp3', '.mp4', '.eab', '.apk', '.zip', '.pem', '.pk8')):
            continue
        p = os.path.join(dp, f)
        try:
            text = io.open(p, encoding='utf8', errors='replace').read()
        except OSError:
            continue
        hits = []
        for i, line in enumerate(text.split('\n'), 1):
            m = rx.search(line)
            if m:
                hits.append((i, m.group(0), line.strip()[:140]))
        if hits:
            total += len(hits)
            if out:
                out.write('\n%s  (%d)\n' % (os.path.relpath(p, ROOT), len(hits)))
                for i, kw, line in hits[:8]:
                    out.write('   L%-5d [%s] %s\n' % (i, kw, line))
if out:
    out.write('\ntotal hits: %d\n' % total)
    out.close()
print('total hits: %d' % total)
