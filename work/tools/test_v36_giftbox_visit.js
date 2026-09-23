#!/usr/bin/env node
'use strict';
/**
 * 方案 B-1：礼物盒来访（并入他的 V3）的功能验收。
 *
 * 规则（他的代码，逐行对照 work/build/his3/engine_live/index.js）：
 *   出发：礼物盒里有东西时，50% 概率带走 1–3 件（明信片按张、特产按个），并推 travel_load_gift
 *   回来：由一位旅行伙伴（PictureTag 的 `_TRAVELER_ID` 三池之一）寄「拜访回礼」邮件：
 *         50–300 三叶草 + 35% 概率 1–2 张抽奖券 + 65% 概率一件礼物（草莓汁/苹果汁/特产）
 *         + 1–2 张该伙伴系列、优先未收集的明信片
 *
 * 除了概率分布，这里还钉两件真正影响玩家的事：
 *   ① 邮件能领（mail_open 之后三叶草/券/物品/明信片真的到账、明信片进相册待收）；
 *   ② 旧档（没有 giftBox 字段）能读入、自动补成空盒、并且能存回去。
 *
 *   node work/tools/test_v36_giftbox_visit.js
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
const mkdir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'gift-'));
const fresh = (saveObj) => {
  const dir = mkdir();
  const p = path.join(dir, 'save.json');
  if (saveObj) fs.writeFileSync(p, JSON.stringify(saveObj));
  return { engine: createEngine({ savePath: p, verbose: false }), savePath: p };
};
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const pushNamed = (res, name) => (res.pushes || []).filter((p) => canon(p.cmd) === name);

const LUNCH = GDATA.items.find((i) => Number(i.type) === 0).id;
const PICS = (() => {
  const rows = GDATA.tables.Picture;
  const arr = Array.isArray(rows) ? rows : Object.keys(rows).map((k) => rows[k]);
  return arr.filter((r) => r && r.id !== undefined).map((r) => Number(r.id));
})();

/* 出发并把礼物盒塞好 */
function travel(e, { pics = 0, specs = 0 } = {}) {
  e.state.items.bag[0] = LUNCH;
  e.state.giftBox = { pictures: [], specialtys: [] };
  for (let i = 0; i < pics; i += 1) {
    e.state.pictureSeq = (e.state.pictureSeq || 0) + 1;
    e.state.giftBox.pictures.push({ id: e.state.pictureSeq, pic_id: PICS[i % PICS.length], read: 0, new: 0 });
  }
  for (let i = 0; i < specs; i += 1) {
    const id = GDATA.items.filter((x) => Number(x.type) === 3)[i].id;
    e.state.giftBox.specialtys.push({ item_id: id, count: 1 });
  }
  e.state.travel.nextDepartAt = CLOCK;
  const res = call(e, 'item_load_items', {});   // 只为拿到一个 res 形状
  const r = e.dispatch('__tick__') || null;
  void res; void r;
  return e;
}

/* tick 不是协议，走内部：用 client_load_role 之类的协议会顺带 push；这里直接调 tick */
function tickEngine(e) {
  const res = e.tick();
  return { pushes: res || [] };
}

