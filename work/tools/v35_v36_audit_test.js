#!/usr/bin/env node
'use strict';
/**
 * 「V3.6 相比 V3.5 没有新增 bug」的命令级审计。
 *
 * 做法：同一份新档、同一串命令（顺序一致）、同一个**可复现的随机数序列**，分别喂给
 * V3.5 与 V3.6，逐条比对：
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
if (!require('fs').existsSync(require('path').join(__dirname, '..', 'build', 'v35_engine', 'index.js'))) {
  console.log('  SKIP  历史引擎 work/build/v35_engine/index.js 不存在（需自备历史版本引擎）');
  process.exit(0);
}
const V35 = path.join(ROOT, 'work', 'build', 'v35_engine', 'index.js');
const V36 = path.join(ROOT, 'work', 'run', 'engine', 'index.js');

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
  'tick',                       // 时间驱动：节奏/自动换家具/自动开工都在这里
  'travel',                     // 出门/回家/礼物盒来访
  'animpicture',                // 与本次无关，但 randInt 序列不同会波及奖励
  'furniture_load_furniture',   // 载荷里 mood / bench_lock 变了
  'client_load_role',           // 角色载荷里含 travel 状态
  'notify_new_mail', 'mail_load', 'mail_open',
  'album_load_new',
];
const EXPECTED_STATE = ['mood', 'benchLock', 'nextAuto', 'prepared', 'travel', 'giftBox'];

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
  const e = load(V35, p);
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

console.log('\n=== V3.5 vs V3.6 命令级审计（同一新档 / 同一随机序列）===');
const base = run(V35, 'v35');
const next = run(V36, 'v36');

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
  const a = load(V35, copyOf('ctrl35'));
  const b = load(V36, copyOf('ctrl36'));
  const f35 = a.dispatch('furniture_load_furniture', {}).reply;
  const f36 = b.dispatch('furniture_load_furniture', {}).reply;
  t('家具载荷 mood：V3.5 恒为 0、V3.6 为心情档位',
    Number(f35.mood) === 0 && Number(f36.mood) >= 1 && Number(f36.mood) <= 5,
    'V3.5=' + f35.mood + ' V3.6=' + f36.mood);

  a.tick(); b.tick();
  const w35 = Number(a.state.travel.nextDepartAt) - CLOCK;
  const w36 = Number(b.state.travel.nextDepartAt) - CLOCK;
  t('在家等待：V3.5 分钟级、V3.6 小时级',
    w35 > 0 && w35 <= 6 * 60 && w36 >= 3 * 3600 - 1 && w36 <= 5 * 3600 + 1,
    'V3.5=' + Math.round(w35 / 60) + ' 分钟 / V3.6=' + (w36 / 3600).toFixed(2) + ' 小时');
  const m35 = Number(a.state.frog.motionNextAt) - CLOCK;
  const m36 = Number(b.state.frog.motionNextAt) - CLOCK;
  t('在家动作间隔：V3.5 45 秒、V3.6 10 分钟',
    m35 === 45 && m36 === 600, 'V3.5=' + m35 + 's / V3.6=' + m36 + 's');
  const src35 = fs.readFileSync(V35, 'utf8');
  const src36 = fs.readFileSync(V36, 'utf8');
  t('出行概率开关只在 V3.6', /FROG_TRAVEL_CHANCE/.test(src36) && !/FROG_TRAVEL_CHANCE/.test(src35));
  t('礼物盒来访只在 V3.6', /GIFTBOX_VISIT_CHANCE/.test(src36) && !/GIFTBOX_VISIT_CHANCE/.test(src35));
  t('家具心情只在 V3.6', /moodStress/.test(src36) && !/moodStress/.test(src35));
  t('开局行李只在 V3.6', /STARTER_LUNCH_IDS/.test(src36) && !/STARTER_LUNCH_IDS/.test(src35));
  t('邮件兑现明信片只在 V3.6（queuePostcardPictures）',
    /queuePostcardPictures/.test(src36) && !/queuePostcardPictures/.test(src35));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
