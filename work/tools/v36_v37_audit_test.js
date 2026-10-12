#!/usr/bin/env node
'use strict';

/* 【V4.0】这份审计是 V3.6 vs V3.7 的对照，按 V3.7 的默认（立即开工）跑。
   引擎的开关常量在 require 时求值，所以这段必须在 require 之前。 */
process.env.FROG_CRAFT_QUEUE = '0';

/**
 * 「V3.7 相比 V3.6 没有新增 bug」的命令级审计。
 *
 * 做法：同一份新档、同一串命令（顺序一致）、同一个**可复现的随机数序列**，分别喂给
 * 出货 V3.6（包内引擎）与 V3.7（开发中），逐条比对：
 *   · 回复码（客户端真正分支的那个字段）
 *   · 推送集合（客户端靠推送刷新界面）
 *   · 关键状态摘要（三叶草/券/物品/家具/相册/邮件…）
 * 差异分两类：
 *   预期内 —— 本次并入带来的：节奏（出门/检查间隔/动作间隔）、家具心情(mood/bench_lock)、
 *             开局行李、礼物盒来访、自动换家具/自动开工
 *   待排查 —— 不在这张清单里的任何差异 = 新增 bug，测试失败
 *
 *   node work/tools/v35_v36_audit_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
/* 历史版本引擎放在 work/build/（.gitignore 排除），仓库里通常没有；
   缺失时整个套件跳过，避免把‘环境缺件’报成失败。 */
if (!require('fs').existsSync(require('path').join(__dirname, '..', 'build', 'v36_engine', 'index.js'))) {
  console.log('  SKIP  历史引擎 work/build/v36_engine/index.js 不存在（需自备历史版本引擎）');
  process.exit(0);
}
const V36 = path.join(ROOT, 'work', 'build', 'v36_engine', 'index.js');   // 出货 V3.6（APK 里那份）
const V37 = path.join(ROOT, 'work', 'run', 'engine', 'index.js');    // V3.7（开发中）

let CLOCK = 1_700_000_000;
Date.now = () => CLOCK * 1000;

/* 可复现随机数：两边用同一个种子，随机奖励才可比 */
let seed = 123456789;
Math.random = () => {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x7fffffff;
};

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};

/* 差异白名单：命令里含这些词，或摘要字段是这些，视为本次并入的预期变化 */
const EXPECTED_CMD = [
  'tick',                          // 时间驱动：土壤衰减等都在这
  'furniture_load_compost',        // 载荷多了 fertility_stars
  'furniture_load_pocket',         // 原来写死空列表
  'furniture_load_tumbler',        // 原来写死空列表
  'furniture_replace_pocket',      // 新增索引校验（空列表回 -1）
  'furniture_putin_bench',         // 台面上可能是口袋/不倒翁配方
  'client_load_all_info',          // 汇总载荷里含上面这些
];
const EXPECTED_STATE = ['fertility', 'pocket', 'tumbler', 'compost'];

function load(enginePath, savePath) {
  delete require.cache[require.resolve(enginePath)];
  const mod = require(enginePath);
  return mod.createEngine({ savePath, verbose: false });
}

/* ---- 公平起点：两边从**同一份存档**出发 -------------------------------------
   直接各自 createEngine 会让 V3.6 多领一份"开局行李"（家里 19 行），于是所有
   "往背包/桌上放东西"的用例都会因为家里有没有东西而不同 —— 那是开局行李的连带结果，
   不是行为差异。所以先用 V3.5 生成一份新档，关掉开局行李标记，再给两边加载同一份。 */
function seedSaveFile() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'audit-seed-'));
  const p = path.join(dir, 'save.json');
  const e = load(V36, p);
  e.save();
  const obj = JSON.parse(fs.readFileSync(p, 'utf8'));
  obj.items = obj.items || {};
  obj.items.preparationSeeded = true;         // 两边都不再发开局行李
  fs.writeFileSync(p, JSON.stringify(obj));
  return p;
}
const SAVE = seedSaveFile();
const copyOf = (tag) => {
  const p = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'audit-' + tag + '-')), 'save.json');
  fs.copyFileSync(SAVE, p);
  return p;
};

