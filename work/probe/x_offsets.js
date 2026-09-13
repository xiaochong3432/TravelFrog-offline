/* x_offsets.js -- byte offsets + line numbers for the handcraft symbols cited in the
 * report, so every client-side claim maps to a reproducible address.
 * Usage: node work/probe/x_offsets.js
 */
const fs = require('fs');
const F = 'work/run/web/js/main.min.js.clean';
const s = fs.readFileSync(F, 'utf8');
const at = (i) => 'line ' + (s.slice(0, i).split('\n').length) + ' @byte ' + i;
const needles = [
  'HandCraftView=function',
  'HandCraftViewSkin.exml',
  'PrayCraftDetailViewSkin.exml',
  'PrayCraftDetailRender=function',
  'this.l_date.text=core.DateFormat.format(1e3*this.data.data.stamp_time',
  '0!=this.data.data.stamp_time',
  'prayData', 'PrayCraftBodyDB=i("prayBodyData")', 'StampCraftDB=i("stampData")',
  'StampCraftPageView=function',
  'for(var t=e.item,i=[],n=t.state;n>=1;n--)',
  'StampCraftItemRender=function',
  'n.state.indexOf(i);r>=0&&(this.i_layer0.source',
  'PrayCraftItemRender=function',
  'e.wishs', 'e.stamps',
];
for (const n of needles) {
  const i = s.indexOf(n);
  console.log((i < 0 ? 'NOT FOUND  ' : at(i).padEnd(26)) + '  ' + n);
}
console.log('\n-- each occurrence of the state loop / l_date / indexOf --');
for (const n of ['n.state;n>=1;n--', 'l_date.text', 'state.indexOf(i)']) {
  let i = -1;
  while ((i = s.indexOf(n, i + 1)) >= 0) console.log('  ' + at(i) + '  ' + n);
}
