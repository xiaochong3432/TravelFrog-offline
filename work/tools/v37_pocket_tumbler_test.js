#!/usr/bin/env node
'use strict';

/* 【V4.0】这套件验证的是 V3.7 的"放上台面即开工"，所以按 V3.7 设好排队开关。
   引擎的开关常量在 require 时求值，所以这段必须在 require 之前。 */
process.env.FROG_CRAFT_QUEUE = '0';

/**
 * V3.7 系统 2+3：口袋（挂兜）与不倒翁（并入他 3.3）
 *
 *   node work/tools/v37_pocket_tumbler_test.js
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
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'pt-')), 'save.json'), verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const give = (e, id, n) => {
  const row = e.state.items.house.find((r) => Number(r.item_id) === Number(id));
  if (row) row.count += n; else e.state.items.house.push({ item_id: Number(id), count: n });
};
const POCKET_BP = 10601, ROPE = 11102, TUMBLER_BP = 10401, FRUIT = 11001;
const KNIFE = 10205, NEEDLE = 10204, BRUSH = 10202;
const CRAFT_SEC = 15 * 60;

console.log('\n[1] 口袋·基础款：绳 + 基材 + 工具 -> 开工 -> 收藏');
{
  const e = fresh();
  e.tick();
  give(e, POCKET_BP, 1); give(e, 10005, 1); give(e, 10004, 1); give(e, 10006, 1);
  give(e, KNIFE, 1); give(e, NEEDLE, 1); give(e, ROPE, 1);
  /* 工具进 1–5 号位，绳进 7 号位（= 物品位 6） */
  eq(call(e, 'furniture_putin_bench', { pos: 1, id: KNIFE }).reply.code, 0, '放小刀');
  eq(call(e, 'furniture_putin_bench', { pos: 2, id: NEEDLE }).reply.code, 0, '放棒针');
  const r = call(e, 'furniture_putin_bench', { pos: 7, id: ROPE });
  eq(r.reply.code, 0, '绳放上台面');
  eq(r.reply.crafting, 1, '绳放上台面就开工');
  eq(e.state.furniture.craft && e.state.furniture.craft.kind, 'pocket', '制作类型 = pocket');
  t('基材被扣掉', [10005, 10004, 10006].every((id) =>
    !e.state.items.house.some((x) => Number(x.item_id) === id && x.count > 0)), '应全扣');
  CLOCK += CRAFT_SEC + 1;
  e.tick();
  const list = e.state.furniture.pocket.list || [];
  eq(list.length, 1, '口袋收藏 +1');
  t('做出来的是三种绳编挂兜之一', [22011, 22012, 22013].indexOf(Number(list[0])) >= 0, 'id=' + list[0]);
  eq((e.state.furniture.owned || []).indexOf(Number(list[0])), -1, '不占家具收藏');
  const pl = call(e, 'furniture_load_pocket', {}).reply;
  eq(pl.list.length, 1, '载荷里能看到它');
  eq(pl.list[0], Number(list[0]), '载荷 id 一致');
  eq(e.state.furniture.benchLock, 0, '工作台解锁');
}

console.log('\n[2] 口袋·专属款：台面上放特殊材料 10104（海螺贝）-> 海洋挂兜 22031');
{
  const e = fresh();
  e.tick();
  give(e, POCKET_BP, 1); give(e, 10005, 1); give(e, 10004, 1); give(e, 10006, 1);
  give(e, KNIFE, 1); give(e, NEEDLE, 1); give(e, 10104, 1); give(e, ROPE, 1);
  call(e, 'furniture_putin_bench', { pos: 1, id: KNIFE });
  call(e, 'furniture_putin_bench', { pos: 2, id: NEEDLE });
  call(e, 'furniture_putin_bench', { pos: 8, id: 10104 });      // 特殊材料进物品位
  const r = call(e, 'furniture_putin_bench', { pos: 7, id: ROPE });
  eq(r.reply.code, 0, '绳放上台面');
  eq(r.reply.crafting, 1, '开工');
  CLOCK += CRAFT_SEC + 1;
  e.tick();
  eq(Number((e.state.furniture.pocket.list || [])[0]), 22031, '做出了海洋挂兜');
  eq(e.state.furniture.bench[7], -1, '特殊材料位被清掉');
}

