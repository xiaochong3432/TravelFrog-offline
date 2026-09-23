#!/usr/bin/env node
'use strict';
/**
 * 方案 B 收尾三项的验收（并入他的 V3）：
 *   ① 手工品阶段时长：祈愿物 86 分钟/阶段、印章 129 分钟/阶段（我们原来 90 秒）
 *   ② 客人回礼增强：三叶草夹到 50–300、按喜好两档概率发【特产/博物馆门票/花种】、35% 追加抽奖券
 *   ③ 旅行中寄明信片：出发时掷好这趟奖励，行程 25–75% 处先把一张"没收集过"的照片寄回家
 *
 *   node work/tools/test_v36_hours_extras.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine, canon } = require(ENGINE);
const GDATA = require(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'));

let CLOCK = 1_700_000_000;
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const fresh = () => createEngine({
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'ex-')), 'save.json'), verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const pushNamed = (res, name) => (res.pushes || []).filter((p) => canon(p.cmd) === name);
const LUNCH = GDATA.items.find((i) => Number(i.type) === 0).id;

console.log('\n[① 阶段时长] 他的 86/129 分钟（env 可覆盖）');
{
  const e = fresh();
  /* 手工工具是开工前提；材料也备上，让 advanceCraft 自己开新活 */
  e.state.items.house.push({ item_id: 7000, count: 1 });
  e.state.items.house.push({ item_id: 8000, count: 5 });
  e.tick();
  const c = e.state.craft || {};
  const wish = (c.wishes || []).find((w) => Number(w.state) === 1);
  const stamp = (c.stamps || []).find((s) => Number(s.state) === 1);
  t('祈愿物阶段 = 86 分钟', !!wish && Math.round((Number(wish.make_time) - CLOCK) / 60) === 86,
    wish ? Math.round((Number(wish.make_time) - CLOCK) / 60) + ' 分钟' : '没开出祈愿物');
  t('印章阶段 = 129 分钟', !!stamp && Math.round((Number(stamp.time) - CLOCK) / 60) === 129,
    stamp ? Math.round((Number(stamp.time) - CLOCK) / 60) + ' 分钟' : '没开出印章');
  const src = fs.readFileSync(ENGINE, 'utf8');
  t('两个 env 开关在源码里（可回到 90 秒）',
    /FROG_CRAFT_WISH_STAGE_SEC \|\| 86 \* 60/.test(src) && /FROG_CRAFT_STAMP_STAGE_SEC \|\| 129 \* 60/.test(src));
  t('木片仍是 270 秒（WOOD_PIECE_SEC = 3×90）', /const WOOD_PIECE_SEC = CRAFT_STAGE_SEC \* 3;/.test(src));
}

console.log('\n[② 客人回礼] 三叶草 50–300 + 奖池 + 35% 额外券');
{
  const ROW_IDS = ((GDATA.tables.Character || {}).rowItemId || []).map(Number);
  const ranges = { clover: 0, ticket: 0, items: 0, mail: 0, fourLeaf: 0 };
  let allInRange = true, anyItem = false, anyTicket = false;
  const TRIALS = 80;
  for (let i = 0; i < TRIALS; i += 1) {
    const e = fresh();
    const now = CLOCK;
    e.state.guest = { id: 1, confirmed: true, served: false, pos: 0, startAt: now, expire_time: now + 1200 };
    /* 挑一个它很喜欢的特产（taste >= 80），喂完再把停留推到过期 */
    const taste = GDATA.tables.Character.data[1].taste;
    let idx = -1;
    for (let k = 0; k < taste.length; k += 1) if (taste[k] >= 80) { idx = k; break; }
    if (idx < 0) idx = 0;
    const itemId = ROW_IDS[idx];
    const row = e.state.items.house.find((x) => Number(x.item_id) === Number(itemId));
    if (row) row.count += 1; else e.state.items.house.push({ item_id: itemId, count: 1 });
    call(e, 'guest_serve', { id: 1, item_id: itemId });
    e.state.guest.expire_time = CLOCK - 1;
    e.tick();
    const mail = (e.state.mails || []).find((m) => m.title === '小伙伴的回礼');
    if (!mail) continue;
    ranges.mail += 1;
    const c = Number(mail.resource.clover_point);
    if (!(c === 0 || (c >= 50 && c <= 300))) { allInRange = false; if (ranges.clover < 3) console.log('       越界样例:', c); }
    if (c === 0) ranges.fourLeaf += 1;
    ranges.clover += c;
    ranges.ticket += Number(mail.resource.ticket) || 0;
    if (Number(mail.resource.ticket) > 0) anyTicket = true;
    if ((mail.items || []).length) { anyItem = true; ranges.items += 1; }
  }
  t('每次都有回礼邮件', ranges.mail >= TRIALS - 5, ranges.mail + '/' + TRIALS);
  /* 抽到「四叶草」那一档时三叶草本来就是 0（3.4 的既有规则：要么三叶草、要么一个四叶草；
     他的引擎同样如此），夹取只作用于三叶草分支。 */
  t('三叶草为 0（四叶草档）或落在 50–300', allInRange,
    '四叶草档 ' + ranges.fourLeaf + ' 次 / 三叶草平均 ' + Math.round(ranges.clover / Math.max(1, ranges.mail)));
  t('会出现额外奖品（特产/门票/花种）', anyItem, ranges.items + ' 封带物品');
  t('会出现额外抽奖券（35% 概率，80 次里应出现）', anyTicket, '累计 ' + ranges.ticket + ' 张');
}

