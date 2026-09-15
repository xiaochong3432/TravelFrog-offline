#!/usr/bin/env node
'use strict';
/**
 * Verify the SHIPPED bundle (work/run/web/__offline-engine.js) -- not the source
 * modules -- answers the client's 行囊「准备完成」 wire command.
 *
 * Why this exists: engine_test.js loads `engine/index.js`, so it cannot catch a
 * bundling mistake (a handler that exists in source but is missing/stale in the
 * artifact we actually ship inside the APK/PC build). This harness loads the
 * generated bundle in a VM with browser-ish stubs, then sends the EXACT envelope
 * the client produces:
 *
 *   ItemModel.setBagLock(true) -> SocketManage.send("item_set_bag_completed", null, true)
 *   -> wire command `item_set_bag_completed`, data {completed:true}, no session
 *
 * and asserts the departure actually happened and the authoritative bag_completed
 * was pushed back (ItemModel.item_load_items reads it into `bagLock`).
 *
 * Usage: node tools/verify_bundle_baglock.js
 * Exit code 0 = PASS, 1 = FAIL.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const BUNDLE = path.join(ROOT, 'work', 'run', 'web', '__offline-engine.js');

const store = new Map();
const sandbox = {
  console: { log() {}, warn() {}, error() {} },
  setTimeout, clearTimeout, setInterval, clearInterval,
  localStorage: {
    getItem: (k) => (store.has(k) ? store.get(k) : null),
    setItem: (k, v) => { store.set(k, String(v)); return true; },
    removeItem: (k) => { store.delete(k); },
  },
};
sandbox.window = sandbox;
sandbox.globalThis = sandbox;
sandbox.self = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(BUNDLE, 'utf8'), sandbox, { filename: BUNDLE });

const E = sandbox.window.FrogEngine;
if (!E) {
  console.error('FAIL: bundle did not define window.FrogEngine');
  process.exit(1);
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-bundle-'));
const engine = E.createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });

const problems = [];
const check = (cond, msg) => { if (!cond) problems.push(msg); };

/* A real lunch box, taken from the tables the bundle itself inlined. */
const gd = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'));
const lunch = (gd.items.find((i) => i.type === 0) || {}).id;
check(typeof lunch === 'number', 'no lunch-box item (type 0) in gamedata.json');

engine.state.items.bag[0] = lunch;
engine.state.travel.nextDepartAt = 0;                 // only the lock can send it out
engine.state.frog.status = 0;

/* The client's own call, verbatim (positional param -> declared name `completed`). */
const res = engine.dispatch('item_set_bag_completed', { completed: true });
const names = (res.pushes || []).map((p) => E.canon ? E.canon(p.cmd) : String(p.cmd).replace('.', '_'));
const items = (res.pushes || []).filter((p) => String(p.cmd).replace('.', '_') === 'item_load_items');

check(res.reply && res.reply.code === 0, `reply code 0 (got ${JSON.stringify(res.reply)})`);
check(engine.state.items.bagCompleted === 1, 'authoritative bag_completed == 1');
check(engine.state.frog.status === 1, `frog departed (status=${engine.state.frog.status})`);
check(engine.state.travel.returnAt > 0, 'returnAt scheduled');
check(items.length === 1, `exactly one item_load_items push (got ${items.length})`);
check(items.length > 0 && items[0].data.bag_completed === 1, 'pushed bag_completed == 1 (client bagLock)');
check(names.includes('client_load_role'), 'client_load_role pushed');

/* Persistence through the bundle's own fs stub. */
const saveKey = 'frog.offline.save';
check(store.has(saveKey), `bundle wrote its save (${saveKey})`);
if (store.has(saveKey)) {
  const saved = JSON.parse(store.get(saveKey));
  check(saved.items && saved.items.bagCompleted === 1, 'saved bag_completed == 1');
  check(saved.frog && saved.frog.status === 1, 'saved frog.status == 1');
}

/* A second tap must not start a second trip. */
const returnAt = engine.state.travel.returnAt;
const trips = engine.state.travel.tripCount;
engine.dispatch('item_set_bag_completed', { completed: true });
check(engine.state.travel.returnAt === returnAt, 'repeat tap did not reschedule the return');
check(engine.state.travel.tripCount === trips, 'repeat tap did not add a trip');

fs.rmSync(dir, { recursive: true, force: true });

if (problems.length) {
  console.error('FAIL: shipped bundle\n  - ' + problems.join('\n  - '));
  process.exit(1);
}
console.log('PASS: the shipped bundle answers item_set_bag_completed and sends the frog out');
console.log(`  lunch box ${lunch}; status=${engine.state.frog.status}; bag_completed=${engine.state.items.bagCompleted}`);
console.log(`  pushes: ${names.join(', ')}`);
