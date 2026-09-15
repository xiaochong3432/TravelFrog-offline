#!/usr/bin/env node
'use strict';
/**
 * Dump every command's reply KEY SET, for the reply-key audit.
 *
 * Why: the client's handlers read the payload under specific key names and silently skip
 * a branch when a key is missing. We have now shipped two bugs of exactly that shape --
 * the 百科 payload (sent species ids where the client indexes the table with long_ids)
 * and album_load_by_id_list (sent `pictures`, the client reads `pic_list`) -- and both
 * looked fine in tests that only checked "a reply came back".
 *
 * Usage: node tools/dump_reply_keys.js [out.json]
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const engineModule = require(path.join(ROOT, 'work', 'run', 'engine', 'index.js'));

const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-keys-'));
process.chdir(cwd);

const eng = engineModule.createEngine({ savePath: 'keys.json' });
const protocol = require(path.join(ROOT, 'work', 'run', 'engine', 'protocol.js'));

/* a best-effort argument set, so handlers do not all take the "missing param" path */
function probeArgs(cmd, params) {
  const d = {};
  for (const p of params || []) {
    if (/^(pos|index|start|count|type|ads_type|is_reward|day|state)$/.test(p)) d[p] = 1;
    else if (/^(id|item_id|shop_id|pic_id|long_id|anim_index|pic_index|uid)$/.test(p)) d[p] = 1;
    else if (/^ids$/.test(p)) d[p] = [1];
    else if (/^id_list$/.test(p)) d[p] = [1];
    else if (/^num$/.test(p)) d[p] = 1;
  }
  return d;
}

/* give the frog something to work with, so data-dependent replies are not all empty */
eng.state.pictures.push({ id: 1, pic_id: 1, read: 0, new: 0 });
eng.state.specialtys.push({ item_id: 3001, count: 1 });
eng.state.handbook.collections.push(0);
eng.state.furniture.owned.push(1);
eng.dispatch('travel_load_picture', {});
eng.dispatch('album_load', { start: 1, count: 20 });

const out = {};
for (const cmd of Object.keys(protocol)) {
  const params = (protocol[cmd] || {}).params || [];
  let reply;
  try {
    reply = eng.dispatch(cmd, probeArgs(cmd, params)).reply;
  } catch (e) {
    out[cmd] = { threw: String(e && e.message) };
    continue;
  }
  if (reply === undefined) {
    out[cmd] = { reply: 'undefined' };
  } else if (reply === null) {
    out[cmd] = { reply: 'null' };
  } else if (Array.isArray(reply)) {
    out[cmd] = { reply: 'array', keys: [] };
  } else if (typeof reply === 'object') {
    out[cmd] = { reply: 'object', keys: Object.keys(reply).sort() };
  } else {
    out[cmd] = { reply: typeof reply };
  }
}

const dest = process.argv[2] || path.join(ROOT, 'work', 'logs', 'reply_keys.json');
fs.writeFileSync(dest, JSON.stringify(out, null, 1));
console.log('wrote %s (%d commands)' % (dest, Object.keys(out).length));
