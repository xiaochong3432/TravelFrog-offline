#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Rewrite the encyclopedia tests for the corrected payload shape, and add a test that
replays EncyView's own table lookups (so a shape mistake fails here, not in the game)."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import io

T = str(PROJECT_ROOT) + "/work/tools/engine_test.js"
text = io.open(T, encoding='utf-8').read()
edits = []


def sub(old, new, what):
    global text
    n = text.count(old)
    assert n == 1, '%s: anchor matched %d times' % (what, n)
    text = text.replace(old, new)
    edits.append(what)


sub("""  assert(r.reply.unlock_list.indexOf(row.id) !== -1,
    `species ${row.id} (${row.name}) should be unlocked`);
  const desc = r.reply.unlock_desc.find((d) => d.id === row.id);
  assert(desc && Array.isArray(desc.list), 'unlock_desc should carry the line indices');
  assert(desc.list.length > 0, 'and they should be non-empty');
  const show = r.reply.show_sub.find((s) => s.id === row.id);
  assert(show && show.sub_id === row.sub_id, 'show_sub should name the variety');""",
    """  /* unlock_list holds LONG_IDs -- the keys of encyclopedia.list -- because
     EncyView.getSubItems does `TABLE[unlock_list[i]]` and only then compares `row.id`.
     Sending the species id (as this used to) indexes nothing and the page stays blank. */
  const unlocked = r.reply.unlock_list.map((l) => ENC.list[String(l)]).filter(Boolean);
  const mine = unlocked.filter((e) => e.id === row.id && e.sub_id === row.sub_id);
  assert(mine.length > 0, `species ${row.id} (${row.name}) should be unlocked`);
  const allOfVariety = Object.keys(ENC.list).map((k) => ENC.list[k])
    .filter((e) => e.id === row.id && e.sub_id === row.sub_id).length;
  eq(mine.length, allOfVariety,
    'the whole variety is unlocked, not a single picture of it');
  const desc = r.reply.unlock_desc.find((d) => d.id === row.id);
  assert(desc && Array.isArray(desc.list), 'unlock_desc should carry the line indices');
  assert(desc.list.length > 0, 'and they should be non-empty');
  const show = r.reply.show_sub.find((s) => s.id === row.id);
  assert(show && show.sub_id === mine[0].long_id,
    'show_sub must carry the LONG_ID of the shown variety (the client uses it as a key)');""",
    'harvest test assertions')

sub("""  for (const id of r.unlock_list) {
    const row = r.unlock_desc.find((x) => x.id === id);
    assert(row && row.list.length > 0, `species ${id} needs its description lines`);
  }
  assert(r.show_sub.length > 0 && typeof r.show_sub[0].sub_id === 'number',
    'show_sub picks the variant, so it needs a real sub_id');""",
    """  for (const longId of r.unlock_list) {
    const e = enc.list[String(longId)];
    assert(e, `unlock_list entry ${longId} must index the encyclopedia table`);
    const d = r.unlock_desc.find((x) => x.id === e.id);
    assert(d && d.list.length > 0, `species ${e.id} needs its description lines`);
  }
  assert(r.show_sub.length > 0, 'the brought-home species must appear in the grid');
  for (const s of r.show_sub) {
    assert(enc.list[String(s.sub_id)],
      `show_sub for species ${s.id} must carry a table key, not a variety number`);
  }""",
    'brought-home test assertions')

sub("""  const enc = call(engine, 'encyclopedia_load', {}).reply;
  assert(enc.unlock_list.length > 0, 'the 百科 must have entries, or its menu entry hides');
  eq(enc.show_sub.length, enc.unlock_list.length,
    'each species needs a show_sub row or the view renders blanks');
  for (const id of enc.unlock_list) {
    const row = enc.unlock_desc.find((x) => x.id === id);
    assert(row && row.list.length > 0, `species ${id} needs its description lines`);
  }""",
    """  const enc = call(engine, 'encyclopedia_load', {}).reply;
  const ENCT = GDATA.tables.encyclopedia;
  const allRows = Object.keys(ENCT.list).map((k) => ENCT.list[k]);
  const species = new Set(allRows.map((r) => r.id));
  assert(enc.unlock_list.length > 0, 'the 百科 must have entries, or its menu entry hides');
  eq(enc.unlock_list.length, allRows.length,
    'unlock_all unlocks every picture row in the table');
  eq(enc.show_sub.length, species.size,
    'every species needs a show_sub row, or its slot in the grid stays blank');
  for (const longId of enc.unlock_list) {
    const e = ENCT.list[String(longId)];
    assert(e, `unlock_list entry ${longId} must index the encyclopedia table`);
    assert(enc.unlock_desc.some((d) => d.id === e.id),
      `species ${e.id} needs its description lines`);
  }""",
    'unlock_all assertions')

