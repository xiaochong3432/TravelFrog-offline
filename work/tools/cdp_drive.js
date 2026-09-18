#!/usr/bin/env node
'use strict';
/**
 * Headless-Edge UI driver for the offline build.
 *
 * WHY THIS EXISTS: cdp_console.js answers "did the page throw?"; it cannot
 * answer "what does the calendar actually show?" or "what happens when I tap
 * that button?". Guessing those from the minified client is exactly the failure
 * mode this project keeps hitting, so this tool drives the real page instead.
 *
 * Steps run IN ORDER, which is the whole point: find a node, tap it, screenshot,
 * then re-read state -- in one browser session.
 *
 *   --step eval:<js>      evaluate in the page (await allowed, object returned)
 *   --step in:<file>      evaluate the file's contents (await allowed)
 *   --step tap:x,y        real mouse press+release at viewport coords
 *   --step wait:ms        sleep
 *   --step shot:<file>    PNG screenshot
 *   --step log           print window.__probeLog (the in-page probe log)
 *
 * Other flags: --url --port --wait(boot) --settle --width --height
 *              --profile <dir>  persistent profile so the SAVE SURVIVES across
 *                               runs (default work/shots/edge-profile)
 *              --fresh          delete that profile first
 *              --keep           leave the browser up for 10 minutes
 *
 * Exit code is 1 if the page threw any uncaught exception.
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
function flag(name) { return process.argv.indexOf('--' + name) >= 0; }
function all(name) {
  const out = [];
  process.argv.forEach((a, i) => { if (a === '--' + name) out.push(process.argv[i + 1]); });
  return out;
}

const url = arg('url', 'http://127.0.0.1:8080/index.html');
const cdpPort = Number(arg('port', 9229));
const bootWait = Number(arg('wait', 32000));
const settle = Number(arg('settle', 1500));
const width = Number(arg('width', 626));
const height = Number(arg('height', 1136));
const steps = all('step');
const keep = flag('keep');
const profile = path.resolve(arg('profile', path.join(__dirname, '..', 'shots', 'edge-profile')));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function getTarget() {
  for (let i = 0; i < 100; i++) {
    try {
      const res = await fetch(`http://127.0.0.1:${cdpPort}/json/list`);
      const list = await res.json();
      const page = list.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (page) return page;
    } catch (e) { /* not up yet */ }
    await sleep(300);
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

const exceptions = [];
const pageErrors = [];

