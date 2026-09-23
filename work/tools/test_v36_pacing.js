#!/usr/bin/env node
'use strict';
/**
 * V3.6 并入「他做的 V3 包」节奏后的**默认行为**验收（独立进程运行）。
 *
 * 为什么单独一个文件：engine_test.js / engine_test_v4.js 为了让既有用例确定性，
 * 在 require 之前把 FROG_TRAVEL_CHANCE 钉成 100（到点必走）。默认是不是真的 50%、
 * 出门是不是真的小时级、开局行李是不是真的发了，只能在一个**没改环境变量**的进程里量。
 *
 * 期望值全部来自他包里的实测（work/tools/his3_pacing_measure.js 跑他引擎的输出）：
 *   在家动作间隔 600 s（10 分钟）      他的 FROG_MOTION_SEC = 10 * 60
 *   到点出门概率 50.5% / 48.3%        他的 TRAVEL_DEPART_CHANCE = 50
 *   带便当一趟 4.5–18.9 小时          他的 TRAVEL_MIN/MAX = 120..510 分钟（×便当加成）
 *   空背包一趟 10–20 分钟（放浪）      他的 DRIFT_RETURN = 表值 10/20 分钟 × 60
 *   没出门时下次检查 3–5 小时          他的 TRAVEL_IDLE/WAIT = 3..5 * 3600
 *
 *   node work/tools/test_v36_pacing.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
if (process.env.FROG_TRAVEL_CHANCE) {
  console.log('这个测试必须在**没有** FROG_TRAVEL_CHANCE 的进程里跑（当前='
    + process.env.FROG_TRAVEL_CHANCE + '）');
  process.exit(2);
}
/* FROG_ENGINE 指到别的引擎源码即可验收那个引擎（例如从出货 APK 里还原出来的那份），
   默认是我们构建用的 work/run/engine/index.js。 */
const ENGINE_PATH = process.env.FROG_ENGINE
  || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine, canon } = require(ENGINE_PATH);
const DEFINE = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'define.json'), 'utf8'));
const GDATA = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));

/* 可控时钟：引擎用 Math.floor(Date.now()/1000) 取时间 */
let CLOCK = 1_700_000_000;
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const fresh = () => createEngine({
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'pacing-')), 'save.json'),
  verbose: false,
});
const countOf = (e, id) => {
  const row = (e.state.items.house || []).find((x) => Number(x.item_id) === Number(id));
  return row ? Number(row.count) : 0;
};
const hasType = (e, type, houseOnly) => GDATA.items.some((it) => Number(it.type) === type
  && (houseOnly ? countOf(e, it.id) > 0 : true)
  && (houseOnly ? true : ((e.state.items.house || []).find((x) => Number(x.item_id) === Number(it.id))
    ? Number((e.state.items.house || []).find((x) => Number(x.item_id) === Number(it.id)).count) : 0) > 0));

/* ---------------------------------------------------------------- ① 在家动作 */
console.log('\n[① 在家动作] 他的 FROG_MOTION_SEC = 10 分钟，按 Frogpattern 组内顺序走');
{
  CLOCK = 1_700_000_000;
  const e = fresh();
  e.state.travel.nextDepartAt = CLOCK + 999999;      // 这一段只看在家动作
  e.tick();
  const iv = Number(e.state.frog.motionNextAt) - CLOCK;
  t('动作间隔 = 600 秒（10 分钟）', iv === 600, 'got ' + iv);
  const pattern = e.state.frog.motionPattern;
  const seq = (DEFINE.maps.Frogpattern || {})[String(pattern)] || [];
  const num = DEFINE.maps.FrogMotionNum || {};
  const want = [];
  let step = Number(e.state.frog.motionStep) || 0;
  for (let i = 0; i < 5; i += 1) {
    step = (step + 1) % seq.length;
    want.push(Number(num[seq[step]]) || 0);
  }
  const got = [];
  for (let i = 0; i < 5; i += 1) {
    CLOCK = Number(e.state.frog.motionNextAt);
    e.tick();
    got.push(Number(e.state.frog.motion));
  }
  t('动作严格按 Frogpattern 的顺序推进（序号逐项对上）',
    JSON.stringify(got) === JSON.stringify(want),
    'got ' + JSON.stringify(got) + ' want ' + JSON.stringify(want));
}

