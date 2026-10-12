#!/usr/bin/env node
'use strict';
/**
 * 「他做的 3.3」改进内容实测：
 *   A. 节奏与时间尺度（出门/等待/客人/手工品阶段）
 *   B. 新系统的真实载荷（口袋/不倒翁/日历/肥力/花盆/商店/任务）
 *   C. 与我们的 V3.6 对照：这些协议/数据表在我们这边有没有
 *
 *   node work/tools/x33_probe.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const HIS = process.env.X33_ENGINE || path.join(ROOT, 'work', 'build', 'x33', 'live', 'index.js');
const OURS = process.env.X36_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');

let CLOCK = 1_700_000_000;
Date.now = () => CLOCK * 1000;

const mk = (ENGINE) => {
  const { createEngine, canon } = require(ENGINE);
  return { createEngine, canon };
};

function fresh(ENGINE) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'x33-'));
  const mod = mk(ENGINE);
  const e = mod.createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
  return { e, canon: mod.canon };
}
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const ok = (r) => r && r.reply && (r.reply.code === 0 || r.reply.code === undefined || r.reply.code === '0');

console.log('他的 3.3 引擎:', HIS);
const { e: his, canon: hc } = fresh(HIS);

console.log('\n================ A. 节奏与时间尺度 ================');
/* 出门一趟：准备行囊后强制到点，测 returnAt-departAt */
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const lunch = GD.items.filter((i) => Number(i.type) === 0).map((i) => Number(i.id));
const trips = [];
for (let i = 0; i < 40; i += 1) {
  his.state.frog.status = 0;
  his.state.items.bag[0] = lunch[i % lunch.length];
  his.state.travel.nextDepartAt = CLOCK;
  his.state.travel.departAt = 0;
  his.tick();
  if (his.state.frog.status === 1 && his.state.travel.departAt) {
    trips.push((his.state.travel.returnAt - his.state.travel.departAt) / 60);
    his.state.frog.status = 2;
    his.state.travel.returnAt = CLOCK - 1;
    his.tick();
  }
}
const mins = (a) => a.length ? `${Math.round(Math.min(...a))}–${Math.round(Math.max(...a))} 分钟` : '没测到';
console.log(`  带便当出门一趟       : ${mins(trips)}（${trips.length} 次）`);
/* 空背包（放浪） */
const stray = [];
for (let i = 0; i < 40; i += 1) {
  his.state.frog.status = 0;
  his.state.items.bag = [-1, -1, -1, -1];
  his.state.travel.nextDepartAt = CLOCK;
  his.state.travel.departAt = 0;
  his.tick();
  if (his.state.frog.status === 1 && his.state.travel.departAt) {
    stray.push((his.state.travel.returnAt - his.state.travel.departAt) / 60);
    his.state.frog.status = 2; his.state.travel.returnAt = CLOCK - 1; his.tick();
  }
}
console.log(`  空背包出门（放浪）   : ${mins(stray)}（${stray.length} 次）`);
/* 在家等待/掷骰窗口 */
const waits = [];
for (let i = 0; i < 30; i += 1) {
  his.state.frog.status = 0;
  his.state.items.bag[0] = lunch[0];
  his.state.travel.nextDepartAt = 0;
  his.tick();
  const nd = his.state.travel.nextDepartAt || his.state.travel.checkAt || 0;
  if (nd > CLOCK) waits.push((nd - CLOCK) / 3600);
  his.state.frog.status = 2; his.state.travel.returnAt = 0;
}
console.log(`  在家等下一次掷骰     : ${waits.length ? Math.min(...waits).toFixed(2) + '–' + Math.max(...waits).toFixed(2) + ' 小时' : '没测到'}`);
/* 客人在家：下一次摇号 */
const gwait = [];
for (let i = 0; i < 20; i += 1) {
  his.state.guest = null;
  his.state.friends = his.state.friends || {};
  const before = CLOCK;
  his.tick();
  const nx = his.state.nextGuestRollAt || his.state.guestNextAt || 0;
  if (nx > before) gwait.push((nx - before) / 3600);
}
console.log(`  下一次客人摇号       : ${gwait.length ? Math.min(...gwait).toFixed(2) + '–' + Math.max(...gwait).toFixed(2) + ' 小时' : '没测到（字段名可能不同）'}`);
console.log('  state 顶层字段:', Object.keys(his.state).join(', '));

