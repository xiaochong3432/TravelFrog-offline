/* x_annual_region.js -- does the 年度总结 (annual review) region draw ANY image, or
 * carry a date? If not, the player's "手工品 栏 / 图片为空白" cannot be that view.
 * Usage: node work/probe/x_annual_region.js
 */
const fs = require('fs');
const file = 'work/run/web/js/main.min.js.clean';
const s = fs.readFileSync(file, 'utf8');
const a = 510468, b = 521000;
const region = s.slice(a, b);
console.log('annual-review region ' + a + '..' + b + ' (' + region.length + ' chars)');
console.log('--- `.source = "..."` assignments ---');
const re = /[A-Za-z_$.]{0,24}\.source\s*=\s*"[^"]*"/g;
let m, n = 0;
while ((m = re.exec(region)) !== null) { n++; console.log('  @' + (a + m.index) + '  ' + m[0]); }
if (!n) console.log('  NONE');
console.log('--- art names (stamp_pic / pray_pic / woodN / paperN) ---');
console.log('  ' + (region.match(/stamp_pic|pray_pic|wood[0-9]|paper[0-9]/g) || ['NONE']).join(', '));
console.log('--- date formatting ---');
console.log('  ' + (region.match(/DateFormat|YYYY|MM\.DD|yyyy/gi) || ['NONE']).join(', '));
console.log('--- payload fields read ---');
const f = {};
const rf = /\bt\.([A-Za-z_][A-Za-z0-9_]*)/g;
while ((m = rf.exec(region)) !== null) f[m[1]] = (f[m[1]] || 0) + 1;
console.log('  ' + Object.keys(f).sort().join(', '));
