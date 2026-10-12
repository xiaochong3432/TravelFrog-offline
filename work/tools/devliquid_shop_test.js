#!/usr/bin/env node
'use strict';
/**
 * "原版可以卖，你就不能卖吗" -- prove the 显影液 can be BOUGHT in the game's own shop, through the
 * client's own protocol (`furniture_buy_shop {shop_id}`), with the price the table says.
 *
 *   FROG_ENGINE=<file> node work/tools/devliquid_shop_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'build', 'merged_v31', 'index.js');
const { createEngine } = require(ENGINE);
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const shopRows = GD.tables.furnitureShopData;
const shop = (id) => (Array.isArray(shopRows) ? shopRows : Object.values(shopRows))
  .find((r) => Number(r.id) === Number(id));

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'frog-shop-'));
const engine = createEngine({ savePath: path.join(dir, 'save.json'), verbose: false });
const call = (cmd, data) => engine.dispatch(cmd, data || {}).reply || {};
const gm = (c) => call('client_gm', { cmd: c });
const house = (id) => {
  const r = (engine.state.items.house || []).find((x) => Number(x.item_id) === Number(id));
  return Number(r && r.count) || 0;
};

let pass = 0; let fail = 0;
const t = (name, cond, extra) => {
  if (cond) { pass += 1; console.log('  PASS  ' + name); } else { fail += 1; console.log('  FAIL  ' + name + (extra ? '   ' + extra : '')); }
};

const payload = call('furniture_load_furniture', {});
const sh = payload.shop || {};
console.log('== 家具店（嘟嘟的商店）当期状态 ==');
console.log('  start_time=%s leave_time=%s  now=%s', sh.start_time, sh.leave_time, Math.floor(Date.now() / 1000));
const inShop = {};
for (const row of sh.shop_list || []) inShop[Number(row.shop_id)] = Number(row.num);
console.log('  shop_list 里的 9001/9002/9003: %s', JSON.stringify({ 9001: inShop[9001], 9002: inShop[9002], 9003: inShop[9003] }));
t('三瓶显影液都在货架上', Number(inShop[9001]) > 0 && Number(inShop[9002]) > 0 && Number(inShop[9003]) > 0);
const open = !sh.leave_time || Number(sh.leave_time) > Math.floor(Date.now() / 1000);
console.log('  商店现在是否营业: %s', open);
t('商店现在营业（leave_time 在未来或未设置）', open);

console.log('');
console.log('== 按原版价格买（价格来自 furnitureShopData）==');
gm('add_clover 20000');
for (const [slot, itemId, price] of [[9001, 8002, 500], [9002, 8003, 1000], [9003, 8004, 1500]]) {
  const row = shop(slot);
  const c0 = engine.state.clover; const h0 = house(itemId);
  const r = call('furniture_buy_shop', { shop_id: slot });
  const c1 = engine.state.clover; const h1 = house(itemId);
  console.log('  shop_id=%d (item %d) -> %s   三叶草 %d -> %d（-%d），家里 %d -> %d',
    slot, itemId, JSON.stringify(r), c0, c1, c0 - c1, h0, h1);
  t(`表里的价格是 ${row && row.price}`, Number(row && row.price) === price);
  t(`买 ${slot} 回复 code 0`, r.code === 0);
  t(`三叶草正好扣 ${price}`, c0 - c1 === price, '扣了 ' + (c0 - c1));
  t(`显影液 ${itemId} 进家 +1`, h1 === h0 + 1);
}

console.log('');
console.log('== 没钱时买不动（不白送）==');
engine.state.clover = 100;
const before = house(8002);
const poor = call('furniture_buy_shop', { shop_id: 9001 });
console.log('  clover=100 时买 9001 -> %s', JSON.stringify(poor));
t('买不起就不给货', house(8002) === before && (poor.code !== 0 || engine.state.clover === 100),
  JSON.stringify({ house: house(8002), clover: engine.state.clover }));

console.log('');
console.log('== 买到手就能用在动态照片上 ==');
const anySkin = Object.keys(GD.tables.animpictureData.pic_map)[0];
engine.state.pictures.push({ id: 99001, pic_id: Number(anySkin), read: 0, new: 1 });
call('animpicture_select_pic', { id: 99001 });
gm('add_clover 20000');
call('furniture_buy_shop', { shop_id: 9001 });
const h = house(8002);
const r2 = call('animpicture_use_item', { id: 8002 });
console.log('  买到的 8002 用于显影 -> %s；家里 %d -> %d', JSON.stringify(r2), h, house(8002));
t('用显影液推进并且消耗掉刚买到的那瓶', typeof r2.phase === 'number' && r2.phase >= 0 && house(8002) === h - 1);

console.log('');
console.log('%d passed, %d failed', pass, fail);
process.exit(fail ? 1 : 0);
