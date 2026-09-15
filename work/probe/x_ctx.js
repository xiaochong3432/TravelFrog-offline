/* x_ctx.js — print byte-offset contexts for regex hits in a minified bundle.
 * Usage: node work/probe/x_ctx.js <file> <regex> [before] [after] [maxHits]
 * The .clean bundle is one giant line, so line numbers are useless there;
 * every hit is reported as file@BYTE_OFFSET so findings stay reproducible.
 */
const fs = require('fs');
const [file, pattern, before = '160', after = '400', maxHits = '12'] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
const re = new RegExp(pattern, 'g');
let m, n = 0;
while ((m = re.exec(src)) !== null && n < Number(maxHits)) {
  n++;
  const s = Math.max(0, m.index - Number(before));
  const e = Math.min(src.length, m.index + m[0].length + Number(after));
  console.log('=== hit ' + n + ' @byte ' + m.index + ' len ' + m[0].length +
    ' (line ' + (src.slice(0, m.index).split('\n').length) + ') ===');
  console.log(src.slice(s, e).replace(/\n/g, '\\n'));
  console.log('');
}
console.log('[hits shown: ' + n + ']');
