'use strict';
/**
 * Route A runtime: static host for the extracted H5 game + offline WS "server".
 *
 *   node server/main.js [--port 8080] [--web ../web] [--save ../save/save.json]
 *
 * - serves the patched web tree (assets/game from base.apk)
 * - accepts the game's WebSocket protocol and answers it from engine/
 * - POST /__log receives client console output so we can debug headlessly
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const ws = require('./ws');
const { createEngine, canon, toWire } = require('../engine');

const args = process.argv.slice(2);
function arg(name, dflt) {
  const i = args.indexOf('--' + name);
  return i >= 0 && args[i + 1] ? args[i + 1] : dflt;
}

const PORT = Number(arg('port', 8080));
const WEB = path.resolve(__dirname, arg('web', '../web'));
const SERVE_HOST = arg('servername', '127.0.0.1');
const SAVE = path.resolve(__dirname, arg('save', '../save/save.json'));
const LOGDIR = path.resolve(__dirname, '..', 'logs');
fs.mkdirSync(LOGDIR, { recursive: true });

const engine = createEngine({ savePath: SAVE, verbose: true });
const protoLog = fs.createWriteStream(path.join(LOGDIR, 'protocol.log'), { flags: 'a' });
const clientLog = fs.createWriteStream(path.join(LOGDIR, 'client.log'), { flags: 'a' });

function stamp() { return new Date().toISOString(); }
function plog(s) { const line = `[${stamp()}] ${s}`; console.log(line); protoLog.write(line + '\n'); }
function clog(s) { clientLog.write(`[${stamp()}] ${s}\n`); }

/* ------------------------------------------------------------- static */

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.xml': 'application/xml; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.lua': 'text/plain; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.mp3': 'audio/mpeg',
  '.mp4': 'video/mp4',
  '.eab': 'application/octet-stream',
  '.atlas': 'text/plain; charset=utf-8',
  '.fnt': 'text/plain; charset=utf-8',
  '.bin': 'application/octet-stream',
  '.zip': 'application/zip',
};

function serveStatic(req, res) {
  let rel = decodeURIComponent(req.url.split('?')[0]);
  if (rel === '/' || rel === '') rel = '/index.html';
  const file = path.join(WEB, rel.replace(/^\/+/, ''));
  if (!file.startsWith(WEB)) { res.writeHead(403); res.end('forbidden'); return; }
  fs.stat(file, (err, st) => {
    if (err || !st.isFile()) {
      console.log(`[http] 404 ${rel}`);
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('not found: ' + rel);
      return;
    }
    const type = MIME[path.extname(file).toLowerCase()] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': type, 'Content-Length': st.size, 'Cache-Control': 'no-store' });
    fs.createReadStream(file).pipe(res);
  });
}

const server = http.createServer((req, res) => {
  // client console/probe sink
  if (req.method === 'POST' && req.url.startsWith('/__log')) {
    let body = '';
    req.on('data', (c) => { body += c; if (body.length > 1 << 20) req.destroy(); });
    req.on('end', () => {
      clog(body);
      process.stdout.write(body.split('\n').map((l) => l && '    | ' + l).join('\n') + '\n');
      res.writeHead(204, { 'Access-Control-Allow-Origin': '*' });
      res.end();
    });
    return;
  }
  if (req.url.startsWith('/__unknowns')) {
    const rep = engine.unknownReport();
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(rep, null, 1));
    return;
  }
  if (req.url.startsWith('/__state')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(engine.state, null, 1));
    return;
  }
  if (req.url.startsWith('/__export')) {
    const body = JSON.stringify(engine.exportSave(), null, 1);
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Content-Disposition': 'attachment; filename="frog-save.json"',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(body);
    return;
  }
  if (req.method === 'POST' && req.url.startsWith('/__import')) {
    let body = '';
    req.on('data', (c) => { body += c; if (body.length > 8 << 20) req.destroy(); });
    req.on('end', () => {
      try {
        engine.importSave(JSON.parse(body));
        plog('-> save imported via /__import');
        res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        res.end('{"ok":true}');
      } catch (e) {
        res.writeHead(400, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        res.end(JSON.stringify({ ok: false, error: String(e && e.message || e) }));
      }
    });
    return;
  }
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    res.end();
    return;
  }
  serveStatic(req, res);
});

/* ---------------------------------------------------------------- ws */

let connSeq = 0;
const conns = new Map();

ws.attach(server, (conn, req) => {
  const id = ++connSeq;
  conns.set(id, conn);
  plog(`CONNECT #${id} from ${req.socket.remoteAddress} url=${req.url}`);
  conn.on('message', (raw) => {
    let msg;
    try { msg = JSON.parse(raw); } catch (e) {
      plog(`#${id} MALFORMED ${raw.slice(0, 200)}`);
      return;
    }
    const cmd = msg.cmd;
    const data = msg.data || {};
    plog(`#${id} <- ${cmd}${msg.session ? ' session=' + msg.session : ''} ${JSON.stringify(data)}`);
    const out = engine.dispatch(cmd, data);
    if (msg.session != null) {
      const payload = { session: msg.session, data: out.reply || {} };
      plog(`#${id} -> (session ${msg.session}) ${cmd} ${JSON.stringify(payload.data)}`);
      conn.send(JSON.stringify(payload));
    } else if (out.reply !== undefined) {
      plog(`#${id} -> (unsolicited reply to ${cmd}) ${JSON.stringify(out.reply)}`);
      conn.send(JSON.stringify({ cmd: toWire(canon(cmd)), data: out.reply }));
    }
    for (const p of out.pushes) {
      plog(`#${id} -> push ${p.cmd} ${JSON.stringify(p.data)}`);
      conn.send(JSON.stringify({ cmd: p.cmd, data: p.data }));
    }
  });
  conn.on('close', () => { conns.delete(id); plog(`CLOSE #${id}`); });
});

/* Drive time-based world state (clover regrowth, frog departures/returns) and
   broadcast whatever the engine wants to push. */
setInterval(() => {
  let pushes;
  try {
    pushes = engine.tick();
  } catch (e) {
    console.error('[tick] failed:', e && e.stack || e);
    return;
  }
  if (!pushes || !pushes.length) return;
  for (const p of pushes) {
    plog(`-> broadcast ${p.cmd} ${JSON.stringify(p.data).slice(0, 400)}`);
    const payload = JSON.stringify({ cmd: p.cmd, data: p.data });
    for (const c of conns.values()) {
      try { c.send(payload); } catch (e) { /* ignore */ }
    }
  }
}, 5000);

server.listen(PORT, '127.0.0.1', () => {
  plog(`offline runtime listening`);
  console.log(`  web root : ${WEB}`);
  console.log(`  save file: ${SAVE}`);
  console.log(`  HTTP     : http://127.0.0.1:${PORT}/index.html`);
  console.log(`  WS       : ws://${SERVE_HOST}:${PORT}  (client gameServer must match)`);
});
