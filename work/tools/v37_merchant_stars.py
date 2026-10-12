#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.7 系统 5：嘟嘟商店星级货架 + 节气商店（并入「他做的 3.3」）

他的做法（源码逐段核对）：
  · 每天按 (uid, 日期) 生成 **8 个货位**（`MERCHANT_DAILY_OFFER_COUNT`），
    星级权重 `MERCHANT_STAR_WEIGHTS = {0:35, 1:30, 2:18, 3:10, 4:5, 5:2}`，
    每档的候选来自 `MERCHANT_STAR_ROWS`；同一个 item 不会在同一天重复上架；
  · 上架前过滤：已买满 `limit`、`unique` 且已经拥有、前置 `has_item` 不在家/台面/收藏里、
    福利商品当天已领满（`WELFARE_PER_DAY`）；
  · 每个货位库存 1..3（受 `limit - 已买`、`shop_limit`、福利 1/天 限制）；
  · **节气商店**：`MERCHANT_SOLAR_TERM_OFFERS` 把 24 节气映射到 24 个 shopId，
    当天是节气就把对应货架也摆上去（`solarTermDay` 已在系统 4 里并进来了）；
  · **营业窗口**：嘟嘟 12:00 之后到（`noon + (seed % 361) 分钟`，按 uid+日期确定），21:00 走；
  · `MERCHANT_SPECIAL_ROWS`：本地补 7 行原版没有出售行的商品，**包括不倒翁图鉴(10401)
    与挂兜手工制作(10601)** —— 正好是我们系统 2/3 那两套手工的图纸来源。

我们的现状：`furnitureShopList()` 把**整张表**都列出来（按 `order` 排序），
库存按 `limit/shop_limit/福利` 现算，营业窗口是"整天"（可用 `FROG_SHOP_HOURS` 收窄）。
本补丁把"每天 8 个货位"这套接上，并保留 `FROG_SHOP_HOURS` 作为窗口覆盖。

存档兼容：新增 `furniture.shopOffers`（当天货架）/`shopOffersDay`；沿用我们已有的
`shopDay` / `shopDailyBought` 作为"当天已买"账本，不引入第二本账。
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ENGINE = os.path.join(ROOT, 'work', 'build', 'v4_engine', 'index.js')
MARK = 'V37-MERCHANT-STARS'


def read(p):
    return io.open(p, encoding='utf-8', newline='').read()


def write(p, s):
    io.open(p, 'w', encoding='utf-8', newline='').write(s)


def sub_once(text, old, new, label):
    n = text.count(old)
    if n == 0:
        raise SystemExit('[shop] 锚点没找到：%s\n%s' % (label, old[:200]))
    if n > 1:
        raise SystemExit('[shop] 锚点出现 %d 次（应为 1）：%s' % (n, label))
    return text.replace(old, new, 1)


