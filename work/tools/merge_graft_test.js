#!/usr/bin/env node
'use strict';
/**
 * Tests for the four repair groups grafted onto our engine from the V3 handover line
 * (see work/tools/merge_into_mainline.py). These are the ones that WRITE to a save, so each
 * one is checked for: it fixes what it claims, it does not fire twice, and it refuses to
 * touch a save that does not need it.
 *
 *   node tools/merge_graft_test.js [name-filter]
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);
const GDATA = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'));

const LUNCH = GDATA.items.find((i) => i.type === 0).id;          // LunchBox
const TOOL = GDATA.items.find((i) => i.type === 2).id;           // Tool
const SPECIALTY = GDATA.items.find((i) => i.type === 3).id;      // 特产
const PIC_KNOWN = GDATA.tables.Picture[0].id;                    // a pic_id the table knows

let passed = 0, failed = 0;
const fails = [];
const filter = process.argv[2] || '';

function boot(save) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-graft-'));
  const savePath = path.join(dir, 'save.json');
  /* parseSave() rejects a save that carries none of SAVE_KNOWN_FIELDS, so every fixture
     needs at least one real field -- otherwise the engine "starts fresh" and the fixture is
     never exercised (the first version of this file got that wrong). */
  if (save) fs.writeFileSync(savePath, JSON.stringify(Object.assign({ clover: 100 }, save)), 'utf8');
  return { engine: createEngine({ savePath, verbose: false }), savePath, dir };
}

function reopen(savePath) {
  return createEngine({ savePath, verbose: false });
}

function onDisk(savePath) {
  return JSON.parse(fs.readFileSync(savePath, 'utf8'));
}

function test(name, fn) {
  if (filter && !name.includes(filter)) return;
  try {
    fn();
    passed++;
    console.log('  PASS  ' + name);
  } catch (e) {
    failed++;
    fails.push(name);
    console.log('  FAIL  ' + name + '\n          ' + (e && e.message));
  }
}

function eq(a, b, msg) {
  if (a !== b) throw new Error(`${msg}: expected ${JSON.stringify(b)}, got ${JSON.stringify(a)}`);
}
function assert(v, msg) { if (!v) throw new Error(msg); }
function house(engine, id) {
  const row = (engine.state.items.house || []).find((h) => Number(h.item_id) === Number(id));
  return Number(row && row.count) || 0;
}

/* ============================ G1  mail / pictures ============================ */

test('G1 mail: an explicit `resource: null` is filled in, so the client cannot throw', () => {
  const { engine } = boot({ mails: [{ id: 1, read: false, resource: null, items: [], pictures: [] }] });
  const r = engine.state.mails[0].resource;
  assert(r && typeof r === 'object', 'resource must not stay null');
  eq(r.clover_point, 0, 'clover_point');
  eq(r.ticket, 0, 'ticket');
  eq(r.reward_gacha, 0, 'reward_gacha');
  eq(r.ads_id, '', 'ads_id');
  eq(r.share_id, '', 'share_id');
});

test('G1 mail: a missing `resource` is filled in too', () => {
  const { engine } = boot({ mails: [{ id: 1, read: false, items: [] }] });
  assert(engine.state.mails[0].resource, 'resource must exist');
  eq(engine.state.mails[0].resource.clover_point, 0, 'default clover_point');
});

test('G1 mail: unknown item ids are dropped, real ones kept with a sane count', () => {
  const { engine } = boot({
    mails: [{ id: 1, resource: {}, items: [{ item_id: 999999, count: 1 }, { item_id: 1000, count: 0 }] }],
  });
  const items = engine.state.mails[0].items;
  eq(items.length, 1, 'only the real item survives');
  eq(items[0].item_id, 1000, 'kept id');
  eq(items[0].count, 1, 'count is at least 1');
});

const KNOWN_NO_LAYERS = '2033';      // shipped Picture row without composed layers

test('G1 pictures: a pic_id the TABLE knows is KEPT even when its art is missing', () => {
  const { engine } = boot({ pictures: [{ id: 0, pic_id: Number(KNOWN_NO_LAYERS), read: 0, new: 1 }] });
  eq(engine.state.pictures.length, 1, 'the row must survive (deleting it would lose a real picture)');
  assert(engine.state.pictures[0].id > 0, 'a missing row id is assigned');
  eq(Number(engine.state.pictures[0].pic_id), Number(KNOWN_NO_LAYERS), 'pic_id preserved');
});

