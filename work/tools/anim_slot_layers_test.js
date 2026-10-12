#!/usr/bin/env node
'use strict';
/**
 * "开存储槽位 → 放照片 → 重启 → 再打开这张动态照片 = 吃坏肚子" 的回归测试。
 *
 * 崩溃链（客户端 main.min.js，逐字核对过）：
 *   AnimPictureShowPage.updatePic()
 *     -> this.pictureList[t].setData(pic)            （只对 pic.id > 0 的槽位调用）
 *     -> PictureItemRender.data -> PictureRender.render(pic)
 *     -> Tabikaeru.loadPicture(pic) / getPictureTexture(pic)
 *         function i(e){ if(e){ for (var i="",n=0,r=e.layers; n<r.length; n++){…} } }
 *         function r(e,i){ for (var n="",r=0,o=e.layers; r<o.length; r++){…} }
 *   `e.layers` 为 undefined 时读 `.length` 直接抛 TypeError -> Reload.JSError = 吃坏肚子。
 *
 * 为什么"开槽位不放照片""放照片但重启前取下来"都不炸：槽位里是 {id:0}，客户端 `id > 0`
 * 才 setData —— 与玩家反馈完全一致。所以引擎必须在 animpicture_load 的 payload 里给每张
 * 照片带上 `layers`（客户端内存里那份来自 album_load，本来就带，所以重启前不炸）。
 *
 *   node work/tools/anim_slot_layers_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine } = require(ENGINE);
const GD = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const LAYERS = JSON.parse(fs.readFileSync(
  path.join(ROOT, 'work', 'run', 'engine', 'data', 'picture-layers.json'), 'utf8'));

const PIC_MAP = Object.keys((GD.tables.animpictureData || {}).pic_map || {});
let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
};

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-animslot-'));
const savePath = path.join(dir, 'save.json');
const engine = createEngine({ savePath, verbose: false });
const call = (e, cmd, data) => e.dispatch(cmd, data || {}).reply;

/* ---- 1) 造出玩家那条路径 ---- */
const animPicId = Number(PIC_MAP[0]);                    // 可做动态照片的明信片（pic_map）
const albumId = 90001;
engine.state.pictures.push({ id: albumId, pic_id: animPicId, read: 0, new: 0 });
/* 槽位里要放的那张（相册照片）：挑一个 layers 表里有记录的 pic_id，好断言"真的能画出来" */
const slotPicId = Number(Object.keys(LAYERS).find((k) => (LAYERS[k].layers || []).length > 0));
const slotId = 90002;
engine.state.pictures.push({ id: slotId, pic_id: slotPicId, read: 0, new: 0 });
/* 开槽位要花一个「照片存储开启物」(9002) */
engine.state.items.house.push({ item_id: 9002, count: 3 });

t('select_pic 建页', call(engine, 'animpicture_select_pic', { id: albumId }).code === 0);
t('open_album 开第一格', call(engine, 'animpicture_open_album', { index: 1 }).code === 0);
const put = call(engine, 'animpicture_album_add_pic',
  { anim_index: 1, pic_index: 1, pic_uid: slotId });
t('album_add_pic 把照片放进槽位', put.code === 0, JSON.stringify(put));

/* ---- 2) 重启：同一份存档，换一个引擎实例 ---- */
const again = createEngine({ savePath, verbose: false });
const payload = call(again, 'animpicture_load', {});
const page = (payload.pic_list || [])[0];
t('重启后仍能读到那一页', !!page && page.pictures && page.pictures.length === 1);

const pic = page && page.pictures && page.pictures[0];
t('槽位里的照片 id > 0（客户端会 setData 它）', !!pic && Number(pic.id) > 0, JSON.stringify(pic));
t('槽位里的照片带 layers 数组 —— 客户端不会再抛 reading \'length\'',
  !!pic && Array.isArray(pic.layers),
  pic ? ('layers=' + JSON.stringify(pic.layers && pic.layers.slice(0, 1))) : 'pic is null');
t('layers 与 picture-layers.json 对得上（不是空壳）',
  !!pic && Array.isArray(pic.layers) && pic.layers.length === (LAYERS[String(pic.pic_id)].layers || []).length,
  pic ? ('pic_id=' + pic.pic_id + ' 层数=' + (pic.layers || []).length) : '');

/* 客户端渲染的等价检查：直接跑它的循环条件 */
let crash = null;
try {
  for (const row of page.pictures) { for (let i = 0; i < row.layers.length; i += 1) void row.layers[i]; }
} catch (e) { crash = e && e.message; }
t('复刻客户端的取层循环不抛错', crash === null, crash || '');

/* ---- 3) exp_pic（制作页里暂存的那几张）也必须带 layers ---- */
const A = again.state.animPicture;
A.expPic = [{ id: 90003, pic_id: slotPicId, read: 0, new: 0 }];
const p2 = call(again, 'animpicture_load', {});
t('exp_pic 里的照片也带 layers 数组',
  Array.isArray((p2.exp_pic || [])[0] && p2.exp_pic[0].layers),
  JSON.stringify(p2.exp_pic && p2.exp_pic[0]));

/* ---- 4) 空图层模板（官方 7 张）应当是空数组而不是 undefined ---- */
const empty = call(again, 'animpicture_load', {});
t('layers 永远是数组（哪怕表里没有这张的记录）',
  (empty.pic_list || []).every((p) => (p.pictures || []).every((x) => Array.isArray(x.layers))));

console.log('\n' + pass + ' passed, ' + fail + ' failed');
try { fs.rmSync(dir, { recursive: true, force: true }); } catch (e) { /* ignore */ }
process.exit(fail ? 1 : 0);
