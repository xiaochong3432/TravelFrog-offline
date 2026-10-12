#!/usr/bin/env node
'use strict';
/**
 * V3.7 系统 8：花盆星级速度 + 花期生命周期 + 花瓶自动更换（并入他 3.3）
 *
 *   node work/tools/v37_flower_vase_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const DAY = 86400;

let CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const fresh = () => createEngine({
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'fv-')), 'save.json'), verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const potOf = (e) => call(e, 'furniture_load_flowerpot', {}).reply;

console.log('\n[1] 土地越肥长得越快（星级 1/2/3 -> 1/2/3 倍速）');
{
  const e = fresh();
  e.tick();
  const base = potOf(e).plant_list;
  t('默认（0 星）按基础时长种下', base.every((p) => {
    const slot = e.state.flowerpot.slots[p.index - 1];
    return Number(slot.stageSec) === Number(process.env.FROG_PLANT_STAGE_SEC || 259200);
  }), JSON.stringify(e.state.flowerpot.slots));
  /* 3 星：清空一个槽，重新种下应当是 1/3 时长 */
  e.state.furniture.compost.fertility = 80;
  e.state.flowerpot.slots[0] = { id: 0, stage: 0, plantedAt: 0 };
  const after = potOf(e).plant_list;
  const slot3 = e.state.flowerpot.slots[after[0].index - 1];
  eq(Number(slot3.stageSec), Math.round(259200 / 3), '3 星 -> 基础时长的 1/3');
  eq(Number(slot3.fertility), 3, '槽位记下了肥力星级');
  /* 按 1/3 时长推进到第二/第三形态 */
  CLOCK += Math.round(259200 / 3);
  potOf(e);                       // 花盆的推进发生在取载荷时（我们的实现）
  eq(Number(e.state.flowerpot.slots[0].stage), 2, '过一个阶段 -> 形态 2');
  CLOCK += Math.round(259200 / 3) * 2;
  potOf(e);
  eq(Number(e.state.flowerpot.slots[0].stage), 3, '再过两个阶段 -> 形态 3（可收）');
  CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
}

console.log('\n[2] 访客离开时补种（他的触发），土不够肥就不种');
{
  const e = fresh();
  e.tick();
  potOf(e);                       // 先建出槽位
  /* 先收掉 1 号槽，让它空着 */
  e.state.flowerpot.slots[0].stage = 3;
  call(e, 'furniture_flowerpot_harvest', { type: 1, index: 1 });
  eq(Number(e.state.flowerpot.slots[0].id), 0, '1 号槽已空');
  /* 土不够肥：访客走了也不种 */
  e.state.furniture.compost.fertility = 0;
  e.state.guest = { id: 1, confirmed: true, served: false, pos: 0, startAt: CLOCK, expire_time: CLOCK - 1 };
  e.tick();
  eq(Number(e.state.flowerpot.slots[0].id), 0, '0 星时不种（空着）');
  /* 1 星：访客走了补种 */
  e.state.furniture.compost.fertility = 20;
  e.state.guest = { id: 1, confirmed: true, served: false, pos: 0, startAt: CLOCK, expire_time: CLOCK - 1 };
  e.tick();
  const slot = e.state.flowerpot.slots[0];
  t('1 星时访客离开补种了一株', Number(slot.id) > 0, JSON.stringify(slot));
  t('补种的槽位标记为访客种下', slot.seededByGuest === true, JSON.stringify(slot));
  eq(Number(slot.stageSec), 259200, '1 星 -> 基础时长（259200 秒（3 天））');
}

