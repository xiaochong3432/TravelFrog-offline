#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Update the two album tests for the corrected reply key, and record the 7 Picture rows
that ship without any layer art (a pre-existing data gap, both at login and live)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

T = str(PROJECT_ROOT) + "/work/tools/engine_test.js"
text = io.open(T, encoding='utf-8').read()

OLD = """  const r = call(engine, 'album_load_by_id_list', { id_list: [21, 23] });
  eq(r.reply.pictures.length, 2, 'only the requested ids');
  eq(r.reply.pictures.map((p) => p.id).sort().join(','), '21,23', 'the right two');
  assert(r.reply.pictures.every((p) => Array.isArray(p.layers)),
    'by-id loads render, so they need layers');
  eq(call(engine, 'album_load_by_id_list', { id_list: [999] }).reply.pictures.length, 0,
    'unknown ids give an empty list, not an error');"""
NEW = """  /* The reply key is `pic_list` -- that is what the client's handler reads; with
     `pictures` the whole branch is skipped (see the reply-key test below). */
  const r = call(engine, 'album_load_by_id_list', { id_list: [21, 23] });
  eq(r.reply.pic_list.length, 2, 'only the requested ids');
  eq(r.reply.pic_list.map((p) => p.id).sort().join(','), '21,23', 'the right two');
  assert(r.reply.pic_list.every((p) => Array.isArray(p.layers)),
    'by-id loads render, so they need layers');
  eq(call(engine, 'album_load_by_id_list', { id_list: [999] }).reply.pic_list.length, 0,
    'unknown ids give an empty list, not an error');"""
assert text.count(OLD) == 1, 'old by-id test'
text = text.replace(OLD, NEW)

# the new test must tolerate the Picture rows that ship without layer art
OLD2 = """  const r = call(engine, 'album_load_by_id_list', { id_list: ids }).reply;
  assert(Array.isArray(r.pic_list),
    'the reply must carry `pic_list`; the client ignores everything else');
  assert(r.pictures === undefined, 'and must not carry the old `pictures` key');
  eq(r.pic_list.length, ids.length, 'one row per requested album entry');
  for (const row of r.pic_list) {
    assert(typeof row.id === 'number', 'each row needs the album handle');
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `album entry ${row.id} needs layers, or its card draws nothing`);
  }"""
NEW2 = """  /* Seven Picture rows ship with no layer art at all (2033/2035/2039/2040/2041/2042/
     2075), so those cards are blank however they are loaded -- at login too. Everything
     else must carry layers. */
  const LAYERS = require(path.join(__dirname, '..', 'run', 'engine', 'data',
    'picture-layers.json'));
  const artless = new Set(engine.state.pictures
    .filter((p) => !LAYERS[String(p.pic_id)]).map((p) => p.id));

  const r = call(engine, 'album_load_by_id_list', { id_list: ids }).reply;
  assert(Array.isArray(r.pic_list),
    'the reply must carry `pic_list`; the client ignores everything else');
  assert(r.pictures === undefined, 'and must not carry the old `pictures` key');
  eq(r.pic_list.length, ids.length, 'one row per requested album entry');
  let withLayers = 0;
  for (const row of r.pic_list) {
    assert(typeof row.id === 'number', 'each row needs the album handle');
    if (artless.has(row.id)) continue;
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `album entry ${row.id} needs layers, or its card draws nothing`);
    withLayers++;
  }
  eq(withLayers, ids.length - artless.size, 'every picture that HAS art must carry it');
  assert(artless.size <= 10, `unexpectedly many art-less pictures (${artless.size})`);"""
assert text.count(OLD2) == 1, 'new album test body'
text = text.replace(OLD2, NEW2)

OLD3 = """  const pushed = byId[0].data.pic_list;
  eq(pushed.length, engine.state.pictures.length,
    'the pushed layers must cover every album entry, not just the new ones');
  for (const row of pushed) {
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `pushed entry ${row.id} needs layers`);
  }"""
NEW3 = """  const pushed = byId[0].data.pic_list;
  eq(pushed.length, engine.state.pictures.length,
    'the pushed layers must cover every album entry, not just the new ones');
  for (const row of pushed) {
    if (artless.has(row.id)) continue;
    assert(Array.isArray(row.layers) && row.layers.length > 0,
      `pushed entry ${row.id} needs layers`);
  }"""
assert text.count(OLD3) == 1, 'push assertions'
text = text.replace(OLD3, NEW3)

io.open(T, 'w', encoding='utf-8', newline='').write(text)
print('album tests updated')
