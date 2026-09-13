// hunt_layers.js -- read-only scan: find any file in the repo that contains a
// REAL (server-shaped) picture layer array, i.e. `layers` next to `pic_id`.
// Usage: node work/probe/hunt_layers.js [rootDir]
const fs = require('fs');
const path = require('path');

const roots = process.argv.slice(2);
const ROOT = roots.length ? roots : ['H:/AI/frog'];
const SKIP = /(^|[\\/])(\.git|node_modules|dist|__pycache__|shots)([\\/]|$)/i;
const NEST = /(^|[\\/])(\.git|node_modules|dist|__pycache__|shots|base|full|extracted|work_extract|pristine|compare-eab|compare-res|from-their-apk|jp_apk)([\\/]|$)/i;
const TEXT = /\.(json|txt|log|js|mjs|md|html|out|lua|xml|py|clean|orig)$/i;
const MAX = 8 * 1024 * 1024;

const hits = [];
let scanned = 0;

function walk(dir, depth) {
  if (depth > 8) return;
  let ents;
  try { ents = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
  for (const e of ents) {
    const p = path.join(dir, e.name);
    if (SKIP.test(p)) continue;
    if (e.isDirectory()) { walk(p, depth + 1); continue; }
    if (!TEXT.test(e.name)) continue;
    let st; try { st = fs.statSync(p); } catch (err) { continue; }
    if (st.size > MAX) continue;
    let s; try { s = fs.readFileSync(p, 'utf8'); } catch (err) { continue; }
    scanned++;
    if (!/layers/.test(s)) continue;
    // real server shape: layers arrays of numbers, or a pic_list entry
    const re = /.{0,160}layers.{0,220}/g;
    let m, n = 0;
    while ((m = re.exec(s)) && n < 4) {
      n++;
      const frag = m[0].replace(/\s+/g, ' ');
      if (/\[\s*\[\s*\d+\s*,\s*-?\d+\s*,\s*-?\d+/.test(m[0]) || /pic_id/.test(m[0])) {
        hits.push({ file: p, frag: frag.slice(0, 340) });
      }
    }
  }
}

for (const r of ROOT) walk(r, 0);
console.log('files scanned: ' + scanned);
console.log('hits: ' + hits.length);
const byFile = {};
for (const h of hits) (byFile[h.file] = byFile[h.file] || []).push(h.frag);
for (const f of Object.keys(byFile)) {
  console.log('\n=== ' + f + '  (' + byFile[f].length + ' hits) ===');
  for (const fr of byFile[f].slice(0, 3)) console.log('   ' + fr);
}