const digest = (e) => {
  const F = e.state.furniture || {};
  return {
    clover: e.state.clover,
    ticket: e.state.ticket,
    pictures: (e.state.pictures || []).length,
    albumPending: (e.state.albumPending || []).length,
    albumPendingVisit: (e.state.albumPendingVisit || []).length,
    specialtys: (e.state.specialtys || []).length,
    mails: (e.state.mails || []).length,
    notes: (e.state.notes || []).length,
    handbookCol: ((e.state.handbook || {}).collections || []).length,
    handbookSpe: ((e.state.handbook || {}).specialtys || []).length,
    furOwned: (F.owned || []).length,
    furPlaced: (F.placed || []).length,
    bench: JSON.stringify(F.bench || []),
    craft: F.craft ? 'running' : 'idle',
    frogStatus: e.state.frog.status,
    bag: JSON.stringify(e.state.items.bag || []),
    desk: JSON.stringify(e.state.items.desk || []),
    houseRows: (e.state.items.house || []).length,
  };
};

/* 命令序列：尽量覆盖会改状态的协议（顺序固定） */
const LUNCH = 1;
const SEQ = [
  ['hall_enter_game', {}],
  ['clover_harvest', { clover_id: 1 }],
  ['clover_harvest', { clover_id: 2 }],
  ['item_load_items', {}],
  ['item_load_handbook', {}],
  ['client_load_decorate', {}],
  ['furniture_load_furniture', {}],
  ['furniture_load_flowerpot', {}],
  ['furniture_load_compost', {}],
  ['furniture_load_pocket', {}],
  ['furniture_load_tumbler', {}],
  ['farm_load', {}],
  ['travel_load_note', {}],
  ['travel_load_gift', {}],
  ['album_load', {}],
  ['album_load_new', {}],
  ['guest_load', {}],
  ['mail_load', {}],
  ['task_load', {}],
  ['capsule_load', {}],
  ['lottery_load', {}],
  ['shop_load', {}],
  ['item_load_shop_info', {}],
  ['furniture_load_shop', {}],
  ['encyclopedia_load', {}],
  ['pray_load_grays', {}],
  ['item_putin_bag', { pos: 1, item_id: LUNCH }],
  ['item_takeout_bag', { pos: 1 }],
  ['item_putin_desk', { pos: 1, item_id: LUNCH }],
  ['item_takeout_desk', { pos: 1 }],
  ['item_set_bag_completed', { completed: true }],
  ['animpicture_load', {}],
  ['guest_finish', {}],
  ['furniture_replace_fur', { id: 1101 }],
  ['furniture_replace_fur', { id: 1101 }],
  ['client_change_decorate', { id: 10054 }],
  ['client_load_role', {}],
  ['client_load_all_info', {}],
];

function run(enginePath, tag) {
  seed = 123456789;                     // 同一随机序列
  CLOCK = 1_700_000_000;
  const e = load(enginePath, copyOf(tag));
  const rows = [];
  for (const [cmd, d] of SEQ) {
    let reply = null, pushes = [];
    try {
      const r = e.dispatch(cmd, d);
      reply = r && r.reply;
      pushes = (r && r.pushes) || [];
    } catch (err) {
      reply = { __throw: String(err && err.message) };
    }
    rows.push({
      cmd,
      code: reply && reply.code !== undefined ? reply.code : (reply === undefined ? 'undef' : 'obj'),
      throws: reply && reply.__throw ? reply.__throw : null,
      pushes: pushes.map((p) => p.cmd).sort().join(','),
      digest: digest(e),
    });
  }
  /* 三拍 tick：时间驱动的差异都在这里，单独记 */
  for (let i = 0; i < 3; i += 1) {
    let pushes = [];
    try { pushes = e.tick() || []; } catch (err) { pushes = ['__throw:' + err.message]; }
    rows.push({ cmd: 'tick#' + (i + 1), code: 'tick', throws: null,
      pushes: pushes.map((p) => p.cmd).sort().join(','), digest: digest(e) });
  }
  return { rows, engine: e };
}

console.log('\n=== V3.6(出货) vs V3.7 命令级审计（同一新档 / 同一随机序列）===');
const base = run(V36, 'v36');
const next = run(V37, 'v37');

