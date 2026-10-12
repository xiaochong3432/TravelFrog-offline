#!/usr/bin/env node
'use strict';
/**
 * 动态照片页「照片存储开启物（9002）」剩余数量的显示一致性。
 *
 * 用户报的现象：界面里显示的剩余数量不是实际剩余数，**重启游戏后才更新**。
 *
 * 原因（已按出货客户端代码定位）：显示值不是单一数字，而是两处相加——
 *   AnimPictureShowPage.updatePic():
 *     this.lbItem.text = "持有" + (ItemModel.getHouseItemCount(9002) + this.data.item_num) + "个"
 * 其中 ItemModel 只由引擎主动推送（`item.load_items` / `item.update`）更新。
 * 开槽位（animpicture_open_album 扣 1 张 9002）以前**不推送**，于是：
 *   - 家里实际只剩 2 张，ItemModel 还是 3  → 界面显示 3（比实际多 1）；
 *   - 重启后开局 load 会重新下发 item 列表 → 界面才对上。
 * 修复就在引擎侧：扣券/发券后主动推送（见 work/tools/v35_anim_storage_count_push.py）。
 *
 * 本测试把客户端那条公式原样搬过来，用引擎真实回包驱动：
 *   1) 出货客户端里确实存在这条公式（不是我们臆造的显示逻辑）；
 *   2) 推送先落模型时，回调里读到 == 真实剩余；
 *   3) 故意丢掉推送（= 修复前的行为）能复现出"显示 ≠ 实际"，证明这条测试真的抓得住这个 bug。
 *
 *   node work/tools/anim_storage_display_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const { createEngine, canon } = require(path.join(ROOT, 'work', 'run', 'engine', 'index.js'));
const CLIENT = path.join(ROOT, 'work', 'run', 'web', 'js', 'main.min.js');
const gd = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const ANIMPIC = Number(Object.keys(gd.tables.animpictureData.pic_map)[0]);
const STORAGE_ITEM = 9002;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};

/* ---------- 1. 出货客户端里确实有这条显示公式 ---------- */
const clientSrc = fs.readFileSync(CLIENT, 'utf8');
const FORMULA = 'getHouseItemCount(9002)+this.data.item_num';
console.log('客户端：' + path.relative(ROOT, CLIENT));
t('客户端持有数 = 家里 9002 数量 + 本页待领数量（出货代码里有这条公式）', clientSrc.includes(FORMULA));

/* ---------- 客户端模型桩：只认引擎推送 ---------- */
function makeClient() {
  const itemModel = { house: {} };      // ItemModel.getHouseItemCount 的数据源
  const animPicture = { item_num: 0 };  // AnimPictureModel.data.item_num
  const applyPush = (p) => {
    const name = canon(p.cmd);
    if (name === 'item_load_items') {
      itemModel.house = {};
      for (const row of p.data.house || []) itemModel.house[Number(row.item_id)] = Number(row.count);
      return true;
    }
    if (name === 'item_update') {
      const it = p.data.item || {};
      if (it.item_id != null) itemModel.house[Number(it.item_id)] = Number(it.count);
      return true;
    }
    return false;
  };
  return {
    itemModel,
    animPicture,
    /* 外壳投递顺序：**推送先于回复**（这是 work/build/v4_shell/__probe.js 的既有保证） */
    deliver(res, onReply) {
      for (const p of res.pushes || []) applyPush(p);
      onReply();
    },
    /* 对照：修复前的行为——回复到了但推送还没到（或压根没有推送） */
    deliverReplyFirst(res, onReply) { onReply(); },
    /* 客户端 updatePic() */
    display() { return (this.itemModel.house[STORAGE_ITEM] || 0) + this.animPicture.item_num; },
    storage9002InPushes(res) {
      const p = (res.pushes || []).find((x) => canon(x.cmd) === 'item_load_items');
      if (!p) return null;
      const row = (p.data.house || []).find((x) => Number(x.item_id) === STORAGE_ITEM);
      return row ? Number(row.count) : 0;
    },
  };
}

function freshEngine(houseCount) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'v35-display-'));
  const e = createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
  e.state.items.house.push({ item_id: STORAGE_ITEM, count: houseCount });
  e.state.pictures.push({ id: 7001, pic_id: ANIMPIC, read: 0, new: 0 });
  e.dispatch('animpicture_select_pic', { id: 7001 });
  return e;
}
const house9002 = (e) => {
  const row = (e.state.items.house || []).find((x) => Number(x.item_id) === STORAGE_ITEM);
  return row ? Number(row.count) : 0;
};
/* 开局 ItemModel 的来源：客户端**没有**请求 item_load_items 的方法（全客户端里它只出现在
   `addProtocolCallback("item_load_items", …)` 那一串里，没有 req_ 版本），只能由引擎推。
   引擎在登录/出门/gm 的 refresh() 里推的就是 handlers.item_load_items() 的载荷，
   所以这里直接取该处理函数的回包当作"开局那一次推送"，数值完全等同。 */
