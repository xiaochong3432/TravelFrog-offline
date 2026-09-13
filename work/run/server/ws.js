'use strict';
/**
 * Minimal RFC6455 WebSocket server - zero dependencies.
 * Only what the game client needs: text frames, ping/pong, close.
 */
const crypto = require('crypto');
const GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';

function acceptKey(key) {
  return crypto.createHash('sha1').update(key + GUID).digest('base64');
}

class WsConn {
  constructor(socket) {
    this.socket = socket;
    this.buf = Buffer.alloc(0);
    this.fragOp = 0;
    this.fragParts = [];
    this.closed = false;
    this.handlers = { message: [], close: [] };
    socket.on('data', (d) => this._onData(d));
    socket.on('close', () => this._fire('close'));
    socket.on('error', () => { try { socket.destroy(); } catch (e) {} });
  }
  on(ev, fn) { (this.handlers[ev] = this.handlers[ev] || []).push(fn); return this; }
  _fire(ev, arg) { (this.handlers[ev] || []).forEach((f) => { try { f(arg); } catch (e) { console.error('[ws] handler error', e); } }); }

  _onData(chunk) {
    this.buf = Buffer.concat([this.buf, chunk]);
    for (;;) {
      const f = this._readFrame();
      if (!f) break;
      this._handleFrame(f);
    }
  }

  _readFrame() {
    const b = this.buf;
    if (b.length < 2) return null;
    const fin = (b[0] & 0x80) !== 0;
    const opcode = b[0] & 0x0f;
    const masked = (b[1] & 0x80) !== 0;
    let len = b[1] & 0x7f;
    let off = 2;
    if (len === 126) {
      if (b.length < off + 2) return null;
      len = b.readUInt16BE(off); off += 2;
    } else if (len === 127) {
      if (b.length < off + 8) return null;
      const hi = b.readUInt32BE(off);
      const lo = b.readUInt32BE(off + 4);
      len = hi * 4294967296 + lo; off += 8;
    }
    let mask = null;
    if (masked) {
      if (b.length < off + 4) return null;
      mask = b.slice(off, off + 4); off += 4;
    }
    if (b.length < off + len) return null;
    const payload = Buffer.from(b.slice(off, off + len));
    this.buf = b.slice(off + len);
    if (mask) for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
    return { fin, opcode, payload };
  }

  _handleFrame(f) {
    switch (f.opcode) {
      case 0x0: // continuation
        this.fragParts.push(f.payload);
        if (f.fin) {
          const all = Buffer.concat(this.fragParts);
          this.fragParts = [];
          if (this.fragOp === 0x1) this._fire('message', all.toString('utf8'));
        }
        break;
      case 0x1: // text
        if (f.fin) this._fire('message', f.payload.toString('utf8'));
        else { this.fragOp = 0x1; this.fragParts = [f.payload]; }
        break;
      case 0x2: // binary (unused by this client)
        if (f.fin) this._fire('message', f.payload);
        else { this.fragOp = 0x2; this.fragParts = [f.payload]; }
        break;
      case 0x8: this.sendClose(); break;
      case 0x9: this._frame(0xA, f.payload); break; // ping -> pong
      case 0xA: break;                               // pong
      default: break;
    }
  }

  _frame(opcode, payload) {
    if (this.closed) return;
    const len = payload.length;
    let header;
    if (len < 126) {
      header = Buffer.alloc(2);
      header[1] = len;
    } else if (len < 65536) {
      header = Buffer.alloc(4);
      header[1] = 126;
      header.writeUInt16BE(len, 2);
    } else {
      header = Buffer.alloc(10);
      header[1] = 127;
      header.writeUInt32BE(Math.floor(len / 4294967296), 2);
      header.writeUInt32BE(len >>> 0, 6);
    }
    header[0] = 0x80 | opcode;
    try { this.socket.write(Buffer.concat([header, payload])); } catch (e) { this.closed = true; }
  }

  send(str) { this._frame(0x1, Buffer.from(String(str), 'utf8')); }
  sendClose() {
    if (this.closed) return;
    this.closed = true;
    this._frame(0x8, Buffer.alloc(0));
    setTimeout(() => { try { this.socket.end(); } catch (e) {} }, 50);
  }
  destroy() { this.closed = true; try { this.socket.destroy(); } catch (e) {} }
}

/**
 * @param {http.Server} server
 * @param {(conn: WsConn, req: http.IncomingMessage) => void} onConnection
 * @param {{path?: string}} [opts]
 */
function attach(server, onConnection, opts) {
  const path = (opts && opts.path) || null;
  server.on('upgrade', (req, socket) => {
    const key = req.headers['sec-websocket-key'];
    if (!key || (path && !req.url.startsWith(path))) {
      socket.write('HTTP/1.1 400 Bad Request\r\n\r\n');
      socket.destroy();
      return;
    }
    socket.write(
      'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      'Sec-WebSocket-Accept: ' + acceptKey(key) + '\r\n\r\n'
    );
    socket.setNoDelay(true);
    onConnection(new WsConn(socket), req);
  });
}

module.exports = { attach, WsConn };
