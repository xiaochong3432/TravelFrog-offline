#!/usr/bin/env node
'use strict';

/* 【V4.0】这套件验证 V3.7 的统一 5 分钟发酵，所以按 V3.7 设好时长。
   引擎的开关常量在 require 时求值，所以这段必须在 require 之前。 */
process.env.FROG_COMPOST_SEC = '300';

/**
 * V3.7 系统 1：土壤肥力星级（并入他 3.3 的点数/星级/衰减，保留我们的 5 分钟发酵）
 *
 *   node work/tools/v37_soil_stars_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);

let CLOCK = 1_700_000_000;
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const fresh = () => createEngine({
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'soil-')), 'save.json'), verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});

console.log('\n[1] 星级阈值与载荷字段');
{
  const e = fresh();
  e.tick();
  const p = call(e, 'furniture_load_compost', {}).reply;
  t('载荷里有 fertility_stars', Object.prototype.hasOwnProperty.call(p, 'fertility_stars'),
    JSON.stringify(p));
  eq(p.fertility_stars, 0, '开局 0 星');
  const c = e.state.furniture.compost;
  t('存档位 fertilityDecayAt 已补', Number(c.fertilityDecayAt) > 0, String(c.fertilityDecayAt));
}

console.log('\n[2] 发酵给点数（20001=10 / 20002=20 / 20003=30）而不是固定 +1');
{
  const e = fresh();
  e.tick();
  const c = e.state.furniture.compost;
  /* 三个格子里放三种肥料（他的点数表），然后让时间走过去 */
  c.boxes = [20001, 20002, 20003, 0, 0, 0];
  c.boxIndex = 0;
  c.job = null;
  c.fertility = 0;
  e.tick();                        // 先让它起锅（job.startedAt = 现在）
  CLOCK += 5 * 60 + 1;             // 一格 5 分钟
  e.tick();
  const after1 = e.state.furniture.compost.fertility;
  t('第一个发酵完成给了它自己的点数（10/20/30 之一）', [10, 20, 30].indexOf(after1) >= 0,
    'fertility=' + after1);
  /* 走完剩下两格 */
  CLOCK += 20 * 60;
  e.tick();
  const total = e.state.furniture.compost.fertility;
  t('三格走完后累计 = 60 点（10+20+30）', total === 60, 'fertility=' + total + ' 剩余格=' + JSON.stringify(e.state.furniture.compost.boxes));
  const p = call(e, 'furniture_load_compost', {}).reply;
  eq(p.fertility_stars, 2, '60 点 → 2 星（阈值 50）');
}

console.log('\n[3] 上限 100 与星级映射');
{
  const e = fresh();
  e.tick();
  const c = e.state.furniture.compost;
  c.fertility = 95;
  c.boxes = [20003, 0, 0, 0, 0, 0];
  c.job = null;
  e.tick();                        // 起锅
  CLOCK += 5 * 60 + 1;
  e.tick();
  eq(e.state.furniture.compost.fertility, 100, '超过上限就夹到 100');
  const p = call(e, 'furniture_load_compost', {}).reply;
  eq(p.fertility_stars, 3, '100 点 → 3 星');
}

console.log('\n[4] 每日 −1（含离线补算）');
{
  const e = fresh();
  e.tick();
  const c = e.state.furniture.compost;
  c.fertility = 50;
  c.job = null;
  c.boxes = [0, 0, 0, 0, 0, 0];
  c.fertilityDecayAt = CLOCK;       // 从现在开始算
  CLOCK += 2 * 86400 + 10;          // 离线两天
  e.tick();
  eq(e.state.furniture.compost.fertility, 48, '两天扣 2 点');
  const decayAt = Number(e.state.furniture.compost.fertilityDecayAt);
  t('fertilityDecayAt 已推进（余数留到下一次）',
    decayAt > CLOCK - 86400 && decayAt <= CLOCK, String(decayAt - CLOCK));
  CLOCK += 86400;
  e.tick();
  eq(e.state.furniture.compost.fertility, 47, '再过一天再扣 1 点');
}

console.log('\n[5] 老档兼容（没有 fertilityDecayAt 的 V3.5/V3.6 档）');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'soil-old-'));
  const p = path.join(dir, 'save.json');
  const seed = fresh();
  seed.tick();
  const raw = JSON.parse(JSON.stringify(seed.exportSave()));
  raw.furniture.compost = { showIndex: 1, replaceIndex: 0, boxIndex: 0,
    boxes: [0, 0, 0, 0, 0, 0], list: [21000], job: null, fertility: 3 };   // 老档：无 decayAt
  delete raw.furniture.compost.fertilityDecayAt;
  raw.saveVersion = 6;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e = createEngine({ savePath: p, verbose: false });
  e.tick();
  const c = e.state.furniture.compost;
  eq(c.fertility, 3, '老档肥力原样保留（不追溯扣分）');
  t('补上了 fertilityDecayAt', Number(c.fertilityDecayAt) > 0);
  const pl = call(e, 'furniture_load_compost', {}).reply;
  eq(pl.fertility_stars, 0, '3 点 → 0 星');
  const again = JSON.parse(JSON.stringify(e.exportSave()));
  eq(again.furniture.compost.fertility, 3, '存回再读仍是 3');
  /* 越界的老档值也要夹住 */
  raw.furniture.compost.fertility = 9999;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e2 = createEngine({ savePath: p, verbose: false });
  e2.tick();
  eq(e2.state.furniture.compost.fertility, 100, '老档越界值夹到 100');
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
