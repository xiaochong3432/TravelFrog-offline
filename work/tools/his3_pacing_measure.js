#!/usr/bin/env node
'use strict';
/**
 * 实测「他做的 V3 包」引擎里那四条节奏/概率设定，并拿我们的 V3.5 做同项对照。
 *
 * 用户转述他的说法：姿势 45 分钟一次顺序、出门是几个小时、背包有东西也是几个小时后检查、
 * 有 50% 概率出门。本脚本把两套引擎都跑起来，直接量：
 *   ① 在家动作切换间隔（motionNextAt - 现在）与是否按 Frogpattern 顺序
 *   ② 一趟出门的实际时长（returnAt - departAt，含便当 HP 加成/门票缩短）
 *   ③ 没准备时下一次检查的间隔（nextDepartAt - 现在）
 *   ④ 到点时出门的概率（多次独立试次统计）
 *
 * 时间由 Date.now 接管成可控假时钟，避免受真实时间影响。
 *
 *   node work/tools/his3_pacing_measure.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const HIS_DIR = path.join(ROOT, 'work', 'build', 'his3', 'engine_live');
const OUR_ENGINE = path.join(ROOT, 'work', 'run', 'engine', 'index.js');

/* ---- 假时钟：engine 用 Math.floor(Date.now()/1000) 取时间 ---- */
let CLOCK = 1_700_000_000;
Date.now = () => CLOCK * 1000;

const his = require(path.join(HIS_DIR, 'index.js'));
const our = require(OUR_ENGINE);
const mkdir = () => fs.mkdtempSync(path.join(os.tmpdir(), 'pacing-'));
const fresh = (mod) => mod.createEngine({ savePath: path.join(mkdir(), 'save.json'), verbose: false });

const min = (s) => (s / 60).toFixed(1) + ' 分钟';
const hour = (s) => (s / 3600).toFixed(2) + ' 小时';

function motionSeq(eng, steps) {
  const seen = [];
  for (let i = 0; i < steps; i += 1) {
    eng.tick();
    seen.push(Number(eng.state.frog.motion));
    CLOCK += Math.max(1, Number(eng.state.frog.motionNextAt) - CLOCK);
  }
  return seen;
}

function measure(tag, mod, isHis) {
  console.log('\n================ ' + tag + ' ================');

  /* ① 在家动作 */
  CLOCK = 1_700_000_000;
  let e = fresh(mod);
  e.tick();
  const interval = Number(e.state.frog.motionNextAt) - CLOCK;
  console.log('① 在家动作间隔           : ' + interval + ' 秒 = ' + min(interval));
  const seq = motionSeq(e, 6);
  console.log('   连续动作编号           : ' + JSON.stringify(seq));
  console.log('   动作组 motionPattern   : ' + e.state.frog.motionPattern
    + '（Frogpattern 有 ' + Object.keys(JSON.parse(fs.readFileSync(
      path.join(HIS_DIR, 'data', 'define.json'), 'utf8')).maps.Frogpattern).length + ' 组）');

  /* ④ 出门概率 + ② 出门时长 + ③ 未出门时的等待：空背包 / 带便当 两种都量 */
  const TRIALS = 400;
  const LUNCH = 3;                              // 3 = 茄汁蛋包饭（H_MAXTIME 72，他注释里的 x1.72 例子）
  for (const variant of ['空背包', '带便当']) {
    let departed = 0; const waits = []; const trips = [];
    for (let i = 0; i < TRIALS; i += 1) {
      e = fresh(mod);
      e.state.frog.status = 0;
      e.state.travel.nextDepartAt = CLOCK;      // 到点，等这一拍决定
      e.state.travel.waitingForBag = false;
      e.state.items.bag = [-1, -1, -1, -1];
      e.state.items.desk = [-1, -1, -1, -1, -1, -1, -1, -1];
      if (variant === '带便当') e.state.items.bag[0] = LUNCH;
      e.tick();
      if (Number(e.state.frog.status) === 1) {
        departed += 1;
        trips.push(Number(e.state.travel.returnAt) - Number(e.state.travel.departAt));
      } else {
        waits.push(Number(e.state.travel.nextDepartAt) - CLOCK);
      }
    }
    const pct = (departed / TRIALS * 100).toFixed(1);
    console.log('④ [' + variant + '] 到点后真的出门 : ' + departed + '/' + TRIALS + ' = ' + pct + '%'
      + (isHis ? '（他：FROG_TRAVEL_CHANCE 默认 50）' : '（我们 V3.6 已并入，同样是 50）'));
    if (trips.length) {
      const mn = Math.min(...trips), mx = Math.max(...trips);
      const avg = Math.round(trips.reduce((a, b) => a + b, 0) / trips.length);
      console.log('② [' + variant + '] 一趟时长     : 最短 ' + min(mn) + ' / 平均 ' + min(avg)
        + ' / 最长 ' + min(mx) + '   (' + hour(mn) + '–' + hour(mx) + ')');
    }
    if (waits.length) {
      const mn = Math.min(...waits), mx = Math.max(...waits);
      console.log('③ [' + variant + '] 下次检查间隔 : ' + min(mn) + ' – ' + min(mx)
        + '   (' + hour(mn) + '–' + hour(mx) + ')');
    }
  }
}

measure('他做的 V3（com.travelfrog.offline）', his, true);
measure('我们的 V3.5', our, false);
