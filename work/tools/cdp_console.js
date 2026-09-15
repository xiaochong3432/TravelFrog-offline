#!/usr/bin/env node
'use strict';
/**
 * Console/exception capture probe.
 *
 * WHY THIS EXISTS: every other probe in this directory drives the engine by
 * calling `FrogEngine.dispatch(...)` directly, so a JS error thrown by the GAME
 * UI never shows up -- the engine keeps answering happily while the page is
 * broken. `cdp_probe.js` also does not subscribe to Runtime exceptions, so a
 * crash loop is invisible to it.
 *
 * The client turns any uncaught JS error into a modal ("呱呱，吃坏肚子了，快重启
 * 一下游戏！" = Reload.JSError) and then RELOADS, so the same error repeats
 * forever and the player can never get in. This tool prints the actual error.
 *
 * Usage:
 *   node tools/cdp_console.js --url http://127.0.0.1:18080/index.html \
 *        --wait 34000 [--settle 3000]
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

const url = arg('url', 'http://127.0.0.1:18080/index.html');
const cdpPort = Number(arg('port', 9229));
const bootWait = Number(arg('wait', 34000));
const settle = Number(arg('settle', 3000));
const width = Number(arg('width', 626));
const height = Number(arg('height', 1136));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getTarget() {
  for (let i = 0; i < 60; i++) {
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

function cdp(wsUrl, onEvent) {
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
      } else if (msg.method && onEvent) {
        onEvent(msg);
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
      close() { try { ws.close(); } catch (e) { } },
    }));
  });
}

(async () => {
  const profile = path.join(os.tmpdir(), 'edge-console-' + Date.now());
  const proc = spawn(EDGE, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    '--disable-extensions', '--enable-unsafe-swiftshader', '--use-angle=swiftshader',
    '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', '--mute-audio',
    `--remote-debugging-port=${cdpPort}`, `--window-size=${width},${height}`,
    `--user-data-dir=${profile}`, url,
  ], { stdio: 'ignore' });

  const exceptions = [];
  const errors = [];
  const warnings = [];
  const logs = [];
  let navCount = 0;

  const onEvent = (msg) => {
    if (msg.method === 'Page.frameNavigated') {
      navCount++;
      console.log(`\n--- navigation #${navCount} -> ${msg.params.frame.url}`);
      return;
    }
    if (msg.method === 'Page.frameStartedLoading') {
      console.log('--- frame started loading (a reload)');
      return;
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      const text = (d.exception && (d.exception.description || d.exception.value)) || d.text;
      const where = d.url ? ` @ ${d.url}:${d.lineNumber + 1}:${d.columnNumber + 1}` : '';
      exceptions.push(String(text) + where);
      console.log(`\n!!! EXCEPTION${where}\n${text}`);
      return;
    }
    if (msg.method === 'Log.entryAdded') {
      const e = msg.params.entry;
      const line = `[${e.level}] ${e.text}${e.url ? ' @ ' + e.url : ''}`;
      if (e.level === 'error') { errors.push(line); console.log('\n!!! LOG ' + line); }
      else if (e.level === 'warning') warnings.push(line);
      else logs.push(line);
      return;
    }
    if (msg.method === 'Runtime.consoleAPICalled') {
      const type = msg.params.type;
      const text = (msg.params.args || []).map((a) => {
        if (a.value !== undefined) return String(a.value);
        if (a.description) return String(a.description);
        return a.type;
      }).join(' ');
      const line = `[console.${type}] ${text}`;
      if (type === 'error') { errors.push(line); console.log('\n!!! CONSOLE ' + line); }
      else if (type === 'warning') warnings.push(line);
      else logs.push(line);
    }
  };

  try {
    const target = await getTarget();
    const client = await cdp(target.webSocketDebuggerUrl, onEvent);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Log.enable');

    console.log(`waiting ${bootWait}ms for boot...`);
    await sleep(bootWait);
    console.log(`settling ${settle}ms...`);
    await sleep(settle);

    // how many times did the page reload? a crash loop reloads repeatedly
    const r = await client.send('Runtime.evaluate', {
      expression: 'JSON.stringify({ ua: navigator.userAgent.slice(0,40), hasEngine: !!window.FrogEngine, href: location.href })',
      returnByValue: true,
    });
    console.log('\n=== page state ===');
    console.log(r.result && r.result.value);

    client.close();
  } catch (e) {
    console.error('probe failed:', e.message);
  } finally {
    try { proc.kill(); } catch (e) { }
  }

  console.log('\n=== SUMMARY ===');
  console.log(`navigations  : ${navCount}${navCount > 2 ? '  <-- RELOAD LOOP' : ''}`);
  console.log(`exceptions   : ${exceptions.length}`);
  console.log(`errors       : ${errors.length}`);
  console.log(`warnings     : ${warnings.length}`);
  if (exceptions.length) {
    console.log('\n--- distinct exceptions ---');
    for (const e of Array.from(new Set(exceptions)).slice(0, 10)) console.log('  ' + e);
  }
  if (errors.length) {
    console.log('\n--- distinct errors ---');
    for (const e of Array.from(new Set(errors)).slice(0, 10)) console.log('  ' + e);
  }
  if (warnings.length) {
    console.log('\n--- distinct warnings ---');
    for (const e of Array.from(new Set(warnings)).slice(0, 20)) console.log('  ' + e);
  }
  process.exitCode = exceptions.length || errors.length ? 1 : 0;
})();
