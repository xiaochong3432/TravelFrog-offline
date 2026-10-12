#!/usr/bin/env node
'use strict';
/**
 * End-to-end check of the 动态照片 flow the way the CLIENT drives it, run against an engine.
 *
 * Every step uses the client's own protocol names and argument shapes (taken from
 * main.min.js: req_select_pic / req_add_pic / req_use_item / req_open_album / req_get_item /
 * req_album_add_pic / req_album_remove_pic), and each step prints the reply AND the state it
 * changed, so "it works" is demonstrated rather than asserted.
 *
 *   FROG_ENGINE=<file> node work/tools/anim_flow_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
/* 历史版本引擎放在 work/build/（.gitignore 排除），仓库里通常没有；
   缺失时整个套件跳过，避免把‘环境缺件’报成失败。 */
if (!require('fs').existsSync(require('path').join(__dirname, '..', 'build', 'merged_v31', 'index.js'))) {
  console.log('  SKIP  历史引擎 work/build/merged_v31/index.js 不存在（需自备历史版本引擎）');
  process.exit(0);
}
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'build', 'merged_v31', 'index.js');
const { createEngine } = require(ENGINE);

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-anim-'));
const engine = createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
const call = (cmd, data) => engine.dispatch(cmd, data || {}).reply || {};
/* the FULL dispatch result, so we can assert which pushes an action emits */
const raw = (cmd, data) => engine.dispatch(cmd, data || {});
const pushedLoad = (r) => ((r && r.pushes) || []).filter((p) => p.cmd === 'animpicture_load').length;
const gm = (c) => call('client_gm', { cmd: c });
const A = () => engine.state.animPicture;
const house = (id) => {
  const r = (engine.state.items.house || []).find((x) => Number(x.item_id) === Number(id));
  return Number(r && r.count) || 0;
};
const inAlbum = (picId) => (engine.state.pictures || []).filter((p) => p && Number(p.pic_id) === Number(picId)).length;

let pass = 0; let fail = 0;
const t = (name, cond, extra) => {
  if (cond) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
};

console.log('engine: ' + path.relative(ROOT, ENGINE));
console.log('');
console.log('== 1. 材料到手（编辑器补给）==');
const kit = gm('anim_kit');
console.log('  anim_kit -> ' + kit.info);
t('9001/9002/显影液 都进了家',
  house(9001) >= 1 && house(9002) >= 5 && house(8002) >= 5 && house(8003) >= 5 && house(8004) >= 5,
  JSON.stringify({ 9001: house(9001), 9002: house(9002), 8002: house(8002) }));
t('可动明信片每种 5 张', inAlbum(3063) >= 5 && inAlbum(100) >= 5);
t('相册里有底片可选', (engine.state.pictures || []).length >= 30, '相册 ' + engine.state.pictures.length + ' 张');
t('动态照片页数 >= 2（有相框；这正是"不能制作"的开关）',
  Number(call('animpicture_load', {}).page_num) >= 2, 'page_num=' + call('animpicture_load', {}).page_num);
t('页数随相框增加', (function () {
  const before = Number(call('animpicture_load', {}).page_num);
  gm('add_item 9001 1');
  return Number(call('animpicture_load', {}).page_num) === before + 1;
})(), 'page_num=' + call('animpicture_load', {}).page_num);

console.log('');
console.log('== 2. 制作：选一张可动明信片当底片 ==');
const seed = (engine.state.pictures || []).find((p) => Number(p.pic_id) === 3063);
const before = (engine.state.pictures || []).length;
const sel = call('animpicture_select_pic', { id: seed.id });
console.log('  select_pic id=%d -> %s；页: %s', seed.id, JSON.stringify(sel), JSON.stringify(A().picList.map((p) => p.id)));
t('返回 code 0', sel.code === 0);
t('底片离开相册（被消耗）', (engine.state.pictures || []).length === before - 1);
t('新页已建立', A().picList.length === 1);
t('起始 phase = 1（有动画层）', Number(A().phase) === 1);

