#!/usr/bin/env node
'use strict';
/**
 * V3.7 系统 4：月历奖励 + 按日期/季节的天气 + 节气日 + 季节性彩蛋（并入他 3.3）
 *
 *   node work/tools/v37_calendar_eggs_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const eng = require(ENGINE);
const { createEngine, weatherForDate, solarTermDay, localDayKeyAt } = eng;

/* 固定一个时刻：2026-07-01 12:00 本地时间 */
const at = (y, m, d, h) => Math.floor(new Date(y, m - 1, d, h || 12, 0, 0, 0).getTime() / 1000);
let CLOCK = at(2026, 7, 1, 12);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const fresh = () => createEngine({
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'cal-')), 'save.json'), verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});

console.log('\n[1] 天气按日期 + 季节决定（同一天恒定、季节里只出应季天气）');
{
  t('导出里有 weatherForDate / solarTermDay / localDayKeyAt',
    typeof weatherForDate === 'function' && typeof solarTermDay === 'function'
    && typeof localDayKeyAt === 'function');
  const summer = [], winter = [];
  for (let d = 1; d <= 20; d += 1) {
    summer.push(weatherForDate(2026, 7, d));
    winter.push(weatherForDate(2026, 1, d));
  }
  t('夏天全部 season=2', summer.every((r) => r.season === 2));
  t('冬天全部 season=4', winter.every((r) => r.season === 4));
  const SUMMER_OK = [1, 2, 3, 4, 5, 7], WINTER_OK = [1, 2, 5, 6, 7, 8, 9];
  t('夏天不会下雪/打霜（不出 6/8/9）', summer.every((r) => SUMMER_OK.indexOf(r.weather) >= 0),
    JSON.stringify(summer.map((r) => r.weather)));
  t('冬天才可能下雪/打霜', winter.every((r) => WINTER_OK.indexOf(r.weather) >= 0),
    JSON.stringify(winter.map((r) => r.weather)));
  const a = weatherForDate(2026, 7, 15), b = weatherForDate(2026, 7, 15);
  eq(a.weather, b.weather, '同一天重复调用结果一致');
  t('相邻两天不一定相同（不是常数）',
    new Set([1, 2, 3, 4, 5, 6, 7, 8].map((d) => weatherForDate(2026, 7, d).weather)).size > 1);
}

console.log('\n[2] 引擎当天用的就是这套天气（重启不重掷）');
{
  const e1 = fresh();
  e1.tick();
  const w1 = call(e1, 'weather_load', {}).reply;
  const expect = weatherForDate(2026, 7, 1);
  eq(Number(w1.season), expect.season, '季节一致');
  eq(Number(w1.weather), expect.weather, '天气一致');
  const e2 = fresh();
  e2.tick();
  eq(Number(call(e2, 'weather_load', {}).reply.weather), expect.weather, '另一份新档同一天天气一致');
}

console.log('\n[3] 节气日（公历公式）');
{
  eq(solarTermDay(2026, 0), 5, '2026 小寒 = 1 月 5 日');
  eq(solarTermDay(2026, 2), 4, '2026 立春 = 2 月 4 日');
  /* 索引按 小寒/大寒/立春/雨水/惊蛰/春分/清明/谷雨/立夏/小满/… 数：
     立夏 = 8、白露 = 16。 */
  eq(solarTermDay(2026, 8), 5, '2026 立夏 = 5 月 5 日');
  eq(solarTermDay(2026, 16), 7, '2026 白露 = 9 月 7 日');
  t('越界索引返回 0', solarTermDay(2026, 99) === 0);
}

