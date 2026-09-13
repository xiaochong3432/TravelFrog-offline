#!/usr/bin/env python3
"""Markers for the final two steps: season .then body and enterGame body."""
MAIN = r"H:\AI\frog\work\run\web\js\main.min.js"
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