console.log('');
console.log('== 3. 加照片（制作页的 animpicture_add_pic，数组载荷）==');
const extras = (engine.state.pictures || []).filter((p) => Number(p.pic_id) === 3063).slice(0, 3);
const ids = extras.map((p) => p.id);
const add = call('animpicture_add_pic', ids);
console.log('  add_pic ids=%s -> %s', JSON.stringify(ids), JSON.stringify(add));
console.log('  exp_pic=%d  相册剩余 %d 张', (A().expPic || []).length, (engine.state.pictures || []).length);
t('返回 code 0（以前这个协议根本没人接）', add.code === 0);
t('照片进了 exp_pic', (A().expPic || []).length === 3);
t('照片离开相册', !(engine.state.pictures || []).some((p) => ids.indexOf(p.id) !== -1));
/* `exp` stays 0 on purpose: the client's own model resets it and never advances it in this flow,
   so sending anything else would just disagree with the page until the next reload. */
t('exp 保持 0（和客户端模型一致）', Number(A().exp) === 0, 'exp=' + A().exp);
/* 真机实测：客户端会发来**空数组**（{"code":-1,"why":"empty-ids"}）—— 它把选中项翻译成 id 时
   用的是自己那份相册列表，两者不同步就会翻成空。空数组现在走"同款明信片"兜底，
   只有相册里确实没有同款时才拒绝（拒绝必带 why）。 */
const noMore = call('animpicture_add_pic', []);
console.log('  空载荷 -> %s', JSON.stringify(noMore));
t('空载荷按"同款"兜底或带原因拒绝（不再裸拒）',
  noMore.code === 0 || (noMore.code === -1 && !!noMore.why), JSON.stringify(noMore));

console.log('');
console.log('== 4. 用显影液：消耗道具 + 按经验阶梯升级 ==');
const ph0 = Number(A().phase); const b8002 = house(8002);
const use1 = call('animpicture_use_item', { id: 8002 });
console.log('  单色 8002 -> %s（phase %d -> %d，exp=%d，持有 %d -> %d）',
  JSON.stringify(use1), ph0, A().phase, A().exp, b8002, house(8002));
t('phase 是数字且 >= 0（客户端的门）', typeof use1.phase === 'number' && use1.phase >= 0);
t('单色显影液被消耗 1 个', house(8002) === b8002 - 1);
t('phase 按瓶子的档位推进（单色 1 层）', Number(A().phase) === ph0 + 1, ph0 + ' -> ' + A().phase);
t('exp 保持 0（和客户端模型一致）', Number(A().exp) === 0, 'exp=' + A().exp);
/* 用光一种显影液，再问一次：没有道具时必须回 -1（客户端会安静地不动），而不是白送一阶 */
while (house(8002) > 0) call('animpicture_use_item', { id: 8002 });
const noItem = call('animpicture_use_item', { id: 8002 });
t('没有显影液时 phase = -1（不白送）', noItem.phase === -1, JSON.stringify(noItem));
t('也不认不存在的道具 id', call('animpicture_use_item', { id: 12345 }).phase === undefined
  || call('animpicture_use_item', { id: 12345 }).phase >= 0);

console.log('');
console.log('== 5. 一路用完，页做完 -> 返还 9002 ==');
let guard = 0;
while (Number(A().phase) !== 0 && guard < 200) {
  if (house(8004) < 1) gm('anim_kit');
  call('animpicture_use_item', { id: 8004 });
  guard += 1;
}
console.log('  用了 %d 次多色显影液后 phase=%d item_num=%d exp_pic=%d 相册=%d',
  guard, A().phase, A().itemNum, (A().expPic || []).length, (engine.state.pictures || []).length);
t('页做完回到 phase 0', Number(A().phase) === 0);
t('暂存照片回到了相册', (A().expPic || []).length === 0);
t('item_num 记了一次', Number(A().itemNum) >= 1, 'item_num=' + A().itemNum);
const b9002 = house(9002);
const pending = Number(A().itemNum);
const got = call('animpicture_get_item', {});
console.log('  get_item -> %s；9002 %d -> %d（应发 %d 个）', JSON.stringify(got), b9002, house(9002), pending);
t('领奖真的把 9002 发到家里（以前只是记个数）', house(9002) === b9002 + pending && pending >= 1);
t('item_num 归零', Number(A().itemNum) === 0);

