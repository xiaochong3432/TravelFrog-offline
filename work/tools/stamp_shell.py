#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rewrite the 存档编辑 panel's BUILD_STAMP to the current local time.

The stamp is how a player can tell which copy of the game they are running, so it has to
be the moment of the build -- hand-editing it produced a stamp 17 minutes in the future
(clock drift between writing the patch and running the build). Run this immediately
before build_wrapper_apk.py.

Usage: python tools/stamp_shell.py [shell.js ...]      (default: work/run/web/__probe.js)
"""
from pathlib import Path as _PortablePath
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import datetime
import io
import re
import sys

DEFAULT = str(PROJECT_ROOT) + "/work/run/web/__probe.js"
targets = sys.argv[1:] or [DEFAULT]

now = datetime.datetime.now().strftime('%Y-%m-%d %H:%M')
for target in targets:
    text = io.open(target, encoding='utf-8').read()
    new, n = re.subn(r"var BUILD_STAMP = '[^']*';",
                     "var BUILD_STAMP = '%s';" % now, text)
    assert n == 1, '%s: expected exactly one BUILD_STAMP, found %d' % (target, n)
    if new != text:
        io.open(target, 'w', encoding='utf-8', newline='').write(new)
    print('%s -> BUILD_STAMP %s' % (target, now))