console.log('\n[3] 花期生命周期：野草 2 天/蜡梅 5 天/栽培 6 天，到点枯萎撤下');
{
  const e = fresh();
  e.tick();
  e.state.decoration.hasList = [{ id: 1001, num: 1 }, { id: 111, num: 1 }];
  e.state.decoration.putId = 1001;
  e.state.decoration.status = 1;
  e.state.decoration.startedAt = CLOCK - Math.floor(1.5 * DAY);
  eq(Number(call(e, 'client_load_decorate', {}).reply.status), 2, '野草第 2 天转形态');
  e.state.decoration.startedAt = CLOCK - Math.floor(2.5 * DAY);
  const wilting = call(e, 'client_load_decorate', {}).reply;
  eq(Number(wilting.put_id), 0, '野草 2 天后枯萎撤下');
  t('枯萎的那件从库存里扣掉了',
    !(e.state.decoration.hasList || []).some((x) => Number(x.id) === 1001),
    JSON.stringify(e.state.decoration.hasList));
  /* 栽培花 6 天寿命、5 天转形态 */
  e.state.decoration.putId = 10011;
  e.state.decoration.status = 1;
  e.state.decoration.startedAt = CLOCK - Math.floor(4.5 * DAY);
  eq(Number(call(e, 'client_load_decorate', {}).reply.status), 1, '栽培花第 4.5 天还在第一形态');
  e.state.decoration.startedAt = CLOCK - Math.floor(5.5 * DAY);
  eq(Number(call(e, 'client_load_decorate', {}).reply.status), 2, '第 5.5 天转第二形态');
  e.state.decoration.startedAt = CLOCK - Math.floor(6.5 * DAY);
  eq(Number(call(e, 'client_load_decorate', {}).reply.put_id), 0, '第 6.5 天枯萎');
}

console.log('\n[4] 花瓶每 24 小时掷一次：35% 概率换成另一件已拥有的花');
{
  const realRandom = Math.random;
  const e = fresh();
  e.tick();
  /* 用 decoration 表里真实存在的 id（10011/10012 是栽培花）。 */
  e.state.decoration.hasList = [{ id: 10011, num: 1 }, { id: 10012, num: 1 }];
  e.state.decoration.putId = 10011;
  e.state.decoration.nextAutoChangeAt = CLOCK - 1;
  const before = Number(e.state.decoration.putId);
  Math.random = () => 0.9;                      // 90 >= 35 -> 不换
  const pushes1 = e.tick();
  eq(Number(e.state.decoration.putId), before, '随机没中时不换');
  /* 没中时不换花。（第一次 tick 时 status 会从 0 -> 1"花刚摆上"，那本身会推一次载荷，
     所以这里只断言"没换"：载荷里的 put_id 仍是原来那件。） */
  const decoPush = pushes1.find((p) => String(p.cmd).indexOf('decorate') >= 0);
  t('没中时不换花（推送里的 put_id 仍是原来那件）',
    !decoPush || Number(decoPush.data.put_id) === before,
    JSON.stringify(decoPush && decoPush.data));
  e.state.decoration.nextAutoChangeAt = CLOCK - 1;
  Math.random = () => 0.0;                      // 0 < 35 -> 换
  const pushes2 = e.tick();
  t('随机中了就换成另一件', Number(e.state.decoration.putId) !== before,
    before + ' -> ' + e.state.decoration.putId);
  eq(Number(e.state.decoration.autoChangeCount), 1, '记了一次自动更换');
  t('换了之后推了 client_load_decorate',
    pushes2.some((p) => String(p.cmd).indexOf('decorate') >= 0), JSON.stringify(pushes2.map((p) => p.cmd)));
  Math.random = realRandom;
}

console.log('\n[5] 老档兼容（没有 startedAt / nextAutoChangeAt 的 V3.5/V3.6 档）');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fv-old-'));
  const p = path.join(dir, 'save.json');
  const seed = fresh();
  seed.tick();
  const raw = JSON.parse(JSON.stringify(seed.exportSave()));
  raw.decoration = { hasList: [{ id: 10011, num: 1 }], putId: 10011, status: 2 };   // 老档：第二形态、无时间
  delete raw.decoration.startedAt;
  delete raw.decoration.nextAutoChangeAt;
  raw.saveVersion = 1;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e = createEngine({ savePath: p, verbose: false });
  e.tick();
  const pl = call(e, 'client_load_decorate', {}).reply;
  eq(Number(pl.put_id), 10011, '老档摆着的花没被直接判死');
  eq(Number(pl.status), 2, '第二形态保留');
  t('补上了 startedAt', Number(e.state.decoration.startedAt) > 0);
  t('补上了 nextAutoChangeAt', Number(e.state.decoration.nextAutoChangeAt) > 0);
  const again = JSON.parse(JSON.stringify(e.exportSave()));
  eq(Number(again.decoration.putId), 10011, '存回再读一致');
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
