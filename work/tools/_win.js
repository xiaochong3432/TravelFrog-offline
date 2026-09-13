// usage: node _win.js <file> <literal> [before] [after] [maxHits]
const fs = require('fs');
const [file, lit, before = 120, after = 200, maxHits = 10] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
let i = 0, n = 0;
while ((i = src.indexOf(lit, i)) !== -1 && n < Number(maxHits)) {
  n++;
  const s = Math.max(0, i - Number(before));
  const e = Math.min(src.length, i + lit.length + Number(after));
  const line = src.slice(0, i).split('\n').length;
  console.log('--- #' + n + ' line ' + line + ' off ' + i + ' ---');
  console.log(src.slice(s, e).replace(/\n/g, '\\n'));
  i += lit.length;
}
if (!n) console.log('NO MATCH for ' + JSON.stringify(lit));