/* ------------------------------------------------------- ②③④ 出门概率与时长 */
console.log('\n[②③④ 出门] 50% 掷骰 / 带便当小时级 / 空背包放浪 10–20 分钟 / 没中则 3–5 小时');
{
  const TRIALS = 400;
  const measure = (packed) => {
    let departed = 0; const waits = []; const trips = []; let strayCount = 0;
    for (let i = 0; i < TRIALS; i += 1) {
      const e = fresh();
      e.state.frog.status = 0;
      e.state.items.bag = [-1, -1, -1, -1];
      e.state.items.desk = [-1, -1, -1, -1, -1, -1, -1, -1];
      if (packed) e.state.items.bag[0] = 1;          // 1 = 草莓可丽饼
      e.state.travel.nextDepartAt = CLOCK;
      e.tick();
      if (Number(e.state.frog.status) === 1) {
        departed += 1;
        trips.push(Number(e.state.travel.returnAt) - Number(e.state.travel.departAt));
        if (e.state.travel.plan && e.state.travel.plan.stray) strayCount += 1;
      } else {
        waits.push(Number(e.state.travel.nextDepartAt) - CLOCK);
      }
    }
    const min = (a) => Math.min(...a), max = (a) => Math.max(...a);
    return {
      departed, pct: departed / TRIALS * 100, strayCount,
      tripMin: trips.length ? min(trips) : null, tripMax: trips.length ? max(trips) : null,
      waitMin: waits.length ? min(waits) : null, waitMax: waits.length ? max(waits) : null,
    };
  };

  const empty = measure(false);
  const packed = measure(true);

  t('空背包也会出门（他 V3 的规则：放浪）', empty.departed > 0, empty.departed + '/400');
  t('空背包出门率 ≈ 50%（允许 40–60%）', empty.pct >= 40 && empty.pct <= 60, empty.pct.toFixed(1) + '%');
  t('带便当出门率 ≈ 50%（允许 40–60%）', packed.pct >= 40 && packed.pct <= 60, packed.pct.toFixed(1) + '%');
  t('带便当那一趟全部不是放浪', packed.strayCount === 0, 'stray=' + packed.strayCount);
  t('空背包那一趟全部是放浪', empty.strayCount === empty.departed, 'stray=' + empty.strayCount);
  t('放浪窗口落在表值 10–20 分钟',
    empty.tripMin >= 10 * 60 && empty.tripMax <= 20 * 60,
    (empty.tripMin / 60).toFixed(1) + '–' + (empty.tripMax / 60).toFixed(1) + ' 分钟');
  t('带便当窗口 ≥ 2 小时且 ≤ 72 小时硬上限',
    packed.tripMin >= 120 * 60 && packed.tripMax <= 72 * 3600,
    (packed.tripMin / 3600).toFixed(2) + '–' + (packed.tripMax / 3600).toFixed(2) + ' 小时');
  t('没掷中时下一次检查落在 3–5 小时',
    empty.waitMin >= 3 * 3600 - 1 && empty.waitMax <= 5 * 3600 + 1,
    (empty.waitMin / 3600).toFixed(2) + '–' + (empty.waitMax / 3600).toFixed(2) + ' 小时');
  t('掷骰结果被记进存档（lastDepartRoll，便于排查）',
    (() => { const e = fresh(); e.state.travel.nextDepartAt = CLOCK; e.tick();
      return e.state.frog.status === 1 || typeof e.state.travel.lastDepartRoll === 'number'; })());
}

/* ------------------------------------------------------------ ⑤ 开局行李 */
console.log('\n[⑤ 开局行李] 他的 STARTER_*：便当/护身符/工具/特产各补一份，只发一次');
{
  const e = fresh();
  t('标记 preparationSeeded 已置位', e.state.items.preparationSeeded === true);
  const lunches = GDATA.items.filter((i) => Number(i.type) === 0 && Number(i.id) > 0).slice(0, 3);
  const drawing = ['value2', 'value3', 'value4']
    .map((k) => Number(String((((GDATA.tables.drawingCommonData || {}).food || {})[k] || [])[0] || '').split(',')[1]))
    .filter((v) => Number.isFinite(v));
  t('便当类已就位（绘本食物 + 前三样便当）',
    Array.from(new Set(drawing.concat(lunches.map((i) => Number(i.id))))).every((id) => countOf(e, id) >= 3),
    JSON.stringify(drawing.concat(lunches.map((i) => Number(i.id)))));
  t('护身符已就位（头两件，含 1000 四叶草）',
    GDATA.items.filter((i) => Number(i.type) === 1 && Number(i.id) > 0).slice(0, 2)
      .every((i) => countOf(e, Number(i.id)) >= 1));
  t('工具已就位（头三件）',
    GDATA.items.filter((i) => Number(i.type) === 2 && Number(i.id) > 0).slice(0, 3)
      .every((i) => countOf(e, Number(i.id)) >= 1));
  t('特产已就位（前八样各 2）',
    GDATA.items.filter((i) => Number(i.type) === 3).slice(0, 8).every((i) => countOf(e, Number(i.id)) >= 2));

  /* 幂等：重新登录一次不能又发一份 */
  const before = (e.state.items.house || []).length;
  const lunchId = lunches[0] && Number(lunches[0].id);
  const countBefore = countOf(e, lunchId);
  e.dispatch('hall_enter_game', {});
  t('再登录一次不会重复发（幂等）',
    (e.state.items.house || []).length === before && countOf(e, lunchId) === countBefore,
    'rows ' + before + '->' + (e.state.items.house || []).length
      + ' / lunch ' + countBefore + '->' + countOf(e, lunchId));

  /* 已经玩过的老档不该被硬塞：家里已有该类物品时就不补 */
  const e2 = fresh();
  e2.state.items.preparationSeeded = false;
  e2.state.items.house = [{ item_id: 3000, count: 5 }];      // 已有特产
  e2.dispatch('hall_enter_game', {});
  t('已有该类物品时不强塞（特产不再补 2 份）',
    countOf(e2, 3000) === 5, 'got ' + countOf(e2, 3000));
}

/* --------------------------------------------- ⑥ 与可覆盖开关并存（不回归） */
console.log('\n[⑥ 开关] 默认小时级，但仍可用环境变量/faithful 切回');
{
  const src = fs.readFileSync(ENGINE_PATH, 'utf8');
  t('默认值就是他包里的那几个数',
    /FROG_MOTION_SEC \|\| 10 \* 60/.test(src)
    && /FROG_TRAVEL_MIN', 120 \* 60/.test(src)
    && /FROG_TRAVEL_MAX', 510 \* 60/.test(src)
    && /FROG_TRAVEL_CHANCE \|\| 50/.test(src)
    && /TRAVEL_HARD_MAX_SEC = 72 \* 60 \* 60/.test(src));
  t('FROG_FAITHFUL 仍然能整表切到原版恢复值',
    /pace = \(envName, offlineDefault, original\)/.test(src) && /FAITHFUL \? original : offlineDefault/.test(src));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