function seedFromBoot(e, c) {
  const res = e.dispatch('item_load_items', {});
  c.itemModel.house = {};
  for (const row of res.reply.house || []) c.itemModel.house[Number(row.item_id)] = Number(row.count);
}

/* ---------- 2. 开槽位：扣 1 张，界面必须立刻少 1 ---------- */
console.log('\n[开槽位] 家里 3 张 → animpicture_open_album 扣 1');
{
  const e = freshEngine(3);
  const c = makeClient();
  c.animPicture.item_num = 0;
  seedFromBoot(e, c);                                  // 开局：家里 3 张，待领 0
  const before = c.display();
  t('开槽位前显示 3（家里 3 + 待领 0）', before === 3, 'got ' + before);

  const res = e.dispatch('animpicture_open_album', { index: 1 });
  t('开槽位回包 code = 0', res.reply && res.reply.code === 0, JSON.stringify(res.reply));
  const real = house9002(e);
  t('引擎实际扣掉 1 张（家里剩 2）', real === 2, 'got ' + real);
  t('推送里带上 9002 = 2', c.storage9002InPushes(res) === 2, 'got ' + c.storage9002InPushes(res));

  /* 正常投递：推送先落模型，再跑客户端回调里的 updatePic() */
  c.deliver(res, () => {});
  const after = c.display();
  t('推送先到时显示 == 实际剩余（2）', after === real, 'display ' + after + ' / real ' + real);

  /* 对照：修复前（回复先到、推送没落模型）就复现用户报的"显示不对，重启才更新" */
  const e2 = freshEngine(3);
  const c3 = makeClient();
  c3.animPicture.item_num = 0;
  seedFromBoot(e2, c3);
  const res3 = e2.dispatch('animpicture_open_album', { index: 1 });
  c3.deliverReplyFirst(res3, () => {});
  const stale = c3.display();
  t('对照：推送未落模型时显示仍是 3 ≠ 实际 2（复现本 bug）', stale === 3 && stale !== house9002(e2),
    'display ' + stale + ' / real ' + house9002(e2));
  t('对照差值正好是刚扣掉的 1 张（与"重启后才对上"一致）', stale - house9002(e2) === 1,
    (stale - house9002(e2)) + '');
}

/* ---------- 3. 领取：发券入屋，待领归零，两者之和不变且等于实数 ---------- */
console.log('\n[领取] 待领 2 张 → animpicture_get_item 发进家里');
{
  const e = freshEngine(3);
  const c = makeClient();
  c.animPicture.item_num = 0;
  seedFromBoot(e, c);
  const open = e.dispatch('animpicture_open_album', { index: 1 });
  c.deliver(open, () => {});
  e.state.animPicture.itemNum = 2;                     // 制作页攒下的待领
  c.animPicture.item_num = 2;
  const beforeDisplay = c.display();
  t('领取前显示 = 家里 2 + 待领 2 = 4', beforeDisplay === 4, 'got ' + beforeDisplay);

  const res = e.dispatch('animpicture_get_item', {});
  t('领取回包 code = 0', res.reply && res.reply.code === 0, JSON.stringify(res.reply));
  const real = house9002(e);
  t('引擎把 2 张发进家里（家里 4）', real === 4, 'got ' + real);
  t('推送里带上 9002 = 4', c.storage9002InPushes(res) === 4, 'got ' + c.storage9002InPushes(res));

  /* 客户端 req_get_item 回调里把 data.item_num 置 0，再重画 */
  c.deliver(res, () => { c.animPicture.item_num = 0; });
  t('领取后显示 == 实际剩余（4）', c.display() === real, 'display ' + c.display() + ' / real ' + real);
  t('家里 + 待领 的口径与重启后一致（都由推送给出）', c.itemModel.house[STORAGE_ITEM] === real,
    JSON.stringify(c.itemModel.house));
}

/* ---------- 4. 两条推送口径一致（双保险：item.update 单件推送同值） ---------- */
console.log('\n[推送一致性] item.load_items 与 item.update 数值必须相同');
{
  const e = freshEngine(5);
  const res = e.dispatch('animpicture_open_album', { index: 1 });
  const load = (res.pushes || []).find((p) => canon(p.cmd) === 'item_load_items');
  const upd = (res.pushes || []).find((p) => canon(p.cmd) === 'item_update');
  const loadVal = load && (load.data.house || []).find((x) => Number(x.item_id) === STORAGE_ITEM);
  t('两种推送都发了', !!load && !!upd, (res.pushes || []).map((p) => p.cmd).join(','));
  t('item.update 的 9002 数值 == item.load_items 的数值',
    !!upd && !!loadVal && Number(upd.data.item.count) === Number(loadVal.count),
    JSON.stringify({ load: loadVal, upd: upd && upd.data.item }));
  t('推送数值 == 引擎真实持有数（4）', !!loadVal && Number(loadVal.count) === house9002(e),
    'push ' + (loadVal && loadVal.count) + ' / real ' + house9002(e));
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
