#!/usr/bin/env node
'use strict';
/**
 * 验证这次两条修复（对应用户手机上的两条报错）：
 *   1) 空数组的 add_pic（真机就是这样发的：{"code":-1,"why":"empty-ids"}）现在走"同款"兜底；
 *   2) 显影液扣完后，客户端会收到 item_load_items 推送（数量不再是旧的 5/5/5），
 *      而且回复里带 used/left；没货时拒绝里带 why='no-item'。
 *
 *   node work/tools/final_two_causes_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'build', 'merged_v31', 'index.js');
const { createEngine } = require(ENGINE);
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-final-'));
const engine = createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
const raw = (cmd, data) => engine.dispatch(cmd, data || {});
const call = (cmd, data) => raw(cmd, data).reply || {};
const gm = (c) => call('client_gm', { cmd: c });
const house = (id) => {
  const r = (engine.state.items.house || []).find((h) => Number(h.item_id) === Number(id));
  return Number(r && r.count) || 0;
};
let pass = 0, fail = 0;
const t = (n, ok, extra) => { if (ok) { pass += 1; console.log('  PASS  ' + n); } else { fail += 1; console.log('  FAIL  ' + n + (extra ? '   ' + extra : '')); } };

console.log('== 1. 空数组的 add_pic（真机就是这么发的）==');
gm('anim_kit');
const seed = (engine.state.pictures || []).filter((p) => Number(p.pic_id) === 3102).pop();
call('animpicture_select_pic', { id: seed.id });
const empty = call('animpicture_add_pic', []);
console.log('  add_pic [] -> %s', JSON.stringify(empty));
t('空数组不再被拒绝，而是按"同款"补上', empty.code === 0 && empty.how === 'same-card', JSON.stringify(empty));
t('确实有照片进了 exp_pic', (engine.state.animPicture.expPic || []).length > 0);

console.log('');
console.log('== 2. 显影液：扣完要把数量推给客户端 ==');
const r = raw('animpicture_use_item', { id: 8004 });
const pushes = (r.pushes || []).map((p) => p.cmd);
console.log('  use_item -> %s；本次推送=%s', JSON.stringify(r.reply), JSON.stringify(pushes));
t('回复里带 used / left', r.reply.used === 8004 && typeof r.reply.left === 'number', JSON.stringify(r.reply));
t('扣完推了物品数量（客户端持有数才会跟上）',
  pushes.some((c) => /item[._]load[._]items/.test(c)), JSON.stringify(pushes));
t('推送里没有 animpicture_load（那会破坏页面手里的 data）',
  pushes.indexOf('animpicture.load') === -1 && pushes.indexOf('animpicture_load') === -1);

console.log('');
console.log('== 3. 显影液用光之后：拒绝要带原因（客户端会用人话提示）==');
engine.state.items.house = (engine.state.items.house || []).filter((h) => Number(h.item_id) !== 8004);
const none = call('animpicture_use_item', { id: 8004 });
console.log('  use_item（一瓶都没有）-> %s', JSON.stringify(none));
t('phase = -1（客户端会安静不动）', none.phase === -1);
t('带 why = no-item', none.why === 'no-item' && none.item === 8004, JSON.stringify(none));

console.log('');
console.log('== 4. 同款也没有了才拒绝（并且带原因）==');
engine.state.pictures = (engine.state.pictures || []).filter((p) => Number(p.pic_id) !== 3102);
engine.state.animPicture.expPic = [];
const noSame = call('animpicture_add_pic', []);
console.log('  add_pic [] -> %s', JSON.stringify(noSame));
t('真的没有同款时拒绝', noSame.code === -1);
t('拒绝带原因 not-found', noSame.why === 'not-found', JSON.stringify(noSame));

console.log('');
console.log('%d passed, %d failed', pass, fail);
process.exit(fail ? 1 : 0);
