#!/usr/bin/env python3
"""Fix the encyclopedia test: pick the decoration by the SAME rule the engine uses."""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
src = io.open(T, encoding="utf-8").read()
old = """  const decos = Object.keys(GDATA.tables.decoration || {});
  const withIcon = decos.filter((k) => {
    const d = GDATA.tables.decoration[k];
    return d && d.icon && d.icon.indexOf('chahua_zhongzhi') === 0;
  });
  assert(withIcon.length > 0, 'expected planted-flower decorations in the table');
  const decId = Number(withIcon[0]);"""
new = """  /* Pick the candidate exactly the way the engine does: a decoration whose `icon` is the
     same string as some encyclopedia row's. */
  const enc = GDATA.tables.encyclopedia || {};
  const encIcons = new Set(Object.keys(enc.list || {})
    .map((k) => enc.list[k]).filter(Boolean)
    .reduce((acc, r) => acc.concat([r.icon, r.pic_img]), []));
  const decos = Object.keys(GDATA.tables.decoration || {});
  const withIcon = decos.filter((k) => {
    const d = GDATA.tables.decoration[k];
    return d && d.icon && encIcons.has(d.icon);
  });
  assert(withIcon.length > 0,
    'expected at least one brought-home flower that maps to an encyclopedia entry');
  const decId = Number(withIcon[0]);"""
assert src.count(old) == 1
io.open(T, "w", encoding="utf-8").write(src.replace(old, new))
print("test fixed")
