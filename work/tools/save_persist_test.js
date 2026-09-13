#!/usr/bin/env node
'use strict';
/**
 * Proves the save actually round-trips through localStorage across a page reload.
 *
 * The reported bug was "quit and reopen the app -> save is gone". The cause was
 * mine: the asset server bound to a RANDOM port (`new ServerSocket(0)`), and
 * localStorage is partitioned per ORIGIN -- scheme + host + port -- so every
 * launch was a brand new origin with an empty store. Fixed by pinning the port.
 *
 * This test drives the real page over CDP and checks the two halves separately:
 *   1. WRITE: engine.save()/importSave() land in localStorage
 *   2. READ:  after a reload the engine comes back with the persisted value
 *
 *   node save_persist_test.js --url http://127.0.0.1:18080/index.html
 */
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : dflt;
}

const url = arg('url', 'http://127.0.0.1:18080/index.html');
const port = Number(arg('port', 9222));
const bootWait = Number(arg('bootwait', 26000));
const MARK = Number(arg('mark', 4321));

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function getTarget() {
  for (let i = 0; i < 40; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${port}/json/list`);
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
    throw new Error('page exception: ' + JSON.stringify(r.exceptionDetails.text || r.exceptionDetails));
  }
  return r.result && r.result.value;
}

const READ_LOCAL = `(function () {
  try {
    var raw = localStorage.getItem('frog.offline.save');
    if (raw == null) return { present: false };
    var o = JSON.parse(raw);
    return { present: true, clover: o.clover, origin: location.origin };
  } catch (e) { return { error: String(e) }; }
})()`;

/* Create a fresh engine through the SAME entry point the game uses, so this
   exercises the real localStorage-backed fs shim. */
const engineClover = `(function () {
  if (!window.FrogEngine) return { error: 'FrogEngine missing' };
  var e = window.FrogEngine.createEngine({ savePath: 'save.json' });
  return { clover: e.state.clover, origin: location.origin };
})()`;

(async () => {
  const profile = path.join(os.tmpdir(), 'edge-save-' + Date.now());
  const args = [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    '--disable-extensions', '--enable-unsafe-swiftshader', '--use-angle=swiftshader',
    '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', '--mute-audio',
    `--remote-debugging-port=${port}`, '--window-size=720,1280',
    `--user-data-dir=${profile}`, url,
  ];
  console.log('launching edge...');
  const proc = spawn(EDGE, args, { stdio: 'ignore' });
  let failures = 0;

  try {
    const target = await getTarget();
    const client = await cdp(target.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');

    console.log(`waiting ${bootWait}ms for boot...`);
    await sleep(bootWait);

    // ---- 1. what the engine does on a fresh origin
    const before = await evaluate(client, READ_LOCAL);
    const eng1 = await evaluate(client, engineClover);
    console.log('after first boot :', JSON.stringify(before), JSON.stringify(eng1));

    // ---- 2. WRITE path: importSave() calls the engine's save() -> the fs shim
    const wrote = await evaluate(client, `(function () {
      var e = window.FrogEngine.createEngine({ savePath: 'save.json' });
      var s = e.exportSave();
      s.clover = ${MARK};
      e.importSave(s);
      var raw = localStorage.getItem('frog.offline.save');
      return { wrote: raw != null, clover: raw ? JSON.parse(raw).clover : null };
    })()`);
    console.log('after write      :', JSON.stringify(wrote));
    if (!wrote || wrote.clover !== MARK) {
      console.log(`  FAIL: write path did not persist clover=${MARK}`);
      failures++;
    }

    // ---- 3. READ path across a real reload
    console.log('reloading page...');
    await client.send('Page.reload', { ignoreCache: false });
    await sleep(bootWait);

    const after = await evaluate(client, READ_LOCAL);
    const eng2 = await evaluate(client, engineClover);
    console.log('after reload     :', JSON.stringify(after), JSON.stringify(eng2));

    if (!after || after.clover !== MARK) {
      console.log(`  FAIL: localStorage lost clover (expected ${MARK})`);
      failures++;
    }
    if (!eng2 || eng2.clover !== MARK) {
      console.log(`  FAIL: engine did not read back clover=${MARK}`);
      failures++;
    }
    if (before && after && before.origin !== after.origin) {
      console.log(`  FAIL: origin changed across reload (${before.origin} -> ${after.origin})`);
      failures++;
    }

    client.close();
  } catch (e) {
    console.error('FAILED:', e.message);
    failures++;
  } finally {
    try { proc.kill(); } catch (e) {}
    await sleep(500);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) {}
  }

  console.log(failures === 0 ? '\nRESULT: PASS' : `\nRESULT: FAIL (${failures})`);
  process.exitCode = failures === 0 ? 0 : 1;
})();