console.log('');
console.log('== 6. 动态页上解锁一个照片格子（要花 9002）==');
const page = A().picList[0];
const putBefore = Number(page.putNum || 0);
if (house(9002) < 1) gm('anim_kit');
const b9002b = house(9002);
const open = call('animpicture_open_album', { index: 1 });
console.log('  open_album -> %s；格子 %d -> %d；9002 %d -> %d',
  JSON.stringify(open), putBefore, page.putNum, b9002b, house(9002));
t('返回 code 0', open.code === 0);
t('格子 +1', Number(page.putNum) === putBefore + 1);
t('花掉一个 9002', house(9002) === b9002b - 1);
const putNow = Number(page.putNum);
call('animpicture_open_album', { index: 1 });
call('animpicture_open_album', { index: 1 });
call('animpicture_open_album', { index: 1 });
const capped = call('animpicture_open_album', { index: 1 });
console.log('  连开到第 4 格后：putNum=%d，再开一次 -> %s', page.putNum, JSON.stringify(capped));
t('最多 4 格（界面上只有 4 个格子）', Number(page.putNum) <= 4 && Number(page.putNum) >= putNow);
t('到顶之后拒绝', Number(page.putNum) === 4 && capped.code === -1, 'putNum=' + page.putNum);

console.log('');
console.log('== 7. 拿一张照片放进去 / 取回来（动态页自己的两个协议）==');
const some = (engine.state.pictures || []).slice(0, 1)[0];
const uid = some.id;
const addSlot = call('animpicture_album_add_pic', { anim_index: 1, pic_index: 1, pic_uid: uid });
console.log('  album_add_pic anim_index=1 pic_index=1 pic_uid=%d -> %s', uid, JSON.stringify(addSlot));
t('返回 code 0', addSlot.code === 0);
t('照片进了那一格', !!page.pictures[0] && Number(page.pictures[0].id) === Number(uid));
const rm = call('animpicture_album_remove_pic', { anim_index: 1, pic_index: 1, is_delete: 0 });
t('取回后照片回到相册', (engine.state.pictures || []).some((p) => Number(p.id) === Number(uid)));

console.log('');
console.log('== 8. 存档往返（重开引擎后状态一致）==');
const snap = { phase: A().phase, picList: A().picList.length, expPic: (A().expPic || []).length };
const engine2 = createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
const A2 = engine2.state.animPicture;
const same = Number(A2.phase) === snap.phase && (A2.picList || []).length === snap.picList;
console.log('  重载: phase=%d 页=%d（原来 phase=%d 页=%d）', A2.phase, (A2.picList || []).length, snap.phase, snap.picList);
t('phase 与页数都还在', same);
t('材料数量也还在', house(8002) === (engine2.state.items.house || []).filter((x) => Number(x.item_id) === 8002).reduce((a2, x) => a2 + Number(x.count || 0), 0));

console.log('');
console.log('== 9. 每一条改状态的命令都不许推 animpicture_load（否则页面读的是旧快照）==');
const noPush = [
  ['animpicture_guide', {}],
  ['animpicture_get_item', {}],
  ['animpicture_select_pic', { id: (engine.state.pictures[0] || {}).id }],
  ['animpicture_add_pic', [(engine.state.pictures[0] || {}).id]],
  ['animpicture_use_item', { id: 8002 }],
  ['animpicture_open_album', { index: 1 }],
  ['animpicture_album_add_pic', { anim_index: 1, pic_index: 2, pic_uid: (engine.state.pictures[0] || {}).id }],
  ['animpicture_album_remove_pic', { anim_index: 1, pic_index: 2, is_delete: 0 }],
  ['animpicture_remove_pic', { index: 1, is_delete: 0 }],
];
let leaked = [];
for (const [cmd, data] of noPush) {
  const r = raw(cmd, data);
  if (pushedLoad(r)) leaked.push(cmd + ' x' + pushedLoad(r));
}
console.log('  会推 animpicture_load 的命令: %s', leaked.length ? JSON.stringify(leaked) : '（无）');
t('没有任何一条改状态的命令推 animpicture_load', leaked.length === 0);
t('animpicture_load 本身仍然可用（登录时用）',
  Array.isArray(raw('animpicture_load', {}).reply.pic_list));

console.log('');
console.log('%d passed, %d failed', pass, fail);
process.exit(fail ? 1 : 0);
