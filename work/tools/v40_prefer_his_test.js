#!/usr/bin/env node
'use strict';
/**
 * V4.0：**默认翻成他 3.3 的做法**的那 7+1 项，逐项验证「新默认」与「回退开关」。
 *
 * 每项都用"清掉相关 env + 重新 require"来取默认值（引擎开关是 require 时求值的）。
 *
 *   node work/tools/v40_prefer_his_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const SRC = fs.readFileSync(ENGINE, 'utf8');

const FLIP_ENVS = ['FROG_SHOP_WINDOW', 'FROG_SHOP_KEEP_SOLD_OUT', 'FROG_CRAFT_QUEUE',
  'FROG_WISH_WORKCLOCK', 'FROG_HANDCRAFT_GATE', 'FROG_COMPOST_SEC',
  'FROG_DRAWING_CHANCE', 'FROG_CRAFT_STRICT_SPECIAL'];

let CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);

/** 清掉所有翻转开关（= V4.0 默认），可选再叠加 env，然后重新 require。 */
const mk = (env) => {
  for (const k of FLIP_ENVS) delete process.env[k];
  if (env) Object.assign(process.env, env);
  delete require.cache[require.resolve(ENGINE)];
  const mod = require(ENGINE);
  const e = mod.createEngine({
    savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'v40-')), 'save.json'), verbose: false,
  });
  for (const k of FLIP_ENVS) delete process.env[k];
  return e;
};
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const give = (e, id, n) => {
  const row = e.state.items.house.find((r) => Number(r.item_id) === Number(id));
  if (row) row.count += n; else e.state.items.house.push({ item_id: Number(id), count: n });
};

console.log('\n[1] 商店营业窗口：默认 = 他的 12:00 后到 / 21:00 走');
{
  const e = mk();
  e.tick();
  const shop = call(e, 'furniture_load_furniture', {}).reply.shop;
  const start = new Date(Number(shop.start_time) * 1000);
  const leave = new Date(Number(shop.leave_time) * 1000);
  t('默认到店时间在 12:00–18:59', start.getHours() >= 12 && start.getHours() <= 18,
    start.toLocaleString());
  eq(leave.getHours(), 21, '默认 21:00 收摊');
  eq(leave.getMinutes(), 0, '整点收摊');
  /* 注意：merchantShop() 是**调用时**读 FROG_SHOP_WINDOW 的，而 mk() 会清 env，
     所以要在 mk() 之后再设。 */
  const e2 = mk();
  process.env.FROG_SHOP_WINDOW = 'always';
  e2.tick();
  const shop2 = call(e2, 'furniture_load_furniture', {}).reply.shop;
  delete process.env.FROG_SHOP_WINDOW;
  t('FROG_SHOP_WINDOW=always 回退成常开（覆盖全天）',
    Number(shop2.leave_time) - Number(shop2.start_time) >= 12 * 3600,
    (Number(shop2.leave_time) - Number(shop2.start_time)) / 3600 + ' 小时');
}

console.log('\n[2] 售罄行：默认 = 他的（售罄就不列）；FROG_SHOP_KEEP_SOLD_OUT=1 回退');
{
  /* 直接模拟"这一格当天已经买光"（写 shopDailyBought），这样与随机 uid 决定的营业窗口无关。 */
  const buyOut = (e) => {
    e.tick();
    const row = call(e, 'furniture_load_furniture', {}).reply.shop.shop_list
      .find((r) => Number(r.num) > 0 && Number(r.type) !== 998);
    if (!row) return null;
    const stock = Number(e.state.furniture.shopOffers[row.shop_id]) || 1;
    e.state.furniture.shopDailyBought = { [row.shop_id]: stock };
    return Number(row.shop_id);
  };
  const e = mk();
  const id = buyOut(e);
  const list = call(e, 'furniture_load_furniture', {}).reply.shop.shop_list;
  t('默认：买光的行不再出现在货架上',
    id != null && !list.some((r) => Number(r.shop_id) === id), 'id=' + id);
  const e2 = mk({ FROG_SHOP_KEEP_SOLD_OUT: '1' });
  const id2 = buyOut(e2);
  const list2 = call(e2, 'furniture_load_furniture', {}).reply.shop.shop_list;
  const kept = list2.find((r) => Number(r.shop_id) === id2);
  t('回退后：买光的行仍列出且 num=0', !!kept && Number(kept.num) === 0,
    JSON.stringify(kept || null));
}

console.log('\n[3] 自动开工：默认 = 他的（排队 + 等工具动作）；FROG_CRAFT_QUEUE=0 回退');
{
  const prep = (e) => {
    e.tick();
    give(e, 10601, 1); give(e, 11102, 1); give(e, 10005, 1); give(e, 10004, 1); give(e, 10006, 1);
    give(e, 10205, 1); give(e, 10204, 1);
    call(e, 'furniture_putin_bench', { pos: 1, id: 10205 });
    call(e, 'furniture_putin_bench', { pos: 2, id: 10204 });
    return call(e, 'furniture_putin_bench', { pos: 7, id: 11102 });
  };
  const e = mk();
  prep(e);
  eq(Number(e.state.furniture.craftQueued), 1, '默认：先排队');
  eq(e.state.furniture.craft, null, '默认：没有立刻开工');
  const e2 = mk({ FROG_CRAFT_QUEUE: '0' });
  prep(e2);
  t('回退后：放上台面即开工', !!e2.state.furniture.craft, JSON.stringify(e2.state.furniture.craft));
}

