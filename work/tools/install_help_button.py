#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Install the re-rendered 制作人员 button texture into a payload's system.eab, and keep
version.json's md5 in step (that file is a file->md5 map, and system.eab's entry matched
the real md5 before the change, so it has to match after it too).

  python tools/install_help_button.py work/run/v3web <new.png>
  python tools/install_help_button.py work/run/web    <new.png>
"""
from pathlib import Path as _PortablePath
# 仓库根：按本文件自身位置推导（深度 2），不写死任何绝对路径 ——
# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys

ROOT = str(PROJECT_ROOT)
ENTRY = 'button_02_png'


def main():
    # resolve both relative to the CALLER's cwd -- resolving against the repo root made
    # `logs/v3tex/x.png` look under <root>/logs, which does not exist.
    payload, png = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])

    eab = os.path.join(payload, 'resource', 'China', 'eab', 'system.eab')
    ver = os.path.join(payload, 'version.json')
    if not os.path.isfile(eab):
        print('!! no %s' % eab)
        return 1

    before = hashlib.md5(open(eab, 'rb').read()).hexdigest()
    backup = eab + '.orig'
    if not os.path.isfile(backup):
        shutil.copy2(eab, backup)
        print('backup: %s' % os.path.basename(backup))

    tmp = eab + '.new'
    r = subprocess.run([sys.executable, os.path.join(ROOT, 'work', 'tools', 'eab_tool.py'),
                        'replace', eab, ENTRY, png, tmp],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    print((r.stdout or r.stderr).strip())
    if r.returncode != 0 or not os.path.isfile(tmp):
        print('!! eab replace failed')
        return 1
    shutil.move(tmp, eab)
    after = hashlib.md5(open(eab, 'rb').read()).hexdigest()
    print('system.eab md5 %s -> %s (%d -> %d bytes)'
          % (before, after, os.path.getsize(backup), os.path.getsize(eab)))

    if os.path.isfile(ver):
        text = io.open(ver, encoding='utf-8').read()
        key = 'resource/China/eab/system.eab'
        m = re.search(r'("%s"\s*:\s*")([0-9a-f]{32})(")' % re.escape(key), text)
        if not m:
            print('!! version.json has no md5 entry for %s' % key)
            return 1
        old = m.group(2)
        if old != before:
            print('note: version.json said %s, the file was %s (already out of step?)' % (old, before))
        if old == after:
            print('version.json: already %s' % after)
        else:
            text = text[:m.start(2)] + after + text[m.end(2):]
            io.open(ver, 'w', encoding='utf-8', newline='').write(text)
            print('version.json: md5 -> %s' % after)
    else:
        print('note: no version.json in this payload')
    return 0


if __name__ == '__main__':
    sys.exit(main())