(async () => {
  if (flag('fresh') && fs.existsSync(profile)) fs.rmSync(profile, { recursive: true, force: true });
  fs.mkdirSync(profile, { recursive: true });

  const proc = spawn(EDGE, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--no-first-run',
    '--disable-extensions', '--enable-unsafe-swiftshader', '--use-angle=swiftshader',
    '--use-gl=angle', '--autoplay-policy=no-user-gesture-required', '--mute-audio',
    `--remote-debugging-port=${cdpPort}`, `--window-size=${width},${height}`,
    '--hide-scrollbars', `--user-data-dir=${profile}`, url,
  ], { stdio: 'ignore' });

  const onEvent = (msg) => {
    if (msg.method === 'Runtime.exceptionThrown') {
      const d = msg.params.exceptionDetails;
      const text = (d.exception && (d.exception.description || d.exception.value)) || d.text;
      exceptions.push(String(text));
      console.log(`\n!!! EXCEPTION\n${text}\n`);
    } else if (msg.method === 'Log.entryAdded' && msg.params.entry.level === 'error') {
      pageErrors.push(msg.params.entry.text);
    } else if (msg.method === 'Runtime.consoleAPICalled' && msg.params.type === 'error') {
      pageErrors.push((msg.params.args || []).map((a) => a.value || a.description).join(' '));
    }
  };

  const show = (r, label) => {
    console.log(`\n=== ${label} ===`);
    if (r.exceptionDetails) {
      exceptions.push((r.exceptionDetails.exception && r.exceptionDetails.exception.description) || r.exceptionDetails.text);
      console.log('EVAL THREW: ' + ((r.exceptionDetails.exception && r.exceptionDetails.exception.description) || r.exceptionDetails.text));
    } else {
      const v = r.result && r.result.value;
      if (v && typeof v === 'object' && v.passed === false) exceptions.push(label + ': probe reported passed=false');
      if (v !== undefined) console.log(typeof v === 'string' ? v : JSON.stringify(v, null, 1));
    }
    return r;
  };

  /* The older probes in work/probe/ are bare IIFEs whose RETURN VALUE is the
     report (`(function () { ... return JSON.stringify(...) })()`). Wrapping that in
     a statement body swallows the value, so the expression form is tried first.
     CRITICAL: the expression form must be the REAL run, not a syntax probe. The
     first version of this evaluated the snippet once to test it and again to print
     it -- so every probe ran TWICE, and its second run saw state its own first run
     had already mutated (which made furniture_replace_other look broken: pocket
     .showIndex was already 1 on the second pass). Only a SyntaxError justifies a
     second attempt, and the value is printed from the run that produced it. */
  const evalSource = async (client, src, label) => {
    const exprForm = `(async()=>{ return (${src}\n); })()`;
    const r = await client.send('Runtime.evaluate', {
      expression: exprForm, returnByValue: true, awaitPromise: true,
    });
    const desc = (r.exceptionDetails && ((r.exceptionDetails.exception && r.exceptionDetails.exception.description) || r.exceptionDetails.text)) || '';
    if (r.exceptionDetails && /SyntaxError/.test(desc)) {
      console.log('(statement form: ' + label + ')');
      const stmt = await client.send('Runtime.evaluate', {
        expression: `(async()=>{${src}\n})()`, returnByValue: true, awaitPromise: true,
      });
      return show(stmt, label);
    }
    return show(r, label);
  };

  try {
    const target = await getTarget();
    const client = await cdp(target.webSocketDebuggerUrl, onEvent);
    await client.send('Page.enable');
    await client.send('Runtime.enable');
    await client.send('Log.enable');
    if (arg('download-dir', '')) {
      const downloadPath = path.resolve(arg('download-dir'));
      fs.mkdirSync(downloadPath, {recursive:true});
      await client.send('Browser.setDownloadBehavior', {behavior:'allow', downloadPath});
    }

    /* --inject <file> runs BEFORE any page script, via
       Page.addScriptToEvaluateOnNewDocument. That is the only way to observe
       something the client does during its own boot (e.g. opening a socket),
       because a normal Runtime.evaluate attaches far too late. */
    for (const f of all('inject')) {
      const src = fs.readFileSync(f, 'utf8');
      await client.send('Page.addScriptToEvaluateOnNewDocument', { source: src });
      console.log('injected (pre-document): ' + f);
    }
    if (all('inject').length) {
      await client.send('Page.reload', { ignoreCache: true });
    }

    console.log(`waiting ${bootWait}ms for boot...`);
    await sleep(bootWait);
    await sleep(settle);

    for (const step of steps) {
      const i = step.indexOf(':');
      const kind = i < 0 ? step : step.slice(0, i);
      const rest = i < 0 ? '' : step.slice(i + 1);

      if (kind === 'eval') {
        await evalSource(client, rest, 'eval');
      } else if (kind === 'in') {
        const src = fs.readFileSync(rest, 'utf8');
        await evalSource(client, src, 'in:' + path.basename(rest));
      } else if (kind === 'tap') {
        const [x, y] = rest.split(',').map(Number);
        for (const type of ['mousePressed', 'mouseReleased']) {
          await client.send('Input.dispatchMouseEvent', {
            type, x, y, button: 'left', clickCount: 1,
            buttons: type === 'mousePressed' ? 1 : 0,
          });
          await sleep(70);
        }
        console.log(`\n=== tap ${x},${y} ===`);
        await sleep(1200);
      } else if (kind === 'wheel') {
        /* `wheel:x,y,dy` -- a TRUSTED wheel event through CDP. Dispatching a
           synthetic WheelEvent from page JS does not scroll anything (untrusted
           events are ignored by the compositor), which made a scrolling check look
           like a failure when the page was fine. */
        const [x, y, dy] = rest.split(',').map(Number);
        await client.send('Input.dispatchMouseEvent', {
          type: 'mouseWheel', x, y, deltaX: 0, deltaY: dy, button: 'none',
        });
        console.log(`\n=== wheel ${dy} at ${x},${y} ===`);
        await sleep(700);
      } else if (kind === 'wait') {
        await sleep(Number(rest));
      } else if (kind === 'shot') {
        const s = await client.send('Page.captureScreenshot', { format: 'png' });
        fs.mkdirSync(path.dirname(path.resolve(rest)), { recursive: true });
        fs.writeFileSync(rest, Buffer.from(s.data, 'base64'));
        console.log(`=== shot -> ${rest} ===`);
      } else if (kind === 'log') {
        await evalSource(client,
          'JSON.stringify(window.__probeLog ? window.__probeLog.slice(-' + (Number(rest) || 80) + ') : null, null, 1)',
          'probe log (tail)');
      } else {
        console.log('unknown step: ' + step);
      }
    }

    if (keep) {
      console.log('\n--keep: leaving the browser open for 10 minutes');
      await sleep(600000);
    }
    client.close();
  } catch (e) {
    exceptions.push('driver failed: ' + e.message);
    console.error('driver failed:', e.message);
  } finally {
    try { proc.kill(); } catch (e) { }
  }

  console.log('\n=== SUMMARY ===');
  console.log(`exceptions : ${exceptions.length}`);
  for (const e of Array.from(new Set(exceptions)).slice(0, 6)) console.log('  ' + e.split('\n')[0]);
  const uniqErr = Array.from(new Set(pageErrors));
  console.log(`page errors: ${pageErrors.length} (${uniqErr.length} distinct)`);
  for (const e of uniqErr.slice(0, 6)) console.log('  ' + e);
  process.exitCode = exceptions.length ? 1 : 0;
})();
