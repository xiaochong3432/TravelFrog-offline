#!/usr/bin/env node

// 仓库根：按本文件自身位置推导，不写死绝对路径
const PROJECT_ROOT = require('path').resolve(__dirname, '..', '..');
/* Decode an encrypted Egret .eab bundle by re-using the CLIENT'S OWN decoder.
 *
 * main.min.js ships two modules we need, verbatim:
 *   var xxtea;!function(e){...}(xxtea||(xxtea={}))   (char 227568..231420)
 *   var eab;!function(e){...}(eab||(eab={}))         (char 231428..~232100)
 * plus Utils.simpleEncrypt (the `k` helper at char ~301862).
 * The `\x1b\n` EAB variant (config.eab) is XXTEA'd; the key is
 *   Utils.simpleEncrypt("r]|lnf\x80X\x81U\x82aq_r", 13)
 * (see main.min.js @231736).
 *
 * Usage: node eab_decode.js <bundle.eab> <entryName> [outFile]
 *        node eab_decode.js <bundle.eab> --list
 */
const fs = require('fs');
const path = require('path');

const JS = PROJECT_ROOT + '/work/base/assets/game/js/main.min.js';
const src = fs.readFileSync(JS, 'utf8');

function slice(fromNeedle, toNeedle) {
  const i = src.indexOf(fromNeedle);
  if (i < 0) throw new Error('not found: ' + fromNeedle);
  const j = src.indexOf(toNeedle, i);
  if (j < 0) throw new Error('end not found: ' + toNeedle);
  return src.slice(i, j + toNeedle.length);
}

const xxteaSrc = slice('var xxtea;', '(xxtea||(xxtea={}));');
const eabSrc = slice('var eab;', '(eab||(eab={}));');
// Utils.simpleEncrypt === function k(e,t){...}
const kSrc = src.slice(src.indexOf('function k(e,t){'), src.indexOf('function P(e){'));
// h()/Utf8ArrayToStr: the eab module references it from the outer scope.
const utf8Src = src.slice(src.indexOf('function h(e){'), src.indexOf('function u(e,n){'));

const sandbox = {};
new Function(
  'exports',
  xxteaSrc + '\n' + eabSrc + '\n' + utf8Src +
  // the client's `h()` is exposed under this name in the eab module's scope
  '\nfunction Utf8ArrayToStr(u8){ return new TextDecoder("utf-8").decode(u8); }' +
  '\nfunction Utils(){} Utils.simpleEncrypt = ' + kSrc.replace(/^function k/, 'function') + ';' +
  '\nexports.xxtea = xxtea; exports.eab = eab; exports.Utils = {simpleEncrypt: Utils.simpleEncrypt};'
)(sandbox);

const xxtea = sandbox.xxtea;
const eab = sandbox.eab;

const bundlePath = process.argv[2];
if (!bundlePath) { console.error('usage: eab_decode.js <bundle.eab> [--list|<entry> [out]]'); process.exit(2); }
const buf = fs.readFileSync(bundlePath);
const decoded = eab.decode(new Uint8Array(buf).buffer);
const manifest = decoded.config;
const raw = new Uint8Array(decoded.raw);

const entry = process.argv[3];
if (!entry || entry === '--list') {
  console.log(`${path.basename(bundlePath)}: ${manifest.length} entries, raw ${raw.length} bytes`);
  for (const e of manifest) console.log(`  ${e.n}\t${e.s}\t${e.t}\t${e.f}`);
  process.exit(0);
}
let off = 0, found = null;
for (const e of manifest) {
  if (e.n === entry) { found = { e, off }; break; }
  off += e.s;
}
if (!found) { console.error('no such entry: ' + entry); process.exit(1); }
const blob = raw.slice(found.off, found.off + found.e.s);
const out = process.argv[4] || path.join(PROJECT_ROOT + '/work/spec', 'eab_' + entry);
fs.writeFileSync(out, Buffer.from(blob));
console.log(`wrote ${out} (${blob.length} bytes)`);
