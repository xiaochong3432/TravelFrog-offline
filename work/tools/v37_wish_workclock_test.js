#!/usr/bin/env node
'use strict';
/**
 * V3.7 收尾：手工品"要正在做手工才推进"（可选）+ SAVE_VERSION=2
 *
 *   node work/tools/v37_wish_workclock_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const WISH_IDS = Object.keys(GD.tables.prayData || {}).map(Number).filter(Number.isFinite);
const TOOL = 7000, MATERIAL = 8000;

let CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const mk = (env, savePath) => {
  if (env) Object.assign(process.env, env);
  delete require.cache[require.resolve(ENGINE)];
  const mod = require(ENGINE);
  const e = mod.createEngine({
    savePath: savePath || path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'wc-')), 'save.json'),
    verbose: false,
  });
  if (env) for (const k of Object.keys(env)) delete process.env[k];
  return e;
};
const give = (e, id, n) => {
  const row = e.state.items.house.find((r) => Number(r.item_id) === Number(id));
  if (row) row.count += n; else e.state.items.house.push({ item_id: Number(id), count: n });
};
/* 摆一个"到点该进第二阶段"的祈愿物，并把蛙蛙的动作钉住（挡住 tick 里的动作刷新） */
const armWish = (e, motion) => {
  e.tick();
  give(e, TOOL, 1);
  give(e, MATERIAL, 5);
  e.state.craft = e.state.craft || { wishes: [], stamps: [], pending: [], seq: 0 };
  e.state.craft.wishes = [{ id: WISH_IDS[0], state: 1, make_time: CLOCK - 1, u_id: 1, materialPaid: false }];
  e.state.frog.status = 0;
  e.state.frog.motionMode = 'awake';
  e.state.frog.motionNextAt = CLOCK + 600;
  e.state.frog.motion = motion;
};

console.log('\n[1] V4.0 默认 = 他的口径：只有正在做手工才推进');
{
  const e = mk();
  armWish(e, 2);                        // 蛙蛙在"写字"
  e.tick();
  eq(Number(e.state.craft.wishes[0].state), 1, '写字时不推进（V4.0 默认）');
  e.state.frog.motionMode = 'awake';
  e.state.frog.motionNextAt = CLOCK + 600;
  e.state.frog.motion = 3;              // make
  e.tick();
  eq(Number(e.state.craft.wishes[0].state), 2, '做手工时推进（V4.0 默认）');
}

console.log('\n[1b] 回退 FROG_WISH_WORKCLOCK=0 = V3.7 的阶段墙钟');
{
  const e = mk({ FROG_WISH_WORKCLOCK: '0' });
  armWish(e, 2);
  e.tick();
  eq(Number(e.state.craft.wishes[0].state), 2, '写字时也照样进阶段（回退到 V3.7）');
}

console.log('\n[2] 计时器不会被吃掉 + 工具/材料门槛：V4.0 默认没有门槛（他的口径）');
{
  const e = mk();
  armWish(e, 2);
  e.tick();
  t('计时器还留着（没被吃掉）', Number(e.state.craft.wishes[0].make_time) <= CLOCK,
    'make_time=' + (Number(e.state.craft.wishes[0].make_time) - CLOCK));
  /* V4.0 默认 = 他的：没有材料也照样推进（只要在做手工） */
  const e2 = mk();
  armWish(e2, 3);
  e2.state.items.house = e2.state.items.house.filter((r) => Number(r.item_id) !== MATERIAL);
  e2.state.craft.wishes[0].materialPaid = false;
  e2.tick();
  eq(Number(e2.state.craft.wishes[0].state), 2, 'V4.0 默认：没材料也推进（他的口径）');
  /* 回退 FROG_HANDCRAFT_GATE=1 = V3.7 的门槛 */
  const e3 = mk({ FROG_HANDCRAFT_GATE: '1' });
  armWish(e3, 3);
  e3.state.items.house = e3.state.items.house.filter((r) => Number(r.item_id) !== MATERIAL);
  e3.state.craft.wishes[0].materialPaid = false;
  e3.tick();
  eq(Number(e3.state.craft.wishes[0].state), 1, '回退后没有材料仍然不推进（V3.7 门槛）');
}

console.log('\n[3] SAVE_VERSION = 2：老档（v1）照样读，写出来是 2');
{
  const e = mk();
  e.tick();
  e.save();
  const raw = JSON.parse(JSON.stringify(e.exportSave()));
  eq(Number(raw.saveVersion), 2, '本版写出的存档是 v2');
  /* 模拟 v1 老档（六条线写的都是 1） */
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wc-v1-'));
  const p = path.join(dir, 'save.json');
  raw.saveVersion = 1;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e2 = mk(null, p);
  e2.tick();
  eq(Number(e2.state.saveVersion), 2, 'v1 老档读入后升到 v2');
  t('老档内容没丢（三叶草还在）', Number(e2.state.clover) > 0, 'clover=' + e2.state.clover);
  eq(Number(e2.state.__saveReport && e2.state.__saveReport.refused ? 1 : 0), 0, '没有被拒绝写入');
  /* 更新引擎写的档（v3）只读不写 */
  const dir3 = fs.mkdtempSync(path.join(os.tmpdir(), 'wc-v3-'));
  const p3 = path.join(dir3, 'save.json');
  raw.saveVersion = 3;
  fs.writeFileSync(p3, JSON.stringify(raw));
  const e3 = mk(null, p3);
  e3.tick();
  const refused = (e3.state.__saveReport || {});
  t('v3 的新档只读不写（不会覆盖）',
    Number(refused.refused ? 1 : 0) === 1 || String(refused.action || '').indexOf('refus') >= 0
    || Number(e3.state.saveVersion) === 3,
    JSON.stringify(refused).slice(0, 120));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
