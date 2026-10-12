#!/usr/bin/env node
'use strict';

/* 【V4.0】这套件验证 V3.7 的常开窗口 + 售罄可见，所以按 V3.7 设好两个开关（[8] 自己切 faithful）。
   引擎的开关常量在 require 时求值，所以这段必须在 require 之前。 */
process.env.FROG_SHOP_WINDOW = 'always';
process.env.FROG_SHOP_KEEP_SOLD_OUT = '1';

/**
 * V3.7 系统 5：嘟嘟商店星级货架 + 节气商店（并入他 3.3）
 *
 *   node work/tools/v37_merchant_stars_test.js
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const ROOT = path.resolve(__dirname, '..', '..');
const ENGINE = process.env.FROG_ENGINE || path.join(ROOT, 'work', 'run', 'engine', 'index.js');
const { createEngine, solarTermDay } = require(ENGINE);
const GD = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'));
const SHOP_ROWS = GD.tables.furnitureShopData;

const at = (y, m, d, h, min) => Math.floor(new Date(y, m - 1, d, h || 12, min || 0, 0, 0).getTime() / 1000);
let CLOCK = at(2026, 7, 10, 14);
Date.now = () => CLOCK * 1000;

let pass = 0, fail = 0;
const t = (name, ok, extra) => {
  if (ok) { pass += 1; console.log('  PASS  ' + name); }
  else { fail += 1; console.log('  FAIL  ' + name + (extra != null ? '   ' + extra : '')); }
};
const eq = (a, b, name) => t(name, a === b, 'expected ' + b + ', got ' + a);
const newEngine = (savePath) => createEngine({
  savePath: savePath || path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'shop-')), 'save.json'),
  verbose: false,
});
const call = (e, cmd, d) => e.dispatch(cmd, d || {});
const shopOf = (e) => call(e, 'furniture_load_furniture', {}).reply.shop;

console.log('\n[1] 每天 8 个货位（节气日多一个），都是表里真实存在的行');
{
  const e = newEngine();
  e.tick();
  const shop = shopOf(e);
  const list = shop.shop_list;
  t('货位数 1..9（8 个 + 可能的节气行）', list.length >= 1 && list.length <= 9, list.length + ' 个');
  t('每个货位都有库存 num ≥ 1', list.every((r) => Number(r.num) >= 1), JSON.stringify(list.slice(0, 3)));
  t('货位 id 都在 furnitureShopData 里',
    list.every((r) => !!SHOP_ROWS[String(r.shop_id)]),
    JSON.stringify(list.map((r) => r.shop_id)));
  t('没有重复货位', new Set(list.map((r) => r.shop_id)).size === list.length);
  /* 【自设计保留】我们的默认是**常开**（离线版按真实时间玩；3.4 文档也这么写）。
     他的"12:00 后到、21:00 走"作为 FROG_SHOP_WINDOW=faithful 可选，见下面 [8]。 */
  t('默认营业窗口是常开的',
    Number(shop.start_time) < Date.now() / 1000 && Date.now() / 1000 < Number(shop.leave_time),
    'start=' + new Date(shop.start_time * 1000).toLocaleString()
    + ' leave=' + new Date(shop.leave_time * 1000).toLocaleString());
}

console.log('\n[2] 同一天恒定（同 uid 重开游戏货架不变）、换天才换');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shop-same-'));
  const p = path.join(dir, 'save.json');
  const e1 = newEngine(p);
  e1.tick();
  e1.save();
  const l1 = shopOf(e1).shop_list.map((r) => r.shop_id + ':' + r.num).sort().join(',');
  const e2 = newEngine(p);            // 同一份档（同 uid、同一天）
  e2.tick();
  const l2 = shopOf(e2).shop_list.map((r) => r.shop_id + ':' + r.num).sort().join(',');
  eq(l2, l1, '同一天重开货架一致');
  const day1 = Number(e1.state.furniture.shopOffersDay);
  CLOCK += 86400;                     // 第二天
  e1.tick();
  call(e1, 'furniture_load_furniture', {});
  const day2 = Number(e1.state.furniture.shopOffersDay);
  t('换天换了货架日期键（本地零点时间戳，+86400）', day2 === day1 + 86400, day1 + ' -> ' + day2);
  t('换天清空了当天已买账本', Object.keys(e1.state.furniture.shopDailyBought).length === 0);
  CLOCK -= 86400;
}

