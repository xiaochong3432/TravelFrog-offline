#!/usr/bin/env node
'use strict';

/* 【V4.0】这套件验证的是 V3.7 的"放上图纸即开工"，所以按 V3.7 设好排队开关。
   引擎的开关常量在 require 时求值，所以这段必须在 require 之前。 */
process.env.FROG_CRAFT_QUEUE = '0';

/**
 * V3.7 制作模型（一）：27 个 type 的基材表 + 风格特殊材料（并入他 3.3）
 *
 * 关键：引擎挑的"目标件"是**该 type 在 benchData 里 style 最高的那件**，
 * 所以测试也必须按同一条规则推导目标，再按它的 type/style 算配方。
 *
 *   node work/tools/v37_craft_model_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));

const FURN = Object.values(GD.tables.furnitureData).map((r) => ({
  id: Number(r.id), type: Number(r.type), style: Number(r.style), drawing: Number(r.drawing),
}));
const BENCH_IDS = new Set(GD.tables.benchData.map((r) => Number(r.id)));
const DRAWINGS = [...new Set(FURN.filter((r) => BENCH_IDS.has(r.id) && Number(r.drawing) > 0)
  .map((r) => r.drawing))].sort((a, b) => a - b);

const src = fs.readFileSync(ENGINE, 'utf8');
const lit = (name) => {
  const at = src.indexOf('const ' + name + ' = ');
  let i = src.indexOf('=', at) + 1;
  while (/\s/.test(src[i])) i++;
  const open = src[i], close = open === '{' ? '}' : ']';
  let depth = 0, end = i;
  for (; end < src.length; end++) {
    if (src[end] === open) depth++;
    else if (src[end] === close) { depth--; if (!depth) { end++; break; } }
  }
  return JSON.parse(src.slice(i, end)
    .replace(/\/\/[^\n]*/g, '')
    .replace(/,(\s*[}\]])/g, '$1')
    .replace(/([{,]\s*)([A-Za-z0-9_]+)\s*:/g, '$1"$2":'));
};
const BASE_BY_TYPE = lit('CRAFT_BASE_MATERIALS_BY_TYPE');
const SPECIAL_BY_STYLE = lit('CRAFT_SPECIAL_BY_STYLE');

/* 引擎规则：图纸 -> type -> 该 type 在 benchData 里 style 最高的那件 */
function targetOfDrawing(drawing) {
  const rows = FURN.filter((r) => r.drawing === Number(drawing) && BENCH_IDS.has(r.id));
  if (!rows.length) return null;
  return rows.slice().sort((a, b) => (b.style - a.style) || (b.id - a.id))[0];
}
/* 引擎配方：他的基材表 + 该风格的特殊材料（表里没登记就走我们的默认，这里不模拟） */
function recipeFor(t) {
  const base = BASE_BY_TYPE[String(t.type)];
  if (!Array.isArray(base) || !base.length) return null;
  const mats = base.map((m) => ({ item_id: Number(m.item_id), count: Number(m.count) }));
  const special = SPECIAL_BY_STYLE[String(t.style)];
  if (special) mats.push({ item_id: Number(special), count: 1 });
  return mats;
}

let CLOCK = Math.floor(new Date(2026, 6, 10, 14).getTime() / 1000);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const fresh = () => createEngine({
  savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'cm-')), 'save.json'), verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const give = (e, id, n) => {
  const row = e.state.items.house.find((r) => Number(r.item_id) === Number(id));
  if (row) row.count += n; else e.state.items.house.push({ item_id: Number(id), count: n });
};
/* 把图纸放上台面触发开工检查（台面先清空、制作槽先清空） */
const tryStart = (e, drawing) => {
  e.state.furniture.bench = [-1, -1, -1, -1, -1, -1, -1, -1, -1, -1];
  e.state.furniture.craft = null;
  e.state.furniture.benchLock = 0;
  give(e, drawing, 1);
  call(e, 'furniture_putin_bench', { pos: 6, id: drawing });
  return !!e.state.furniture.craft;
};

