#!/usr/bin/env node
'use strict';
/**
 * 嘟嘟商店「反复快速点向右翻页键 -> 商品消失/空白页」的回归测试。
 *
 * 根因（客户端 main.min.js 的 PageGroupScroller，商店翻页箭头就挂在它的
 * prevCursor/nextCursor 上）：
 *     onNext(){ this.selectedIndex += 1 }              // 无上限、无节流
 *     getPageScrollH(){ return Math.min(contentWidth, width*curPageIndex + offset) }
 *     updateCursors(){ nextCursor.visible = selectedIndex < numPages - 1 }
 * 连点 -> 页码超过 numPages-1 -> 滚动位置取到 contentWidth（内容尾部之外）-> 视口停在
 * 空白区；同时 next 箭头因越界被隐藏，玩家点不回来，只能退出商店重进（视图重建、页码归零）。
 *
 * 本测试把 PageGroupScroller 从客户端里抠出来，用桩实例连点 20 次，断言：
 *   · 页码永远不越界；
 *   · 滚动位置永远不超过 contentWidth - viewport.width（滚不出内容）。
 * 默认测我们打过补丁的客户端；FROG_CLIENT 指向上游客户端即可看到越界（对照）。
 *
 *   node work/tools/shop_paging_test.js
 */
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const CLIENT = process.env.FROG_CLIENT
  || path.join(ROOT, 'work', 'run', 'web', 'js', 'main.min.js');
const src = fs.readFileSync(CLIENT, 'utf8');

function extractClass(text, name) {
  const start = text.indexOf(name + '=function');
  if (start < 0) throw new Error('找不到 ' + name);
  const end = text.indexOf('__reflect(' + name + '.prototype', start);
  if (end < 0) throw new Error('找不到 ' + name + ' 的结束标记');
  // 往前找到 }(eui.Scroller); 这一段的结尾
  const tail = text.lastIndexOf('}(eui.Scroller);', end);
  return text.slice(start, tail + '}(eui.Scroller);'.length);
}

const logs = [];
const sandbox = { console, Math, JSON, Object, Array, String, Number, Boolean, Error, RegExp, Promise };
sandbox.window = sandbox;
/* ---- egret / eui / 工具的桩 ---- */
sandbox.__extends = function (sub, base) {
  sub.prototype = Object.create(base.prototype);
  sub.prototype.constructor = sub;
  sub.__super = base;
};
class Point { constructor() { this.x = 0; this.y = 0; } setTo(x, y) { this.x = x; this.y = y; } }
const Tween = {
  removeTweens() { },
  get() { const c = { to() { return c; }, call(fn) { if (fn) fn(); return c; }, set() { return c; }, wait() { return c; } }; return c; },
};
class Group { constructor() { this.layout = { horizontalGap: 0 }; } }
class Scroller {
  constructor() { this.viewport = null; }
  addEventListener() { }
  removeEventListener() { }
  dispatchEvent() { }
  invalidateProperties() { }
  $onAddToStage() { }
  $onRemoveFromStage() { }
  $doAddChild() { }
  $doRemoveChild() { }
}
sandbox.egret = {
  Point, Tween,
  TouchEvent: { TOUCH_BEGIN: 'b', TOUCH_MOVE: 'm', TOUCH_END: 'e' },
  Event: function (t, b, c, d) { this.type = t; this.data = d; },
  getTimer: () => Date.now(),
};
sandbox.eui = {
  Scroller, Group,
  ScrollPolicy: { OFF: 'off', ON: 'on', AUTO: 'auto' },
  UIEvent: { CHANGE_END: 'changeEnd' },
  PropertyEvent: function (t, b, c, p) { this.type = t; this.property = p; },
};
sandbox.Utils = { FpsManager: { instance: () => ({ boostIn() { }, boost() { }, resume() { } }) } };
vm.createContext(sandbox);
vm.runInContext(extractClass(src, 'PageGroupScroller'), sandbox);

const proto = sandbox.PageGroupScroller.prototype;
const W = 768, PAGES = 5, GAP = 0;
function makeInstance() {
  const inst = Object.create(proto);
  inst.offset = 0;
  inst._curPageIndex = 0;
  inst.pageHorizontalGap = GAP;
  inst.viewport = {
    contentWidth: W * PAGES,
    width: W,
    scrollH: 0,
    validateDisplayList() { },
    addEventListener() { },
    removeEventListener() { },
    parent: { width: W },
  };
  inst.invalidateProperties = function () { };     // onNext -> selectedIndex setter
  inst.prevCursor = { visible: false };
  inst.nextCursor = { visible: true };
  inst.scrolling = false;
  return inst;
}

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
};

console.log('客户端：' + path.relative(ROOT, CLIENT));

/* ---- 连点向右 20 次（页面只有 5 页）---- */
const inst = makeInstance();
const idxSeen = [];
for (let i = 0; i < 20; i += 1) {
  inst.onNext();
  idxSeen.push(inst.selectedIndex);
  inst.viewport.scrollH = Math.max(0, Math.min(inst.viewport.contentWidth - inst.viewport.width,
    inst.getPageScrollH()));
}
console.log('  连点 20 次后的页码序列 = ' + JSON.stringify(idxSeen.slice(0, 8)) + ' … 末值 ' + idxSeen[idxSeen.length - 1]);
t('页码永远不超过最后一页（numPages-1）',
  idxSeen.every((v) => v <= inst.numPages - 1), 'max=' + Math.max.apply(null, idxSeen) + ' numPages=' + inst.numPages);
t('滚动位置永远滚不出内容（<= contentWidth - viewport.width）',
  inst.getPageScrollH() <= inst.viewport.contentWidth - inst.viewport.width,
  'scrollH=' + inst.getPageScrollH() + ' 上限=' + (inst.viewport.contentWidth - inst.viewport.width));
t('最后一页仍然看得见内容（不是空白）',
  inst.getPageScrollH() === inst.viewport.contentWidth - inst.viewport.width,
  'scrollH=' + inst.getPageScrollH());

/* ---- 连点向左 20 次 ---- */
for (let i = 0; i < 20; i += 1) inst.onPrev();
t('向左连点也不会滚成负值', inst.selectedIndex === 0 && inst.getPageScrollH() === 0,
  'index=' + inst.selectedIndex + ' scrollH=' + inst.getPageScrollH());

/* ---- 正常翻一页仍然是"正好一页" ---- */
const one = makeInstance();
one.onNext();
t('正常翻一页 = 正好一页宽', one.getPageScrollH() === W, 'scrollH=' + one.getPageScrollH());

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
