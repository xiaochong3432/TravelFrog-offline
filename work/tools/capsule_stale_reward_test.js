#!/usr/bin/env node
'use strict';
/**
 * V3.3.1 那条「扭蛋奖励 id 清理」修复的回归测试。
 *
 * 崩溃链路（他给的注释 + 客户端实际读法）：
 *   CapsuleView.update() -> capsuleData.get("reward")[reward.toString()]
 * 旧表（v1001）有 30 个键，旧存档抽到 108/109/110/209/311 这些当前表已删掉的 id 时，
 * 查表得到 undefined，紧接着读 `.type` 直接抛错 —— 玩家看到的就是"扭蛋机打不开"。
 *
 * 本测试做两件事：
 *   1) 读档时把这类陈旧 id 从存档里清掉（refreshCapsule 里的清理）；
 *   2) 发送侧 capsule_load 的 reward_list 只含当前表认识的 id，且每一条都能安全读出 `.type`
 *      （这正是客户端会做的动作）。
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);
const GD = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const CAPSULE_REWARD = (GD.tables.capsuleData || {}).reward || {};

/* 旧存档里真实存在、但当前表已经没有的 id（他点名的 108/109/110/209/311）。 */
const STALE = [108, 109, 110, 209, 311].filter((id) => !CAPSULE_REWARD[String(id)]);
const KNOWN = Object.keys(CAPSULE_REWARD).map(Number).filter((n) => Number.isFinite(n));
if (!STALE.length) {
  console.error('FAIL: 当前表里已经没有可用的“陈旧 id”样本，测试无意义');
  process.exit(2);
}

let pass = 0, fail = 0;
const check = (ok, label, extra) => {
  if (ok) { pass++; console.log('  PASS  ' + label); }
  else { fail++; console.log('  FAIL  ' + label + (extra ? '  [' + extra + ']' : '')); }
};

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-capsule-'));
const savePath = path.join(dir, 'save.json');

/* ---- 1) 造一份"旧存档"：reward_list 里混进当前表没有的 id ---- */
const engine = createEngine({ savePath, verbose: false });
engine.state.capsule = Object.assign({}, engine.state.capsule, {
  rewardList: [KNOWN[0], ...STALE.slice(0, 2), 99999],
  started: 1,
  endTime: 0,
});
fs.writeFileSync(savePath, JSON.stringify(engine.state));

const again = createEngine({ savePath, verbose: false });
/* 清理挂在 refreshCapsule() 上，而它由胶囊相关命令触发（capsule_load 等），不是读档即时。
   所以这里先看"发出去的 payload 干不干净"，再看"一次 capsule_load 之后存档是否自愈"。 */
let reply = null;
try {
  reply = again.dispatch('capsule_load', {}).reply;
} catch (e) {
  check(false, 'capsule_load 不应该抛错', e && e.message);
}
const pruned = again.state.capsule.rewardList;
check(pruned.every((id) => CAPSULE_REWARD[String(Number(id))]),
  '一次 capsule_load 之后，存档里的陈旧奖励 id 已被清掉', JSON.stringify(pruned));
check(pruned.indexOf(KNOWN[0]) !== -1, '已经抽到的合法奖励不会被误删');

/* ---- 发送侧：capsule_load 的 payload 必须干净，且能安全读 .type ---- */
if (reply) {
  const list = reply.reward_list || [];
  check(list.every((id) => CAPSULE_REWARD[String(Number(id))] !== undefined),
    'capsule_load 的 reward_list 只含表里有的 id', JSON.stringify(list));
  let crash = null;
  for (const id of list) {
    try {
      /* 客户端就是这么读的：取不到行 -> undefined，再读 .type 就抛 */
      const row = CAPSULE_REWARD[String(Number(id))];
      void row.type;
    } catch (e) { crash = id + ': ' + (e && e.message); }
  }
  check(crash === null, '每条奖励都能安全读出 .type（客户端不会再“吃坏肚子”）', crash || '');
}

/* ---- 3) 干净存档不受影响（幂等） ---- */
const n = again.state.capsule.rewardList.length;
again.dispatch('capsule_load', {});
check(again.state.capsule.rewardList.length === n && n === pruned.length,
  '再刷新一次不会继续删（幂等）');

console.log('\n' + pass + ' passed, ' + fail + ' failed');
try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { /* ignore */ }
process.exit(fail ? 1 : 0);
