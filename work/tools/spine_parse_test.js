#!/usr/bin/env node
'use strict';
/**
 * 用**客户端自己那份 spine 运行时**（payload 里的 js/spine.min.js）在 node 里解析动态照片的骨骼数据，
 * 复现 `SpineView.load()` 的每一步：
 *     createTextureAtlas(name, atlas, {name.png: tex}) -> createSkeletonData(name, json, atlas)
 *     -> new spine.SkeletonAnimation(data) -> skeleton.setSkinByName("default")
 * 任何一步抛错，在游戏里都是**静默失败**（Promise 没有 catch）：SpineView 对象在、像素不在。
 *
 *   node work/tools/spine_parse_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..');
const JS = path.join(ROOT, 'work', 'build', 'v31_payload', 'js');
const GFX = path.join(ROOT, 'work', 'build', 'v31_payload', 'resource', 'China', 'animation', 'gif_photo');

/* ---- 一个够用的 DOM/浏览器外壳，只为让 spine.min.js 能加载 ---- */
const noop = () => ({});
const canvasStub = () => ({
  width: 0, height: 0, style: {},
  getContext: () => ({ drawImage: noop, getImageData: () => ({ data: [] }), putImageData: noop }),
});
const sandbox = {
  console,
  setTimeout, clearTimeout, setInterval, clearInterval,
  Promise, Math, JSON, Date, Error, TypeError, Uint8Array, Uint16Array, Uint32Array,
  Int8Array, Int16Array, Int32Array, Float32Array, Float64Array, ArrayBuffer, DataView, Array, Object, String, Number, Boolean, RegExp, Map, Set,
  document: { createElement: canvasStub, body: { appendChild: noop, removeChild: noop }, addEventListener: noop, removeEventListener: noop },
  navigator: { userAgent: 'node' },
  location: { href: 'http://127.0.0.1/' },
  addEventListener: noop, removeEventListener: noop, Image: function () { return { width: 1, height: 1, src: '' }; },
};
sandbox.window = sandbox;
sandbox.self = sandbox;
sandbox.globalThis = sandbox;
vm.createContext(sandbox);

const spineSrc = fs.readFileSync(path.join(JS, 'spine.min.js'), 'utf8');
try {
  vm.runInContext(spineSrc, sandbox, { filename: 'spine.min.js' });
} catch (e) {
  console.log('spine.min.js 在 node 里加载失败（不一定代表游戏里失败）：' + e.message);
}
const spine = sandbox.spine || (sandbox.window && sandbox.window.spine);
console.log('spine 命名空间: %s', spine ? 'OK' : '取不到');
if (spine) {
  console.log('  createTextureAtlas: %s', typeof spine.createTextureAtlas);
  console.log('  createSkeletonData: %s', typeof spine.createSkeletonData);
  console.log('  SkeletonAnimation  : %s', typeof spine.SkeletonAnimation);
}

/* ---- 拿一个真实的层来试：3102 卡片第 2 层 gif_4_bg（用户用的就是 3102） ---- */
const target = process.argv[2] || 'gif_4_bg';
let dir = null;
for (const d of fs.readdirSync(GFX)) {
  if (fs.existsSync(path.join(GFX, d, target + '.json'))) dir = path.join(GFX, d);
}
if (!dir) { console.log('找不到 %s', target); process.exit(1); }
const atlasText = fs.readFileSync(path.join(dir, target + '.atlas'), 'utf8');
const jsonText = fs.readFileSync(path.join(dir, target + '.json'), 'utf8');
const json = JSON.parse(jsonText);
console.log('');
console.log('数据: %s  skeleton.spine=%s  skins 类型=%s  皮肤名=%s',
  target, (json.skeleton || {}).spine, Array.isArray(json.skins) ? 'array' : typeof json.skins,
  Array.isArray(json.skins) ? json.skins.map((s) => s.name).join(',') : Object.keys(json.skins || {}).join(','));

const fakeTex = { width: 904, height: 634, source: { width: 904, height: 634 } };
const textureMap = {};
for (const line of atlasText.split('\n')) {
  const t = line.trim();
  if (/\.png$/i.test(t) && !t.includes(':')) textureMap[t] = fakeTex;
}
console.log('图集页: %s', Object.keys(textureMap).join(','));

function attempt(label, fn) {
  try {
    const r = fn();
    console.log('  [OK]   %s', label);
    return r;
  } catch (e) {
    console.log('  [FAIL] %s -> %s: %s', label, e && e.name, e && e.message);
    return null;
  }
}

if (!spine) { console.log('\n无法继续（运行时没加载起来）。'); process.exit(0); }
console.log('');
console.log('== 复现 SpineView.load() 的每一步 ==');
const atlas = attempt('createTextureAtlas(name, atlasText, {png: tex})',
  () => spine.createTextureAtlas(target, atlasText, textureMap));
const data = atlas && attempt('createSkeletonData(name, json, atlas)',
  () => spine.createSkeletonData(target, jsonText, atlas));
if (data) {
  attempt('data.findSkin("default")',
    () => { const s = data.findSkin('default'); if (!s) throw new Error('findSkin 返回空'); return s; });
  attempt('data.findAnimation("default")（客户端默认名）',
    () => data.findAnimation('default'));
  attempt('data.animations[0]（客户端的兜底）',
    () => { if (!data.animations || !data.animations.length) throw new Error('没有动画'); return data.animations[0].name; });
  const anim = attempt('new spine.SkeletonAnimation(data)', () => new spine.SkeletonAnimation(data));
  if (anim) {
    attempt('skeleton.setSkinByName("default")（客户端就是这么调的）',
      () => anim.skeleton.setSkinByName('default'));
    attempt('skeleton.drawOrder.length（准备绘制的 slot 数）',
      () => { const n = anim.skeleton.drawOrder ? anim.skeleton.drawOrder.length : -1; if (n <= 0) throw new Error('slot 数=' + n); return n; });
  }
}