console.log('\n[3] 不倒翁：果子 + 基材 + 工具 -> 收藏里带 layers');
{
  const e = fresh();
  e.tick();
  give(e, TUMBLER_BP, 1); give(e, 10001, 1); give(e, 10006, 1);
  give(e, BRUSH, 1); give(e, KNIFE, 1); give(e, FRUIT, 1);
  call(e, 'furniture_putin_bench', { pos: 1, id: BRUSH });
  call(e, 'furniture_putin_bench', { pos: 2, id: KNIFE });
  const r = call(e, 'furniture_putin_bench', { pos: 8, id: FRUIT });
  eq(r.reply.crafting, 1, '果子放上台面就开工');
  eq(e.state.furniture.craft && e.state.furniture.craft.kind, 'tumbler', '制作类型 = tumbler');
  CLOCK += CRAFT_SEC + 1;
  e.tick();
  const list = (e.state.furniture.tumbler.list || []);
  eq(list.length, 1, '不倒翁收藏 +1');
  t('基础款是四种之一', [20011, 20021, 20031, 20041].indexOf(Number(list[0].id)) >= 0, 'id=' + (list[0] || {}).id);
  t('带上了外观图层（眼睛 bdw_eye_*）',
    Array.isArray(list[0].layers) && list[0].layers.length > 0 && list[0].layers[0].layer[0] > 0,
    JSON.stringify(list[0].layers));
  const tl = call(e, 'furniture_load_tumbler', {}).reply;
  eq(tl.tumbler_list.length, 1, '载荷里能看到它');
  eq(Number(tl.tumbler_list[0].id), Number(list[0].id), '载荷 id 一致');
  eq((e.state.furniture.owned || []).indexOf(Number(list[0].id)), -1, '不占家具收藏');
}

console.log('\n[4] 缺工具 / 缺材料就不开工');
{
  const e = fresh();
  e.tick();
  give(e, POCKET_BP, 1); give(e, 10005, 1); give(e, 10004, 1); give(e, 10006, 1); give(e, ROPE, 1);
  const r = call(e, 'furniture_putin_bench', { pos: 7, id: ROPE });
  eq(r.reply.crafting, undefined, '没工具不开工');
  eq(!!e.state.furniture.craft, false, '没有进行中的制作');
  eq(e.state.furniture.benchLock, 0, '工作台没锁');
  /* 补上工具，但把基材拿掉 -> 仍不开工 */
  give(e, KNIFE, 1); give(e, NEEDLE, 1);
  e.state.items.house = e.state.items.house.filter((x) => ![10005, 10004, 10006].includes(Number(x.item_id)));
  e.state.furniture.craft = null;
  e.state.furniture.bench[6] = ROPE;      // 绳还在台面上
  const r2 = call(e, 'furniture_putin_bench', { pos: 1, id: KNIFE });
  eq(!!e.state.furniture.craft, false, '缺基材也不开工');
  t('工具确实放上去了（不是被别的原因挡住）', e.state.furniture.bench[0] === KNIFE, 'bench[0]=' + e.state.furniture.bench[0]);
}

console.log('\n[5] 老档兼容（没有 pocket/tumbler 列表的 V3.5/V3.6 档）');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'pt-old-'));
  const p = path.join(dir, 'save.json');
  const seed = fresh();
  seed.tick();
  const raw = JSON.parse(JSON.stringify(seed.exportSave()));
  delete raw.furniture.pocket.list;
  delete raw.furniture.tumbler.list;
  raw.furniture.pocket.clover = '7';                 // 老档里是字符串
  raw.furniture.tumbler.list = [{ id: 20011 }, 99999, null];   // 缺 layers + 脏数据
  raw.saveVersion = 1;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e = createEngine({ savePath: p, verbose: false });
  e.tick();
  t('口袋列表补齐为空数组', Array.isArray(e.state.furniture.pocket.list) && e.state.furniture.pocket.list.length === 0);
  eq(e.state.furniture.pocket.clover, 7, '三叶草数字化了');
  const tl = e.state.furniture.tumbler.list;
  t('不倒翁列表保留合法项、清掉脏数据',
    tl.length === 1 && Number(tl[0].id) === 20011 && Array.isArray(tl[0].layers), JSON.stringify(tl));
  const again = JSON.parse(JSON.stringify(e.exportSave()));
  eq(again.furniture.pocket.clover, 7, '存回再读一致');
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