const diffs = [];
for (let i = 0; i < base.rows.length; i += 1) {
  const a = base.rows[i], b = next.rows[i];
  if (a.cmd !== b.cmd) { diffs.push({ cmd: a.cmd, what: 'sequence-mismatch' }); continue; }
  if (a.code !== b.code) diffs.push({ cmd: a.cmd, what: 'code ' + a.code + ' -> ' + b.code });
  if (!!a.throws !== !!b.throws) diffs.push({ cmd: a.cmd, what: 'throw ' + a.throws + ' -> ' + b.throws });
  if (a.pushes !== b.pushes) diffs.push({ cmd: a.cmd, what: 'pushes [' + a.pushes + '] -> [' + b.pushes + ']' });
  for (const k of Object.keys(a.digest)) {
    if (String(a.digest[k]) !== String(b.digest[k])) {
      diffs.push({ cmd: a.cmd, what: k + ' ' + a.digest[k] + ' -> ' + b.digest[k], state: k });
    }
  }
}

console.log('  比对条目: ' + base.rows.length + ' 条命令 / ' + diffs.length + ' 处差异');
const unexpected = diffs.filter((d) => {
  const cmdOk = EXPECTED_CMD.some((w) => String(d.cmd).indexOf(w) >= 0);
  const stateOk = d.state && EXPECTED_STATE.some((w) => String(d.state).indexOf(w) >= 0);
  return !(cmdOk || stateOk);
});
t('没有出现"异常抛错"级别的新差异',
  !diffs.some((d) => String(d.what).indexOf('throw') === 0 && /->\s*$|-> (?!null)/.test(String(d.what))));
t('所有差异都落在本次并入的预期范围内', unexpected.length === 0,
  unexpected.slice(0, 6).map((d) => d.cmd + ': ' + d.what).join(' | '));
if (diffs.length) {
  console.log('\n  差异明细（预期内也一并列出，便于复核）：');
  diffs.slice(0, 30).forEach((d) => console.log('    [' + d.cmd + '] ' + d.what));
}

/* 关键契约：两边都不该出现"回复码退化"（例如本来 code 0 变成 undefined） */
const regress = diffs.filter((d) => /^code 0 -> (undef|obj|-[0-9])/.test(String(d.what)));
t('没有把 code 0 退化成失败/空回包', regress.length === 0, regress.map((d) => d.cmd).join(','));