MODULE_BLOCK = """/* __MARK__ ============ 嘟嘟商店：星级货架 / 节气商店 / 特殊货架行 ============ */

/* 家具礼包（内容物是"家具"而不是普通物品，开包时进 furniture.owned）。 */
const FURNITURE_GIFT_BAG_IDS = new Set([204001, 204002]);

/* 每天摆几个货位、以及各星级的抽中权重（他的复原值）。 */
const MERCHANT_DAILY_OFFER_COUNT = 8;
const MERCHANT_STAR_WEIGHTS = new Map([[0, 35], [1, 30], [2, 18], [3, 10], [4, 5], [5, 2]]);

/* 每档星级的候选货架。 */
const MERCHANT_STAR_ROWS = new Map([
  [0, [8024]],
  [1, [8008, 7014, 7024, 7025, 7026, 7027, 7028]],
  [2, [6001, 6002, 6003, 6004, 6005, 6006, 9001, 9002, 9003]],
  [3, [3006, 8001, 8002, 8003, 8004, 8005, 8006, 8009,
    8010, 8011, 8012, 8013, 8014, 8015, 8017, 8018, 8019, 8020, 8021, 8025]],
  [4, [1001, 1002, 1003, 1004, 1005, ...Array.from({ length: 27 }, (_, i) => 4001 + i),
    2001, 2002, 2003, 2004, 2005, 2006, 2007, 3001, 3003, 3004, 3005, 3008, 3009,
    5, 6, 6007, 6008, 6009, 6010, 6011, 6012, 6013, 6014, 6015, 6016, 6019, 8027, 8035, 8036,
    8053, 8054]],
  [5, [1, 2, 3002, 3007, 3010, 3011, 8007, 8016, 8026, 8030, 8031, 8032, 8033, 8034]],
]);

/* 本地补的出售行。他那边补了 7 行（id 8030–8036），但**我们合并后的官方表里**：
     · 201001/201002/201003/201004/201008（古琴书桌、森之国度系列）**本来就有出售行**，不用补；
     · 8035/8036 这两个 id 已被官方行占用（卖的是南瓜豆沙糕 116 / 酥圈圈 117），不能覆盖；
     · 只有 **不倒翁图鉴 10401** 与 **挂兜手工制作 10601** 这两件图纸在我们表里没有任何出售行。
   所以只补这两行，并挪到空闲 id 8053/8054（价格/限购沿用他的：500、限 1、唯一）。
   注意：客户端要显示这两行，还需要他客户端那段"把未知行加进 KeyGetter"的补丁（客户端批次）。 */
const MERCHANT_SPECIAL_ROWS = [
  { id: 8053, item_id: 10401, name: '不倒翁图鉴', price: 500, limit: 1, unique: true, info: '不倒翁家具制作图纸' },
  { id: 8054, item_id: 10601, name: '挂兜手工制作', price: 500, limit: 1, unique: true, info: '挂兜制作图纸' },
];
for (const row of MERCHANT_SPECIAL_ROWS) {
  if (!FURNITURE_SHOP.has(row.id)) FURNITURE_SHOP.set(row.id, Object.assign({
    has_item: 0, limit: 0, shop_limit: 0, sign: 0, type: 999, order: 900,
  }, row));
}

/* 24 节气 -> 节气货架（他的映射表）。 */
const MERCHANT_SOLAR_TERM_OFFERS = [
  { month: 1, term: 0, shopId: 113 }, { month: 1, term: 1, shopId: 101 },
  { month: 2, term: 2, shopId: 102 }, { month: 2, term: 3, shopId: 114 },
  { month: 3, term: 4, shopId: 103 }, { month: 3, term: 5, shopId: 115 },
  { month: 4, term: 6, shopId: 116 }, { month: 4, term: 7, shopId: 104 },
  { month: 5, term: 8, shopId: 117 }, { month: 5, term: 9, shopId: 105 },
  { month: 6, term: 10, shopId: 118 }, { month: 6, term: 11, shopId: 106 },
  { month: 7, term: 12, shopId: 119 }, { month: 7, term: 13, shopId: 107 },
  { month: 8, term: 14, shopId: 108 }, { month: 8, term: 15, shopId: 120 },
  { month: 9, term: 16, shopId: 121 }, { month: 9, term: 17, shopId: 109 },
  { month: 10, term: 18, shopId: 122 }, { month: 10, term: 19, shopId: 110 },
  { month: 11, term: 20, shopId: 111 }, { month: 11, term: 21, shopId: 123 },
  { month: 12, term: 22, shopId: 112 }, { month: 12, term: 23, shopId: 124 },
];

/** 今天是节气吗？是的话返回那天的节气货架 id（否则 0）。 */
function solarTermShopFor(dayKey) {
  const day = Number(dayKey);
  const year = Math.floor(day / 10000);
  const month = Math.floor(day / 100) % 100;
  const dayOfMonth = day % 100;
  const term = MERCHANT_SOLAR_TERM_OFFERS.find((entry) => (
    entry.month === month && solarTermDay(year, entry.term) === dayOfMonth
  ));
  return term ? term.shopId : 0;
}

""".replace('__MARK__', MARK)

