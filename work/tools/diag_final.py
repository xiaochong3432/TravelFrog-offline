#!/usr/bin/env python3
"""Markers for the final two steps: season .then body and enterGame body."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
MAIN = str(PROJECT_ROOT) + "/work/run/web/js/main.min.js"
d = open(MAIN, encoding="utf8").read()

EDITS = [
    ("season then-body",
     "Promise.resolve()).then(function(){ResourceLoader.instance().loadResource(),n.loadComplete=!0",
     "Promise.resolve()).then(function(){console.log('[offline] season then-body'),ResourceLoader.instance().loadResource(),n.loadComplete=!0"),
    ("season then-body variant",
     "Promise.resolve()).then(function(){ResourceLoader.instance().loadResource(),e.loadComplete=!0",
     "Promise.resolve()).then(function(){console.log('[offline] season then-body B'),ResourceLoader.instance().loadResource(),e.loadComplete=!0"),
    ("enterGame body",
     'true&&(Music.play("BGM_Default"',
     'true&&(console.log("[offline] enterGame body"),Music.play("BGM_Default"'),
]

for name, old, new in EDITS:
    if new in d:
        print(f"  [skip] {name}")
    elif old in d:
        d = d.replace(old, new)
        print(f"  [ok]   {name} ({d.count(new)} present)")
    else:
        print(f"  [MISS] {name}")

open(MAIN, "w", encoding="utf8").write(d)
print("written")
