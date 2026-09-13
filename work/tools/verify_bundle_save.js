#!/usr/bin/env node
'use strict';
/**
 * Verify the SHIPPED bundle's save layer in a browser-like store.
 *
 * engine_test.js exercises the same logic on real files, but the browser host is
 * a DIFFERENT storage model: there are no files, only localStorage keys. The
 * bundle's `fs` stub therefore maps the engine's sibling slots onto keys:
 *
 *   save.json              -> frog.offline.save            (UNCHANGED -- this is
 *   save.json.bak          -> frog.offline.save::save.json.bak
 *   save.json.tmp          -> frog.offline.save::save.json.tmp
 *   save.json.corrupt-<ts> -> frog.offline.save::save.json.corrupt-<ts>
 *
 * Nothing here would be caught by the Node tests, and a mistake in the mapping
 * would be invisible in the game until a save is damaged -- exactly the kind of
 * silent failure this layer exists to remove. So this harness loads the real
 * generated bundle in a VM with a spec-faithful localStorage (getItem/setItem/
 * removeItem/key/length) and drives the save paths directly.
 *
 * Usage: node tools/verify_bundle_save.js
 * Exit code 0 = PASS, 1 = FAIL.
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const BUNDLE = path.join(ROOT, 'work', 'run', 'web', '__offline-engine.js');
const PRIMARY = 'frog.offline.save';
const SLOT = PRIMARY + '::';

const problems = [];
function check(cond, msg) {
  if (!cond) problems.push(msg);
}

/** A store that behaves like the real one: `key(i)` and `length` included. */
function newStore(initial) {
  const map = new Map(Object.entries(initial || {}));
  return {
    map,
    getItem(k) { return map.has(String(k)) ? map.get(String(k)) : null; },
    setItem(k, v) {
      if (this.failKeys && this.failKeys.has(String(k))) {
        const e = new Error('QuotaExceededError: the quota has been exceeded.');
        e.name = 'QuotaExceededError';
        throw e;
      }
      map.set(String(k), String(v));
      return true;
    },
    removeItem(k) { map.delete(String(k)); },
    key(i) { const ks = Array.from(map.keys()); return i < ks.length ? ks[i] : null; },
    get length() { return map.size; },
  };
}

/** Boot the shipped bundle against one store. Returns {engine, store, mirror}. */
function boot(store, mirrorValue) {
  const mirror = { value: mirrorValue === undefined ? null : mirrorValue, writes: [] };
  const sandbox = {
    console: { log() {}, warn() {}, error() {} },
    setTimeout, clearTimeout, setInterval, clearInterval,
    localStorage: store,
  };
  if (mirrorValue !== undefined) {
    sandbox.FrogNative = {
      readMirrorSave: () => mirror.value,
      mirrorSave: (t) => { mirror.writes.push(String(t)); mirror.value = String(t); },
    };
  }
  sandbox.window = sandbox;
  sandbox.globalThis = sandbox;
  sandbox.self = sandbox;
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync(BUNDLE, 'utf8'), sandbox, { filename: BUNDLE });
  const E = sandbox.window.FrogEngine;
  if (!E) throw new Error('bundle did not define window.FrogEngine');
  return { engine: E.createEngine({ savePath: 'save.json', verbose: false }), store, mirror };
}

const gm = (engine, cmd) => engine.dispatch('client_gm', { cmd });
const slotsOf = (store, prefix) => Array.from(store.map.keys()).filter((k) => k.indexOf(prefix) === 0);
const bakKey = SLOT + 'save.json.bak';
const tmpKey = SLOT + 'save.json.tmp';

/* --- 1. the primary key is exactly what earlier builds used ----------------- */
{
  const { store, engine } = boot(newStore(), undefined);
  gm(engine, 'set_clover 1234');
  check(store.getItem(PRIMARY) != null,
    'the primary save must live under the historical key ' + PRIMARY);
  check(JSON.parse(store.getItem(PRIMARY)).clover === 1234, 'and hold the played state');
  check(store.getItem(bakKey) == null, 'the very first save has no previous version to back up');
  check(store.getItem(tmpKey) == null, 'and leaves no .tmp behind');
  const stale = slotsOf(store, SLOT);
  check(stale.length === 0, 'a healthy first save writes no sibling slots, got ' + JSON.stringify(stale));
}

/* --- 2. the previous good version is kept under its own key ---------------- */
{
  const { store, engine } = boot(newStore(), undefined);
  gm(engine, 'set_clover 1111');
  gm(engine, 'set_clover 2222');
  check(store.getItem(bakKey) != null, 'the second commit writes ' + bakKey);
  check(JSON.parse(store.getItem(bakKey)).clover === 1111,
    'and the backup holds the version that was replaced (1111)');
  check(JSON.parse(store.getItem(PRIMARY)).clover === 2222, 'while the primary moves on');
}

