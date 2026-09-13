// usage: node _ctxfind.js <file> <regex> [before] [after] [maxHits]
const fs = require('fs');
const [file, pat, before = 200, after = 600, maxHits = 20] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
const re = new RegExp(pat, 'g');
let m, n = 0;
while ((m = re.exec(src)) && n < Number(maxHits)) {
  n++;
  const s = Math.max(0, m.index - Number(before));
  const e = Math.min(src.length, m.index + m[0].length + Number(after));
  // compute line number
  const line = src.slice(0, m.index).split('\n').length;
  const col = m.index - src.lastIndexOf('\n', m.index - 1);
  console.log('=== #' + n + ' line ' + line + ' col ' + col + ' ===');
  console.log(src.slice(s, e).replace(/\n/g, '\\n'));
  console.log('');
}
if (!n) console.log('NO MATCH');
