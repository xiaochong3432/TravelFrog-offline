#!/usr/bin/env node
'use strict';
/**
 * Verify the SHIPPED bundle carries the merged A-tier content and that the new rows are
 * actually USABLE through the protocol (not just present in a JSON file).
 *
 *   * shop slot 65 (许愿池家具券, item 204002, 3000 clover, no prerequisite) buys,
 *     deducts exactly once and lands in the house;
 *   * shop slot 64 (动态照片3, item 9001) has `before_buy ["shop","58"]` -- a purchase
 *     attempted before slot 58 must be REFUSED (this is the new prerequisite chain);
 *   * the new furniture-shop row (id 8027 -> item 1200, 550 clover) buys.
 *
 * Usage: node tools/verify_bundle_a_tier.js
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
sandbox.window = sandbox; sandbox.globalThis = sandbox; sandbox.self = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(BUNDLE, 'utf8'), sandbox, { filename: BUNDLE });

const E = sandbox.window.FrogEngine;
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-atier-'));
const engine = E.createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
const problems = [];
const check = (cond, msg) => { if (!cond) problems.push(msg); };

const gd = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'));
check(Object.keys(gd.tables.furnitureData).length === 324, 'gamedata furnitureData should have 324 rows');
check(gd.items.length === 411, 'gamedata should list 411 items');
const gdRow65 = (gd.tables.shopData || []).find((r) => String(r.id) === '65');
check(!!gdRow65, 'gamedata has shop row 65');

engine.state.clover = 5000;

/* ---- shop slot 65: no prerequisite, must buy ---- */
const before = engine.state.clover;
const buy65 = engine.dispatch('item_buy', { shop_id: 65 });
check(buy65.reply && buy65.reply.code === 0, `buy 65 should succeed (${JSON.stringify(buy65.reply)})`);
check(engine.state.clover === before - 3000, `clover should drop by 3000 (got ${before - engine.state.clover})`);
const house = engine.state.items.house || [];
check(house.some((h) => Number(h.item_id) === 204002), 'item 204002 should be in the house');
const pushed = (buy65.pushes || []).some((p) => String(p.cmd).replace('.', '_') === 'item_update');
check(pushed, 'item_update push required (client addHouseItem is a stub)');

/* ---- shop slot 64: prerequisite ["shop","58"] not bought -> must be REFUSED ---- */
const buy64 = engine.dispatch('item_buy', { shop_id: 64 });
check(buy64.reply && buy64.reply.code !== 0, `buy 64 before slot 58 must be refused (${JSON.stringify(buy64.reply)})`);
check(!(engine.state.items.house || []).some((h) => Number(h.item_id) === 9001), 'item 9001 must NOT be granted');

/* ---- new furniture shop row 8027 (item 1200, 550) ---- */
const cloverBefore = engine.state.clover;
const fbuy = engine.dispatch('furniture_buy_shop', { shop_id: 8027 });
check(fbuy.reply && fbuy.reply.code === 0, `furniture_buy_shop 8027 should succeed (${JSON.stringify(fbuy.reply)})`);
check(engine.state.clover === cloverBefore - 550, `clover should drop by 550 (got ${cloverBefore - engine.state.clover})`);

fs.rmSync(dir, { recursive: true, force: true });

if (problems.length) {
  console.error('FAIL: shipped bundle / A-tier content\n  - ' + problems.join('\n  - '));
  process.exit(1);
}
console.log('PASS: shipped bundle carries the merged A-tier rows and they trade correctly');
console.log(`  shop 65 bought (item 204002), shop 64 refused without slot 58, furniture 8027 bought (item 1200)`);
