/* x_slice.js — dump [start,start+len) of a file (minified bundles have no useful
 * line numbers, so ranges are addressed by byte offset).
 * Usage: node work/probe/x_slice.js <file> <start> <len>
 */
const fs = require('fs');
const [file, start, len] = process.argv.slice(2);
const s = fs.readFileSync(file, 'utf8');
const a = Number(start);
console.log(s.slice(a, a + Number(len)));