console.log('\n[③ 旅行中寄明信片] 出发掷好奖励、中段先寄一张、回家不重复');
{
  /* 找一趟"有没收集过的照片"的行程（随机，所以多试几次） */
  let e = null, res = null;
  for (let k = 0; k < 60 && !e; k += 1) {
    const cand = fresh();
    cand.state.items.bag[0] = LUNCH;
    for (let n = 0; n < 40; n += 1) {
      cand.state.frog.status = 0;
      cand.state.items.bag[0] = LUNCH;
      cand.state.travel.nextDepartAt = CLOCK;
      cand.tick();
      if (cand.state.frog.status === 1) break;
    }
    if ((cand.state.travel.postcardPics || []).length) { e = cand; res = null; }
  }
  t('出发时就把这趟奖励掷好（travel.rewards）', !!e && !!e.state.travel.rewards,
    e ? Object.keys(e.state.travel.rewards || {}).join(',') : '60 次都没遇到带新照片的行程');
  if (e) {
    const pics = e.state.travel.postcardPics || [];
    const dur = Number(e.state.travel.returnAt) - Number(e.state.travel.departAt);
    const at = Number(e.state.travel.postcardAt) - Number(e.state.travel.departAt);
    t('寄件时刻落在行程 25%–75% 之间',
      at >= Math.floor(dur * 0.25) - 1 && at <= Math.floor(dur * 0.75) + 1,
      Math.round(100 * at / dur) + '% of ' + Math.round(dur / 60) + ' 分钟');
    const before = e.state.albumPending.length;
    CLOCK = Number(e.state.travel.postcardAt) + 1;
    res = e.tick();
    t('中段真的寄回来了（入待收 + 推 album_load_new）',
      e.state.travel.postcardSent === true && e.state.albumPending.length > before
        && pushNamed({ pushes: res }, 'album_load_new').length === 1,
      'pending ' + before + '->' + e.state.albumPending.length);
    /* 回家：中段寄过的那几张不再重复入待收 */
    const pendingMid = e.state.albumPending.length;
    CLOCK = Number(e.state.travel.returnAt) + 5;
    e.tick();
    CLOCK = 1_700_000_000;
    const dup = pics.filter((id) => e.state.albumPending
      .filter((p) => Number(p.pic_id) === Number(id)).length > 1);
    t('回家不重复发中段寄过的那几张', dup.length === 0,
      '待收 ' + pendingMid + '->' + e.state.albumPending.length + (dup.length ? ' 重复 ' + JSON.stringify(dup) : ''));
    t('回家后寄件状态被清掉（下一趟重新算）',
      !e.state.travel.postcardAt && (e.state.travel.postcardPics || []).length === 0
        && e.state.travel.postcardSent === false && e.state.travel.rewards === null);
  }
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
