// usage: node _slice.js <file> <line> <startCol> <endCol>
const fs = require('fs');
const [file, lineNo, sc, ec] = process.argv.slice(2);
const lines = fs.readFileSync(file, 'utf8').split('\n');
const L = lines[Number(lineNo) - 1];
if (L === undefined) { console.log('no such line'); process.exit(0); }
console.log(L.slice(Number(sc), Number(ec)));
