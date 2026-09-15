#!/usr/bin/env node
'use strict';
/**
 * 悬浮球的「一键」按钮能不能拿到**新增内容**？
 *
 * 编辑器按钮 -> gm('all_furniture') / gm('unlock_pictures') -> 引擎的 GM 实现。
 * 两个实现都是查表的（unlockFurniture() 遍历 furnitureData；PICTURE_IDS 来自 Picture），
 * 所以这里直接跑一遍数数，源码与**打包产物**各验一次，并检查相册容量够不够放 351 张。
 *
 * Usage: node tools/verify_editor_new_content.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const gd = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'));

const NEW_FURNITURE = [2001, 2002, 2025, 2027, 10104, 10105, 10106];
const NEW_PICTURES = [3102, 3103];

function runOn(engine, label) {
  const problems = [];
  const info = {};
  const r1 = engine.dispatch('client_gm', { cmd: 'all_furniture' });
  const owned = engine.state.furniture.owned || [];
  info.furnitureTotal = owned.length;
  info.furnitureMsg = r1.reply && r1.reply.info;
  info.newFurnitureOwned = NEW_FURNITURE.filter((id) => owned.indexOf(id) !== -1);
  if (info.newFurnitureOwned.length !== NEW_FURNITURE.length) {
    problems.push(`${label}: 新家具没全给到（缺 ${NEW_FURNITURE.filter((i) => owned.indexOf(i) < 0)}）`);
  }
  const tableRows = Object.keys(gd.tables.furnitureData).length;
  if (owned.length !== tableRows) problems.push(`${label}: 家具总数 ${owned.length} != 表行数 ${tableRows}`);

  const r2 = engine.dispatch('client_gm', { cmd: 'unlock_pictures' });
  const pics = engine.state.pictures || [];
  info.pictureTotal = pics.length;
  info.pictureMsg = r2.reply && r2.reply.info;
  info.newPictures = NEW_PICTURES.filter((id) => pics.some((p) => Number(p.pic_id) === id));
  if (info.newPictures.length !== NEW_PICTURES.length) {
    problems.push(`${label}: 新明信片没进相册（缺 ${NEW_PICTURES.filter((i) => !pics.some((p) => Number(p.pic_id) === i))}）`);
  }
  const pictureRows = (gd.tables.Picture || []).length;
  if (pics.length !== pictureRows) problems.push(`${label}: 相册 ${pics.length} != Picture 表 ${pictureRows}`);
  const noPicId = pics.filter((p) => p.pic_id === undefined || p.pic_id === null).length;
  if (noPicId) problems.push(`${label}: 有 ${noPicId} 张缺 pic_id（会显示空白）`);
  const dupHandles = new Set();
  let dup = 0;
  for (const p of pics) { if (dupHandles.has(p.id)) dup++; dupHandles.add(p.id); }
  if (dup) problems.push(`${label}: 相册句柄重复 ${dup} 个`);

  /* 相册容量：客户端 ALBUM_MAX / 我们的 capacity 字段够不够放 351 张 */
  info.albumCapacity = engine.state.albumCapacity || engine.state.albumCapacity === 0
    ? engine.state.albumCapacity : undefined;
  const cap = Number(engine.state.albumCapacity || 0);
  info.capacityOk = !cap || cap >= pics.length;
  if (cap && cap < pics.length) problems.push(`${label}: 相册容量 ${cap} < ${pics.length} 张`);

  return { label, problems, info };
}

const results = [];

/* --- source engine --- */
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-editor-src-'));
  const engine = require(path.join(ROOT, 'work', 'run', 'engine', 'index.js'))
    .createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
  results.push(runOn(engine, 'source'));
  fs.rmSync(dir, { recursive: true, force: true });
}

/* --- shipped bundle --- */
{
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
  const BUNDLE = path.join(ROOT, 'work', 'run', 'web', '__offline-engine.js');
  vm.runInContext(fs.readFileSync(BUNDLE, 'utf8'), sandbox, { filename: BUNDLE });
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-editor-bnd-'));
  const engine = sandbox.window.FrogEngine.createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
  results.push(runOn(engine, 'bundle'));
  fs.rmSync(dir, { recursive: true, force: true });
}

let bad = 0;
for (const r of results) {
  console.log(`\n=== ${r.label} ===`);
  console.log(`  一键获得全部家具 : ${r.info.furnitureTotal} 件（表 ${Object.keys(gd.tables.furnitureData).length} 行）`
    + `  新增已在: ${r.info.newFurnitureOwned.join(',') || '—'}`);
  console.log(`    ${r.info.furnitureMsg}`);
  console.log(`  一键解锁明信片   : ${r.info.pictureTotal} 张（Picture 表 ${(gd.tables.Picture || []).length} 行）`
    + `  新增已在: ${r.info.newPictures.join(',') || '—'}`);
  console.log(`    ${r.info.pictureMsg}`);
  console.log(`  相册容量         : ${r.info.albumCapacity === undefined ? '(未设置)' : r.info.albumCapacity}  ${r.info.capacityOk ? 'OK' : '不足'}`);
  if (r.problems.length) { bad += r.problems.length; r.problems.forEach((p) => console.log('  PROBLEM: ' + p)); }
}
console.log(bad ? `\nRESULT: PROBLEMS (${bad})` : '\nRESULT: OK -- 悬浮球两个"一键"按钮都已包含新增内容');
process.exit(bad ? 1 : 0);
