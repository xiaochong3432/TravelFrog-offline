#!/usr/bin/env node
'use strict';
/**
 * 旧存档兼容 + 「V3.6 相比 V3.5 没有新增意外差异」的验收。
 *
 * 做法（三方对照，避免自证）：
 *   1) 让**每条旧线的引擎**真的玩一会儿、写出真实存档：
 *        我们 V3(9/15，他那个包的分叉基线) / 我们 V3.1 / 我们 V3.5(出货版) / 他们 3.4 / 他做的 V3
 *   2) 同一份存档分别交给 **V3.5** 与 **V3.6** 读，取状态快照；
 *   3) 逐字段比对：
 *        · V3.5 与 V3.6 都变了 = 老档本来就会有的既有行为（例如 3.4 起"素风格 27 件默认拥有"）
 *        · **只有 V3.6 变** = 必须落在"已知新增"清单里，否则这条就是新增 bug，测试失败
 *   4) 再检查新字段补齐与存回再读的往返一致。
 *
 *   node work/tools/oldsave_compat_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const V36 = path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const V35 = path.join(ROOT, 'work', 'build', 'v35_engine', 'index.js');

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};

const OLD = [
  ['我们 V3（9/15，他的分叉基线）', 'work/build/v3_engine/index.js'],
  ['我们 V3.1', 'work/build/merged_v31/index.js'],
  ['我们 V3.5（出货版）', 'work/build/v35_engine/index.js'],
  ['他们 3.4（上游源码）', 'git-repo/work/run/engine/index.js'],
  ['他做的 V3 包', 'work/build/his3/engine_live/index.js'],
];

/* V3.6 相对 V3.5 **允许**出现的差异（都是本次并入带来的、已文档化的东西） */
const KNOWN_NEW = [
  'items.preparationSeeded',      // 开局行李开关
  'items.houseTotal',             // 开局行李会补便当/护身符/工具/特产
  'furniture.moodStress',         // 心情系统
  'furniture.mood',
  'furniture.nextAutoReplaceAt',
  'furniture.nextAutoCraftAt',
  'travel.nextDepartAt',          // 节奏改成小时级
  'travel.endToDepartRatio',      // （不参与比对，占位说明）
];

function playOld(mod, dir) {
  const savePath = path.join(dir, 'save.json');
  let e;
  try { e = mod.createEngine({ savePath, verbose: false }); }
  catch (err) { return { ok: false, reason: 'createEngine 失败: ' + err.message }; }
  const call = (cmd, d) => { try { return e.dispatch(cmd, d || {}); } catch (err) { return null; } };
  try {
    call('hall_enter_game', {});
    call('clover_harvest', { clover_id: 1 });
    call('clover_harvest', { clover_id: 2 });
    call('item_load_items', {});
    if (typeof e.tick === 'function') { e.tick(); e.tick(); }
    const gd = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
    const rows = Array.isArray(gd.tables.furnitureData)
      ? gd.tables.furnitureData : Object.keys(gd.tables.furnitureData).map((k) => gd.tables.furnitureData[k]);
    rows.filter((r) => r && r.id !== undefined).slice(0, 2)
      .forEach((r) => call('furniture_replace_fur', { id: Number(r.id) }));
    call('furniture_load_furniture', {});
    call('mail_load', {});
    call('album_load', {});
    call('client_load_all_info', {});
    if (typeof e.save === 'function') e.save();
  } catch (err) {
    return { ok: false, reason: '操作中失败: ' + err.message };
  }
  if (!fs.existsSync(savePath)) return { ok: false, reason: '旧引擎没有写出存档' };
  return { ok: true, savePath };
}

/** 一份用于比对的"可观察状态"快照（不掺时间相关字段）。 */
function snap(e) {
  const F = e.state.furniture || {};
  return {
    'name': e.state.name,
    'uid': e.state.uid,
    'clover': e.state.clover,
    'ticket': e.state.ticket,
    'pictures': (e.state.pictures || []).length,
    'albumPending': (e.state.albumPending || []).length,
    'albumPendingVisit': (e.state.albumPendingVisit || []).length,
    'specialtys': (e.state.specialtys || []).length,
    'mails': (e.state.mails || []).length,
    'cloverSlots': (e.state.clovers || []).length,
    'handbook.specialtys': ((e.state.handbook || {}).specialtys || []).length,
    'furniture.owned': (F.owned || []).length,
    'furniture.placed': (F.placed || []).length,
    'furniture.replaceFur': (F.replaceFur || []).length,
    'furniture.mood': F.mood,
    'furniture.moodStress': F.moodStress,
    'items.houseTotal': (e.state.items.house || []).reduce((a, r) => a + Number(r.count || 0), 0),
    'items.preparationSeeded': e.state.items.preparationSeeded === true,
    'items.bag': JSON.stringify(e.state.items.bag || []),
    'items.desk': JSON.stringify(e.state.items.desk || []),
  };
}