NEW_TEST = """
test('encyclopedia: the payload indexes the table the way EncyView does', ({ engine }) => {
  /* A replay of the client's own lookups:
       getItemsByTab(tab): for (k in show_sub) { row = TABLE[show_sub[k]]; row.tab == tab }
       getSubItems(id):    for (l of unlock_list) { row = TABLE[l]; row.id == id }
       getPicItems(id, s): the same, keeping row.sub_id == s
       tab.enabled = getItemsByTab(tab).length > 0
     If show_sub carried a variety NUMBER instead of a long_id, every one of these is
     undefined, every tab is disabled and the grid renders as twelve blank slots --
     which is what the player saw. */
  const T = GD.tables.encyclopedia;
  const keys = Object.keys(T.list);
  /* the engine derives the key as Number(k); the row also carries `long_id` */
  for (const k of keys) {
    eq(String(T.list[k].long_id), k, 'the table key must equal the row long_id');
  }

  call(engine, 'client_gm', { cmd: 'unlock_all' });
  const p = call(engine, 'encyclopedia_load', {}).reply;

  const show = {};
  for (const s of p.show_sub) show[s.id] = s.sub_id;
  const itemsByTab = (tab) => {
    const out = [];
    for (const k in show) {
      const row = T.list[String(show[k])];
      if (row && row.tab === tab) out.push(row);
    }
    return out;
  };
  const rowsOf = (id) => p.unlock_list.map((l) => T.list[String(l)]).filter((r) => r && r.id === id);

  for (const s of p.show_sub) {
    const row = T.list[String(s.sub_id)];
    assert(row, `show_sub[${s.id}] = ${s.sub_id} is not a table key`);
    eq(row.id, s.id, 'the row behind show_sub must belong to the species it is filed under');
  }
  const speciesIds = [...new Set(keys.map((k) => T.list[k].id))];
  eq(p.show_sub.length, speciesIds.length, 'every species is listed once');

  for (const longId of p.unlock_list) {
    assert(T.list[String(longId)], `unlock_list entry ${longId} is not a table key`);
  }

  /* every tab has to have something, or the client greys it out */
  for (const tab of [1, 2, 3, 4]) {
    assert(itemsByTab(tab).length > 0,
      `tab ${tab} is empty -- the client disables it and the page looks broken`);
  }

  /* the variety list of a species, and the picture carousel of the shown variety */
  const first = p.show_sub[0];
  const varieties = [...new Set(rowsOf(first.id).map((r) => r.sub_id))];
  assert(varieties.length > 0, 'the variety list (listSub) must not be empty');
  eq(varieties.length,
    [...new Set(keys.map((k) => T.list[k]).filter((r) => r.id === first.id).map((r) => r.sub_id))].length,
    'every variety of the species should be unlocked');
  const shownSub = T.list[String(first.sub_id)].sub_id;
  const pics = rowsOf(first.id).filter((r) => r.sub_id === shownSub);
  eq(pics.length, keys.map((k) => T.list[k])
      .filter((r) => r.id === first.id && r.sub_id === shownSub).length,
    'the carousel gets every picture row of the shown variety');
  assert(pics.length > 0, 'and it must not be empty');

  /* a locked species must NOT be listed: EncyView pads the grid to 12 empty slots and
     disables tabs with nothing in them, i.e. a short list is the normal case */
  const fresh = engine;
  fresh.state.encyAll = false;
  fresh.state.flowerpot.grown = [];
  fresh.state.decoration.hasList = [];
  const empty = call(fresh, 'encyclopedia_load', {}).reply;
  eq(empty.unlock_list.length, 0, 'nothing grown or brought home yet');
  eq(empty.show_sub.length, 0, 'so the grid lists no species');
  eq(empty.unlock_desc.length, 0, 'and no description is unlocked');
});
"""

sub("""test('encyclopedia: desc line indices all exist in the table', ({ engine }) => {""",
    NEW_TEST.lstrip('\n') + """
test('encyclopedia: desc line indices all exist in the table', ({ engine }) => {""",
    'new client-replay test')

io.open(T, 'w', encoding='utf-8', newline='').write(text)
print('patched engine_test.js: %d edits' % len(edits))
for e in edits:
    print('  *', e)
