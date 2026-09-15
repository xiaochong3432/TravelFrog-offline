#!/usr/bin/env node
'use strict';
/**
 * Restart-persistence test -- the real analogue of "quit the app and reopen it".
 *
 * A page reload is not enough: it keeps the same process. This test:
 *
 *   run 1  boot page on port A, write a marker save, shut the browser DOWN
 *   run 2  relaunch the SAME profile on port A -> marker must still be there
 *   run 3  same profile but port B -> marker must be GONE
 *
 * Run 2 is the fix (the port, and therefore the origin, is now stable).
 * Run 3 demonstrates the original bug: localStorage is partitioned per origin and
 * the origin includes the port, so the old random-port server handed the page a
 * new, empty origin on every launch.
 *
 *   node save_restart_test.js --urlA http://127.0.0.1:18080/index.html \
 *                             --urlB http://127.0.0.1:18081/index.html
 */
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

/* 浏览器可执行文件：$FROG_BROWSER 优先，否则按各系统的常见位置与 PATH 查找
   （Edge / Chrome；Windows、macOS、Linux 都试一遍），不再写死某一台机器的路径。 */
const EDGE = (function () {
  const fs = require('fs');
  const cp = require('child_process');
  const env = process.env.FROG_BROWSER;
  if (env && fs.existsSync(env)) return env;
  const cands = process.platform === 'win32' ? [
    'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe',
    'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe',
    'C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe',
  ] : [
    '/usr/bin/microsoft-edge', '/usr/bin/microsoft-edge-stable',
    '/usr/bin/google-chrome', '/usr/bin/google-chrome-stable',
    '/usr/bin/chromium', '/usr/bin/chromium-browser',
    '/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ];
  for (const c of cands) { try { if (fs.existsSync(c)) return c; } catch (e) { /* skip */ } }
  for (const name of ['msedge', 'microsoft-edge', 'google-chrome', 'chromium']) {
    try {
      const out = cp.execSync((process.platform === 'win32' ? 'where ' : 'command -v ') + name,
        { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim().split(/\r?\n/)[0];
      if (out) return out;
    } catch (e) { /* not on PATH */ }
  }
  console.error('找不到 Edge/Chrome：请设置 FROG_BROWSER=<浏览器可执行文件路径>');
  process.exit(2);
})();

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : dflt;
}

const urlA = arg('urlA', 'http://127.0.0.1:18080/index.html');
const urlB = arg('urlB', 'http://127.0.0.1:18081/index.html');
const cdpPort = Number(arg('port', 9224));
const bootWait = Number(arg('bootwait', 26000));
const MARK = Number(arg('mark', 7777));

const profile = arg('profile', path.join(os.tmpdir(), 'edge-restart-fixed'));
fs.rmSync(profile, { recursive: true, force: true });

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function getTarget() {
  for (let i = 0; i < 50; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${cdpPort}/json/list`);
      const list = await res.json();
      const page = list.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page;
    } catch (e) { /* not up yet */ }
    await sleep(400);
  }
  throw new Error('no CDP page target');
}

function cdp(wsUrl) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    let id = 0;
    const pending = new Map();
    ws.addEventListener('message', (ev) => {
      let msg;
      try { msg = JSON.parse(ev.data); } catch (e) { return; }
      if (msg.id && pending.has(msg.id)) {
        const { res, rej } = pending.get(msg.id);
        pending.delete(msg.id);
        msg.error ? rej(new Error(JSON.stringify(msg.error))) : res(msg.result);
      }
    });
    ws.addEventListener('error', () => reject(new Error('ws error')));
    ws.addEventListener('open', () => {
      resolve({
        send(method, params) {
          const mid = ++id;
          return new Promise((res, rej) => {
            pending.set(mid, { res, rej });
            ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
          });
        },
        close() { try { ws.close(); } catch (e) {} },
      });
    });
  });
}

async function evaluate(client, expression) {
  const r = await client.send('Runtime.evaluate', {
    expression, returnByValue: true, awaitPromise: false,
  });
  if (r.exceptionDetails) {
    // Report the WHOLE detail: "Uncaught" alone sent me hunting for a bug in the page
    // when the real cause was the page not being loaded at all.
    throw new Error('page exception: ' + JSON.stringify(r.exceptionDetails));
  }
  return r.result && r.result.value;
}

const READ = `(function () {
  try {
    var raw = localStorage.getItem('frog.offline.save');
    if (raw == null) return { present: false, origin: location.origin };
    return { present: true, clover: JSON.parse(raw).clover, origin: location.origin };
  } catch (e) { return { error: String(e) }; }
})()`;

/** One full browser session: launch, wait for boot, run `action`, shut down. */
async function session(label, url, action) {
  console.log(`\n--- ${label} ---`);
  const proc = spawn(EDGE, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    '--disable-extensions', '--enable-unsafe-swiftshader', '--use-angle=swiftshader',
    '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', '--mute-audio',
    `--remote-debugging-port=${cdpPort}`, '--window-size=720,1280',
    `--user-data-dir=${profile}`, url,
  ], { stdio: 'ignore' });

  let client = null;
  try {
    const target = await getTarget();
    client = await cdp(target.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    console.log(`booting (${bootWait}ms)...`);
    await sleep(bootWait);
    const value = await action(client);
    // Graceful shutdown so localStorage is flushed to disk -- killing the process
    // outright could lose the write and make this test lie.
    try { await client.send('Browser.close'); } catch (e) { /* expected */ }
    await sleep(3000);
    if (!proc.killed) proc.kill();
    await sleep(1500);
    return value;
  } catch (e) {
    try { proc.kill(); } catch (ignored) {}
    throw e;
  } finally {
    if (client) client.close();
  }
}

(async () => {
  let failures = 0;
  try {
    // run 1: write the marker
    const r1 = await session('run 1: write marker', urlA, async (c) => {
      const before = await evaluate(c, READ);
      const wrote = await evaluate(c, `(function () {
        var e = window.FrogEngine.createEngine({ savePath: 'save.json' });
        var s = e.exportSave();
        s.clover = ${MARK};
        e.importSave(s);
        return JSON.parse(localStorage.getItem('frog.offline.save')).clover;
      })()`);
      console.log('  before:', JSON.stringify(before), ' wrote clover=', wrote);
      if (wrote !== MARK) failures++;
      return before;
    });

    // run 2: same origin -> the whole point of the fix
    const r2 = await session('run 2: SAME port, fresh browser process', urlA, async (c) => {
      const now = await evaluate(c, READ);
      console.log('  after restart:', JSON.stringify(now));
      if (!now || now.clover !== MARK) {
        console.log(`  FAIL: save did not survive a browser restart (expected ${MARK})`);
        failures++;
      }
      return now;
    });

    // run 3: different port -> proves the original root cause
    const r3 = await session('run 3: DIFFERENT port (the old random-port bug)', urlB, async (c) => {
      const now = await evaluate(c, READ);
      console.log('  other origin:', JSON.stringify(now));
      if (now && now.clover === MARK) {
        console.log(`  UNEXPECTED: the other port can see the marker (${MARK})`);
        failures++;
      } else {
        console.log(`  as expected: a different port is a different origin, so it has its`);
        console.log(`  own store (clover=${now && now.clover}) and cannot see the marker ${MARK}.`);
        console.log('  This is exactly the old bug: a fresh frog on every random port.');
      }
      return now;
    });

    console.log('\n---------------- summary ----------------');
    console.log(`origin used           : ${(r1 && r1.origin) || urlA}`);
    console.log(`write marker          : clover=${MARK}`);
    console.log(`survived browser quit : ${r2 && r2.clover === MARK ? 'YES' : 'NO'}`);
    console.log(`other port sees marker: ${r3 && r3.clover === MARK ? 'YES (bad)' : 'no (as expected)'}`);
  } catch (e) {
    console.error('FAILED:', e.message);
    failures++;
  } finally {
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) {}
  }
  console.log(failures === 0 ? '\nRESULT: PASS' : `\nRESULT: FAIL (${failures})`);
  process.exitCode = failures === 0 ? 0 : 1;
})();
