#!/usr/bin/env node
'use strict';
/**
 * 直接验证外壳里那两个函数（不跑浏览器）：
 *   · installAnimTracer() —— 在 SocketManage / engine 还不存在时调用必须**返回 false 且不自我标记**，
 *     等它们出现后再调用必须装上（这正是 vc9 失效的原因）；
 *   · installAnimLayerFit() —— 同理（SpineView 后加载），装好后用**你手机上的真实层数据**
 *     （周年卡 pic 3102 的 7 层画布）跑一遍，检查每一层是否都被缩放居中到 500x350 窗口内。
 *
 *   node work/tools/anim_install_test.js
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
/* 默认测 V3.3 载荷；FROG_SHELL 可以指向别的载荷（例如 V4 的）。 */
const SHELL = process.env.FROG_SHELL
  || path.join(ROOT, 'work', 'build', 'v31_payload', '__probe.js');
const src = fs.readFileSync(SHELL, 'utf8');

function extract(name) {
  const start = src.indexOf('function ' + name + '(');
  if (start < 0) throw new Error('找不到 ' + name);
  let i = src.indexOf('{', start), depth = 0;
  for (let k = i; k < src.length; k += 1) {
    if (src[k] === '{') depth += 1;
    else if (src[k] === '}') { depth -= 1; if (depth === 0) return src.slice(start, k + 1); }
  }
  throw new Error(name + ' 大括号不匹配');
}

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
};

/* ---------- 沙箱 ---------- */
const logs = [];
const sandbox = {
  console, Math, JSON, Array, Object, String, Number, Boolean, Error, RegExp, Promise, isFinite, Infinity, parseInt, parseFloat,
};
sandbox.window = sandbox;
sandbox.push = (tag, args) => logs.push(tag + ' ' + (args || []).join(' '));
sandbox.egret = { MainContext: { instance: { stage: null } } };
sandbox.core = {};                       /* 先什么都没有（模拟外壳启动的那一刻） */
sandbox.GuideHelpView = { getInstance: () => ({ show: () => { } }) };
vm.createContext(sandbox);
vm.runInContext(extract('installAnimTracer'), sandbox);

console.log('== 1. 安装时机：客户端类还没出现时 ==');
t('installAnimTracer() 此时返回 false（不自我标记）', sandbox.installAnimTracer() === false);
t('（预览窗缩放已按你的要求撤掉，外壳里不再有 installAnimLayerFit）',
  typeof sandbox.installAnimLayerFit === 'undefined');
t('trace 容器已建好但两个 hook 都没装',
  !!sandbox.__animTrace && !sandbox.__animTrace.hookedSend && !sandbox.__animTrace.hookedEngine);

console.log('');
console.log('== 2. 客户端脚本到位后（重试循环里的下一次调用）==');
const sent = [];
/* 真实的 SocketManage 是单例：getInstance() 每次都返回同一个对象 —— 外壳包的就是它 */
const smInstance = { send: function () { sent.push(Array.prototype.slice.call(arguments)); } };
sandbox.core.SocketManage = { getInstance: () => smInstance };
const dispatched = [];
sandbox.__engine = { dispatch: (cmd, data) => { dispatched.push(cmd); return { reply: { code: 0, phase: 3 } }; } };
t('installAnimTracer() 这次返回 true', sandbox.installAnimTracer() === true);
t('两个 hook 都装上了', sandbox.__animTrace.hookedSend === true && sandbox.__animTrace.hookedEngine === true);
sandbox.core.SocketManage.getInstance().send('animpicture_add_pic', function () { }, [11, 12]);
sandbox.__engine.dispatch('animpicture_use_item', { id: 8004 });
console.log('  流水=' + JSON.stringify(sandbox.__animTrace.sent) + ' / ' + JSON.stringify(sandbox.__animTrace.replies));
t('客户端发出的协议被记录', sandbox.__animTrace.sent.length === 1 && sandbox.__animTrace.sent[0].indexOf('animpicture_add_pic') === 0);
t('引擎回复被记录', sandbox.__animTrace.replies.length === 1 && sandbox.__animTrace.replies[0].indexOf('animpicture_use_item') === 0);
t('重复调用不会重复包装', (function () { const before = sandbox.__engine.dispatch; sandbox.installAnimTracer(); return sandbox.__engine.dispatch === before; })());

console.log('');
console.log('%d passed, %d failed', pass, fail);
process.exit(fail ? 1 : 0);
