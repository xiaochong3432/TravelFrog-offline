// usage: node _owner.js <file> <offset>
const fs = require('fs');
const [file, off] = process.argv.slice(2);
const src = fs.readFileSync(file, 'utf8');
const i = Number(off);
const line = src.slice(0, i).split('\n').length;
const col = i - src.lastIndexOf('\n', i - 1);
console.log('offset ' + i + ' -> line ' + line + ' col ' + col);
const re = /__reflect\(([A-Za-z_$][\w$]*)\.prototype,"([\w$]+)"\)/g;
let m, prev = null;
while ((m = re.exec(src))) {
  if (m.index < i) prev = m; else break;
}
console.log('enclosing class (last __reflect before): ' + (prev ? prev[2] + ' at off ' + prev.index : 'none'));
if (m) console.log('next class after: ' + m[2] + ' at off ' + m.index);
