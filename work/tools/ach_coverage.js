const path = require('path');
const ROOT = 'H:/AI/frog';
const GD = require(path.join(ROOT, 'work/run/engine/data/gamedata.json'));
const ACH = GD.tables.Achieve;
const names = GD.items.map(i => i.name);
function resolve(label) {
  if (names.indexOf(label) !== -1) return 1;
  const hits = GD.items.filter(i => i.name && (i.name.indexOf(label) !== -1 || label.indexOf(i.name) !== -1));
  return hits.length === 1 ? 1 : 0;
}
const patterns = [
  [/^（默认）$/, 'default'],
  [/^旅行达到(\d+)次$/, 'travel'],
  [/^登录达到(\d+)天$/, 'logindays'],
  [/^拥有超过(\d+)万棵三叶草$/, 'clover'],
  [/^抽奖(\d+)次以上$/, 'gacha'],
  [/^获得(\d+)种纪念品$/, 'collections'],
  [/^获得(\d+)种特产$/, 'specialtys'],
  [/^获得所有特产食材$/, 'allingredients'],
  [/^出发不到30分钟就回家$/, 'shorttrip'],
  [/^出发超过24小时还没回家$/, 'longtrip'],
  [/^六一期间登录$/, 'childrensday'],
];
let ok = 0, unmapped = [], unimplemented = [];
for (const a of ACH) {
  if (Number(a.is_special)) { unimplemented.push([a.id, a.info]); continue; }
  const info = String(a.info || '');
  const m = /^(.+?)超过(\d+)个$/.exec(info);
  if (m) { if (resolve(m[1])) ok++; else unmapped.push([a.id, m[1]]); continue; }
  if (patterns.some(([re]) => re.test(info))) { ok++; continue; }
  unimplemented.push([a.id, info]);
}
console.log(`Achieve rows            : ${ACH.length}`);
console.log(`evaluable by the engine : ${ok}  (${(100*ok/ACH.length).toFixed(0)}%)`);
console.log(`unresolvable item label : ${unmapped.length} ${JSON.stringify(unmapped)}`);
console.log(`deliberately not built  : ${unimplemented.length}`);
for (const [id, info] of unimplemented) console.log(`    id=${id} ${info}`);