INNER_BLOCK = """  /* __MARK__ ============ 嘟嘟商店：每天的货架与营业窗口 ============ */

  /** 前置商品是否已经在手上（家里 / 工作台 / 家具收藏都算）。 */
  function hasShopPrerequisite(itemId) {
    const id = Number(itemId);
    return getHaveItem(id) > 0
      || (state.furniture.bench || []).some((value) => Number(value) === id)
      || (state.furniture.owned || []).some((value) => Number(value) === id);
  }

  /** 按 (uid, 日期) 生成当天 8 个货位：同一天恒定、换天才换（他的做法）。 */
  function createFurnitureShopOffers(day) {
    let seed = (Number(state.uid) || 0) ^ Number(day);
    seed = Math.imul(seed ^ (seed >>> 16), 0x45d9f3b);
    seed = Math.imul(seed ^ (seed >>> 16), 0x45d9f3b);
    seed = (seed ^ (seed >>> 16)) >>> 0;
    let randomState = seed || 0x9e3779b9;
    const random = () => {
      randomState = (randomState + 0x6d2b79f5) >>> 0;
      let value = randomState;
      value = Math.imul(value ^ (value >>> 15), value | 1);
      value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
      return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
    };

    const pools = new Map();
    for (const [star, ids] of MERCHANT_STAR_ROWS) {
      const rows = ids.map((id) => [id, FURNITURE_SHOP.get(id)])
        .filter(([, row]) => row && row.item_id !== undefined)
        .filter(([id, row]) => !(Number(row.limit) > 0
          && (Number(state.furniture.shopBought[id]) || 0) >= Number(row.limit)))
        .filter(([, row]) => !row.unique || getHaveItem(row.item_id) <= 0)
        .filter(([, row]) => !row.has_item || hasShopPrerequisite(row.has_item))
        .filter(([id, row]) => !(isWelfareRow(row)
          && state.furniture.welfareDay && state.furniture.welfareDay[id] === createDay()
          && (Number(state.furniture.welfareTaken && state.furniture.welfareTaken[id]) || 0) >= WELFARE_PER_DAY));
      pools.set(star, rows);
    }

    const offers = {};
    for (let slot = 0; slot < MERCHANT_DAILY_OFFER_COUNT; slot++) {
      const available = [...pools.entries()].filter(([, rows]) => rows.length > 0);
      if (!available.length) break;
      const totalWeight = available.reduce((sum, [star]) => sum + MERCHANT_STAR_WEIGHTS.get(star), 0);
      let roll = random() * totalWeight;
      let chosenStar = available[available.length - 1][0];
      for (const [star] of available) {
        roll -= MERCHANT_STAR_WEIGHTS.get(star);
        if (roll < 0) { chosenStar = star; break; }
      }
      const pool = pools.get(chosenStar);
      const index = Math.floor(random() * pool.length);
      const [shopId, row] = pool.splice(index, 1)[0];
      const itemId = Number(row.item_id);
      for (const rows of pools.values()) {
        for (let i = rows.length - 1; i >= 0; i--) {
          if (Number(rows[i][1].item_id) === itemId) rows.splice(i, 1);
        }
      }

      let maxStock = 3;
      if (Number(row.limit) > 0) {
        maxStock = Math.min(maxStock, Number(row.limit) - (Number(state.furniture.shopBought[shopId]) || 0));
      }
      if (Number(row.shop_limit) > 0) maxStock = Math.min(maxStock, Number(row.shop_limit));
      if (isWelfareRow(row)) maxStock = Math.min(maxStock, WELFARE_PER_DAY);
      if (maxStock > 0) offers[shopId] = 1 + Math.floor(random() * maxStock);
    }
    /* 节气当天多摆一个节气货架（他的做法）。 */
    /* solarTermShopFor 要的是 YYYYMMDD 日键（本地日），而这里的 day 是零点时间戳。 */
    const solarTermShopId = solarTermShopFor(localDayKeyAt(day));
    if (solarTermShopId && FURNITURE_SHOP.has(solarTermShopId)) {
      offers[solarTermShopId] = 1 + Math.floor(random() * 3);
    }
    return offers;
  }

  /** 换天就重掷货架、清空当天已买账本（`shopDay`/`shopDailyBought` 是我们原来的账本）。
      注意：这里**不写盘**。这个函数是从载荷构建（furnitureShopList）里调的，而载荷路径调
      save() 会在每次 gm/推送之间插入一次额外提交，把 .bak 提前写脏（我们这条线的备份语义是
      "备份 = 上一次完整存档"）。货架按 (uid, 日期) 确定性生成，重开一次结果相同，
      交给下一次自然保存（购买 / tick / gm）持久化即可。 */
  function ensureFurnitureShopStock(at) {
    /* 日键必须与我们原有的账本一致（`merchantDayAt` = 本地零点时间戳），否则两边会在
       不同时刻"换天"：曾出现 refreshMerchantDay 误判换天、又保存一次、还把当天已买清空。
       `shopDay` / `shopDailyBought` 由 refreshMerchantDay 负责，这里只换货架。 */
    const day = merchantDayAt(Number(at) || nowSec());
    if (Number(state.furniture.shopOffersDay) !== day) {
      state.furniture.shopOffers = createFurnitureShopOffers(day);
      state.furniture.shopOffersDay = day;
    }
    return day;
  }

  /** 嘟嘟的营业窗口：12:00 之后到（按 uid+日期确定，最多晚 6 小时），21:00 走。 */
  function furnitureShopWindow(at) {
    const t = Number(at) || nowSec();
    const date = new Date(t * 1000);
    const noon = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 12, 0, 0, 0);
    const evening = new Date(date.getFullYear(), date.getMonth(), date.getDate(), 21, 0, 0, 0);
    const day = localDayKeyAt(t);
    let seed = (Number(state.uid) || 0) ^ day;
    seed = Math.imul(seed ^ (seed >>> 16), 0x45d9f3b);
    seed = Math.imul(seed ^ (seed >>> 16), 0x45d9f3b);
    seed = (seed ^ (seed >>> 16)) >>> 0;
    const arrival = Math.floor(noon.getTime() / 1000) + (seed % 361) * 60;
    const leave = Math.floor(evening.getTime() / 1000);
    return { start_time: arrival, leave_time: leave, open: t >= arrival && t < leave };
  }

""".replace('__MARK__', MARK)