console.log('\n[4] 堆肥发酵：默认 = 他的（20001–3 立即 / 20004–6 三天）；FROG_COMPOST_SEC=300 回退');
{
  /* 引擎没有"放入堆肥"的协议（客户端的堆肥是买肥料自动进格子），
     所以照 v37_soil_stars_test.js 的做法：直接摆格子 + tick 起锅。 */
  const put = (e, id) => {
    e.tick();
    const c = e.state.furniture.compost;
    c.boxes = [id, 0, 0, 0, 0, 0];
    c.job = null;
    e.tick();
    return e.state.furniture.compost.job;
  };
  const job4 = put(mk(), 20004);
  t('20004 要三天', job4 && (Number(job4.finishAt) - Number(job4.startedAt)) === 3 * 86400,
    JSON.stringify(job4));
  const e1 = mk();
  const job1 = put(e1, 20001);
  const fert1 = Number(e1.state.furniture.compost.fertility);
  t('20001 立即（0 秒，或当拍就已结算 +10）',
    (job1 && (Number(job1.finishAt) - Number(job1.startedAt)) === 0) || fert1 === 10,
    'job=' + JSON.stringify(job1) + ' fertility=' + fert1);
  const jobC = put(mk({ FROG_COMPOST_SEC: '300' }), 20004);
  t('回退后统一 300 秒', jobC && (Number(jobC.finishAt) - Number(jobC.startedAt)) === 300,
    JSON.stringify(jobC));
}

console.log('\n[5] 手工品：默认 = 他的（只要在做手工就推进、不要工具材料）');
{
  const e = mk();
  e.tick();
  give(e, 7000, 1);
  give(e, 8000, 5);
  const wishId = Number(Object.keys(GD.tables.prayData || {})[0]);
  e.state.craft = e.state.craft || { wishes: [], stamps: [], pending: [], seq: 0 };
  e.state.craft.wishes = [{ id: wishId, state: 1, make_time: CLOCK - 1, u_id: 1, materialPaid: false }];
  e.state.frog.status = 0;
  e.state.frog.motionMode = 'awake';
  e.state.frog.motionNextAt = CLOCK + 600;
  e.state.frog.motion = 3;
  e.tick();
  eq(Number(e.state.craft.wishes[0].state), 2, '默认：做手工时推进');
  /* 没工具/材料也推进（他的口径） */
  const e2 = mk();
  e2.tick();
  e2.state.items.house = [];
  e2.state.craft = e2.state.craft || { wishes: [], stamps: [], pending: [], seq: 0 };
  e2.state.craft.wishes = [{ id: wishId, state: 1, make_time: CLOCK - 1, u_id: 1, materialPaid: false }];
  e2.state.frog.status = 0;
  e2.state.frog.motionMode = 'awake';
  e2.state.frog.motionNextAt = CLOCK + 600;
  e2.state.frog.motion = 3;
  e2.tick();
  eq(Number(e2.state.craft.wishes[0].state), 2, '默认：没工具没材料也推进');
  /* 回退：要工具材料 + 阶段墙钟 */
  const e3 = mk({ FROG_HANDCRAFT_GATE: '1', FROG_WISH_WORKCLOCK: '0' });
  e3.tick();
  e3.state.items.house = [];
  e3.state.craft = e3.state.craft || { wishes: [], stamps: [], pending: [], seq: 0 };
  e3.state.craft.wishes = [{ id: wishId, state: 1, make_time: CLOCK - 1, u_id: 1, materialPaid: false }];
  e3.state.frog.status = 0;
  e3.state.frog.motionMode = 'awake';
  e3.state.frog.motionNextAt = CLOCK + 600;
  e3.state.frog.motion = 2;
  e3.tick();
  eq(Number(e3.state.craft.wishes[0].state), 1, '回退后：没材料不推进（V3.7 门槛）');
}

console.log('\n[6] 邀约概率：默认 20（他的）；FROG_DRAWING_CHANCE 回退到 75');
{
  t('默认值写在引擎里是 20', /FROG_DRAWING_CHANCE \|\| 20/.test(SRC));
  t('回退开关名在引擎里', /FROG_DRAWING_CHANCE/.test(SRC));
}

console.log('\n[7] 风格特殊材料：默认仍可做（27 种）；FROG_CRAFT_STRICT_SPECIAL=1 才是他的"不可做"');
{
  const benchIds = new Set(GD.tables.benchData.map((r) => Number(r.id)));
  const rows = Object.values(GD.tables.furnitureData);
  const drawing = rows.filter((r) => benchIds.has(Number(r.id)) && Number(r.drawing) > 0)[0].drawing;
  const mats = [10001, 10002, 10003, 10004, 10005, 10006, 10007,
    10101, 10102, 10103, 10104, 10105, 10106, 10107, 10108];
  const attempt = (e) => {
    e.state.items.house = [{ item_id: Number(drawing), count: 1 }]
      .concat(mats.map((id) => ({ item_id: id, count: 5 })));
    call(e, 'furniture_putin_bench', { pos: 6, id: Number(drawing) });
    return !!e.state.furniture.craft;
  };
  const e = mk({ FROG_CRAFT_QUEUE: '0' });
  t('默认：材料齐了就能做（不受特殊材料表限制）', attempt(e));
  const e2 = mk({ FROG_CRAFT_STRICT_SPECIAL: '1', FROG_CRAFT_QUEUE: '0' });
  eq(attempt(e2), false, '启用他的严格规则后：这张图纸做不了（style 14 没有特殊材料）');
}

console.log('\n[8] 商店补行（8053/8054）在两个模式下都还在');
{
  t('引擎的星级 4 池里有 8053/8054', /8053, 8054/.test(SRC));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
