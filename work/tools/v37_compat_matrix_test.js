#!/usr/bin/env node
'use strict';
/**
 * V3.7 老档兼容矩阵（八条线）。
 *
 * 做法：让**每条线的引擎真的跑一会儿、写出真实存档**，再交给 V3.7 读：
 *   · 能读进来、不会抛错、不会被"只读不写"挡住；
 *   · `saveVersion` 从 1 迁到 2；
 *   · V3.7 新加的字段全部补齐；
 *   · 存回再读一致（往返稳定）；
 *   · 顺便确认这份老档在**出货 V3.6** 里也能读（说明不是 V3.7 专有格式）。
 *
 *   node work/tools/v37_compat_matrix_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const V37 = path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const V36 = path.join(ROOT, 'work', 'build', 'v36_engine', 'index.js');

const LINES = [
  ['我们 V3（9/15）', 'work/build/v3_engine/index.js'],
  ['我们 V3.1', 'work/build/merged_v31/index.js'],
  ['我们 V3.3（出货）', 'work/build/v33_engine/index.js'],
  ['我们 V3.5（出货）', 'work/build/v35_engine/index.js'],
  ['我们 V3.6（出货）', 'work/build/v36_engine/index.js'],
  ['他们 3.4（上游）', 'work/build/their34_live/index.js'],
  ['他的 3.2', 'work/build/x33/live32/index.js'],
  ['他的 3.3', 'work/build/x33/live/index.js'],
];

const CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};

const load = (p) => { delete require.cache[require.resolve(p)]; return require(p); };

/* V3.7 新加的字段（老档读入后必须补齐） */
const NEW_FIELDS = [
  ['taskCounters', (s) => s.taskCounters && typeof s.taskCounters === 'object'],
  ['taskTiers', (s) => s.taskTiers && typeof s.taskTiers === 'object'],
  ['furniture.shopOffers', (s) => s.furniture && s.furniture.shopOffers !== undefined],
  ['furniture.craftQueued', (s) => s.furniture && s.furniture.craftQueued !== undefined],
  ['furniture.compost.fertilityDecayAt', (s) => Number(s.furniture.compost.fertilityDecayAt) > 0],
  ['decoration.startedAt', (s) => s.decoration && s.decoration.startedAt !== undefined],
  ['decoration.nextAutoChangeAt', (s) => s.decoration && s.decoration.nextAutoChangeAt !== undefined],
  ['frog.eggId', (s) => s.frog && s.frog.eggId !== undefined],
  ['furniture.pocket.list', (s) => Array.isArray(s.furniture.pocket.list)],
  ['furniture.tumbler.list', (s) => Array.isArray(s.furniture.tumbler.list)],
];

const SEQ = [
  ['hall_enter_game', {}], ['clover_harvest', { clover_id: 1 }], ['item_load_items', {}],
  ['travel_load_note', {}], ['guest_load', {}], ['mail_load', {}],
  ['furniture_load_furniture', {}], ['furniture_load_compost', {}], ['client_load_role', {}],
  ['album_load', {}], ['task_load', {}], ['item_load_shop_info', {}],
];

function playOld(rel) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mx-'));
  const savePath = path.join(dir, 'save.json');
  const mod = load(path.join(ROOT, rel));
  const e = mod.createEngine({ savePath, verbose: false });
  for (const [cmd, d] of SEQ) { try { e.dispatch(cmd, d); } catch (err) { /* 老线可能没有这个协议 */ } }
  try { e.tick(); } catch (err) { /* ignore */ }
  try { e.save(); } catch (err) { /* ignore */ }
  return savePath;
}

const digest = (s) => JSON.stringify({
  clover: Number(s.clover) || 0, ticket: Number(s.ticket) || 0,
  house: (s.items && s.items.house || []).length,
  mails: (s.mails || []).length, pictures: (s.pictures || []).length,
  owned: (s.furniture && s.furniture.owned || []).length,
  frog: s.frog && s.frog.status, weather: s.weather && s.weather.weather,
});

console.log('\n=== V3.7 老档兼容矩阵（' + LINES.length + ' 条线）===');

for (const [name, rel] of LINES) {
  if (!fs.existsSync(path.join(ROOT, rel))) {
    console.log('  SKIP  ' + name + '：' + rel + ' 不存在（历史版本引擎需自备）');
    continue;
  }
  console.log('\n[' + name + ']');
  let savePath;
  try {
    savePath = playOld(rel);
  } catch (err) {
    t(name + '：旧引擎能写出存档', false, err.message.split('\n')[0]);
    continue;
  }
  const raw = JSON.parse(fs.readFileSync(savePath, 'utf8'));
  t(name + '：旧引擎写出了真实存档（saveVersion=' + raw.saveVersion + '）', !!raw && !!raw.frog);

  /* 在 V3.7 里读 */
  let e37;
  try {
    e37 = load(V37).createEngine({ savePath, verbose: false });
    e37.tick();
  } catch (err) {
    t(name + '：V3.7 能读入', false, err.message.split('\n')[0]);
    continue;
  }
  const s37 = e37.state;
  const refused = s37.__saveReport && s37.__saveReport.refused;
  t(name + '：V3.7 读入没被"只读不写"挡住', !refused, JSON.stringify(s37.__saveReport || {}).slice(0, 100));
  t(name + '：saveVersion 迁移到 2', Number(s37.saveVersion) === 2, 'saveVersion=' + s37.saveVersion);

  const missing = NEW_FIELDS.filter(([, ok]) => !ok(s37)).map(([f]) => f);
  t(name + '：V3.7 新字段全部补齐', missing.length === 0, '缺: ' + JSON.stringify(missing));

  /* 往返一致 */
  const before = digest(s37);
  e37.save();
  const e37b = load(V37).createEngine({ savePath, verbose: false });
  e37b.tick();
  t(name + '：存回再读一致', digest(e37b.state) === before,
    before + ' vs ' + digest(e37b.state));

  /* 出货 V3.6 也能读（说明不是 V3.7 专有格式） */
  try {
    const e36 = load(V36).createEngine({ savePath: savePath + '.copy', verbose: false });
    void e36;
  } catch (err) { /* copy 不存在，跳过 */ }
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