console.log('\n[3] 默认常开：任何时间都能买，买完库存 -1');
{
  const e = newEngine();
  e.tick();
  const shop = shopOf(e);
  const priced = shop.shop_list.find((r) => Number(r.price) > 0)
    || shop.shop_list[0];
  const row = SHOP_ROWS[String(priced.shop_id)];
  e.state.clover = 999999;
  /* 默认常开（我们的自设计；他的 12:00–21:00 见 [8]）：凌晨 3:30 也能买 */
  CLOCK = at(2026, 7, 10, 3, 30);
  e.tick();
  const before = Number(e.state.clover);
  const r = call(e, 'furniture_buy_shop', { shop_id: priced.shop_id });
  eq(r.reply.code, 0, '凌晨也能买（默认常开）');
  const paid = Number(row.type) === 998 ? 0 : (Number(row.price) || 0);
  eq(before - Number(e.state.clover), paid, '扣的钱等于标价（福利品不收费）');
  const after = shopOf(e).shop_list.find((x) => Number(x.shop_id) === priced.shop_id);
  eq(Number(after.num), Number(priced.num) - 1, '该货位库存 -1');
  /* 卖光之后再买同一行必须被拒 */
  if (Number(after.num) === 0) {
    eq(call(e, 'furniture_buy_shop', { shop_id: priced.shop_id }).reply.code, -1, '卖光的行再买被拒');
  }
  CLOCK = at(2026, 7, 10, 14);
}

console.log('\n[4] 节气当天多摆一个节气货架');
{
  /* 2026-02-04 是立春（term 索引 2）→ 映射到 shopId 102 */
  eq(solarTermDay(2026, 2), 4, '确认 2026-02-04 是立春');
  const e = newEngine();
  CLOCK = at(2026, 2, 4, 14);
  e.tick();
  const list = shopOf(e).shop_list.map((r) => Number(r.shop_id));
  t('立春当天货架里有 102', list.indexOf(102) !== -1, JSON.stringify(list));
  CLOCK = at(2026, 2, 5, 14);
  e.tick();
  const list2 = shopOf(e).shop_list.map((r) => Number(r.shop_id));
  t('第二天就没有那个节气货架了', list2.indexOf(102) === -1, JSON.stringify(list2));
  CLOCK = at(2026, 7, 10, 14);
}

console.log('\n[5] 前置商品只在手上时才上架');
{
  const e = newEngine();
  e.tick();
  const list = shopOf(e).shop_list;
  const bad = list.filter((r) => {
    const need = Number(SHOP_ROWS[String(r.shop_id)].has_item) || 0;
    if (!need) return false;
    return !(e.state.items.house.some((x) => Number(x.item_id) === need)
      || (e.state.furniture.bench || []).some((v) => Number(v) === need)
      || (e.state.furniture.owned || []).some((v) => Number(v) === need));
  });
  eq(bad.length, 0, '上架的每一行前置都满足');
}