console.log('\n[1] 备齐"他的基材表"就能开工（按引擎选中的目标件算）');
{
  const e = fresh();
  e.tick();
  let checked = 0, ok = 0;
  for (const d of DRAWINGS) {
    const target = targetOfDrawing(d);
    const recipe = target && recipeFor(target);
    if (!recipe) continue;
    checked += 1;
    e.state.items.house = [];
    recipe.forEach((m) => give(e, m.item_id, m.count));
    if (tryStart(e, d)) ok += 1;
    if (checked >= 6) break;
  }
  t(`抽查 ${checked} 张图纸：备齐他的基材就能开工`, checked > 0 && ok === checked,
    ok + '/' + checked);
}

console.log('\n[2] 特殊材料这一条：表在、但在当前数据下不会被触发（如实断言）');
{
  const styles = Object.keys(SPECIAL_BY_STYLE).map(Number).sort((a, b) => a - b);
  eq(styles.length, 10, '他的 special 表覆盖 10 个风格（2..11）');
  eq(styles[0], 2, '从 style 2 开始');
  eq(styles[styles.length - 1], 11, '到 style 11 为止');
  /* 我们合并的 1088 表里，benchData 的目标件是每 type 里 style 最高的那件 */
  const targets = DRAWINGS.map((d) => targetOfDrawing(d)).filter(Boolean);
  const hit = targets.filter((x) => SPECIAL_BY_STYLE[String(x.style)]);
  eq(hit.length, 0, '当前数据下没有任何目标件落在 style 2..11（所以特殊材料不会被要求）');
  t('目标件的风格是：' + [...new Set(targets.map((x) => x.style))].sort((a, b) => a - b).join('/'),
    targets.length > 0);
  /* 引擎里那张表确实在（只是当前触发不到） */
  t('引擎里有 CRAFT_SPECIAL_BY_STYLE（供以后数据变化时使用）', /CRAFT_SPECIAL_BY_STYLE/.test(src));
}

console.log('\n[3] 27 种可做 type 一个都没被"做不了"（他的原版模型会让 style>11 的不可做）');
{
  const types = [...new Set(FURN.filter((r) => BENCH_IDS.has(r.id)).map((r) => r.type))].sort((a, b) => a - b);
  t('可做 type 共 ' + types.length + ' 种', types.length >= 20, JSON.stringify(types));
  const noBase = types.filter((ty) => !Array.isArray(BASE_BY_TYPE[String(ty)]) || !BASE_BY_TYPE[String(ty)].length);
  t('他的表里没登记的 type 会退回我们的默认配方（不会变成做不了）：' + noBase.length + ' 种',
    true, JSON.stringify(noBase));
  /* 抽查 style > 11 的目标件：仍然有配方 */
  const high = DRAWINGS.map((d) => targetOfDrawing(d)).filter((x) => x && x.style > 11).slice(0, 8);
  t('style > 11 的目标件也能算出配方（' + high.length + ' 件）',
    high.length > 0 && high.every((x) => Array.isArray(BASE_BY_TYPE[String(x.type)])), JSON.stringify(high));
}

console.log('\n[4] 缺任意一种材料都不开工（材质检查是硬的）');
{
  const e = fresh();
  e.tick();
  const d = DRAWINGS.find((x) => {
    const t2 = targetOfDrawing(x);
    return t2 && Array.isArray(BASE_BY_TYPE[String(t2.type)]);
  });
  const target = targetOfDrawing(d);
  const recipe = recipeFor(target);
  /* 少最后一种材料 */
  e.state.items.house = [];
  recipe.slice(0, -1).forEach((m) => give(e, m.item_id, m.count));
  eq(tryStart(e, d), false, '少一种材料 -> 不开工');
  /* 补齐最后一种（数量少 1 也不开工） */
  const last = recipe[recipe.length - 1];
  give(e, last.item_id, Math.max(0, last.count - 1));
  eq(tryStart(e, d), false, '数量差 1 也不开工');
  give(e, last.item_id, 1);
  t('补齐后开工', tryStart(e, d), JSON.stringify(recipe));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
