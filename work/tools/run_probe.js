#!/usr/bin/env node
'use strict';
/**
 * Run a browser-style probe (work/probe/*.js) against the engine in plain Node.
 *
 * WHY: those probes only use `window.FrogEngine` and `dispatch`, so the browser is
 * not actually required -- and running them here is seconds instead of a 40s Edge
 * boot, with no localStorage in the way. That matters when a check is off by 2 and
 * you need to know whether the drift is the engine's or the harness's.
 *
 * Usage:
 *   node tools/run_probe.js work/probe/persist_sweep.js
 *   node tools/run_probe.js work/probe/persist_verify.js --same-dir <dir>
 *
 * IMPORTANT: the probes hardcode RELATIVE save paths (`savePath: 'sweep.json'`),
 * which Node resolves against the process CWD. Running two probes from the repo
 * root therefore shares one file and state accumulates across runs -- that is what
 * made persist_verify report a 3-item recycle bin after a single delete. So each
 * invocation runs inside a fresh temp CWD unless --same-dir keeps one around for a
 * sweep/verify pair.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const engineModule = require(path.join(ROOT, 'work', 'run', 'engine', 'index.js'));

const file = process.argv[2];
if (!file) {
  console.error('usage: node tools/run_probe.js <probe.js> [--same-dir <dir>]');
  process.exit(2);
}
const si = process.argv.indexOf('--same-dir');
const startCwd = process.cwd();                 // resolve the probe against where it was invoked
const cwd = si > 0 ? path.resolve(process.argv[si + 1])
  : fs.mkdtempSync(path.join(os.tmpdir(), 'frog-probe-'));
fs.mkdirSync(cwd, { recursive: true });
process.chdir(cwd);

// the probes expect a browser-ish global
global.window = global.window || {};
global.window.FrogEngine = engineModule;
global.FrogEngine = engineModule;

const src = fs.readFileSync(path.resolve(startCwd, file), 'utf8');
// The probes are IIFEs; evaluate as an expression so their return value comes back.
let result;
try {
  result = eval(`(${src}\n)`);            // eslint-disable-line no-eval
} catch (e) {
  console.error('probe threw:', e && e.stack || e);
  process.exit(1);
}
console.log(JSON.stringify({
  probe: path.basename(file),
  cwd,
  result: typeof result === 'string' ? JSON.parse(result) : result,
}, null, 1));
