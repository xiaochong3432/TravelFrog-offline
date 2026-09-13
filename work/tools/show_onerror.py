#!/usr/bin/env python3
"""Print the full window.onerror block(s) from the client log."""
import re

P = r"H:\AI\frog\work\run\logs\client.log"
txt = open(P, encoding="utf8", errors="replace").read()

idx = [m.start() for m in re.finditer(r"\[window\.onerror\]", txt)]
print(f"onerror entries: {len(idx)}")
for i, off in enumerate(idx[:3]):
    seg = txt[off:off + 2000]
    print(f"\n{'='*80}\nentry {i+1}\n{'='*80}")
    print(seg)