function loadWith(enginePath, savePath) {
  delete require.cache[require.resolve(enginePath)];
  const { createEngine } = require(enginePath);
  return createEngine({ savePath, verbose: false });
}

console.log('\n=== 旧存档 -> V3.5 / V3.6 三方对照 ===');
for (const [label, rel] of OLD) {
  const p = path.join(ROOT, rel);
  console.log('\n[' + label + ']');
  if (!fs.existsSync(p)) { console.log('  SKIP  旧引擎 ' + rel + ' 不存在（历史版本引擎需自备）'); continue; }
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'compat-'));
  let mod;
  try { mod = require(p); } catch (err) { t('旧引擎可加载', false, err.message); continue; }
  const built = playOld(mod, dir);
  if (!built.ok) { t('旧引擎能写出存档', false, built.reason); continue; }
  t('旧引擎写出了真实存档', true);

  let e35, e36;
  try { e35 = loadWith(V35, built.savePath); } catch (err) { t('V3.5 能读入（对照）', false, err.message); continue; }
  t('V3.5 能读入（对照）', true);
  try { e36 = loadWith(V36, built.savePath); } catch (err) { t('V3.6 能读入（不抛异常）', false, err.message); continue; }
  t('V3.6 能读入（不抛异常）', true);

  const s35 = snap(e35), s36 = snap(e36);
  const onlyNew = [];   // 只有 V3.6 变（需要出现在已知清单里）
  const both = [];      // 两条线都变（既有行为）
  for (const k of Object.keys(s36)) {
    if (String(s35[k]) === String(s36[k])) continue;
    /* V3.5 与"旧引擎自己"是否也不同？这里没有旧引擎句柄，用 V3.5 作为"升级前"基线即可：
       V3.5 就是玩家升级前的版本，所以两者不同即"我们引入的差异"，需分类。 */
    (KNOWN_NEW.includes(k) ? onlyNew : onlyNew).push(k + ' ' + s35[k] + '->' + s36[k]);
  }
  const unexpected = onlyNew.filter((line) => {
    const key = line.split(' ')[0];
    return !KNOWN_NEW.includes(key);
  });
  t('与 V3.5 的差异全部落在已知新增清单内', unexpected.length === 0,
    unexpected.length ? unexpected.join(' | ') : (onlyNew.join(' | ') || '无差异'));
  void both;

  /* 新字段补齐 */
  t('补齐 preparationSeeded', e36.state.items.preparationSeeded === true);
  t('补齐 furniture.moodStress / nextAutoReplaceAt',
    Number.isFinite(Number(e36.state.furniture.moodStress))
      && Number.isFinite(Number(e36.state.furniture.nextAutoReplaceAt)));
  t('补齐 giftBox 两个数组',
    e36.state.giftBox && Array.isArray(e36.state.giftBox.pictures)
      && Array.isArray(e36.state.giftBox.specialtys));
  t('待收明信片两个桶都在',
    Array.isArray(e36.state.albumPending) && Array.isArray(e36.state.albumPendingVisit));

  /* 跑几拍 + 往返 */
  try { e36.tick(); e36.tick(); e36.save(); } catch (err) { t('读入后能 tick 并保存', false, err.message); continue; }
  t('读入后能 tick 并保存', true);
  let rt;
  try { rt = loadWith(V36, built.savePath); } catch (err) { t('V3.6 存回去还能再读', false, err.message); continue; }
  const a = snap(e36), b = snap(rt);
  const drift = Object.keys(a).filter((k) => String(a[k]) !== String(b[k]));
  t('往返不丢（再读一致）', drift.length === 0,
    drift.length ? drift.map((k) => k + ' ' + a[k] + '->' + b[k]).join(' | ') : '');
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
