#!/usr/bin/env node
'use strict';
/**
 * 方案 B-2：家具工坊「心情/压力 + 自动换家具」的验收（并入他的 V3）。
 *
 * 他的模型：
 *   moodStress 0-2 → mood 1 很高兴 / 3-7 → 2 开心 / 8-17 → 3 平静 / 18-26 → 4 生气 / >=27 → 5 很生气
 *   客户端只在 mood==5 时把工作台画成"罢工"，且 bench_lock=1 时工作台不接受编辑。
 *   压力：换一件摆放中的家具 +1；安抚：旅行回来 +5、手工品完成 +3、家具做成 +2。
 *   自动换家具：每 8–12 小时检查一次、35% 概率把摆放中的家具换成同类型另一件（已拥有）。
 *
 *   node work/tools/test_v36_workshop_mood.js
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
const fresh = (saveObj) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ws-'));
  const p = path.join(dir, 'save.json');
  if (saveObj) fs.writeFileSync(p, JSON.stringify(saveObj));
  return { engine: createEngine({ savePath: p, verbose: false }), savePath: p };
};
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const gm = (e, cmd) => { const r = call(e, 'client_gm', { cmd }); return (r.reply && (r.reply.info || '')) || ''; };
const furPayload = (e) => call(e, 'furniture_load_furniture', {}).reply;

/* 家具表里找同一 type 的两件（用于反复"换家具"） */
const FUR = (() => {
  const rows = GDATA.tables.furnitureData;
  const arr = Array.isArray(rows) ? rows : Object.keys(rows).map((k) => rows[k]);
  const byType = new Map();
  arr.forEach((r) => {
    if (!r || r.id === undefined || r.type === undefined) return;
    const ty = Number(r.type);
    if (!byType.has(ty)) byType.set(ty, []);
    byType.get(ty).push(Number(r.id));
  });
  for (const [ty, ids] of byType) if (ids.length >= 2) return { type: ty, a: ids[0], b: ids[1] };
  return null;
})();

console.log('\n[心情] 新档平静、换家具涨压力、到阈值工作台乱掉');
{
  const { engine } = fresh();
  const p0 = furPayload(engine);
  /* 注意：他的 defaultState 里写的是 `mood: CALM(3)`，但 normalizeFurnitureMood() 会按
     stress=0 立刻算成 1（0-2 → 很高兴）—— 实测两边引擎都是 1，这里按实际行为钉。 */
  eq(p0.mood, 1, '新档 mood = 1（压力 0 → 很高兴）');
  eq(p0.bench_lock, 0, '新档 bench_lock = 0');
  eq(engine.state.furniture.moodStress, 0, '新档压力 0');

  /* 换 13 轮（每轮两件）= 26 次：压力 26 -> mood 4（生气），还不该锁工作台 */
  const stressOnce = () => { call(engine, 'furniture_replace_fur', { id: FUR.a }); call(engine, 'furniture_replace_fur', { id: FUR.b }); };
  for (let i = 0; i < 13; i += 1) stressOnce();
  eq(engine.state.furniture.moodStress, 26, '换 26 次家具 -> 压力 26');
  eq(furPayload(engine).mood, 4, '压力 26 -> mood 4（生气）');
  eq(furPayload(engine).bench_lock, 0, '生气还不锁工作台');

  /* 再换 1 次 -> 27 = 阈值：mood 5 + bench_lock 1 + 拒绝开工 */
  call(engine, 'furniture_replace_fur', { id: FUR.a });
  eq(engine.state.furniture.moodStress, 27, '换第 27 次 -> 压力 27');
  eq(furPayload(engine).mood, 5, '压力 27 -> mood 5（很生气：客户端画罢工）');
  eq(furPayload(engine).bench_lock, 1, 'mood 5 时 bench_lock = 1（工作台不接受编辑）');
  /* 手动路径（摆好图纸+材料就开工）与 gm 路径都必须被心情挡住。
     craft_start 的 id 必须是"该 type 的图纸真正做出来的那件"，引擎的报错里会给出正确 id，
     所以按提示重试一次，免得把"id 不匹配"误判成"心情没挡住"。 */
  let refused = gm(engine, 'craft_start 1101');
  const hint = /做出来的是 (\d+)/.exec(refused);
  if (hint) refused = gm(engine, 'craft_start ' + hint[1]);
  t('心情差时 craft_start 被拒（并说明原因）', /心情|乱/.test(refused), refused.slice(0, 60));
  eq(engine.state.furniture.craft, null, '而且确实没开工');
  t('furniture_mood 能看状态', /家具心情/.test(gm(engine, 'furniture_mood')));
}