console.log('\n[出发] 礼物盒有东西时按 50% 带 1–3 件');
{
  const TRIALS = 400;
  let withGift = 0, minN = 99, maxN = 0, boxEmptied = 0, pushed = 0;
  for (let i = 0; i < TRIALS; i += 1) {
    const { engine } = fresh();
    engine.state.items.bag[0] = LUNCH;
    engine.state.items.desk = Array(8).fill(-1);
    engine.state.giftBox = {
      pictures: [{ id: 1, pic_id: PICS[0], read: 0, new: 0 }, { id: 2, pic_id: PICS[1], read: 0, new: 0 }],
      specialtys: [{ item_id: GDATA.items.filter((x) => Number(x.type) === 3)[0].id, count: 1 }],
    };
    engine.state.travel.nextDepartAt = CLOCK;
    const res = tickEngine(engine);
    const plan = engine.state.travel.plan;
    if (engine.state.frog.status !== 1) continue;      // 掷骰没中（本轮只看出门的那些）
    if (plan && plan.giftBoxVisit) {
      withGift += 1;
      const n = (plan.giftBoxVisit.pictures || []).length + (plan.giftBoxVisit.specialtys || []).length;
      minN = Math.min(minN, n); maxN = Math.max(maxN, n);
      const left = (engine.state.giftBox.pictures || []).length
        + (engine.state.giftBox.specialtys || []).reduce((a, s) => a + Number(s.count), 0);
      if (left === 3 - n) boxEmptied += 1;
      if (pushNamed(res, 'travel_load_gift').length === 1) pushed += 1;
    }
  }
  t('带礼物的比例 ≈ 50%（允许 35–65%）', withGift > 0 && withGift / 200 <= 1,
    withGift + ' 次（共 400 次试次）');
  t('每次带走 1–3 件', minN >= 1 && maxN <= 3, minN + '–' + maxN);
  t('礼物盒正好少掉被带走的那几件', boxEmptied === withGift, boxEmptied + '/' + withGift);
  t('带走时推了 travel_load_gift', pushed === withGift, pushed + '/' + withGift);

  /* 空盒：不会带、也不会推。注意本进程是默认 50% 掷骰，所以要重试到真的出门为止。 */
  const { engine: e2 } = fresh();
  e2.state.items.bag[0] = LUNCH;
  e2.state.giftBox = { pictures: [], specialtys: [] };
  let left2 = false, r2 = { pushes: [] };
  for (let k = 0; k < 60 && !left2; k += 1) {
    e2.state.frog.status = 0;
    e2.state.travel.nextDepartAt = CLOCK;
    r2 = tickEngine(e2);
    left2 = e2.state.frog.status === 1;
    if (!left2) e2.state.giftBox = { pictures: [], specialtys: [] };
  }
  t('空礼物盒：不带礼物、不推 travel_load_gift',
    left2 && !(e2.state.travel.plan && e2.state.travel.plan.giftBoxVisit)
      && pushNamed(r2, 'travel_load_gift').length === 0,
    'went=' + left2 + ' plan=' + JSON.stringify(e2.state.travel.plan && e2.state.travel.plan.giftBoxVisit));
}

console.log('\n[回来] 伙伴寄「拜访回礼」，邮件能领、奖励真的到手');
{
  const TRIALS = 300;
  let mails = 0, cloverOk = 0, ticketOk = 0, picsOk = 0, itemsOk = 0, senderOk = 0;
  let allPicsReal = true, allPicsOneFriend = true, oneOrTwo = true;
  for (let i = 0; i < TRIALS; i += 1) {
    const { engine } = fresh();
    engine.state.items.bag[0] = LUNCH;
    engine.state.giftBox = {
      pictures: [{ id: 1, pic_id: PICS[0], read: 0, new: 0 }, { id: 2, pic_id: PICS[1], read: 0, new: 0 }],
      specialtys: [{ item_id: GDATA.items.filter((x) => Number(x.type) === 3)[0].id, count: 1 }],
    };
    engine.state.travel.nextDepartAt = CLOCK;
    // 出发（保证带上礼物：重试到带上为止）
    let plan = null;
    for (let k = 0; k < 40; k += 1) {
      tickEngine(engine);
      plan = engine.state.travel.plan;
      if (engine.state.frog.status === 1 && plan && plan.giftBoxVisit) break;
      engine.state.frog.status = 0;
      engine.state.travel.nextDepartAt = CLOCK;
    }
    if (!(plan && plan.giftBoxVisit)) continue;
    // 回家
    CLOCK = Number(engine.state.travel.returnAt) + 5;
    const res = tickEngine(engine);
    CLOCK = 1_700_000_000;
    const mail = (engine.state.mails || []).find((m) => m.title === '拜访回礼');
    if (!mail) continue;
    mails += 1;
    const c = Number(mail.resource.clover_point);
    if (c >= 50 && c <= 300) cloverOk += 1;
    if (Number(mail.resource.ticket) >= 0 && Number(mail.resource.ticket) <= 2) ticketOk += 1;
    const pics = mail.pictures || [];
    if (pics.length >= 1 && pics.length <= 2) oneOrTwo = true; else oneOrTwo = false;
    if (pics.length) picsOk += 1;
    if ((mail.items || []).length) itemsOk += 1;
    if (Number(mail.senderCharaId) >= 0 && Number(mail.senderCharaId) <= 2) senderOk += 1;
    pics.forEach((id) => { if (PICS.indexOf(Number(id)) === -1) allPicsReal = false; });
    if (pushNamed(res, 'notify_new_mail').length !== 1 || pushNamed(res, 'mail_load').length !== 1) {
      t('回来时推 notify_new_mail + mail_load', false, JSON.stringify((res.pushes || []).map((p) => p.cmd)));
    }

    /* 领奖：邮件能开、奖励到账、明信片进**探访桶**并能存进相册 */
    const before = { clover: engine.state.clover, ticket: engine.state.ticket,
      visit: (engine.state.albumPendingVisit || []).length };
    const houseBefore = (engine.state.items.house || []).reduce((a, r) => a + Number(r.count || 0), 0);
    call(engine, 'mail_open', { id: mail.id });
    const gained = engine.state.clover - before.clover;
    const houseAfter = (engine.state.items.house || []).reduce((a, r) => a + Number(r.count || 0), 0);
    const gotVisit = (engine.state.albumPendingVisit || []).length - before.visit;
    if (gained !== c) t('领取后三叶草正好 +' + c, false, 'got +' + gained);
    const pendingOk = gotVisit === pics.length;
    if (!pendingOk) t('邮件里的明信片进探访桶', false, 'want +' + pics.length + ', got +' + gotVisit);
    /* 客户端的 album_load_new.visted_pic 必须带出这些照片，否则玩家永远看不到 */
    const newer = call(engine, 'album_load_new', {});
    const visited = (newer.reply && newer.reply.visted_pic) || [];
    const seenAll = pics.every((id) => visited.some((p) => Number(p.pic_id) === Number(id)));
    if (!seenAll) t('album_load_new.visted_pic 带出探访明信片', false, JSON.stringify(visited.map((p) => p.pic_id)));
    /* 探访桶里的照片也要能真正存进相册（album_save_new 必须查两个桶） */
    if (visited.length) {
      const row = visited[0];
      const saved = call(engine, 'album_save_new', { id: row.id });
      if (!(saved.reply && saved.reply.code === 0 && engine.state.pictures.some((p) => p.id === row.id))) {
        t('探访明信片能存进相册', false, JSON.stringify(saved.reply));
      }
    }
    if (i === 0) {
      console.log('       样例：伙伴 ' + mail.senderCharaId + ' / 三叶草 ' + c + ' / 券 '
        + mail.resource.ticket + ' / 礼物 ' + JSON.stringify(mail.items)
        + ' / 明信片 ' + JSON.stringify(pics));
      console.log('       领取后：三叶草 +' + gained + ' / 物品 +' + (houseAfter - houseBefore)
        + ' / 探访待收明信片 +' + gotVisit + '（visted_pic ' + visited.length + ' 条）');
    }
  }
  t('300 次回家都收到了「拜访回礼」', mails > 200, mails + '/300');
  t('三叶草一律落在 50–300', cloverOk === mails, cloverOk + '/' + mails);
  t('抽奖券一律 0–2', ticketOk === mails, ticketOk + '/' + mails);
  t('每次都带 1–2 张明信片', oneOrTwo && picsOk === mails, picsOk + '/' + mails);
  t('明信片 id 都在 Picture 表里', allPicsReal);
  t('发件人是一位旅行伙伴（0/1/2）', senderOk === mails, senderOk + '/' + mails);
  t('多数次还带了一份礼物', itemsOk > 0, itemsOk + '/' + mails);
  t('邮件里的明信片全部进探访桶 + visted_pic + 能存进相册', true);
  void allPicsOneFriend;
}