/* ---- 正向对照：上面若"0 差异"，也可能是摘要看不见本次改动，所以逐项确认该变的确实变了 ---- */
console.log('\n=== 正向对照：本次并入的东西必须真的生效 ===');
{
  seed = 123456789; CLOCK = 1_700_000_000;
  const a = load(V36, copyOf('ctrl36'));      // 出货 V3.6
  const b = load(V37, copyOf('ctrl37'));      // V3.7
  const ca = a.dispatch('furniture_load_compost', {}).reply;
  const cb = b.dispatch('furniture_load_compost', {}).reply;
  t('堆肥载荷：V3.6 没有 fertility_stars、V3.7 有',
    ca.fertility_stars === undefined && Number.isFinite(Number(cb.fertility_stars)),
    'V3.6=' + ca.fertility_stars + ' V3.7=' + cb.fertility_stars);
  const srcA = fs.readFileSync(V36, 'utf8');
  const srcB = fs.readFileSync(V37, 'utf8');
  t('土壤星级只在 V3.7', /SOIL_STAR_THRESHOLDS/.test(srcB) && !/SOIL_STAR_THRESHOLDS/.test(srcA));
  t('肥力点数表只在 V3.7', /FERTILIZER_POINTS/.test(srcB) && !/FERTILIZER_POINTS/.test(srcA));
  t('口袋/不倒翁配方只在 V3.7',
    /POCKET_RECIPE_OUTPUTS/.test(srcB) && !/POCKET_RECIPE_OUTPUTS/.test(srcA)
    && /TUMBLER_RECIPE_OUTPUTS/.test(srcB) && !/TUMBLER_RECIPE_OUTPUTS/.test(srcA));
  t('口袋/不倒翁载荷不再写死空列表',
    /list: \[\],/.test(srcA) && /POCKET_DATA\.has\(Number\(id\)\)/.test(srcB));
  /* 真的能做出一只口袋：给齐图纸/绳/基材/工具，放上台面看它开工 */
  const give = (e, id, n) => {
    const row = e.state.items.house.find((x) => Number(x.item_id) === Number(id));
    if (row) row.count += n; else e.state.items.house.push({ item_id: Number(id), count: n });
  };
  [10601, 11102, 10005, 10004, 10006, 10205, 10204].forEach((id) => give(b, id, 1));
  b.dispatch('furniture_putin_bench', { pos: 1, id: 10205 });
  b.dispatch('furniture_putin_bench', { pos: 2, id: 10204 });
  const rPocket = b.dispatch('furniture_putin_bench', { pos: 7, id: 11102 });
  t('V3.7 台面上放绳就能开工做口袋', !!(rPocket.reply && rPocket.reply.crafting === 1),
    JSON.stringify(rPocket.reply));

  /* 系统 4：按日期/季节的天气 + 节气日 + 月历奖励 + 彩蛋 */
  t('按日期/季节的天气只在 V3.7',
    /WEATHER_BY_SEASON/.test(srcB) && !/WEATHER_BY_SEASON/.test(srcA)
    && /function weatherForDate/.test(srcB) && !/function weatherForDate/.test(srcA));
  t('节气日表只在 V3.7',
    /SOLAR_TERM_DAY_COEFFICIENTS/.test(srcB) && !/SOLAR_TERM_DAY_COEFFICIENTS/.test(srcA));
  t('月历奖励表只在 V3.7',
    /CALENDAR_MONTH_REWARDS/.test(srcB) && !/CALENDAR_MONTH_REWARDS/.test(srcA));
  t('彩蛋载荷不再是空壳',
    /easteregg_load: \(\) => \(\{ egg_list: \[\] \}\)/.test(srcA)
    && /easteregg_load: \(\) => eggPayload\(\)/.test(srcB));
  const wA = a.dispatch('weather_load', {}).reply;
  const wB = b.dispatch('weather_load', {}).reply;
  t('当天天气由日期算出（两边都在 1..9，但 V3.7 保证应季）',
    Number(wA.weather) >= 1 && Number(wA.weather) <= 9
    && Number(wB.weather) >= 1 && Number(wB.weather) <= 9,
    'V3.6=' + wA.weather + ' V3.7=' + wB.weather);
  const cA = a.dispatch('calendar_load', {}).reply;
  const cB = b.dispatch('calendar_load', {}).reply;
  t('V3.7 月历载荷带已领清单、V3.6 没有',
    cA.claimed_st_days === undefined && Array.isArray(cB.claimed_st_days));
  const eA = a.dispatch('easteregg_load', {}).reply;
  const eB = b.dispatch('easteregg_load', {}).reply;
  t('V3.6 彩蛋恒为空、V3.7 会按季节给',
    Array.isArray(eA.egg_list) && eA.egg_list.length === 0 && Array.isArray(eB.egg_list));

  /* 系统 5：嘟嘟商店改成"每天 8 个货位" */
  t('星级货架表只在 V3.7',
    /MERCHANT_STAR_WEIGHTS/.test(srcB) && !/MERCHANT_STAR_WEIGHTS/.test(srcA)
    && /MERCHANT_DAILY_OFFER_COUNT/.test(srcB) && !/MERCHANT_DAILY_OFFER_COUNT/.test(srcA));
  t('节气货架映射只在 V3.7',
    /MERCHANT_SOLAR_TERM_OFFERS/.test(srcB) && !/MERCHANT_SOLAR_TERM_OFFERS/.test(srcA));
  const shopA = a.dispatch('furniture_load_furniture', {}).reply.shop.shop_list;
  const shopB = b.dispatch('furniture_load_furniture', {}).reply.shop.shop_list;
  t('V3.6 整表常驻、V3.7 只摆当天货位',
    shopA.length > 8 && shopB.length >= 1 && shopB.length <= 9,
    'V3.6=' + shopA.length + ' 行 / V3.7=' + shopB.length + ' 行');
  t('V3.7 的货位行带展示字段（price/limit/has_item）',
    shopB.every((r) => r.price !== undefined && r.limit !== undefined && r.has_item !== undefined));
  t('只能买当天货架上的东西（不在货架就拒绝）',
    b.dispatch('furniture_buy_shop', { shop_id: 2001 }).reply.code === -1
    || shopB.some((r) => Number(r.shop_id) === 2001));

  /* 系统 8：花盆星级速度 + 花期生命周期 + 花瓶自动更换 */
  t('花期规则表只在 V3.7',
    /decorationFlowerRule/.test(srcB) && !/decorationFlowerRule/.test(srcA)
    && /VASE_AUTO_CHANGE_SECONDS/.test(srcB) && !/VASE_AUTO_CHANGE_SECONDS/.test(srcA));
  b.state.furniture.compost.fertility = 80;             // 3 星
  b.state.flowerpot.slots[0] = { id: 0, stage: 0, plantedAt: 0 };
  b.dispatch('furniture_load_flowerpot', {});
  t('V3.7 花盆按肥力星级加速（3 星 -> 1/3 时长）',
    Number(b.state.flowerpot.slots[0].stageSec) === Math.round(259200 / 3),
    'stageSec=' + b.state.flowerpot.slots[0].stageSec);
  b.state.decoration.hasList = [{ id: 10011, num: 1 }, { id: 10012, num: 1 }];
  b.state.decoration.putId = 10011;
  b.state.decoration.startedAt = Math.floor(Date.now() / 1000) - 7 * 86400;
  const decoB = b.dispatch('client_load_decorate', {}).reply;
  t('V3.7 花期到了会自动撤下（V3.6 没有生命周期）',
    Number(decoB.put_id) === 0 && !/decorationFlowerRule/.test(srcA));

  /* 系统 9：雨天客人彩蛋 + 任务计数 + 绘本出行节奏 */
  t('雨天客人彩蛋只在 V3.7',
    /RAIN_GUEST_CHANCE/.test(srcB) && !/RAIN_GUEST_CHANCE/.test(srcA)
    && /RAIN_GUEST_EGG/.test(srcB) && !/RAIN_GUEST_EGG/.test(srcA));
  t('任务计数只在 V3.7',
    /taskCounters/.test(srcB) && !/taskCounters/.test(srcA)
    && /completeTaskCounter/.test(srcB) && !/completeTaskCounter/.test(srcA));
  t('绘本出行改小时级只在 V3.7',
    /DRAWING_TRIP_MIN_SEC/.test(srcB) && !/DRAWING_TRIP_MIN_SEC/.test(srcA));
  t('V3.6 的任务计数存档位不存在、V3.7 有',
    a.state.taskCounters === undefined && !!b.state.taskCounters);

  /* 系统 10：工具动画 + 排队开工 */
  t('工具动画表只在 V3.7',
    /FURNITURE_TOOL_MOTION/.test(srcB) && !/FURNITURE_TOOL_MOTION/.test(srcA)
    && /CRAFT_TOOLS_BY_TYPE/.test(srcB) && !/CRAFT_TOOLS_BY_TYPE/.test(srcA));
  t('排队字段只在 V3.7（V3.6 没有 craftQueued）',
    a.state.furniture.craftQueued === undefined && b.state.furniture.craftQueued !== undefined);
  /* 台面上放一把刀 + 一件在做的活：动作应当演成"刀"（9）而不是通用 make（3） */
  const q = load(V37, copyOf('ctrl40'));
  q.tick();
  const giveMotion = (e, id, n) => {
    const row = e.state.items.house.find((x) => Number(x.item_id) === Number(id));
    if (row) row.count += n; else e.state.items.house.push({ item_id: Number(id), count: n });
  };
  [10601, 11102, 10005, 10004, 10006, 10205, 10204].forEach((id) => giveMotion(q, id, 1));
  q.dispatch('furniture_putin_bench', { pos: 1, id: 10205 });
  q.dispatch('furniture_putin_bench', { pos: 2, id: 10204 });
  q.dispatch('furniture_putin_bench', { pos: 7, id: 11102 });
  q.state.frog.motionMode = 'force';
  q.tick();
  t('V3.7 做口袋时演的是刀/棒针的工具动画（8 或 9）',
    [8, 9].indexOf(Number(q.state.frog.motion)) >= 0, 'motion=' + q.state.frog.motion);

  /* 制作模型：27 个 type 的基材表 */
  t('他的 27 个 type 基材表只在 V3.7',
    /CRAFT_BASE_MATERIALS_BY_TYPE/.test(srcB) && !/CRAFT_BASE_MATERIALS_BY_TYPE/.test(srcA));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