console.log('\n[4] 月历奖励（他的月历表 + 已领不再下发）');
{
  const e = fresh();
  e.tick();
  const p1 = call(e, 'calendar_load', {}).reply;
  t('载荷带 claimed_st_days / claimed_lucky_days',
    Array.isArray(p1.claimed_st_days) && Array.isArray(p1.claimed_lucky_days));
  const day1 = p1.st_days.find((r) => Number(r.day) === 1);
  eq(Number(day1.item_id), 200000, '1 号奖励是三叶草（200000）');
  eq(Number(day1.num), 30, '1 号给 30 个');
  const day2 = p1.st_days.find((r) => Number(r.day) === 2);
  eq(Number(day2.item_id), 101, '2 号奖励是物品 101（他的月历表第 2 项）');
  const before = e.state.clover;
  const r1 = call(e, 'calendar_get_st_reward', {});
  eq(r1.reply.code, 0, '领取成功');
  eq(Number(r1.reply.item_id), 200000, '回包带 item_id');
  eq(Number(r1.reply.count), 30, '回包带数量');
  eq(e.state.clover - before, 30, '三叶草 +30');
  const r2 = call(e, 'calendar_get_st_reward', {});
  eq(r2.reply.code, 0, '重复领取仍然回 0（客户端不会卡住）');
  eq(e.state.clover - before, 30, '但不会重复发');
  const p2 = call(e, 'calendar_load', {}).reply;
  t('已领的 1 号不再下发（否则重启会长红点）',
    !p2.st_days.some((r) => Number(r.day) === 1), JSON.stringify(p2.st_days.slice(0, 3)));
  t('claimed 清单里有 1', p2.claimed_st_days.indexOf(1) !== -1, JSON.stringify(p2.claimed_st_days));
}

console.log('\n[5] 换月重置');
{
  const e = fresh();
  e.tick();
  call(e, 'calendar_get_st_reward', {});
  CLOCK = at(2026, 8, 1, 12);
  e.tick();
  const p = call(e, 'calendar_load', {}).reply;
  eq(p.claimed_st_days.length, 0, '新月已领清单清空');
  /* 【V4.0】并入他 3.3 的月历模型：固定月奖励**全部**走 st_days（客户端每个格子才有图标），
     lucky_days 留给"当日活动"，没有活动时为空。
     （旧断言写的是我们 V3.6 的模型：7/14/21/28 走 lucky_days —— 已随他模型作废。） */
  eq(p.st_days.length, 31, '8 月 31 天都有奖励（每天都有图标，全部在 st_days）');
  eq(p.lucky_days.length, 0, '没有当日活动时 lucky_days 为空');
  CLOCK = at(2026, 7, 1, 12);
}

console.log('\n[6] 季节性彩蛋');
{
  const e = fresh();
  e.tick();
  /* 开局是否出彩蛋取决于动作与随机：把随机钉成 0.99（扇子 10% 与季节彩蛋都不成立），
     这样"没有彩蛋"才是确定性的断言。 */
  const realRandom = Math.random;
  Math.random = () => 0.99;
  e.state.frog.eggId = 0;
  e.state.frog.motionMode = 'force-refresh';
  CLOCK += 60;
  e.tick();
  const seasonal = call(e, 'easteregg_load', {}).reply.egg_list.filter((id) => id !== 201);
  eq(seasonal.length, 0, '把随机钉死后开局没有季节彩蛋');
  Math.random = realRandom;
  e.state.frog.eggId = 3;
  t('当前彩蛋会出现在载荷里', call(e, 'easteregg_load', {}).reply.egg_list.indexOf(3) !== -1);
  e.state.frog.eggId = 0;
  /* 夏天夜里（21:00 之后）应当是"萤火虫 201" */
  CLOCK = at(2026, 7, 15, 22);
  e.tick();
  t('夏天夜里出萤火虫 201',
    call(e, 'easteregg_load', {}).reply.egg_list.indexOf(201) !== -1,
    JSON.stringify(call(e, 'easteregg_load', {}).reply));
  CLOCK = at(2026, 1, 15, 22);
  e.tick();
  t('冬天夜里没有萤火虫',
    call(e, 'easteregg_load', {}).reply.egg_list.indexOf(201) === -1,
    JSON.stringify(call(e, 'easteregg_load', {}).reply));
  CLOCK = at(2026, 7, 1, 12);
}

console.log('\n[7] 老档兼容（没有 eggId 的 V3.5/V3.6 档）');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'cal-old-'));
  const p = path.join(dir, 'save.json');
  const seed = fresh();
  seed.tick();
  const raw = JSON.parse(JSON.stringify(seed.exportSave()));
  delete raw.frog.eggId;
  delete raw.calendar.claimedSt;
  delete raw.calendar.claimedLucky;
  raw.saveVersion = 1;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e = createEngine({ savePath: p, verbose: false });
  e.tick();
  eq(Number(e.state.frog.eggId), 0, 'eggId 补 0');
  const pl = call(e, 'calendar_load', {}).reply;
  t('claimed 清单补空数组', Array.isArray(pl.claimed_st_days) && pl.claimed_st_days.length === 0);
  const again = JSON.parse(JSON.stringify(e.exportSave()));
  eq(Number(again.frog.eggId), 0, '存回再读一致');
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