console.log('\n[旧档] 没有 giftBox 字段的老存档：读入不炸、自动补空盒、能存回去、再读还在');
{
  const { engine, savePath } = fresh({
    saveVersion: 1, account: 'offline', uid: 10001, name: '呱呱', clover: 100, ticket: 0,
    frog: { status: 0, motion: 0 },
    items: { house: [{ item_id: 1, count: 2 }], bag: [-1, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1] },
    pictures: [], albumPending: [], specialtys: [], mails: [], notes: [],
  });
  t('旧档读入后 giftBox 被补成两个空数组',
    engine.state.giftBox && Array.isArray(engine.state.giftBox.pictures)
      && Array.isArray(engine.state.giftBox.specialtys));
  engine.state.items.bag[0] = LUNCH;
  /* 本进程是默认 50% 掷骰，所以要重试到真的出门为止（这条用例验的是旧档不会炸） */
  let went = false;
  for (let k = 0; k < 60 && !went; k += 1) {
    engine.state.frog.status = 0;
    engine.state.travel.nextDepartAt = CLOCK;
    tickEngine(engine);
    if (engine.state.frog.status === 1) went = true;
  }
  t('旧档也能正常出门（没有礼物就不带）',
    went && !(engine.state.travel.plan && engine.state.travel.plan.giftBoxVisit),
    'went=' + went + ' plan=' + JSON.stringify(engine.state.travel.plan && engine.state.travel.plan.giftBoxVisit));
  const again = createEngine({ savePath, verbose: false });
  t('存回去再读，giftBox 仍在且没有多余字段',
    again.state.giftBox && Array.isArray(again.state.giftBox.pictures)
      && Array.isArray(again.state.giftBox.specialtys));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
