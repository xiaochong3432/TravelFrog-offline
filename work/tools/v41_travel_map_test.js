#!/usr/bin/env node
'use strict';
/**
 * V4.1 专测：旅行地图「伙伴同行 / 路遇 / 照片伙伴图层」（并入他 3.3）
 *   node work/tools/v41_travel_map_test.js
 */
const fs = require('fs'), os = require('os'), path = require('path');
const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const SRC = fs.readFileSync(ENGINE, 'utf8');
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const LAYERS = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'picture-layers.json'), 'utf8'));
const { createEngine } = require(ENGINE);

let pass = 0, fail = 0;
const t = (n, ok, extra) => { if (ok) { pass += 1; console.log('  PASS  ' + n); } else { fail += 1; console.log('  FAIL  ' + n + (extra != null ? '   ' + extra : '')); } };
const eq = (a, b, n) => t(n, a === b, 'expected ' + b + ', got ' + a);
const fresh = () => createEngine({ savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'tv-')), 'save.json'), verbose: false });
const call = (e, c, d) => e.dispatch(c, d || {});

/* 复刻引擎里 variants 的索引规则 */
const resources = GD.tables.resources || {};
const byPath = {};
Object.keys(resources).forEach((id) => { byPath[String(resources[id]).toLowerCase()] = Number(id); });
const VARIANTS = {};
Object.keys(resources).forEach((id) => {
  const src = String(resources[id]).toLowerCase();
  const m = src.match(/^(.*)_bh(_[a-z0-9]+)?$/);
  if (!m) return;
  const tail = m[2] || '';
  const v = ['bh', 'cw', 'yhc'].map((s) => byPath[m[1] + '_' + s + tail] || byPath[m[1] + '_' + s]);
  if (v.every((x) => x !== undefined)) VARIANTS[Number(id)] = v;
});

console.log('\n[1] 代码层面的并入标记');
t('引擎里有 TV_TRAVEL_FRIEND_SLOT', /TV_TRAVEL_FRIEND_SLOT/.test(SRC));
t('引擎里有 TV_COMPANION_LAYER_VARIANTS', /TV_COMPANION_LAYER_VARIANTS/.test(SRC));
t('引擎里有 tvEncounterSlot / tvTripTravelerSlot', /function tvEncounterSlot/.test(SRC) && /function tvTripTravelerSlot/.test(SRC));
t('引擎里有 pictureLayersFor / companionSlotForPicture', /function pictureLayersFor/.test(SRC) && /function companionSlotForPicture/.test(SRC));
t('走位时记录了 travelerSlot', /travelerSlot: tvEncounterSlot\(e\)/.test(SRC));
t('下发照片时套用伙伴图层', /companionSlotForPicture\(p\) >= 0 \? pictureLayersFor\(p, rec\)/.test(SRC));
t('变体表已建立（' + Object.keys(VARIANTS).length + ' 组）', Object.keys(VARIANTS).length > 0);

console.log('\n[2] 路遇概率：边的 en/ep 决定遇到谁');
{
  const edges = Object.values(GD.tables.travel ? {} : {});
  const travel = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'travel.json'), 'utf8'));
  const withEnc = Object.entries(travel.edges || {}).filter(([, e]) => e && e.en && Number(e.ep) > 0);
  t('travel.json 里有带 enc_name/enc_per 的边（' + withEnc.length + ' 条）', withEnc.length > 0,
    JSON.stringify(withEnc.slice(0, 2)));
  if (withEnc.length) {
    const names = new Set(withEnc.map(([, e]) => String(e.en).toLowerCase()));
    t('这些 en 都能映射到伙伴槽位（' + [...names].join('/') + '）',
      [...names].every((n) => ['bh', 'cw', 'yhc'].indexOf(n) >= 0));
  }
}

console.log('\n[3] 照片图层：有伙伴 -> 换成那位；没伙伴 -> 去掉该图层');
{
  /* 找一张"第一个图层是可替换伙伴图层"的照片 */
  let pick = null;
  for (const [picId, rec] of Object.entries(LAYERS)) {
    const l0 = (rec.layers || []).find((x) => x && x.role === 'bh' && x.layer && VARIANTS[Number(x.layer[0])]);
    if (l0) { pick = { picId: Number(picId), rec, l0 }; break; }
  }
  t('找到可用于验证的照片', !!pick, pick && ('pic_id=' + pick.picId));
  if (pick) {
    const e = fresh();
    e.tick();
    const rowBase = { id: 1, pic_id: pick.picId, read: 1, new: 0 };
    /* 有伙伴（槽位 2） */
    e.state.pictures = [Object.assign({}, rowBase, { travelerSlot: 2 })];
    const got = call(e, 'album_load', {}).reply;
    const list = got.pictures || got.pic_list || got.album || [];
    const row = (list || []).find((r) => Number(r.pic_id) === pick.picId) || (list || [])[0];
    const l0 = row && (row.layers || []).find((x) => x && x.role === 'bh');
    t('图层被换成第 2 位伙伴的图层', l0 && Number(l0.layer[0]) === VARIANTS[Number(pick.l0.layer[0])][2],
      JSON.stringify(l0));
    /* 没伙伴 -> 该图层被去掉 */
    e.state.pictures = [Object.assign({}, rowBase)];
    const got2 = call(e, 'album_load', {}).reply;
    const list2 = got2.pictures || got2.pic_list || got2.album || [];
    const row2 = (list2 || []).find((r) => Number(r.pic_id) === pick.picId) || (list2 || [])[0];
    /* 【V4.1 的取舍】他的实现是"没遇到伙伴就把伙伴图层去掉（独角蛙照片）"，
       但那会改变我们既有照片的画面；这里改成"没有伙伴信息时保持原图层"，
       只有行上确实记录了伙伴才替换 —— 所以断言"原图层还在"。 */
    const bh2 = (row2 && row2.layers || []).find((x) => x && x.role === 'bh');
    const bh0 = (pick.rec.layers || []).find((x) => x && x.role === 'bh');
    t('没有伙伴信息时保持原图层（不回退既有画面）',
      !!bh2 && !!bh0 && Number(bh2.layer[0]) === Number(bh0.layer[0]),
      JSON.stringify(bh2) + ' vs ' + JSON.stringify(bh0));
    /* 礼物盒好友照片：老档没有 travelerSlot 时按 PictureTag 救援 */
    const friend = Object.entries(GD.tables.PictureTag || {}).length ? null : null;
    t('礼物盒好友照片救援逻辑在引擎里', /isGiftBoxFriendPicture\(out\.pic_id\)/.test(SRC));
  }
}

console.log('\n[4] 老档兼容：没有 travelerSlot 的照片照常显示');
{
  const e = fresh();
  e.tick();
  const anyPic = Number(Object.keys(LAYERS)[0]);
  e.state.pictures = [{ id: 1, pic_id: anyPic, read: 1, new: 0 }];
  const r = call(e, 'album_load', {}).reply;
  t('相册载荷正常返回', !!r);
  const s = JSON.parse(JSON.stringify(e.exportSave()));
  t('存档里没有多余的顶层字段（travelerSlot 只在有伙伴时出现）',
    s.pictures[0].travelerSlot === undefined);
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