console.log('\n================ B. 新系统的真实载荷 ================');
function show(label, cmd, data, pick) {
  try {
    const r = call(his, cmd, data);
    const rep = r && r.reply;
    const val = pick ? pick(rep) : rep;
    const s = JSON.stringify(val);
    console.log(`  ${label}\n      ${cmd} -> ${s ? s.slice(0, 460) : s}`);
    return rep;
  } catch (err) {
    console.log(`  ${label}\n      ${cmd} 抛错: ${err.message}`);
    return null;
  }
}
show('① 口袋（挂兜）系统', 'furniture_load_pocket', {}, (r) => r);
show('② 不倒翁系统', 'furniture_load_tumbler', {}, (r) => r);
show('③ 日历 / 节气奖励', 'calendar_load', {}, (r) => r);
show('④ 堆肥 / 土壤肥力', 'furniture_load_compost', {}, (r) => r);
show('⑤ 花盆', 'furniture_load_flowerpot', {}, (r) => r);
show('⑥ 家具商店（星级货架）', 'item_load_shop_info', {}, (r) => r);
show('⑦ 任务（新协议 task_client_pro）', 'task_load_list', {}, (r) => r);
show('⑧ 家具工坊（心情字段）', 'furniture_load_furniture', {}, (r) => r);
console.log('  家具状态字段:', JSON.stringify(Object.keys(his.state.furniture || {})));
console.log('  心情相关:', JSON.stringify({
  moodStress: his.state.furniture && his.state.furniture.moodStress,
  mood: his.state.furniture && his.state.furniture.mood,
  angerChanges: his.state.furniture && his.state.furniture.angerChanges,
}));

console.log('\n================ C. 和我们 V3.6 的对照 ================');
const ours = fs.readFileSync(OURS, 'utf8');
const hisSrc = fs.readFileSync(path.join(ROOT, 'work', 'build', 'x33', 'live', 'index.js'), 'utf8');
const FEATURES = [
  ['口袋/挂兜（pocketData）', 'POCKET_DATA', 'furniture_load_pocket'],
  ['不倒翁（tumblerData）', 'TUMBLER_DATA', 'furniture_load_tumbler'],
  ['土壤肥力/星级', 'SOIL_FERTILITY_MAX', null],
  ['节气日历奖励', 'CALENDAR_MONTH_REWARDS', 'calendar_get_st_reward'],
  ['嘟嘟商店星级', 'MERCHANT_STAR_WEIGHTS', 'item_load_shop_info'],
  ['家具暴怒（多次换家具）', 'FURNITURE_ANGER_CHANCE', null],
  ['花瓶自动更换', 'VASE_AUTO_CHANGE_CHANCE', null],
  ['雨天客人', 'RAIN_GUEST_CHANCE', null],
  ['绘本/邀约节奏', 'DRAWING_TRIP_MIN_SEC', null],
  ['制作工具按 type 细分', 'CRAFT_TOOLS_BY_TYPE', null],
  ['旅行中寄明信片', 'deliverTravelPostcard', null],
  ['礼物盒来访', 'GIFTBOX_VISIT_CHANCE', null],
];
console.log('  ' + '功能'.padEnd(30) + '他的3.3   我们V3.6');
for (const [label, marker] of FEATURES) {
  const a = hisSrc.indexOf(marker) >= 0;
  const b = ours.indexOf(marker) >= 0;
  console.log('  ' + label.padEnd(28) + (a ? '  有  ' : '  —   ') + '   ' + (b ? '有' : '—'));
}
/* 数据表层面 */
const hisGD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'build', 'x33', 'live', 'data', 'gamedata.json'), 'utf8'));
const ourGD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
console.log('\n  数据表里有没有这些新系统要用的表：');
for (const t of ['pocketData', 'tumblerData', 'tumblerPathData', 'soilData', 'calendarData',
  'solarTermData', 'merchantData', 'flowerpotData', 'decorationData']) {
  const a = !!(hisGD.tables && hisGD.tables[t]);
  const b = !!(ourGD.tables && ourGD.tables[t]);
  console.log('    ' + t.padEnd(18) + '他的3.3: ' + (a ? '有' : '—').padEnd(4) + ' 我们V3.6: ' + (b ? '有' : '—'));
}
console.log('\n  我们那条线的修复在他 3.3 里：');
for (const [label, marker] of [['加照片协议 animpicture_add_pic', 'animpicture_add_pic'],
  ['动态照片 layers 兜底 withLayers', 'withLayers'],
  ['存储券数量主动推送', '存储券的持有数必须主动推给客户端'],
  ['老档邮件归一化 normalizeMails', 'normalizeMails'],
  ['老档真图片 id realPictureId', 'realPictureId'],
  ['行李槽位只扣一次账', 'debitPackedSlotsOnce'],
  ['商店翻页夹取（客户端）', 'V35-PAGING-FIX']]) {
  console.log('    ' + label.padEnd(34) + (hisSrc.indexOf(marker) >= 0 ? '有' : '—'));
}
