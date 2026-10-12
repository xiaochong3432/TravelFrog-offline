#!/usr/bin/env node
'use strict';
/**
 * V3.7 系统 9：雨天客人彩蛋 + 任务计数 + 绘本出行节奏（并入他 3.3）
 *
 *   node work/tools/v37_rain_tasks_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);
const HOUR = 3600;

let CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const fresh = () => createEngine({
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'rt-')), 'save.json'), verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});

console.log('\n[1] 雨天来的客人有 30% 概率带"雨天装扮"彩蛋');
{
  const realRandom = Math.random;
  const e = fresh();
  e.tick();
  e.state.weather.weather = 3;                 // 雨
  e.state.guestNextRollAt = CLOCK;             // 马上摇一次
  e.state.guestCoolUntil = 0;
  Math.random = () => 0.0;                     // 摇中 + 30% 命中
  e.tick();
  const guest = e.state.guest;
  t('摇来了一位客人', !!guest, JSON.stringify(guest));
  t('客人带上了雨天彩蛋', [102, 103, 104].indexOf(Number(guest && guest.rainEgg)) >= 0,
    JSON.stringify(guest && guest.rainEgg));
  t('彩蛋出现在 easteregg_load 里',
    call(e, 'easteregg_load', {}).reply.egg_list.indexOf(Number(guest.rainEgg)) >= 0,
    JSON.stringify(call(e, 'easteregg_load', {}).reply));
  /* 同样的雨天，但随机没命中 -> 不带 */
  const e2 = fresh();
  e2.tick();
  e2.state.weather.weather = 3;
  e2.state.guestNextRollAt = CLOCK;
  e2.state.guestCoolUntil = 0;
  Math.random = () => 0.9;                     // 0.9 >= 0.30 -> 不命中
  e2.tick();
  t('随机没中就不带雨天彩蛋', !(e2.state.guest && e2.state.guest.rainEgg),
    JSON.stringify(e2.state.guest && e2.state.guest.rainEgg));
  /* 非雨天也不会带：挑一个当天天气不是 3/4 的日子（tick 会按日期刷新天气，
     所以直接改 state.weather 会被覆盖）。 */
  const { weatherForDate } = require(ENGINE);
  let day = 11;
  while ([3, 4].indexOf(Number(weatherForDate(2026, 7, day).weather)) >= 0 && day < 28) day += 1;
  const nonRain = Math.floor(new Date(2026, 6, day, 14).getTime() / 1000);
  const e3 = fresh();
  CLOCK = nonRain;
  e3.tick();
  e3.state.guestNextRollAt = CLOCK;
  e3.state.guestCoolUntil = 0;
  Math.random = () => 0.0;
  e3.tick();
  t('非雨天客人不带雨天彩蛋（' + day + ' 日天气 ' + weatherForDate(2026, 7, day).weather + '）',
    !(e3.state.guest && e3.state.guest.rainEgg),
    JSON.stringify(e3.state.guest && e3.state.guest.rainEgg));
  CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
  Math.random = realRandom;
}

console.log('\n[2] 任务计数（月历奖励 -> 任务 407 记一次）');
{
  const e = fresh();
  e.tick();
  t('state.taskCounters 存在', e.state.taskCounters && typeof e.state.taskCounters === 'object');
  t('state.taskTiers 存在', e.state.taskTiers && typeof e.state.taskTiers === 'object');
  eq(Number(e.state.taskCounters['407'] || 0), 0, '开局 407 计数为 0');
  call(e, 'calendar_get_st_reward', {});
  eq(Number(e.state.taskCounters['407']), 1, '领当日奖励后 407 记 1');
  /* 同一天再领（被拒）不该再加 */
  call(e, 'calendar_get_st_reward', {});
  eq(Number(e.state.taskCounters['407']), 1, '重复领取不会重复计数');
  /* 第二天再领仍然是 1（他只在不足 1 时记） */
  CLOCK += 86400;
  e.tick();
  call(e, 'calendar_get_st_reward', {});
  eq(Number(e.state.taskCounters['407']), 1, '第二天领奖不把计数累加（与他的 completeTaskCounter 一致）');
  CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
}

console.log('\n[3] 绘本（友情邀约）出行改成 4–8 小时，回来歇 1 小时、冷却 8 小时');
{
  const e = fresh();
  e.tick();
  e.state.drawing.state = 4;                    // visit（伙伴出门中）
  e.state.drawingReturnAt = 0;
  e.tick();
  const trip = Number(e.state.drawingReturnAt) - CLOCK;
  t('出门时长落在 4–8 小时', trip >= 4 * HOUR && trip <= 8 * HOUR,
    Math.round(trip / 60) + ' 分钟');
  /* 时间走到回程之后 */
  CLOCK = Number(e.state.drawingReturnAt) + 1;
  e.tick();
  eq(Number(e.state.drawing.state), 0, '回来后回到待机');
  t('回来先在家歇 1 小时',
    Math.abs(Number(e.state.drawingRestUntil) - CLOCK - HOUR) <= 2,
    'rest=' + (Number(e.state.drawingRestUntil) - CLOCK) + 's');
  t('之后按 8 小时冷却再摇',
    Math.abs(Number(e.state.drawingNextRollAt) - CLOCK - 8 * HOUR) <= 2,
    'next=' + Math.round((Number(e.state.drawingNextRollAt) - CLOCK) / 3600) + ' 小时');
  CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
}

console.log('\n[4] 老档兼容（没有 taskCounters / taskTiers 的 V3.5/V3.6 档）');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'rt-old-'));
  const p = path.join(dir, 'save.json');
  const seed = fresh();
  seed.tick();
  const raw = JSON.parse(JSON.stringify(seed.exportSave()));
  delete raw.taskCounters;
  delete raw.taskTiers;
  raw.saveVersion = 1;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e = createEngine({ savePath: p, verbose: false });
  e.tick();
  t('taskCounters 补成空对象', e.state.taskCounters && typeof e.state.taskCounters === 'object');
  t('taskTiers 补成空对象', e.state.taskTiers && typeof e.state.taskTiers === 'object');
  const again = JSON.parse(JSON.stringify(e.exportSave()));
  t('存回再读仍在', again.taskCounters && again.taskTiers);
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
