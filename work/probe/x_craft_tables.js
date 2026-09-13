/* x_craft_tables.js -- what the 印章/祈愿物 tables actually declare, and whether every
 * image name they reference really exists in this package.
 *
 * Answers three questions in one pass:
 *   1. does ANY of stampData / prayData / prayBodyData / prayNoteData / Word carry a
 *      date/time field, or is the displayed date necessarily a payload field?
 *   2. what exactly does `formatPathImage(...)` receive, and does that name resolve?
 *   3. is there any 印章本/图鉴-style table (Collection etc.) behind these features?
 *
 * Usage: node work/probe/x_craft_tables.js
 */
const fs = require('fs');
const G = JSON.parse(fs.readFileSync('work/run/engine/data/gamedata.json', 'utf8'));
const T = G.tables || {};
const RES = JSON.parse(fs.readFileSync('work/run/web/resource/China/default.res.json', 'utf8'));

/* every name the engine can hand `formatPathImage` OR that a skin can name as a source */
const resNames = new Set((RES.resources || []).map((x) => x.name));
const sheetNames = new Set();
const sheetDir = 'work/run/web/resource/China/sheet';
for (const f of fs.readdirSync(sheetDir)) {
  if (!/\.json$/.test(f)) continue;
  try {
    const j = JSON.parse(fs.readFileSync(sheetDir + '/' + f, 'utf8'));
    for (const k of Object.keys(j.frames || {})) sheetNames.add(k);
  } catch (e) { /* not an atlas */ }
}
const exists = (name) => resNames.has(name) || sheetNames.has(name);

const TABLES = ['stampData', 'prayData', 'prayBodyData', 'prayNoteData', 'Word', 'Collection', 'Item'];
console.log('=== table presence + field census ===');
for (const name of TABLES) {
  const t = T[name];
  if (!t) { console.log('  ' + name + ': MISSING in gamedata.tables'); continue; }
  const rows = Array.isArray(t) ? t : Object.values(t);
  const keys = new Set();
  for (const r of rows) if (r && typeof r === 'object') Object.keys(r).forEach((k) => keys.add(k));
  console.log('  ' + name + ': ' + rows.length + ' rows, fields = [' + [...keys].sort().join(', ') + ']');
}

console.log('\n=== does ANY field look like a date/time? ===');
for (const name of TABLES) {
  const t = T[name];
  if (!t) continue;
  const rows = Array.isArray(t) ? t : Object.values(t);
  const hits = new Set();
  for (const r of rows) {
    if (!r || typeof r !== 'object') continue;
    for (const k of Object.keys(r)) if (/time|date|day|stamp_time|create|start|end/i.test(k)) hits.add(k);
  }
  console.log('  ' + name + ': ' + (hits.size ? [...hits].join(', ') : 'NONE'));
}

console.log('\n=== formatPathImage coverage for 印章 (stampData) ===');
const stampRows = Object.values(T.stampData || {});
let missing = 0, total = 0;
for (const r of stampRows) {
  const refs = [r.desk_pic].concat(r.stamp_pic || [], r.pattern_pic || []);
  const bad = [];
  for (const ref of refs) {
    if (!ref || !ref.index) continue;
    total++;
    const n = ref.index + '_png';            // Tabikaeru.path.formatPathImage -> `<index>_png`
    if (!exists(n)) { bad.push(n); missing++; }
  }
  if (bad.length) console.log('  stampData[' + r.id + '] MISSING: ' + bad.join(', '));
}
console.log('  stampData refs checked=' + total + ' missing=' + missing + '; state arrays = ' +
  JSON.stringify([...new Set(stampRows.map((r) => JSON.stringify(r.state)))]));

console.log('\n=== formatPathImage coverage for 祈愿物 (prayData / prayBodyData) ===');
let total2 = 0, missing2 = 0;
for (const r of Object.values(T.prayData || {})) {
  const refs = [r.desk_pic].concat((r.wood_body || []).map(() => null), (r.paper || []).map(() => null));
  for (const ref of refs) {
    if (!ref || !ref.index) continue;
    total2++;
    if (!exists(ref.index + '_png')) { missing2++; console.log('  prayData[' + r.id + '] MISSING ' + ref.index + '_png'); }
  }
}
/* the body/paper ids are looked up in prayBodyData, whose pray_pic is what gets drawn */
for (const r of Object.values(T.prayBodyData || {})) {
  if (!r.pray_pic) continue;
  total2++;
  if (!exists(r.pray_pic.index + '_png')) { missing2++; console.log('  prayBodyData[' + r.id + '] MISSING ' + r.pray_pic.index + '_png'); }
}
console.log('  pray refs checked=' + total2 + ' missing=' + missing2 +
  '; prayBodyData ids=' + Object.keys(T.prayBodyData || {}).length +
  '; prayData state = ' + JSON.stringify([...new Set(Object.values(T.prayData || {}).map((r) => JSON.stringify(r.state)))]));
console.log('  prayBodyData sample: ' + JSON.stringify(Object.values(T.prayBodyData || {})[0]));
console.log('  prayNoteData sample: ' + JSON.stringify(Object.values(T.prayNoteData || {})[0]));

console.log('\n=== is there a 印章本 / 图鉴 table for these? ===');
console.log('  gamedata.tables keys containing stamp/pray/word/collect/enc: ' +
  Object.keys(T).filter((k) => /stamp|pray|word|collect|enc/i.test(k)).join(', '));
console.log('  Collection rows: ' + Object.keys(T.Collection || {}).length +
  ', sample: ' + JSON.stringify(Object.values(T.Collection || {})[0]));
console.log('  Word rows: ' + Object.keys(T.Word || {}).length +
  ', sample: ' + JSON.stringify(Object.values(T.Word || {})[0]));
