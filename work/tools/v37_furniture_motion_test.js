#!/usr/bin/env node
'use strict';

/* 【V4.0】这套件的 [1][2] 验证 V3.7 的立即开工，[3] 自己用 fresh() 切到排队模式。
   引擎的开关常量在 require 时求值，所以这段必须在 require 之前。 */
process.env.FROG_CRAFT_QUEUE = '0';

/**
 * V3.7 系统 10：做家具的工具动画 + 排队开工（并入他 3.3）
 *
 *   node work/tools/v37_furniture_motion_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));

/* 工具动画编号（他的表） */
const TOOL_MOTION = { saw: 5, brush: 6, hammer: 7, needle: 8, knife: 9 };
const TOOL_ITEMS = { saw: 10205, brush: 10202, hammer: 10203, needle: 10204, knife: 10205 };
const KNIFE = 10205, NEEDLE = 10204, BRUSH = 10202;
const POCKET_BP = 10601, ROPE = 11102;

let CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const fresh = (env) => {
  if (env) Object.assign(process.env, env);
  delete require.cache[require.resolve(ENGINE)];
  const mod = require(ENGINE);
  const e = mod.createEngine({
    savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'fm-')), 'save.json'), verbose: false,
  });
  if (env) for (const k of Object.keys(env)) delete process.env[k];
  return e;
};
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const give = (e, id, n) => {
  const row = e.state.items.house.find((r) => Number(r.item_id) === Number(id));
  if (row) row.count += n; else e.state.items.house.push({ item_id: Number(id), count: n });
};

console.log('\n[1] 做口袋时"做"的动作会变成具体工具动画（不是笼统的 make=3）');
{
  const e = fresh();
  e.tick();
  give(e, POCKET_BP, 1); give(e, ROPE, 1); give(e, 10005, 1); give(e, 10004, 1); give(e, 10006, 1);
  give(e, KNIFE, 1); give(e, NEEDLE, 1);
  call(e, 'furniture_putin_bench', { pos: 1, id: KNIFE });
  call(e, 'furniture_putin_bench', { pos: 2, id: NEEDLE });
  eq(call(e, 'furniture_putin_bench', { pos: 7, id: ROPE }).reply.crafting, 1, '口袋开工');
  /* 让动作刷新跑一次（换个模式强制刷新） */
  e.state.frog.motionMode = 'force';
  e.tick();
  const motion = Number(e.state.frog.motion);
  t('动作是刀或棒针的工具动画（9 / 8），不是 make=3',
    motion === TOOL_MOTION.knife || motion === TOOL_MOTION.needle, 'motion=' + motion);
  /* 口袋工具就是 knife/needle，所以一定会在这两个里轮换 */
  const seen = new Set();
  for (let i = 0; i < 6; i += 1) {
    e.state.frog.motionMode = 'force' + i;
    e.tick();
    seen.add(Number(e.state.frog.motion));
  }
  t('轮换里只出现刀/棒针两种工具动画',
    [...seen].every((m) => m === TOOL_MOTION.knife || m === TOOL_MOTION.needle),
    JSON.stringify([...seen]));
}

console.log('\n[2] 默认（我们的做法）：抽中即开工');
{
  const e = fresh();
  e.tick();
  give(e, POCKET_BP, 1); give(e, ROPE, 1); give(e, 10005, 1); give(e, 10004, 1); give(e, 10006, 1);
  give(e, KNIFE, 1); give(e, NEEDLE, 1);
  call(e, 'furniture_putin_bench', { pos: 1, id: KNIFE });
  call(e, 'furniture_putin_bench', { pos: 2, id: NEEDLE });
  call(e, 'furniture_putin_bench', { pos: 7, id: ROPE });
  eq(Number(e.state.furniture.craftQueued), 0, '默认不排队（放上台面即开工）');
  t('制作已经开始了', !!e.state.furniture.craft, JSON.stringify(e.state.furniture.craft));
}

console.log('\n[3] FROG_CRAFT_QUEUE=1（他的做法）：先排队，等蛙蛙拿起对应工具的动作才开工');
{
  const e = fresh({ FROG_CRAFT_QUEUE: '1' });
  e.tick();
  give(e, POCKET_BP, 1); give(e, ROPE, 1); give(e, 10005, 1); give(e, 10004, 1); give(e, 10006, 1);
  give(e, KNIFE, 1); give(e, NEEDLE, 1);
  call(e, 'furniture_putin_bench', { pos: 1, id: KNIFE });
  call(e, 'furniture_putin_bench', { pos: 2, id: NEEDLE });
  const placed = call(e, 'furniture_putin_bench', { pos: 7, id: ROPE });
  eq(placed.reply.code, 0, '绳放上台面成功（排队模式）');
  eq(Number(e.state.furniture.craftQueued), 1, '排队模式下先排队');
  eq(e.state.furniture.craft, null, '并不立刻开工');
  t('记住了要做什么', Number(e.state.furniture.craftQueuedFurnitureId) > 0,
    'id=' + e.state.furniture.craftQueuedFurnitureId);
  /* 注意：tick 里会先刷新动作，会覆盖我们手工设的 motion。
     所以把 motionMode/motionNextAt 设成"刚刷过、还没到下一次"，让刷新直接返回。 */
  /* 【V4.0】排队时引擎会把动作刷成"制作"模式（这样蛙蛙才会演工具动作），
     所以要按住不匹配的动作，必须把模式也按成 'craft'（否则会被刷新覆盖）。 */
  const holdMotion = (motion) => {
    e.state.frog.motionMode = 'craft';
    e.state.frog.motionNextAt = CLOCK + 600;
    e.state.frog.motion = motion;
  };
  /* 动作不匹配（比如在写东西）时不该开工 */
  e.state.frog.status = 0;
  holdMotion(2);                           // write
  e.tick();
  eq(e.state.furniture.craft, null, '动作不匹配时不开工');
  /* 让蛙蛙拿起刀 -> 应当开工 */
  holdMotion(9);                           // knife
  e.tick();
  t('拿起对应工具后真的开工', !!e.state.furniture.craft, JSON.stringify(e.state.furniture.craft));
  eq(Number(e.state.furniture.craftQueued), 0, '排队标记被清掉');
}

console.log('\n[4] 老档兼容（没有 craftQueued 的 V3.5/V3.6 档）');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fm-old-'));
  const p = path.join(dir, 'save.json');
  const seed = fresh();
  seed.tick();
  const raw = JSON.parse(JSON.stringify(seed.exportSave()));
  delete raw.furniture.craftQueued;
  delete raw.furniture.craftQueuedFurnitureId;
  delete raw.furniture.craftQueuedBenchSlot;
  delete raw.furniture.nextCraftCheckAt;
  raw.saveVersion = 1;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e = createEngine({ savePath: p, verbose: false });
  e.tick();
  eq(Number(e.state.furniture.craftQueued), 0, 'craftQueued 补 0');
  eq(Number(e.state.furniture.craftQueuedBenchSlot), -1, 'benchSlot 补 -1');
  const again = JSON.parse(JSON.stringify(e.exportSave()));
  eq(Number(again.furniture.craftQueued), 0, '存回再读一致');
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