test('G1 pictures: a pic_id the table does NOT know is dropped', () => {
  const { engine } = boot({ pictures: [{ id: 1, pic_id: 999999, read: 0, new: 1 }] });
  eq(engine.state.pictures.length, 0, 'unknown pic_id dropped');
});

test('G1 pictures: a row without a pic_id is dropped, and one without an id gets one', () => {
  const { engine } = boot({ pictures: [{ id: 5, read: 0 }, { id: 0, pic_id: Number(PIC_KNOWN), read: 0 }] });
  eq(engine.state.pictures.length, 1, 'only the usable row remains');
  assert(engine.state.pictures[0].id > 0, 'id assigned');
});

test('G1: all of it is persisted, and a second load changes nothing', () => {
  const { engine, savePath } = boot({ mails: [{ id: 1, resource: null, items: [] }] });
  assert(engine.state.mails[0].resource, 'fixed');
  const again = reopen(savePath);
  assert(again.state.mails[0].resource, 'still fixed after reopen');
  eq(house(again, 0), 0, 'no phantom items');
});

/* ============================== G2 slot repair ============================== */

test('G2a: a slot holding the WRONG type is emptied and the item is not lost', () => {
  // bag slot 0 must hold a lunch box; put a tool there
  const { engine } = boot({ items: { bag: [TOOL, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [] } });
  eq(engine.state.items.bag[0], -1, 'wrong-type slot cleared');
  /* Both lines repair this; they differ in WHERE the item goes -- the 3.1 engine puts it in
     another slot of its own type first (placeBack), V3 returns it to the house. Either is
     fine, as long as it is not destroyed. */
  const inBag = engine.state.items.bag.indexOf(TOOL) !== -1;
  const inDesk = engine.state.items.desk.indexOf(TOOL) !== -1;
  assert(inBag || inDesk || house(engine, TOOL) === 1,
    'the tool must land in a valid slot or come home');
});

test('G2a: an item id that does not exist is cleared without minting an item', () => {
  const { engine } = boot({ items: { bag: [999999, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [] } });
  eq(engine.state.items.bag[0], -1, 'cleared');
  /* V3.6 起开局行李会往家里补便当/护身符/工具/特产（他 V3 的口径），所以"家里必须为空"
     不再是判据 —— 这里钉的是"没有为那个不存在的 id 凭空造一件"。 */
  assert(!engine.state.items.house.find((x) => Number(x.item_id) === 999999),
    'nothing invented for the bogus id');
  assert(engine.state.items.house.every((x) => GDATA.items.some((i) => Number(i.id) === Number(x.item_id))),
    'and every row it does hold is a real Item.json id');
});

test('G2b: an OLD save (from the pre-3.1 lines) has its occupied slots debited ONCE', () => {
  const { engine, savePath } = boot({
    items: { bag: [LUNCH, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [{ item_id: LUNCH, count: 2 }] },
  });
  eq(house(engine, LUNCH), 1, 'the unit sitting in the slot is taken out of the house');
  eq(engine.state.items.packedSlotsDebited, true, 'and the repair is marked done');
  const again = reopen(savePath);
  eq(house(again, LUNCH), 1, 'reopening does NOT debit a second time');
});

test('G2b: a save written by the 3.1 line is left alone (it already debits per operation)', () => {
  const { engine } = boot({
    furniture: { shopDailyBought: {} },                 // 3.1-only field = 3.1-written save
    items: { bag: [LUNCH, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [{ item_id: LUNCH, count: 2 }] },
  });
  eq(house(engine, LUNCH), 2, 'no second debit');
  eq(engine.state.items.packedSlotsDebited, true, 'marked, so it never runs later either');
});

test('G2b: nothing in the house means nothing to debit (no negative counts)', () => {
  const { engine } = boot({ items: { bag: [LUNCH, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [] } });
  eq(house(engine, LUNCH), 0, 'house stays empty');
  assert(!(engine.state.items.house || []).some((h) => h.count < 0), 'no negative row');
});

/* ============================ G3 packing handlers ============================ */

test('G3: packing a lunch box takes the real unit out of the house', () => {
  const { engine } = boot({ items: { bag: [-1, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [{ item_id: LUNCH, count: 1 }] } });
  const r = engine.dispatch('item_putin_bag', { pos: 1, item_id: LUNCH });
  eq(r.reply.code, 0, 'accepted');
  eq(engine.state.items.bag[0], LUNCH, 'in the bag');
  eq(house(engine, LUNCH), 0, 'and no longer in the house');
});

test('G3: taking it out gives the unit back exactly once', () => {
  const { engine } = boot({ items: { bag: [-1, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [{ item_id: LUNCH, count: 1 }] } });
  engine.dispatch('item_putin_bag', { pos: 1, item_id: LUNCH });
  const r = engine.dispatch('item_takeout_bag', { pos: 1 });
  eq(r.reply.code, 0, 'accepted');
  eq(engine.state.items.bag[0], -1, 'slot empty');
  eq(house(engine, LUNCH), 1, 'back in the house (not two)');
});

test('G3: packing something you do not own is refused', () => {
  const { engine } = boot({ items: { bag: [-1, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [] } });
  const r = engine.dispatch('item_putin_bag', { pos: 1, item_id: LUNCH });
  eq(r.reply.code, -1, 'refused');
  eq(engine.state.items.bag[0], -1, 'nothing packed');
});

test('G3: packing a TOOL into a lunch-box slot is refused', () => {
  const { engine } = boot({ items: { bag: [-1, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [{ item_id: TOOL, count: 1 }] } });
  const r = engine.dispatch('item_putin_bag', { pos: 1, item_id: TOOL });
  eq(r.reply.code, -1, 'type must match the slot');
  eq(house(engine, TOOL), 1, 'and the item stayed home');
});

test('G3: packing pushes item_update so the client counter follows', () => {
  const { engine } = boot({ items: { bag: [-1, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1], house: [{ item_id: LUNCH, count: 3 }] } });
  const r = engine.dispatch('item_putin_bag', { pos: 1, item_id: LUNCH });
  /* pushed commands come out in wire form (`item_update` -> `item.update`), so accept both */
  const pushes = (r.pushes || []).filter((p) => /item[._]update/.test(p.cmd));
  assert(pushes.length >= 1, 'item_update expected, got ' +
    JSON.stringify((r.pushes || []).map((p) => p.cmd)));
});

/* ========================= specialty → house migration ======================= */

test('G4: specialtys that only lived in state.specialtys reach the house and the 图鉴', () => {
  const { engine } = boot({ specialtys: [{ item_id: SPECIALTY, count: 2 }], items: { house: [] } });
  eq(house(engine, SPECIALTY), 2, 'house now holds them');
  assert((engine.state.handbook.specialtys || []).indexOf(SPECIALTY) !== -1, 'and the handbook knows');
  eq(engine.state.tripSpecialtysInHouse, true, 'migration marked done');
});

test('G4: it never doubles what is already in the house', () => {
  const { engine } = boot({
    specialtys: [{ item_id: SPECIALTY, count: 2 }],
    items: { house: [{ item_id: SPECIALTY, count: 2 }] },
  });
  eq(house(engine, SPECIALTY), 2, 'topped up to the recorded count, not doubled');
});

test('G4: a second load adds nothing (idempotent)', () => {
  const { engine, savePath } = boot({ specialtys: [{ item_id: SPECIALTY, count: 2 }], items: { house: [] } });
  eq(house(engine, SPECIALTY), 2, 'first load');
  const again = reopen(savePath);
  eq(house(again, SPECIALTY), 2, 'second load');
});

test('G4: a save that already carries the flag is untouched', () => {
  /* 对照法：V3.6 的开局行李本来就可能补 2 份特产，所以"家里有多少"不再是判据。
     同样的存档跑两份，只有 specialtys 有无之别：迁移若被 flag 跳过，两者必须一样。 */
  const withSp = boot({
    tripSpecialtysInHouse: true,
    specialtys: [{ item_id: SPECIALTY, count: 2 }],
    items: { house: [] },
  }).engine;
  const without = boot({
    tripSpecialtysInHouse: true,
    specialtys: [],
    items: { house: [] },
  }).engine;
  eq(house(withSp, SPECIALTY), house(without, SPECIALTY), 'migration skipped by its own flag');
});

console.log(`\n${passed} passed, ${failed} failed`);
if (failed) {
  console.log('failing: ' + fails.join(' | '));
  process.exit(1);
}
