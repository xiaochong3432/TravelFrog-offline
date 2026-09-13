#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Exact key names the client reads in each album handler (same class of bug as 百科:
right data, wrong key -> the client silently skips)."""
import io
import re

SRC = r"H:\AI\frog\work\run\web\js\main.min.js"
OUT = r"H:\AI\frog\work\logs\album_keys.txt"

text = io.open(SRC, encoding='utf-8', errors='replace').read()
out = io.open(OUT, 'w', encoding='utf-8')

for name in ['album_load', 'album_load_all', 'album_load_new', 'album_load_recover',
             'album_load_by_id_list', 'album_save_new', 'album_delete', 'album_recover']:
    pat = 't.prototype.%s=function' % name
    i = text.find(pat)
    out.write('\n=== %s @%d\n' % (name, i))
    if i < 0:
        out.write('  (not found)\n')
        continue
    seg = text[i:i + 1100]
    out.write(seg + '\n')
    out.write('  keys read: %r\n' % sorted(set(re.findall(r'\b[et]\.([a-z_]{3,})', seg))))
out.close()
print('wrote logs/album_keys.txt')