console.log('\n[6] 手工图纸行（他的特殊行）可以买到');
{
  /* 他补的 7 行里，只有两张图纸在我们官方表里没有出售行；他用的 id 8035/8036 在我们表里
     被官方行占用（南瓜豆沙糕/酥圈圈），所以补在空闲 id 8053(不倒翁图鉴 10401)/8054(挂兜 10601)。 */
  const e = newEngine();
  e.tick();
  e.state.clover = 999999;
  e.state.furniture.shopOffers = { 8054: 1 };
  e.state.furniture.shopDailyBought = {};
  const shop = shopOf(e);
  if (!shop.shop_list.some((r) => Number(r.shop_id) === 8054)) {
    e.state.furniture.shopOffers = { 8054: 1 };
    const s2 = shopOf(e);
    t('挂兜图纸行 8054 在货架上', s2.shop_list.some((r) => Number(r.shop_id) === 8054),
      JSON.stringify(s2.shop_list.map((r) => r.shop_id)));
    CLOCK = Number(s2.start_time) + 60;
    e.tick();
  } else {
    CLOCK = Number(shop.start_time) + 60;
    e.tick();
  }
  const r = call(e, 'furniture_buy_shop', { shop_id: 8054 });
  eq(r.reply.code, 0, '买得到挂兜图纸');
  t('图纸进了家里（10601）', e.state.items.house.some((x) => Number(x.item_id) === 10601 && x.count > 0),
    JSON.stringify(e.state.items.house.filter((x) => Number(x.item_id) === 10601)));
  /* 官方 8036（酥圈圈 117）不能被我们的补行覆盖 */
  const official = JSON.parse(fs.readFileSync(path.join(ROOT, 'work', 'run', 'engine', 'data', 'gamedata.json'), 'utf8'))
    .tables.furnitureShopData['8036'];
  eq(Number(official.item_id), 117, '官方 8036 仍然是酥圈圈（没被覆盖）');
  CLOCK = at(2026, 7, 10, 14);
}

console.log('\n[7] 老档兼容（没有 shopOffers 的 V3.5/V3.6 档）');
{
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'shop-old-'));
  const p = path.join(dir, 'save.json');
  const seed = newEngine();
  seed.tick();
  const raw = JSON.parse(JSON.stringify(seed.exportSave()));
  delete raw.furniture.shopOffers;
  delete raw.furniture.shopOffersDay;
  raw.saveVersion = 1;
  /* 老档的当天已买账本（我们原来的字段）要保留 */
  raw.furniture.shopDailyBought = {};
  raw.furniture.shopDay = 0;
  fs.writeFileSync(p, JSON.stringify(raw));
  const e = newEngine(p);
  e.tick();
  const shop = shopOf(e);
  t('老档进来照样能生成当天货架', Array.isArray(shop.shop_list) && shop.shop_list.length > 0,
    JSON.stringify(shop.shop_list.slice(0, 3)));
  t('shopOffersDay 已补齐', Number(e.state.furniture.shopOffersDay) > 0);
  const again = JSON.parse(JSON.stringify(e.exportSave()));
  t('存回再读货架还在', Object.keys(again.furniture.shopOffers || {}).length > 0);
}

console.log('\n[8] 他的营业窗口（FROG_SHOP_WINDOW=faithful）可选启用');
{
  process.env.FROG_SHOP_WINDOW = 'faithful';
  delete require.cache[require.resolve(ENGINE)];
  const mod = require(ENGINE);
  const e = mod.createEngine({ savePath: path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'shop-f-')), 'save.json'), verbose: false });
  e.tick();
  const shop = call(e, 'furniture_load_furniture', {}).reply.shop;
  const start = new Date(Number(shop.start_time) * 1000);
  const leave = new Date(Number(shop.leave_time) * 1000);
  t('faithful 模式：12:00–18:00 之间到店', start.getHours() >= 12 && start.getHours() < 19,
    start.toLocaleString());
  t('faithful 模式：21:00 走', leave.getHours() === 21 && leave.getMinutes() === 0,
    leave.toLocaleString());
  /* 开门前买不了 */
  CLOCK = Math.floor(start.getTime() / 1000) - 3600;
  e.tick();
  const first = call(e, 'furniture_load_furniture', {}).reply.shop.shop_list[0];
  eq(call(e, 'furniture_buy_shop', { shop_id: first.shop_id }).reply.code, -1, 'faithful 模式下开门前买不了');
  CLOCK = at(2026, 7, 10, 14);
  delete process.env.FROG_SHOP_WINDOW;
  delete require.cache[require.resolve(ENGINE)];
}

console.log('\n' + pass + ' passed, ' + fail + ' failed');
process.exit(fail ? 1 : 0);
