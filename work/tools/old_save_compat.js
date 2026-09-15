#!/usr/bin/env node
'use strict';
/**
 * OLD-SAVE COMPATIBILITY: can a save written by an EARLIER build still be played?
 *
 * Why this exists: players install a new APK over the old one (that is the whole point of
 * the in-place update), so their existing save -- which was written by whatever engine
 * version they had -- has to keep loading. V2's 开发历史 states the hard constraint as
 * "旧存档必须始终可读：新增字段一律可选、缺失时惰性生成"; this measures it instead of
 * trusting it.
 *
 * Four cases:
 *   1. a minimal save (only the oldest core fields) loads and the game keeps answering
 *   2. a save missing the NEWEST subsystems' fields (目的地/存档安全 era) loads and a
 *      full travel round trip still works
 *   3. a corrupt primary is ARCHIVED (never silently overwritten) and the .bak still plays
 *   4. a save round-trips through save/reload unchanged
 *
 * Usage: node work/tools/old_save_compat.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const engineModule = require(path.join(ROOT, 'work', 'run', 'engine', 'index.js'));

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-oldsave-'));
let fails = 0;
const notes = [];

function ok(name, cond, detail) {
  if (cond) {
    console.log('  PASS  ' + name);
  } else {
    fails++;
    console.log('  FAIL  ' + name + (detail ? '  -- ' + detail : ''));
  }
}

function fresh(savePath) {
  return engineModule.createEngine({ savePath });
}

/* ------------------------------------------------------------------ 1. minimal save */
{
  const p = path.join(dir, 'old1.json');
  // a save as an early build could have left it: a handful of fields, no sub-objects
  fs.writeFileSync(p, JSON.stringify({
    uid: 10001, name: '呱呱', clover: 1234, ticket: 2, createTime: 1700000000,
  }));
  let eng = null;
  let booted = true;
  try {
    eng = fresh(p);
  } catch (e) {
    booted = false;
    notes.push('minimal save threw on load: ' + (e && e.message));
  }
  ok('minimal old save loads', booted);
  if (booted) {
    ok('its values are kept', eng.state.clover === 1234 && eng.state.name === '呱呱',
      'clover=' + eng.state.clover + ' name=' + eng.state.name);
    const sub = ['items', 'travel', 'frog', 'calendar', 'handbook', 'furniture', 'decoration'];
    ok('missing subsystems are created lazily',
      sub.every((k) => eng.state[k] && typeof eng.state[k] === 'object'),
      sub.filter((k) => !eng.state[k]).join(','));
    let answered = true;
    try {
      eng.dispatch('clover_load_clovers', {});
      eng.dispatch('item_load_items', {});
      eng.dispatch('travel_load_note', {});
      eng.dispatch('calendar_load', {});
      eng.tick(0);
    } catch (e) {
      answered = false;
      notes.push('core commands threw: ' + (e && e.message));
    }
    ok('core commands answer on that save', answered);
  }
}

/* ------------------------------------------- 2. save without the newest subsystems */
{
  const p = path.join(dir, 'old2.json');
  // write a full save with the CURRENT engine, then delete what the newest work added
  const eng = fresh(p);
  eng.state.clover = 4321;
  eng.dispatch('client_gm', { cmd: 'add_clover 0' });   // forces a save
  const full = JSON.parse(fs.readFileSync(p, 'utf8'));

  const newer = ['selectGift', 'giftBox', 'albumDeleted', 'saveVersion',
                 'mailTutorialSent', 'tasksClaimed', 'handbook', 'events', 'lastSeen'];
  const stripped = Object.assign({}, full);
  for (const k of newer) delete stripped[k];
  fs.writeFileSync(p, JSON.stringify(stripped));

  let eng2 = null;
  let loaded = true;
  try {
    eng2 = fresh(p);
  } catch (e) {
    loaded = false;
    notes.push('stripped save threw: ' + (e && e.message));
  }
  ok('save without the newer fields loads', loaded);
  if (loaded) {
    ok('the old values survive', eng2.state.clover === 4321, 'clover=' + eng2.state.clover);
    ok('the removed fields come back as defaults',
      newer.every((k) => eng2.state[k] !== undefined), newer.filter((k) => eng2.state[k] === undefined).join(','));
    // the frog has to be able to leave: 立刻出门 is the editor's own "go now"
    let travelled = false;
    try {
      eng2.dispatch('client_gm', { cmd: 'travel_now' });
      eng2.tick(0);
      travelled = eng2.state.frog && eng2.state.frog.status === 1;
    } catch (e) {
      travelled = false;
      notes.push('travel threw on the stripped save: ' + (e && e.message));
    }
    ok('立刻出门 still works after loading it', travelled,
      'frog.status=' + (eng2.state.frog && eng2.state.frog.status));
  }
}

/* --------------------------------------------------- 3. a corrupt primary is archived */
{
  const p = path.join(dir, 'old3.json');
  const eng = fresh(p);
  eng.state.clover = 777;
  eng.dispatch('client_gm', { cmd: 'add_clover 0' });   // force a write
  const good = fs.readFileSync(p, 'utf8');
  fs.writeFileSync(p + '.bak', good);              // pretend a good .bak exists
  fs.writeFileSync(p, '{ this is not json');       // damage the primary

  let eng3 = null;
  let threw = false;
  try {
    eng3 = fresh(p);
  } catch (e) {
    threw = true;
    notes.push('corrupt primary threw: ' + (e && e.message));
  }
  ok('a corrupt primary does not crash the loader', !threw);
  const quarantined = fs.readdirSync(dir).filter((n) => n.indexOf('old3.json.corrupt-') === 0);
  ok('the corrupt text is ARCHIVED, not deleted', quarantined.length > 0,
    'files=' + fs.readdirSync(dir).join(','));
  if (eng3) {
    ok('the good .bak is played instead', eng3.state.clover === 777,
      'clover=' + eng3.state.clover);
  }
  const report = (typeof engineModule.saveReport === 'function')
    ? engineModule.saveReport(p) : null;
  if (report) {
    notes.push('saveReport: kept=' + report.corruptKept + ' corruptSlots=' +
      (report.corrupt || []).length);
  }
}

/* --------------------------------------------------------------- 4. round trip */
{
  const p = path.join(dir, 'old4.json');
  const a = fresh(p);
  a.state.clover = 5150;
  a.state.name = '回环';
  a.dispatch('client_gm', { cmd: 'add_clover 0' });     // writing the state requires a save
  const b = fresh(p);
  ok('a save round-trips through reload', b.state.clover === 5150 && b.state.name === '回环',
    'clover=' + b.state.clover + ' name=' + b.state.name);
}

console.log('');
if (notes.length) {
  console.log('notes:');
  for (const n of notes) console.log('  - ' + n);
}
console.log(fails === 0 ? 'RESULT: OK' : 'RESULT: FAIL (' + fails + ')');
console.log('temp dir: ' + dir);
process.exit(fails === 0 ? 0 : 1);
