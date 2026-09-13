#!/usr/bin/env node
'use strict';
/**
 * General-purpose probe for the running offline game over CDP.
 *
 * The screenshot tool (cdp_shot.js) answers "does it look right?". This one
 * answers "is the STATE right?" -- it can tap the canvas to drive the UI and then
 * evaluate arbitrary JS in the page, which is how each gameplay subsystem gets
 * verified (render + state change + persistence) without a device.
 *
 * Both --tap and --eval may be repeated; they are executed in the order given:
 *
 *   node cdp_probe.js --url http://127.0.0.1:18080/index.html --wait 26000 \
 *        --eval "localStorage.getItem('frog.offline.save')" \
 *        --tap 300,900 --wait 2500 \
 *        --eval "JSON.parse(localStorage.getItem('frog.offline.save')).clover" \
 *        --shot after.png
 *
 * A --wait applies to everything that follows it, so interleave to pace a
 * sequence. Output is one JSON line per evaluation, prefixed with its index.
 */
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

function flag(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : dflt;
}

/** Collect an ordered script of the steps given by repeated flags. */
function buildScript() {
  const steps = [];
  const argv = process.argv.slice(2);
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--tap') {
      const [x, y] = String(argv[++i]).split(',').map(Number);
      steps.push({ kind: 'tap', x, y });
    } else if (a === '--drag') {
      const parts = String(argv[++i]).split(',').map(Number);
      steps.push({ kind: 'drag', x0: parts[0], y0: parts[1], x1: parts[2], y1: parts[3] });
    } else if (a === '--eval') {
      steps.push({ kind: 'eval', expr: argv[++i] });
    } else if (a === '--evalfile') {
      steps.push({ kind: 'eval', expr: fs.readFileSync(argv[++i], 'utf8'), label: argv[i] });
    } else if (a === '--wait') {
      steps.push({ kind: 'wait', ms: Number(argv[++i]) });
    } else if (a === '--reload') {
      steps.push({ kind: 'reload' });
    } else if (a === '--shot') {
      steps.push({ kind: 'shot', out: argv[++i] });
    }
  }
  return steps;
}

const url = flag('url', 'http://127.0.0.1:18080/index.html');
const cdpPort = Number(flag('port', 9230));
const width = Number(flag('width', 720));
const height = Number(flag('height', 1280));
const script = buildScript();

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
    ws.addEventListener('open', () => resolve({
      send(method, params) {
        const mid = ++id;
        return new Promise((res, rej) => {
          pending.set(mid, { res, rej });
          ws.send(JSON.stringify({ id: mid, method, params: params || {} }));
        });
      },
      close() { try { ws.close(); } catch (e) {} },
    }));
  });
}

async function evaluate(client, expr) {
  const r = await client.send('Runtime.evaluate', {
    expression: `(function(){ try { return JSON.stringify(${expr}); }
      catch (e) { return JSON.stringify({ __error: String(e && e.stack || e) }); } })()`,
    returnByValue: true,
    awaitPromise: false,
  });
  if (r.exceptionDetails) {
    return { __error: 'exception: ' + (r.exceptionDetails.text || 'unknown') };
  }
  const raw = r.result && r.result.value;
  try { return JSON.parse(raw); } catch (e) { return raw; }
}

async function tap(client, x, y) {
  for (const type of ['mousePressed', 'mouseReleased']) {
    await client.send('Input.dispatchMouseEvent', {
      type, x, y, button: 'left', clickCount: 1,
      buttons: type === 'mousePressed' ? 1 : 0,
    });
    await sleep(60);
  }
}

/**
 * A real drag: press, move in steps, release. Used for the 存档编辑 ball, where the
 * interesting part is that a DRAG must not be mistaken for a tap (and vice versa) --
 * so this goes through the browser's own input path, not synthetic DOM events.
 */
async function drag(client, x0, y0, x1, y1) {
  await client.send('Input.dispatchMouseEvent', {
    type: 'mousePressed', x: x0, y: y0, button: 'left', clickCount: 1, buttons: 1,
  });
  await sleep(50);
  const steps = 8;
  for (let i = 1; i <= steps; i++) {
    await client.send('Input.dispatchMouseEvent', {
      type: 'mouseMoved',
      x: Math.round(x0 + (x1 - x0) * i / steps),
      y: Math.round(y0 + (y1 - y0) * i / steps),
      button: 'left', buttons: 1,
    });
    await sleep(30);
  }
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseReleased', x: x1, y: y1, button: 'left', clickCount: 1, buttons: 0,
  });
  await sleep(80);
}

(async () => {
  const profile = path.join(os.tmpdir(), 'edge-probe-' + Date.now());
  const proc = spawn(EDGE, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    '--disable-extensions', '--enable-unsafe-swiftshader', '--use-angle=swiftshader',
    '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', '--mute-audio',
    `--remote-debugging-port=${cdpPort}`, `--window-size=${width},${height}`,
    `--user-data-dir=${profile}`, url,
  ], { stdio: 'ignore' });

  let failures = 0;
  try {
    const target = await getTarget();
    const client = await cdp(target.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');

    let evalIndex = 0;
    for (const step of script) {
      if (step.kind === 'wait') {
        await sleep(step.ms);
      } else if (step.kind === 'tap') {
        await tap(client, step.x, step.y);
        console.log(`tap ${step.x},${step.y}`);
      } else if (step.kind === 'drag') {
        await drag(client, step.x0, step.y0, step.x1, step.y1);
        console.log(`drag ${step.x0},${step.y0} -> ${step.x1},${step.y1}`);
      } else if (step.kind === 'reload') {
        await client.send('Page.reload', { ignoreCache: false });
        console.log('reload');
      } else if (step.kind === 'shot') {
        const s = await client.send('Page.captureScreenshot', { format: 'png' });
        fs.writeFileSync(step.out, Buffer.from(s.data, 'base64'));
        console.log(`shot -> ${step.out}`);
      } else if (step.kind === 'eval') {
        const v = await evaluate(client, step.expr);
        console.log(`eval[${evalIndex++}] ${JSON.stringify(v)}`);
        if (v && v.__error) failures++;
      }
    }
    client.close();
  } catch (e) {
    console.error('FAILED:', e.message);
    failures++;
  } finally {
    try { proc.kill(); } catch (e) {}
    await sleep(400);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) {}
  }
  if (failures) console.log(`\n${failures} evaluation(s) failed`);
  process.exitCode = failures ? 1 : 0;
})();
