#!/usr/bin/env python3
"""The museumday window test asserted the event is always open; it is now switched OFF.

Rewrite it to the new contract (the entry must be hidden while MUSEUM_DAY_ENABLED is
false), and add tests for the three new editor commands.
"""
import io

T = r"H:\AI\frog\work\tools\engine_test.js"
src = io.open(T, encoding="utf-8").read()

old = """test('museumday: the window is payload-only, and it is ALWAYS OPEN', ({ engine }) => {
  /* getActivityTime() is `end_time > 0 ? [1, end_time] : [0, 0]` and nothing about the
     dates is hardcoded in the client, so a future end_time is the whole开关. We roll
     `now + 20 days` instead of a far-future constant because the client arms a close
     timer of 1000 * (end_time - now + 1), which overflows int32 past ~24.8 days. */
  const r = call(engine, 'museumday_load', {}).reply;
  const now = Math.floor(Date.now() / 1000);
  assert(r.end_time > now, 'end_time must be in the future or the entry never appears');
  assert(r.end_time - now <= 24 * 86400,
    'and within int32-safe range for the client close timer');
});"""
new = """test('museumday: the event is switched OFF, and the museum 图鉴 replaces it', ({ engine }) => {
  /* The player asked for 大冒险 to go away for now ("太麻烦了") and for the museum 图鉴 to
     be unlocked instead. `end_time` is the whole switch for the client
     (`getActivityTime() = end_time > 0 ? [1, end_time] : [0,0]`), so 0 hides the entry and
     stops it arming its activity timer. The commands themselves are still implemented:
     flip MUSEUM_DAY_ENABLED in the engine to bring the event back. */
  const r = call(engine, 'museumday_load', {}).reply;
  eq(r.end_time, 0, 'a closed window is what hides the 大冒险 entry');
  eq(r.cur_museum, 0, 'and no museum is in progress');

  /* The museum postcards used to come from that event only, so boot must grant them. */
  call(engine, 'hall_enter_game', {});
  const list = call(engine, 'museum_load', {}).reply.museum_list;
  for (const m of list) {
    assert(m.pic_list.length > 0, `museum ${m.id} must report its postcards as owned`);
    assert(m.collections.length > 0, `museum ${m.id} needs its collectibles too`);
  }
  const total = list.reduce((n, m) => n + m.pic_list.length, 0);
  assert(total >= 12, `expected the museums' postcards in the album, got ${total}`);
  const album = call(engine, 'album_load', {}).reply;
  for (const m of list) {
    for (const pic of m.pic_list) {
      assert(album.pictures.some((p) => p.pic_id === pic),
        `postcard ${pic} must actually be in the album, not just reported`);
    }
  }
  eq(engine.state.museumUnlocked, true, 'and the grant is recorded so it happens once');
});"""
assert src.count(old) == 1, "museumday window test not found"
src = src.replace(old, new)

anchor = "/* ------------------------------------------------------------------ done */"
tests = """test('editor: unlock_all fills the 图鉴, the 百科 and the museum', ({ engine }) => {
  const g = (cmd) => call(engine, 'client_gm', { cmd }).reply;
  const before = call(engine, 'item_load_handbook', {}).reply;
  eq(before.collections.length, 0, 'a fresh save has an empty 图鉴');
  eq(before.specialtys.length, 0, 'and no specialties');

  const r = g('unlock_all');
  eq(r.succeed, true, 'unlock_all reports success');

  const hand = call(engine, 'item_load_handbook', {}).reply;
  const colIds = new Set(Object.keys(GDATA.tables.Collection || {}).map(Number));
  const specIds = new Set(GDATA.items.filter((i) => i.type === 3).map((i) => i.id));
  for (const id of hand.collections) assert(colIds.has(id), `collection ${id} is unknown`);
  for (const id of hand.specialtys) assert(specIds.has(id), `specialty ${id} is unknown`);
  assert(hand.collections.length >= colIds.size - 1,
    'every Collection row should be recorded, or the 图鉴 still shows ?');
  assert(hand.specialtys.length >= specIds.size - 1, 'and every specialty item');

  const enc = call(engine, 'encyclopedia_load', {}).reply;
  assert(enc.unlock_list.length > 0, 'the 百科 must have entries, or its menu entry hides');
  eq(enc.show_sub.length, enc.unlock_list.length,
    'each species needs a show_sub row or the view renders blanks');
  for (const id of enc.unlock_list) {
    const row = enc.unlock_desc.find((x) => x.id === id);
    assert(row && row.list.length > 0, `species ${id} needs its description lines`);
  }
  assert(engine.state.encyAll, 'the flag is persisted so a reopen keeps it');

  const museums = call(engine, 'museum_load', {}).reply.museum_list;
  for (const m of museums) {
    assert(m.pic_list.length > 0, `museum ${m.id} postcards`);
    assert(m.collections.length > 0, `museum ${m.id} collectibles`);
  }
});

test('editor: all_furniture grants every row, and the client payload carries them', ({ engine }) => {
  const g = (cmd) => call(engine, 'client_gm', { cmd }).reply;
  eq(engine.state.furniture.owned.length, 0, 'a fresh save owns no furniture');
  const r = g('all_furniture');
  eq(r.succeed, true, 'all_furniture reports success');
  const rows = Object.keys(GDATA.tables.furnitureData || {}).map(Number);
  eq(engine.state.furniture.owned.length, rows.length,
    'one entry per furnitureData row');
  const loaded = call(engine, 'furniture_load_furniture', {}).reply;
  eq((loaded.has_fur || []).length, rows.length,
    'and the payload the 家具 book renders from carries all of them');
  /* running it twice must not duplicate */
  g('all_furniture');
  eq(engine.state.furniture.owned.length, rows.length, 'idempotent');
});

"""
assert src.count(anchor) == 1
src = src.replace(anchor, tests + anchor)
io.open(T, "w", encoding="utf-8").write(src)
print("tests rewritten/added")