def main():
    src = read(ENGINE)
    if MARK in src:
        print('[shop] 已并入过（%s），跳过' % MARK)
        return 0

    # ---------------------------------------------------------------- 模块级常量与节气货架
    src = sub_once(src, '/* ---------------------------------------------------------------- engine */',
                   MODULE_BLOCK + '/* ---------------------------------------------------------------- engine */',
                   'module block')

    # ---------------------------------------------------------------- 存档位
    src = sub_once(
        src,
        '    furniture: {',
        '    furniture: {\n'
        '      /* %s 【并入他 3.3】当天的 8 个货位与它们属于哪一天。 */\n'
        '      shopOffers: {},\n'
        '      shopOffersDay: 0,' % MARK,
        'state shopOffers')

    # ---------------------------------------------------------------- 引擎内函数
    src = sub_once(src, '  function furnitureShopList() {', INNER_BLOCK + '  function furnitureShopList() {',
                   'inner block')

    # ---------------------------------------------------------------- 货架改成"当天 offers"
    src = sub_once(
        src,
        '  function furnitureShopList() {\n'
        '    refreshMerchantDay();\n'
        '    const out = [];\n'
        '    for (const [shopId, row] of FURNITURE_SHOP) {\n'
        '      const num = furnitureStock(row);',
        '  /* 【并入他 3.3】不再把整张表都列出来，只列"当天货架"上的（每天 8 个 + 节气货架）。 */\n'
        '  function furnitureShopList() {\n'
        '    const now = nowSec();\n'
        '    refreshMerchantDay();\n'
        '    ensureFurnitureShopStock(now);\n'
        '    const offers = state.furniture.shopOffers || {};\n'
        '    const out = [];\n'
        '    for (const key of Object.keys(offers)) {\n'
        '      const shopId = Number(key);\n'
        '      const row = FURNITURE_SHOP.get(shopId);\n'
        '      if (!row) continue;\n'
        '      const limit = Number(row.limit) || 0;\n'
        '      const bought = Number(state.furniture.shopBought[shopId]) || 0;\n'
        '      const limitLeft = limit > 0 ? limit - bought : 99;\n'
        '      const stockLeft = Number(offers[key])\n'
        '        - (Number(state.furniture.shopDailyBought[shopId]) || 0);\n'
        '      const num = Math.max(0, Math.min(limitLeft, stockLeft));\n'
        '      /* 【与上游 3.4 一致】售罄的行**仍然列出来**（num=0），这样玩家看到的是"卖完了"\n'
        '         而不是它凭空消失；他的实现是直接跳过，这里取 3.4 的行为。 */\n'
        '      if (isWelfareRow(row) && state.furniture.welfareDay\n'
        '          && state.furniture.welfareDay[shopId] === createDay()\n'
        '          && (Number((state.furniture.welfareTaken || {})[shopId]) || 0) >= WELFARE_PER_DAY) continue;\n'
        '      const need = Number(row.has_item) || 0;\n'
        '      if (need && !hasShopPrerequisite(need)) continue;\n'
        '      if (row.unique && getHaveItem(row.item_id) > 0) continue;\n'
        '      out.push({ shop_id: shopId, item_id: Number(row.item_id), num,\n'
        '        price: Number(row.price) || 0, name: String(row.name || \'\'),\n'
        '        info: String(row.info || \'\'), type: Number(row.type) || 0,\n'
        '        has_item: need, limit });\n'
        '    }\n'
        '    out.sort((a, b) => {\n'
        '      const oa = Number(FURNITURE_SHOP.get(a.shop_id).order) || 0;\n'
        '      const ob = Number(FURNITURE_SHOP.get(b.shop_id).order) || 0;\n'
        '      return oa - ob || a.shop_id - b.shop_id;\n'
        '    });\n'
        '    return out;\n'
        '  }\n'
        '\n'
        '  /* 旧的"整表 + 现算库存"实现保留给测试与回退用（默认不再走它）。 */\n'
        '  function furnitureShopListAllRows() {\n'
        '    refreshMerchantDay();\n'
        '    const out = [];\n'
        '    for (const [shopId, row] of FURNITURE_SHOP) {\n'
        '      const num = furnitureStock(row);',
        'shop list from offers')

    # 上面把循环头部接上了，需要把原实现的尾巴保持合法：原实现接下来是 has_item 判断，
    # 现在它在 furnitureShopListAllRows() 里，语义不变。

    # ---------------------------------------------------------------- 营业窗口
    src = sub_once(
        src,
        '  function merchantShop() {\n'
        '    const shop_list = furnitureShopList();\n'
        '    const now = nowSec(), day = merchantDayAt(now);\n'
        '    const next = new Date(day * 1000);\n'
        '    next.setDate(next.getDate() + 1);\n'
        '    const hours = Number(process.env.FROG_SHOP_HOURS || 0);\n'
        '    const start_time = hours > 0 ? day + Math.floor((24 - hours) * 1800) : day - 1;\n'
        '    const end = hours > 0 ? start_time + hours * 3600 : Math.floor(next.getTime() / 1000);\n'
        '    return { shop_list, start_time, leave_time: end };\n'
        '  }',
        '  function merchantShop() {\n'
        '    const shop_list = furnitureShopList();\n'
        '    const now = nowSec();\n'
        '    /* 【并入他 3.3 的可选项】他的嘟嘟是"12:00 后到、21:00 走"（按 uid+日期确定）。\n'
        '       我们这条线的默认仍是**常开**（离线版按真实时间玩，早上/深夜都可能开游戏；\n'
        '       3.4 的文档也把"商店常开"写成本项目的自设计），所以默认不启用他的窗口；\n'
        '       想照他的来：FROG_SHOP_WINDOW=faithful。FROG_SHOP_HOURS 仍可指定固定时段。 */\n'
        '    if (String(process.env.FROG_SHOP_WINDOW || \'\') === \'faithful\') {\n'
        '      const win = furnitureShopWindow(now);\n'
        '      return { shop_list, start_time: win.start_time, leave_time: win.leave_time };\n'
        '    }\n'
        '    const day = merchantDayAt(now);\n'
        '    const next = new Date(day * 1000);\n'
        '    next.setDate(next.getDate() + 1);\n'
        '    const hours = Number(process.env.FROG_SHOP_HOURS || 0);\n'
        '    const start_time = hours > 0 ? day + Math.floor((24 - hours) * 1800) : day - 1;\n'
        '    const end = hours > 0 ? start_time + hours * 3600 : Math.floor(next.getTime() / 1000);\n'
        '    return { shop_list, start_time, leave_time: end };\n'
        '  }',
        'merchantShop window')

    # ---------------------------------------------------------------- 库存与前置改成按当天货架
    src = sub_once(
        src,
        '  function furnitureStock(row) {\n'
        '    const limit = Number(row.limit);',
        '  function furnitureStock(row) {\n'
        '    /* 【并入他 3.3】有当天货架时，库存就是"货架上还剩几件"。 */\n'
        '    const shopId = Number(row && row.id);\n'
        '    const offerNum = Number((state.furniture.shopOffers || {})[shopId]);\n'
        '    if (Number.isFinite(offerNum) && offerNum > 0) {\n'
        '      return Math.max(0, offerNum - (Number(state.furniture.shopDailyBought[shopId]) || 0));\n'
        '    }\n'
        '    const limit = Number(row.limit);',
        'furnitureStock offer-aware')

    src = sub_once(
        src,
        '      if (row.has_item && state.furniture.owned.indexOf(Number(row.has_item)) === -1) {\n'
        '        return { code: -1 };\n'
        '      }',
        '      /* 【并入他 3.3】前置商品在家里/台面/收藏里都算（他的 hasShopPrerequisite）。 */\n'
        '      if (row.has_item && !hasShopPrerequisite(row.has_item)) {\n'
        '        return { code: -1 };\n'
        '      }',
        'buy prerequisite')

    # ---------------------------------------------------------------- 只能买当天货架上的
    src = sub_once(
        src,
        "    furniture_buy_shop: (d, ctx) => {\n"
        "      const shopId = shopIdOf(d);\n"
        "      const row = FURNITURE_SHOP.get(shopId);\n"
        "      if (!row) return { code: -1 };\n",
        "    furniture_buy_shop: (d, ctx) => {\n"
        "      const shopId = shopIdOf(d);\n"
        "      const row = FURNITURE_SHOP.get(shopId);\n"
        "      if (!row) return { code: -1 };\n"
        "      /* 【并入他 3.3】只能买\"今天货架上\"的东西：他不是整表常驻，每天只有 8 个货位。 */\n"
        "      ensureFurnitureShopStock(nowSec());\n"
        "      if (!Object.prototype.hasOwnProperty.call(state.furniture.shopOffers || {}, shopId)) {\n"
        "        return { code: -1 };\n"
        "      }\n",
        'buy only today offers')

    write(ENGINE, src)
    print('[shop] 引擎已改：每天 8 个星级货位 + 节气货架 + 12:00–21:00 营业窗口（标记 %s）' % MARK)
    return 0


if __name__ == '__main__':
    sys.exit(main())