/* --- 3. damage in the primary restores from the backup slot in the browser -- */
{
  const { store, engine } = boot(newStore(), undefined);
  gm(engine, 'set_clover 1111');
  gm(engine, 'set_clover 2222');
  const broken = store.getItem(PRIMARY).slice(0, 40);          // cut off mid-write
  store.setItem(PRIMARY, broken);

  const again = boot(store, undefined);
  check(again.engine.state.clover === 1111,
    'a truncated browser save loads the backup slot, got clover ' + again.engine.state.clover);
  check(again.engine.state.__saveReport.action === 'restore',
    'and reports a restore (' + again.engine.state.__saveReport.action + ')');
  check(again.engine.state.__saveReport.restoredFrom === 'backup',
    'from the backup, not from somewhere else (' + again.engine.state.__saveReport.restoredFrom + ')');
  const kept = slotsOf(store, SLOT + 'save.json.corrupt-');
  check(kept.length === 1, 'the unreadable text is archived to one corrupt slot, got ' + kept.length);
  check(kept.length === 1 && store.getItem(kept[0]) === broken,
    'and that slot holds the damaged bytes verbatim');

  const third = boot(store, undefined);
  check(slotsOf(store, SLOT + 'save.json.corrupt-').length === 1,
    'booting again on the same damage does not pile up more archives');
  check(third.engine.state.clover === 1111, 'and still restores the same save');
}

/* --- 4. a save written by an OLD build (no slots at all) still loads ------- */
{
  const legacy = JSON.stringify({ clover: 4321, ticket: 7, name: '老档', items: {} });
  const { store, engine } = boot(newStore({ [PRIMARY]: legacy }), undefined);
  check(engine.state.clover === 4321, 'an old save (primary key only) keeps its clover');
  check(engine.state.name === '老档', 'and its name');
  check(engine.state.__saveReport.action === 'load', 'and is a normal load, not a repair');
  check(store.getItem(PRIMARY) === legacy, 'loading never rewrites it');
}

/* --- 5. the native mirror is the last resort, never the first choice ------- */
{
  const good = JSON.stringify({ clover: 555, items: {} });
  const empty = boot(newStore(), good);
  check(empty.engine.state.clover === 555, 'with localStorage empty the mirror is used');
  check(empty.engine.state.__saveReport.restoredFrom === 'mirror', 'and reported as the mirror');

  const both = boot(newStore({ [PRIMARY]: JSON.stringify({ clover: 999, items: {} }) }), good);
  check(both.engine.state.clover === 999,
    'a healthy localStorage save always wins over the mirror');

  const damaged = boot(newStore({ [PRIMARY]: '{not json' }), good);
  check(damaged.engine.state.clover === 555,
    'a damaged primary falls back to the mirror when there is no backup');
  check(damaged.engine.state.__saveReport.restoredFrom === 'mirror', 'reported as the mirror');

  /* the mirror is written for the PRIMARY only: slot writes must not touch it */
  const { store, engine, mirror } = boot(newStore(), good);
  gm(engine, 'set_clover 666');
  gm(engine, 'set_clover 777');
  check(store.getItem(bakKey) != null, 'precondition: a backup slot was written');
  check(mirror.writes.every((t) => JSON.parse(t).clover !== undefined),
    'every mirror write is a whole save, never a slot payload');
  check(mirror.writes.length === 2,
    'one mirror write per commit (slot writes do not reach the phone), got ' + mirror.writes.length);
}

/* --- 6. a quota failure is reported, and the stored save survives it ------- */
{
  const { store, engine } = boot(newStore(), undefined);
  gm(engine, 'set_clover 8080');
  const before = store.getItem(PRIMARY);
  store.failKeys = new Set([PRIMARY]);                        // full disk, silent-ish failure
  gm(engine, 'set_clover 9090');
  const ok = engine.save();
  check(ok === false, 'save() must report false when the primary cannot be written');
  check(engine.state.__saveReport.lastError === 'write-main',
    'and say which write failed, got ' + engine.state.__saveReport.lastError);
  check(store.getItem(PRIMARY) === before, 'the stored save is byte-identical afterwards');
  check(store.getItem(tmpKey) != null, 'a complete copy is left in the .tmp slot');
  store.failKeys = new Set();
  check(engine.save() === true, 'and saving works again once space is available');
  check(JSON.parse(store.getItem(PRIMARY)).clover === 9090, 'with the latest state');
  check(store.getItem(tmpKey) == null, 'and the .tmp slot cleaned up');
}

/* --- 7. a save from a newer engine is loaded but never overwritten --------- */
{
  const future = JSON.stringify({ saveVersion: 99, clover: 246, items: {}, extra: 'keep me' });
  const { store, engine } = boot(newStore({ [PRIMARY]: future }), undefined);
  check(engine.state.clover === 246, 'a newer-format save still plays');
  check(engine.save() === false, 'but cannot be overwritten by this build');
  check(store.getItem(PRIMARY) === future, 'the file is untouched, unknown fields included');
}

/* ------------------------------------------------------------------ report */
if (problems.length) {
  console.log('FAIL: ' + problems.length + ' problem(s)');
  for (const p of problems) console.log('  - ' + p);
  process.exit(1);
}
console.log('PASS: browser save slots, fallback chain and failure reporting all behave');
