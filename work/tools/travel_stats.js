#!/usr/bin/env node
'use strict';
/* Diagnostic: what does a map-driven trip actually pay out?
   Replays real trips through the engine (same code path the player hits) and diffs
   the save after each one, so the rates below are observed, not modelled.

   node work/tools/travel_stats.js [roundsPerGroup] */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const { createEngine } = require(path.join(ROOT, 'work', 'run', 'engine', 'index.js'));
const GD = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'));

const ROUNDS = Number(process.argv[2] || 200);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-travel-'));
const engine = createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });

const foods = GD.items.filter((i) => i.type === 0).map((i) => i.id);
const amulets = GD.items.filter((i) => i.type === 1 && i.spend !== 1).map((i) => i.id);
const tools = GD.items.filter((i) => i.type === 2).map((i) => i.id);

function snap() {
  return {
    sp: (engine.state.handbook.specialtys || []).length,
    col: (engine.state.handbook.collections || []).length,
    pic: (engine.state.albumPending || []).length + (engine.state.pictures || []).length,
    note: (engine.state.notes || []).length,
    areas: JSON.stringify(engine.state.travel.visited || {}),
  };
}

/** Read one trip's real payout out of the pushes the return generated. */
function tripPushes(pushes) {
  const out = { items: 0, collection: 0, pictures: 0, clover: 0, ticket: 0, notes: 0 };
  (pushes || []).forEach((p) => {
    const cmd = String(p.cmd || '').replace(/\./g, '_');
    if (cmd === 'notify_new_event' && p.data && p.data.event) {
      const ev = p.data.event;
      const v = ev.evt_value || [];
      if (Number(ev.evt_type) === 2) {                 // BackHome
        out.clover = Number(v[2]) || 0;
        out.ticket = Number(v[3]) || 0;
        out.collection = Number(v[4]) >= 0 ? 1 : 0;
        out.items = Math.max(0, v.length - 5);
      }
      if (Number(ev.evt_type) === 15) out.notes += 1;
    }
    if (cmd === 'album_load_new' && p.data) {
      out.pictures += (p.data.new_picture_list || p.data.list || []).length
        || (p.data.pictures || []).length;
    }
    if (cmd === 'travel_load_note' && p.data) {
      out.notes += 1;
    }
  });
  return out;
}

function runGroup(label, pick) {
  const t = { items: 0, collection: 0, pictures: 0, notes: 0, min: 0, clover: 0, ticket: 0 };
  for (let i = 0; i < ROUNDS; i++) {
    engine.state.items.bag = [-1, -1, -1, -1];
    const bag = pick(i);
    for (let k = 0; k < 4; k++) engine.state.items.bag[k] = bag[k] === undefined ? -1 : bag[k];
    engine.state.travel.nextDepartAt = 1;
    engine.state.travel.returnAt = 0;
    engine.tick();
    const at = engine.state.travel.plan && engine.state.travel.plan.at;
    engine.state.travel.returnAt = 1;
    const pushes = engine.tick() || [];
    const r = tripPushes(pushes);
    t.items += r.items;
    t.collection += r.collection;
    t.pictures += r.pictures;
    t.notes += r.notes;
    t.clover += r.clover;
    t.ticket += r.ticket;
    if (at) t.min += (engine.state.travel.minTripSec || 0) > 0 ? 1 : 0;
  }
  const per = (n) => (n / ROUNDS).toFixed(2);
  console.log([
    label.padEnd(26),
    ('trips=' + ROUNDS).padEnd(10),
    ('特产/趟 ' + per(t.items)).padEnd(12),
    ('典藏/趟 ' + per(t.collection)).padEnd(12),
    ('明信片/趟 ' + per(t.pictures)).padEnd(13),
    ('笔记/趟 ' + per(t.notes)).padEnd(11),
    '三叶草/趟 ' + per(t.clover),
  ].join(' '));
}

runGroup('lunch only', (i) => [foods[i % foods.length]]);
runGroup('lunch + amulet', (i) => [foods[i % foods.length], amulets[i % amulets.length]]);
runGroup('lunch + tool', (i) => [foods[i % foods.length], undefined, tools[i % tools.length]]);
runGroup('lunch + amulet + 2 tools',
  (i) => [foods[i % foods.length], amulets[i % amulets.length],
    tools[i % tools.length], tools[(i * 3 + 1) % tools.length]]);

console.log('\nvisited:', JSON.stringify(engine.state.travel.visited || {}));
console.log('handbook: specialtys=%d collections=%d  notes=%d  pending=%d',
  engine.state.handbook.specialtys.length, engine.state.handbook.collections.length,
  (engine.state.notes || []).length, (engine.state.albumPending || []).length);
