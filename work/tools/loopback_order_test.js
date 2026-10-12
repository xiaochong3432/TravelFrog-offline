#!/usr/bin/env node
'use strict';
/**
 * 外壳回环的投递顺序：**推送必须先于回复**。
 *
 * 客户端很多回复回调是"重新读模型再刷界面"，最典型的是动态照片制作页用显影液：
 *   req_use_item(a, new core.Action(function () {
 *       s = ItemModel.getHouseItemCount(a), n.text = String(s), r.visible = 0 >= s, ...
 *   }))
 * 只有引擎推的 `item_load_items` 先落到 ItemModel，回调里读到的才是扣完的数量；
 * 反序（先回复后推送）就会出现"用了显影液数量不马上减少，要再用一次/退出重进才少 1 个"。
 *
 * 本测试从外壳里抠出 `P.send` 的实现，用桩驱动一遍，记录"推送"和"回复"到达的先后。
 * 默认测我们 V4 的外壳；FROG_SHELL 指到旧外壳即可看到反序（对照）。
 *
 *   node work/tools/loopback_order_test.js
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const SHELL = process.env.FROG_SHELL || path.join(ROOT, 'work', 'run', 'web', '__probe.js');
const src = fs.readFileSync(SHELL, 'utf8');

/* 抠出 "P.send = function (json) { … };" 这一整块 */
function extractSend(text) {
  const start = text.indexOf('P.send = function');
  if (start < 0) throw new Error('找不到 P.send');
  let i = text.indexOf('{', start), depth = 0;
  for (let k = i; k < text.length; k += 1) {
    if (text[k] === '{') depth += 1;
    else if (text[k] === '}') { depth -= 1; if (depth === 0) return text.slice(start, k + 1); }
  }
  throw new Error('P.send 大括号不匹配');
}

const order = [];
const logs = [];
const sandbox = {
  console, Math, JSON, Array, Object, String, Number, Boolean, Error, Promise, parseInt,
};
sandbox.window = sandbox;
sandbox.push = (tag, args) => logs.push(tag);
sandbox.core = { SocketState: { ConnectionSucceed: 1 }, Socket: function () { } };
sandbox.egret = { WebSocket: { TYPE_STRING: 'string' } };
sandbox.window.FrogEngine = { toWire: (x) => x, canon: (x) => x };
/* 引擎桩：回复 + 一条推送（就是显影液那次的形状） */
sandbox.engine = {
  dispatch: () => ({
    reply: { phase: 3, used: 8002, left: 4 },
    pushes: [{ cmd: 'item_load_items', data: { marker: 'push' } }],
  }),
};
vm.createContext(sandbox);
vm.runInContext('var P = core.Socket.prototype;\n' + extractSend(src) + '\n', sandbox);

/* 驱动一遍：deliver 被外壳调用时会带上 cmd/data 或 session/data */
const deliver = (sock, obj) => {
  if (obj.session != null) order.push('reply');
  else if (obj.data && obj.data.marker === 'push') order.push('push');
  else order.push('reply');
};
sandbox.deliver = deliver;

const sock = { _socketState: 1 };
sandbox.P.send.call(sock, JSON.stringify({ cmd: 'animpicture_use_item', data: { id: 8002 } }));

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
};

console.log('外壳：' + path.relative(ROOT, SHELL));
console.log('  到达顺序 = ' + JSON.stringify(order));
t('投递了两次（一条推送 + 一个回复）', order.length === 2, JSON.stringify(order));
t('推送先到（item_load_items 先落模型）', order[0] === 'push', JSON.stringify(order));
t('回复后到（回调里读到的才是扣完的数量）', order[1] === 'reply', JSON.stringify(order));

/* session 回调（客户端等回包的那种）同样要求推送先行 */
order.length = 0;
sandbox.P.send.call(sock, JSON.stringify({ cmd: 'animpicture_use_item', session: 7 }));
t('带 session 的回包也是"推送在前"', order[0] === 'push' && order[1] === 'reply', JSON.stringify(order));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
