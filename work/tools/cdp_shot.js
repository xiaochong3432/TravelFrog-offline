#!/usr/bin/env node
'use strict';
/**
 * Reliable wall-clock screenshot via Chrome DevTools Protocol.
 * Uses Node's built-in WebSocket client (Node >= 22), so no dependencies.
 *
 *   node cdp_shot.js --url <pageUrl> --out shot.png [--wait 25000]
 *                    [--port 9222] [--width 640] [--height 1136] [--tap x,y]
 *
 * Launches its own headless Edge, waits real time, optionally taps, screenshots.
 */
const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i >= 0 && process.argv[i + 1] !== undefined ? process.argv[i + 1] : dflt;
}

const url = arg('url', 'http://127.0.0.1:8080/index.html');
const out = path.resolve(arg('out', 'shot.png'));
const waitMs = Number(arg('wait', 25000));
const port = Number(arg('port', 9222));
const width = Number(arg('width', 640));
const height = Number(arg('height', 1136));
const tapAt = arg('tap', null);
const tapDelay = Number(arg('tapdelay', 0));

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
    ws.addEventListener('error', (e) => reject(new Error('ws error')));
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

(async () => {
  const profile = path.join(os.tmpdir(), 'edge-cdp-' + Date.now());
  const args = [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    '--disable-extensions', '--enable-unsafe-swiftshader', '--use-angle=swiftshader',
    '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', '--mute-audio',
    `--remote-debugging-port=${port}`, `--window-size=${width},${height}`,
    `--user-data-dir=${profile}`, url,
  ];
  console.log('launching edge...');
  const proc = spawn(EDGE, args, { stdio: 'ignore' });

  try {
    const target = await getTarget();
    console.log('page target:', target.url);
    const client = await cdp(target.webSocketDebuggerUrl);
    await client.send('Page.enable');
    await client.send('Runtime.enable');

    if (tapAt && tapDelay > 0) await sleep(tapDelay);
    if (tapAt) {
      const [x, y] = tapAt.split(',').map(Number);
      for (const type of ['mousePressed', 'mouseReleased']) {
        await client.send('Input.dispatchMouseEvent', {
          type, x, y, button: 'left', clickCount: 1,
          buttons: type === 'mousePressed' ? 1 : 0,
        });
        await sleep(60);
      }
      console.log(`tapped ${x},${y}`);
      await sleep(4000);
    }

    console.log(`waiting ${waitMs}ms...`);
    await sleep(waitMs);

    const shot = await client.send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(out, Buffer.from(shot.data, 'base64'));
    console.log(`screenshot -> ${out} (${fs.statSync(out).size} bytes)`);
    client.close();
  } catch (e) {
    console.error('FAILED:', e.message);
    process.exitCode = 1;
  } finally {
    try { proc.kill(); } catch (e) {}
    await sleep(500);
    try { fs.rmSync(profile, { recursive: true, force: true }); } catch (e) {}
  }
})();