console.log('\n[安抚] 旅行回来 -5、家具做成 -2、手工完成 -3');
{
  const { engine } = fresh();
  engine.state.furniture.moodStress = 27;
  /* 旅行：出门 -> 回家（把时钟推过 returnAt） */
  engine.state.items.bag[0] = GDATA.items.find((i) => Number(i.type) === 0).id;
  let left = false;
  for (let k = 0; k < 60 && !left; k += 1) {
    engine.state.frog.status = 0;
    engine.state.travel.nextDepartAt = CLOCK;
    engine.tick();
    left = engine.state.frog.status === 1;
  }
  const before = engine.state.furniture.moodStress;
  CLOCK = Number(engine.state.travel.returnAt) + 5;
  engine.tick();
  CLOCK = 1_700_000_000;
  eq(engine.state.furniture.moodStress, before - 5, '旅行回来压力 -5');
  eq(engine.state.furniture.moodRecoverTrips, 1, '记了一次旅行安抚');

  /* 家具做成：直接放一个进行中的制作，然后让它到点结算 */
  const fid = FUR.a;
  engine.state.furniture.craft = { furnitureId: fid, drawing: 0, materials: [], startedAt: CLOCK, finishAt: CLOCK - 1 };
  engine.state.furniture.benchLock = 1;
  const beforeCraft = engine.state.furniture.moodStress;
  engine.tick();
  eq(engine.state.furniture.moodStress, beforeCraft - 2, '家具做成压力 -2');
  t('家具入库', (engine.state.furniture.owned || []).indexOf(fid) !== -1);
}

console.log('\n[自动换家具] 35% 检查 + 手动 force');
{
  const { engine } = fresh();
  engine.state.furniture.owned = [FUR.a, FUR.b];
  engine.state.furniture.placed = [{ type: FUR.type, id: FUR.a }];
  eq(gm(engine, 'furniture_auto force').indexOf('已换'), 0, 'furniture_auto force 立刻换一件');
  const placed = engine.state.furniture.placed.find((p) => Number(p.type) === FUR.type);
  eq(Number(placed.id), FUR.b, '换成同类型的另一件');
  eq(engine.state.furniture.autoReplaceCount, 1, '计数 +1');
  t('换过之后 replace_fur 记了这个 type', (engine.state.furniture.replaceFur || []).indexOf(FUR.type) !== -1);

  /* tick 路径：把下次检查时间设为过去，多次 tick 后必然发生（每次 35%） */
  const { engine: e2 } = fresh();
  e2.state.furniture.owned = [FUR.a, FUR.b];
  e2.state.furniture.placed = [{ type: FUR.type, id: FUR.a }];
  e2.state.furniture.nextAutoReplaceAt = CLOCK - 1;
  for (let i = 0; i < 40 && !(Number(e2.state.furniture.autoReplaceCount) > 0); i += 1) {
    e2.state.furniture.nextAutoReplaceAt = CLOCK - 1;   // 每拍都到点，等价于多次检查
    e2.tick();
  }
  t('tick 会自动换家具（35% 检查，40 拍内必发生）', Number(e2.state.furniture.autoReplaceCount) > 0,
    'count=' + e2.state.furniture.autoReplaceCount);
  t('自动换家具会记排期（nextAutoReplaceAt 在将来）',
    Number(e2.state.furniture.nextAutoReplaceAt) > CLOCK);
}

console.log('\n[旧档] 没有心情字段的老存档：补齐、不炸、能存回去');
{
  const { engine, savePath } = fresh({
    saveVersion: 1, account: 'offline', uid: 10001, name: '呱呱', clover: 100, ticket: 0,
    frog: { status: 0, motion: 0 },
    items: { house: [{ item_id: 1, count: 2 }], bag: [-1, -1, -1, -1], desk: [-1, -1, -1, -1, -1, -1, -1, -1] },
    furniture: { bench: [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1], benchLock: 0, craft: null,
      owned: [], placed: [], replaceFur: [], shopBought: {}, shopDay: 0, shopDailyBought: {},
      welfareTaken: {}, welfareDay: {}, compost: { boxes: [0, 0, 0, 0, 0, 0], list: [] },
      pocket: { showIndex: 0, replaceIndex: 0, clover: 0 }, tumbler: { showIndex: 0, replaceIndex: 0 } },
    pictures: [], albumPending: [], specialtys: [], mails: [], notes: [],
  });
  eq(engine.state.furniture.moodStress, 0, '旧档压力补成 0');
  eq(furPayload(engine).mood, 1, '旧档心情 = 1（压力 0 → 很高兴）');
  engine.tick();
  const again = createEngine({ savePath, verbose: false });
  eq(again.state.furniture.mood, 1, '存回去再读仍是同样的心情');
  t('旧档心情字段完整', ['moodStress', 'nextAutoCraftAt', 'nextAutoReplaceAt']
    .every((k) => again.state.furniture[k] !== undefined));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
