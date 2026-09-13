# 道具 / 商店购买 / 抽奖 / 兑换 —— 字段级实现规格

> 适用对象：`work/run/engine/index.js`
> 唯一判定准绳：`work/base/assets/game/js/main.min.js`（下称 **client**，所有偏移均为
> **字符偏移**，与 `work/tools/occur.py`、`where_literal.py` 一致；用 `work/tools/dump_chars.py` 复核）
> 数据表来源：`work/run/web/resource/China/eab/config.eab`（经客户端自己的 XXTEA 解码器解出）
>
> 本文档**只做规格**，不含引擎改动。每条结论后括注依据（客户端函数名 / 偏移）。

---

## 0. 结论速览（最重要的 6 条）

1. **商店价格表一直在客户端本地**，不在服务端下发：`ShopDataDB = new IdGetter("shopData", RES.getRes("shopData_json"))`
   （client@406685，DataManager 构造函数）。价格 `price`、限购 `limit`、`order`、`is_hide_before`/`before_buy`
   全部来自 `shopData.json`。**`item_buy` 只需要回包 + 推送，价格不用下发。**
   该文件位于 `config.eab::shopData_json`（64 条），已解出到 `work/spec/data/shopData.json`。
2. **客户端的"家/背包/桌子"库存 100% 由服务端驱动**：`ItemModel.prototype.addHouseItem` 是**空函数**
   （client@137164，全局仅此一处定义）：
   `t.prototype.addHouseItem=function(e,t,i){void 0===i&&(i=!0)}`。
   真正改库存的只有 `doAddHouseItem`(@137225) / `doConsumeHouseItem`(@138569)，
   而它们**只被 `item_load_items`(@143330) 和 `item_update`(@141518) 调用**。
   → **购买 / 抽奖领取之后必须由服务端推 `item_update`，否则物品永远不出现。**
3. 同理 `UserModel.addClover`(@213035) / `addTicket`(@213616) 也是空函数。
   三叶草/抽奖券的**显示值只能靠 `clover_update` / `item_update_ticket` 推送改变**。
   客户端自己的 `consumeClover(price)` 只是**余额检查**（`return this.clover>=e`，@213242），不扣钱。
4. `item_load_shop_info.purchased[].item_id` 里装的其实是 **shopData 的 `id`（商店条目 id）**，不是道具 id
   （client@140663 handler 内 `this.purchasedMap[o.item_id]=o.count`
   + @136692 `getShopItemBuynums(e){...this.purchasedMap[e]||0}` 被 `isShopItemBuyLimit`(@136828) 调用）。
   **这是最容易写错的一处命名陷阱。**
5. 抽奖：`item_gacha` 回包 `{ticket:<prizeRank>}`（client 处理器 @144215 `this.gachaColorBall=e.ticket`），
   rank 见 §3.4。之后客户端发 `item_redeem_prize{prize_id}`（fire-and-forget），**服务端要发奖 + 推 `item_update`**，
   并把 `gacha.color_ball` 复位为 `-1`。奖池来源是本地表 `Prize.json`（23 条，rank 0..5），
   权重可以从 `Tabikaeru.Define.PrizeBalls` 原样抄（client@420578）。
6. **`item_use_gift_code` 成功码是 `200`，不是 `0`**（client@544284 `if(200==e.code)`）。
   回 `{code:0}` 会被客户端当成"礼包码无效"。

---

## 1. 数据表在哪、怎么拿

### 1.1 权威表 = `config.eab`（加密 EAB）

运行时的资源组 `config` 指向 `config_eab`，即 `work/run/web/resource/China/eab/config.eab`：

```
work/run/web/resource/China/default.res.json:
  {"url": "config_eab", "type": "eab_asset", "name": "shopData_json"}
  {"url": "config_eab", "type": "eab_asset", "name": "Prize_json"}
  {"url": "config_eab", "type": "eab_asset", "name": "Item_json"}
  groups["config"] = "...Prize_json,Shop_json,Specialty_json,Item_json,shopData_json..."
```

`config.eab` 是 **`\x1b\n` 变体**（magic `89 45 41 42 0D 0A 1B 0A`），整包被 XXTEA 加密；
密钥是 `Utils.simpleEncrypt("r]|lnf\x80X\x81U\x82aq_r", 13)`（client@231736）。

- 解码实现：client 自带的 `var eab;!function(e){...}`（client@231428..~232100）
  + `var xxtea;...`（client@227568..231420）+ `Utils.simpleEncrypt` = `function k(e,t){...}`（client@301862）。
- 已封装脚本：**`work/tools/eab_decode.js`**（把上述三段原样 eval，用客户端自己的算法解码，避免手抄出错）
  ```
  node work/tools/eab_decode.js work/run/web/resource/China/eab/config.eab --list
  node work/tools/eab_decode.js <bundle> <entryName> <outFile>
  ```
- 入口尺寸（用于校验）：`config.eab` 1765824 B，60 条目，解出 raw 1760834 B。

### 1.2 本子系统用到的表（全部来自 `config.eab`）

| eab 条目 | eab 原始路径 | 行数 | 已解出 | 主要消费者 |
|---|---|---|---|---|
| `Item_json` | `config/MainData/Item.json` | 410 | `work/spec/data/item.json` | `ItemDB = i("Item")`，client@405959 |
| `shopData_json` | `config/ShopData/shopData.json` | 64 | `work/spec/data/shopData.json` | `ShopDataDB = i("shopData")`，client@406685 |
| `Prize_json` | `config/MainData/Prize.json` | 23 | `work/spec/data/prize.json` | `PrizeDB = n("Prize")`，client@405935 |
| `Collection_json` | `config/MainData/Collection.json` | 62 | `work/spec/data/collection.json` | `CollectDB = i("Collection")`，client@405844 |
| `Specialty_json` | `config/MainData/Specialty.json` | 64 | `work/spec/data/specialty.json` | `SpecialtyDB = n("Specialty")`，client@405875 |
| `GiftData_json` | `config/Gift/GiftData.json` | 3 | `work/spec/data/giftData.json` | **无客户端消费者（见 §4.7）** |
| `Shop_json` | `config/MainData/Shop.json` | 22 | `work/spec/data/shopTable.json` | **无客户端消费者（见 §4.3）** |
| `lotteryData_json` | `config/lottery/lotteryData.json` | dict | `work/spec/data/lotteryData.json` | `lotteryData=t("lotteryData")`，client@407685 |

Dump 命令（复现用）：
```
node work/tools/eab_decode.js work/run/web/resource/China/eab/config.eab Item_json     work/spec/data/item.json
node work/tools/eab_decode.js work/run/web/resource/China/eab/config.eab shopData_json work/spec/data/shopData.json
node work/tools/eab_decode.js work/run/web/resource/China/eab/config.eab Prize_json    work/spec/data/prize.json
node work/tools/eab_decode.js work/run/web/resource/China/eab/config.eab Collection_json work/spec/data/collection.json
node work/tools/eab_decode.js work/run/web/resource/China/eab/config.eab Specialty_json  work/spec/data/specialty.json
```
（`work/spec/data/` 下另有并发会话产出的 `*_json.json` 同名副本，内容一致，可任选。）

### 1.3 `ShopDataDB` 到底吃什么 —— 关键代码

```js
// client@405844...  DataManager 构造函数
function t(e){ return new o(e, RES.getRes(e+"_json")) }            // KeyGetter（按 [] 取值）
function i(e,t){ return void 0===t&&(t="id"), new a(e, RES.getRes(e+"_json"), t) } // IdGetter（按行内 "id" 建字典）
function n(e){ return new s(e, RES.getRes(e+"_json")) }            // ItemGetter（IdGetter 子类，另有 getItem(itemId)）
...
this.CollectDB   = i("Collection"),
this.SpecialtyDB = n("Specialty"),
this.PrizeDB     = n("Prize"),
this.ItemDB      = i("Item"),
...
this.ShopDataDB  = i("shopData"),        // ← 价格表
```
- `IdGetter.prototype.get(k)` = `this.dictSrc[k]`，字典键为行内 `id` 字段（client@405844 之后 `var a=function(){...}`）。
- 因此：**`ShopDataDB.get(shop_id)` 的入参是 `shopData.json` 的 `id`，返回该行。**
- `ItemGetter` 子类额外有 `getItem(itemId)`（线性查找 `n.itemId===e`）——`SpecialtyDB`/`PrizeDB` 用它。

**结论（正面回答任务里的"已知缺口"）**：价格 ↔ item_id 映射的**唯一来源是客户端本地的 `shopData.json`**
（`ShopDataDB`），通过 `itemId` 字段关联 `ItemDB`。服务端**从不下发价格**，`item_load_shop_info` 只回"已购次数"。
引擎若要校验/扣费，必须**自己**把 `shopData.json` 读进服务端（复制到 `work/run/engine/data/` 即可，纯静态表）。

### 1.4 现有 `gamedata.json` 的局限（务必注意）

`work/run/engine/data/gamedata.json` 是早期从运行时探针日志 `[dbd]`/`[dbitemd]` 里抓的**降级快照**，
只有 `{id,type,sub_type}` 和若干 **id 列表**：

- `tables.Shop` = 64 个 id（0..63）→ 与 §1.2 的 `shopData.json` 64 条**对应的是 shopData 不是 Shop.json**；名字有误导。
- `tables.Prize` = 23 个 id（0..22）→ 与 `Prize.json` 条数一致。
- `tables.Item` = 410 个 id → 与 `Item.json` 条数一致（**说明探针快照与 eab 是同一版本**）。
- `items[]` 没有 `name/price/spend/own_num/img/sub_type` → **必须换成解出来的 `item.json`**。

---

## 2. 枚举（全部抄自客户端，逐一标注依据）

### 2.1 `Tabikaeru.DataType.ItemType`（道具大类，`Item.json.type` 的取值域）

client@408520..409034（值字面量块 @408520 起，`e.ItemType||(e.ItemType=` @409013）：

| 值 | 名称 | 含义 / 用途（依据） |
|---|---|---|
| -1 | `NONE` | 无效 |
| 0 | `LunchBox` | 便当/食物 → 物品栏。放入 bag 的第 0 格（`BagItem.LunchBox=0`）才能"锁行李"出发（`Bag.lock`@433653：`-1===this.itemModel.getBagDataList()[Tabikaeru.BagItem.LunchBox]`） |
| 1 | `Amulet` | 护身符 → 物品栏。`sub_type==ItemAmuletType.FLOWER(1)` 时图标要换成花盆里的实时贴图（client@437449 `s.type==ItemType.Amulet&&s.sub_type==ItemAmuletType.FLOWER`） |
| 2 | `Tools` | 道具（消耗品/工具）→ 物品栏。首次购买会弹引导（client@1077177 `checkIsFristTimeBuyTool`，由 ShopView.buy 的关窗回调调用） |
| 3 | `Specialty` | 特产 → 物品栏；同时进图鉴 `specialtysList`（client@137280 附近 `n.type==ItemType.Specialty&&-1==this.specialtysList.indexOf(n.id)`） |
| 5 | `Gift` | 礼包 / 合成秘方（4、6 **未使用**） |
| 7 | `HandCraftTool` | 手工工具 → 工具栏 |
| 8 | `HandCraftStuff` | 手工材料 → 工具栏 |
| 9 | `Other` | 其它（相册扩容／动态相框／照片存储开启物 都在这里） |
| 10 | `FURNITURE_RESOURCE` | 家具材料 |
| 11 | `FURNITURE_ITEM` | 家具半成品 |
| 12 | `FURNITURE_TOOL` | 家具工具 |
| 13 | `FURNITURE_PAPER` | 家具图纸 |
| 14 | `RESOURCE` | **不占格子的"数值/货币"载体**，靠 `sub_type` 决定语义，见 §2.2。`doAddHouseItem`(@137225) 遇到它**直接转成货币，不进库存** |
| 15 | `Courtyard` | 庭院 |
| 16 | `COMPOSE` | 合成图纸（`ComposeId:5502`） |

`work/spec/data/item.json` 中按 type 计数：
`0:91, 14:83, 3:64, 1:55, 13:30, 15:17, 12:15, 2:12, 5:12, 11:11, 10:7, 8:5, 16:3, 9:3, 7:2`
（无 4、6，与枚举一致。）

`Tabikaeru.Define.ItemPutDesc`（client@421100）给出分类中文名，可做 GM 指令提示：
`LunchBox=物品栏-食物, Amulet=物品栏-护身符, Tools=物品栏-道具, Specialty=物品栏-特产,
HandCraftTool=工具栏-工具, HandCraftStuff=工具栏-材料, Other=工具栏-其他,
FURNITURE_RESOURCE/FURNITURE_ITEM=工具栏-材料, FURNITURE_TOOL=工具栏-工具,
Courtyard=工具栏-庭院, COMPOSE=工具栏-其他`。

### 2.2 `DataType.ItemResourceType`（`ItemType.RESOURCE(14)` 的 `sub_type`）

client@409147..409280（值字面量 @409147，`e.ItemResourceType||(e.ItemResourceType=` @409265）：`CLOVER=1, TICKET=2, COMPASS=3, WATER=4, CHANGE=5`。

`doAddHouseItem`(@137225) 的分派（**原样抄**）：
```js
if(n.type==Tabikaeru.DataType.ItemType.RESOURCE){
  if(n.sub_type==Tabikaeru.DataType.ItemResourceType.TICKET)  return void this.getModel(UserModel).addTicket(t);   // 抽奖券
  if(n.sub_type==Tabikaeru.DataType.ItemResourceType.COMPASS) return void(this.getModel(MuseumDayModel).data.compass+=t);
  if(n.sub_type==Tabikaeru.DataType.ItemResourceType.CLOVER)  return void this.getModel(UserModel).addClover(t);   // 三叶草
  if(n.sub_type==Tabikaeru.DataType.ItemResourceType.WATER)   return void this.getModel(RechargeModel).data.water++;
  if(n.sub_type==Tabikaeru.DataType.ItemResourceType.CHANGE)  return void this.getModel(RechargeModel).data.change++;
}
```
由于 `addTicket`/`addClover` 是空函数（§0.3），**用 `item_update` 发 RESOURCE 类道具并不能真的改货币显示**；
货币仍须另推 `item_update_ticket` / `clover_update`。

实际存在的 RESOURCE 道具（`work/spec/data/item.json`，83 条）关键 id：
| item_id | sub_type | name |
|---|---|---|
| 200000 | 1 CLOVER | 三叶草 |
| 200001 | 2 TICKET | 兑奖券 |
| 200002 | 3 COMPASS | 罗盘 |
| 200003 | 4 WATER | 浇水 |
| 200004 | 5 CHANGE | 换货 |
| 200005 | 7 | 扭蛋币 |
| 200006 | 9 | 奶油 |
| 200007 | 10 | 翻糖 |
| 200008..200016 | 6 | 新春贴纸袋 / 宝箱 / 周边 / 广告替代品 / 许愿池开启 … |
| 201001.. | 6 | 家具/庭院装饰类礼包 |

### 2.3 其它相关枚举

| 枚举 | 定义（偏移） | 值 |
|---|---|---|
| `DataType.ItemAmuletType` | @409061（枚举体 @409087） | `FLOWER=1` |
| `DataType.DropType` | @409400 附近（枚举体 @409529） | `NONE=-1, ITEM=1, PICTURE=2, NOTE=3, BOX=4, RESOURCE=5, CARDTAGS=100, SPRINGCARDTAGS=101` |
| `DataType.ItemID` | @417045（枚举体 @417223） | `DRAWING_BOOK=7001, WATAR=7002, FERTILIZER=7003, CLOVER=200000, TICKET=200001, COMPASS=200002` |
| `DataType.Gift` | @417287 | `NONE=-1, Clover=0, FourClover=1, Ticket=2, MAX=3` |
| `DataType.BagItem`（bag 4 格语义） | @417560 附近 | `NONE=-1, LunchBox=0, Amulet=1, Tool_1=2, Tool_2=3, MAX=4` |
| `DataType.DeskItem`（desk 8 格语义） | @417626 起（枚举体 @417854） | `NONE=-1, LunchBox_1=0, LunchBox_2=1, Amulet_1=2, Amulet_2=3, Tool_1=4, Tool_2=5, Tool_3=6, Tool_4=7, MAX=8` |
| `Prize.Rank` | @413348..@413430 | `NONE=-1, White=0, Blue=1, Purple=2, Green=3, Red=4, Gold=5, FURNITURE=6, RankMax=7` |
| `LotteryState` | @417902 | `Open=0, Select=1, Complete=2, Reward=3` |
| `Collection.Rare` | @411115 | `NONE=-1, C=0, B=1, A=2, S=3` |
| `Collection.ShowType` | @411250 | `NONE=-1, Collect=0, Specialty=1` |
| `Item.Type`（另一套，仅 0..3） | @411407 | `NONE=-1, LunchBox=0, Amulet=1, Tool=2, Specialty=3, _ElmMax=4` |

### 2.4 全局常量（`Tabikaeru.Define`，client@418000..423600）——抽奖/商店规则就藏在这

```
RAFFEL_NEEDTICKETS: 5,          // @419653  每次抽奖消耗 5 张券
SHOP_TICKET_PER: 15,            // @420150  商店购买赠券概率 15%（见 §6.8，本 build 中仅此处出现，属"服务端规则残留"）
PRIZE_WHITE_ID: 0,              // @420561  rank=White 对应的 prize.id 固定为 0
PrizeBalls: { White:40, Blue:25, Purple:22, Green:9, Red:3, Gold:1, RankMax:100 },   // @420578
PrizeBallName: { White:"白玉", Blue:"青玉", Purple:"紫玉", Green:"绿玉", Red:"红玉", Gold:"黄玉" },  // @420756
PrizeClover:  { White:10, Blue:30, Purple:50, Green:100, Red:350, Gold:1000 },       // @420926
ItemPutDesc:  { LunchBox/Amulet/Tools/Specialty/HandCraftTool/... -> 分类名 },        // @421100
BAGITEMS: 4, DESKITEMS: 8,
HaveItemMax: 99, COLLECT_MAX: 100, SPECIALTY_MAX: 100, COLLECT_PER:[15,30,50,100], SPECIALTY_PER: 60,
ItemIDBorder: 10000, CollectionIDBorder: 30000, FourLeafCloverID: 1000, TicketMax: 999,
TutorialShopID: 0, TutorialBuyItemID: 0, ComposeId: 5502,
```
`PrizeBalls` / `PrizeClover` 在客户端**各只出现一次**（只在定义处，`occur.py PrizeBalls` = 1 hit），
即它们是**原服务端的权重/价值表，客户端只留了常量**——可直接照抄进引擎，属于高置信依据而非猜测。
`PrizeBallName` 有 2 处（定义 @420756 + 抽奖结果文案 @977293 附近 `resultLabel.text="获得了"+PrizeBallName[rank]`）。

---

## 3. 表结构详解

### 3.1 `Item.json` → `ItemDB`（按 `id` 索引）· 410 行

字段并集：`id, type, sub_type, name, info, img{src,index}, price, spend, own_num, effects[]`

样例（`work/spec/data/item.json` 第 0 行）：
```json
{ "AchieveName": "", "id": 0, "type": 0,
  "img": {"src":"Icon/goods","index":"goods_4"},
  "info": "……", "name": "奶油华夫饼", "own_num": "", "price": 10, "spend": 1,
  "effects": [ {"effect":"HP","effectType":"H_MAXTIME","effectValue":6},
               {"effect":"ITEM_PERCENT","effectType":"I_CLOVER","effectValue":10},
               {"effect":"ITEM_PERCENT","effectType":"I_CLOVER_RND","effectValue":20},
               {"effect":"ITEM_PERCENT","effectType":"I_TICKET","effectValue":1},
               {"effect":"FRIENDSHIP","effectType":"F_NONE","effectValue":2} ] }
```

- `type` = §2.1；`sub_type` 见 §2.2 / §2.3。
- **`price` 是"参考价"，商店真正收费以 `shopData.price` 为准**（`buyItem` @439380 用 `ShopDataDB.get(shopId).price`）。
  `Item.price` 与 `shopData.price` 在本 build 中一致，但以 shopData 为准。
- **`spend` 语义**（由 `isShopItemBuyLimit` @136828 反推）：
  - `spend == 1` → **消耗品**，可重复购买，不用 `own_num` 限购；
  - `spend != 1`（本表里是 `0`）→ **永久/唯一持有**，此时若 `own_num > 0`，还额外用 `getHaveItem(id) >= own_num` 限购。
  - 实测：`1001 玉佩 spend=0`、`2000..2011 工具 spend=0`、`7000/7001 spend=0`、`9000/9001 spend=0`、
    `10201..10205 家具工具 spend=0`；其余消耗品 `spend=1`。`own_num` 多为 `""`（字符串），仅 `7000/7001` 为 `1`。
- `effects[]` 是**旅行数值**（`H_MAXTIME/H_UP/WAY_SPEED/COST_STEP/AREA_STEP/I_CLOVER/I_CLOVER_RND/I_TICKET/FRIENDSHIP`…），
  目前引擎的旅行结算没有消费它。**当前不实现也不影响道具/商店/抽奖链路。**

### 3.2 `shopData.json` → `ShopDataDB`（按 `id` 索引）· **64 行** ← 价格表本体

字段：`id, itemId, name, info, price, limit, order, is_hide_before, is_sold_out_hide, before_buy[]`

| shop id | itemId | item.type | name | price | limit | order | is_hide_before | before_buy | is_sold_out_hide |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 0 | 0 | 奶油华夫饼 | 10 | 0 | 0 | 0 | [] | 0 |
| 1 | 1 | 0 | 草莓可丽饼 | 30 | 0 | 1 | 0 | [] | 0 |
| 2 | 2 | 0 | 沙拉皮塔饼 | 50 | 0 | 2 | 0 | [] | 0 |
| 3 | 3 | 0 | 茄汁蛋包饭 | 80 | 0 | 3 | 0 | [] | 0 |
| 4 | 19 | 0 | 饺子 | 90 | 0 | 4 | 0 | [] | 0 |
| 5 | 4 | 0 | 香葱烤包子 | 100 | 0 | 5 | 0 | [] | 0 |
| 6 | 5 | 0 | 海苔煎豆腐 | 100 | 0 | 6 | 0 | [] | 0 |
| 7 | 15 | 0 | 桂花蒸米糕 | 100 | 0 | 7 | 0 | [] | 0 |
| 8 | 16 | 0 | 彩椒烙蛋饼 | 100 | 0 | 8 | 0 | [] | 0 |
| 9 | 1001 | 1 | 玉佩 | 3000 | 1 | 10 | 0 | [] | 0 |
| 10 | 2009 | 2 | 围巾~纯色~ | 150 | 1 | 11 | 0 | [] | 0 |
| 11 | 2010 | 2 | 围巾~雪花~ | 250 | 1 | 12 | 0 | [] | 0 |
| 12 | 2011 | 2 | 围巾~云纹~ | 400 | 1 | 13 | 0 | [] | 0 |
| 13 | 2000 | 2 | 竹筒 | 300 | 1 | 14 | 0 | [] | 0 |
| 14 | 2001 | 2 | 葫芦 | 450 | 1 | 15 | 0 | [] | 0 |
| 15 | 2002 | 2 | 水壶 | 750 | 1 | 16 | 0 | [] | 0 |
| 16 | 2003 | 2 | 朴素纸伞 | 450 | 1 | 17 | 0 | [] | 0 |
| 17 | 2004 | 2 | 自然纸伞 | 700 | 1 | 18 | 0 | [] | 0 |
| 18 | 2005 | 2 | 水墨纸伞 | 1200 | 1 | 19 | 0 | [] | 0 |
| 19 | 2006 | 2 | 简易睡垫 | 600 | 1 | 20 | 0 | [] | 0 |
| 20 | 2007 | 2 | 时尚睡垫 | 900 | 1 | 21 | 0 | [] | 0 |
| 21 | 2008 | 2 | 高级睡垫 | 1500 | 1 | 22 | 0 | [] | 0 |
| 22 | 9000 | 9 | 相册扩容·1 | 1000 | 1 | 23 | 0 | [] | 1 |
| 23..26 | 9000 | 9 | 相册扩容·2..5 | 1250/1500/2000/3000 | 1 | 24..27 | 1 | `["shop","N-1"]` | 1 |
| 27 | 7000 | 7 | 手工品制作工具 | 2000 | 1 | 100 | 0 | [] | 0 |
| 28 | 8000 | 8 | 手工品材料 | 150 | 0 | 101 | 1 | `["shop","27"]` | 0 |
| 29..33 | 9000 | 9 | 相册扩容·6..10 | 2000/1500/1250/1000/1250 | 1 | 28..32 | 1 | 链式 | 1 |
| 34 | 33 | 0 | 水果沙拉 | 100 | 0 | 9 | 0 | [] | 0 |
| 35 | 7001 | 7 | 友情绘本 | 1000 | 1 | 102 | 0 | [] | 0 |
| 36..55 | 9000 | 9 | 相册扩容·11..30 | 1500/2000/3000/… | 1 | 33..52 | 1 | 链式 | 1 |
| 56 | 9001 | 9 | 动态相框·1 | 3000 | 1 | 201 | 0 | [] | 1 |
| 57 | 9002 | 9 | 照片存储开启物 | 500 | 0 | 200 | 0 | [] | 0 |
| 58 | 9001 | 9 | 动态相框·2 | 3000 | 1 | 202 | 1 | `["shop","56"]` | 0 |
| 59..63 | 9000 | 9 | 相册扩容·31..35 | 1500/1250/1000/1250/1500 | 1 | 53..57 | 1 | 链式 | 1（63 为 0） |

完整表在 `work/spec/data/shopData.json`，可读版在 `work/spec/_shop_table.txt`。

**重要**：`work/cdn/v1021/resource/China/config/ShopData/shopData.json` 是**另一个（旧）build** 的副本，
只有 34 条、名字写成"相册扩容Ⅰ"。**运行时用的是 `config.eab` 里那 64 条**，请勿混用。

字段语义（全部有客户端消费点）：
- `price`：`buyItem`(@439380) 校验与扣费基准（`a.getClover()-s.price<0`、`a.consumeClover(s.price)`）。
  另 ShopView 在点击选择商品时也会二次校验（client@1073270：`if(i.price>r){ ...弹"三叶草不足"... }`）。
- `limit`：`isShopItemBuyLimit`(@136828) 的限购上限，`limit<=0` 表示不限购。
- `itemId`：给玩家的 `Item.json` id（`buyItem(shopId, itemId, cb)` 由 `ShopView.selectItem`(@1072696)
  的回调传入：`t.buy(i.id,i.itemId,i.name)`，@1073351）。
- `order`：仅 UI 排序（client `ShopView.getAllItem`@1077683：`sort(... e.order-t.order || e.id-t.id)`）。
- `is_sold_out_hide`：售罄后是否隐藏（同 @1077683：`a ? r.is_sold_out_hide&&(s=!0) : ...`）。
- `is_hide_before` + `before_buy: ["shop"|"item", "<id>"]`：前置解锁条件，见 `checkShopItemHideBefore`：
  ```js
  // client@1078631
  t.prototype.checkShopItemHideBefore=function(e){
    if(e.before_buy){ var t=e.before_buy[0], i=Number(e.before_buy[1]);
      switch(t){ case"shop": return this.getModel(ItemModel).getShopItemBuynums(i)>0;
                 case"item": return this.getModel(ItemModel).checkHaveItem(i) } }
    return!0 }
  ```
  → `["shop","N"]` 表示"买过 shop N"；`["item","N"]` 表示"拥有 item N"。
- `name` / `info`：UI 文本（`info` 被空格切成 3 段塞进 info1/2/3，`ShopView.updateInfo`@1077485）。

**服务端要做的事**：`item_buy` 时按 `shopData` 查 `price`/`limit`/`itemId`，而不是信任客户端传来的 itemId。

### 3.3 `Shop.json`（`Shop_json`）· 22 行 —— **本 build 中无消费者**

字段：`id, itemId, info, fixPos_Y`。

依据：`work/tools/find_table.py Shop` 在 main.min.js 中**找不到任何 `"Shop"` 字面量**
（`Res.getRes("Shop_json")` / `i("Shop")` / `n("Shop")` 均不存在）；DataManager 只加载 `shopData`。
→ **`Shop_json` 是废弃表**（可能是老版本的货架布局表，`fixPos_Y` 明显是 UI 坐标）。**推测**：原服务端曾用它，
但当前客户端完全不读。引擎**不需要**它。

### 3.4 `Prize.json` → `PrizeDB`（`ItemGetter`，键 `id`，另有 `getItem(itemId)`）· 23 行

```json
[ {"id":0,"itemId":-1,"rank":0,"stock":1}, {"id":1,"itemId":1002,"rank":1,"stock":1}, ... ]
```

| prize.id | rank | itemId | 道具 | item.type |
|---|---|---|---|---|
| 0 | 0 White | **-1** | （无道具，纯发券） | — |
| 1..5 | 1 Blue | 1002..1006 | 绿/白/红/蓝/桃色铃铛 | 1 Amulet |
| 6..9 | 2 Purple | 1013..1016 | 绿/黄/红/蓝色帆船 | 1 Amulet |
| 10..14 | 3 Green | 6,7,8,10,9 | 椒盐/芥末/蜂蜜/五香/原味花生 | 0 LunchBox |
| 15..18 | 4 Red | 11,12,13,14 | 菠萝/草莓/甜椒/苹果汁 | 0 LunchBox |
| 19..22 | 5 Gold | 1007..1010 | 绿/白/红/蓝色千纸鹤 | 1 Amulet |

- `stock` 全是 `1`（`PrizeSelector` 用 `t.stock` 当数量，client@982120 `addHouseItem(t.itemId,t.stock)`；
  White 分支用 `addTicket(i[o].stock)`，client@976028）。
- `Prize.Rank.FURNITURE=6` **在 Prize.json 中没有对应行** → **引擎不要产出 rank 6**，否则
  `showResult` 的 `default` 分支会拿到空数组，`PrizeSelector` 会开出空列表（client@976079：`default:for(a=[],o=0;o<i.length;o++)i[o].rank==t&&a.push(i[o])`）。
- `PRIZE_WHITE_ID=0`（client@420561）：`Prize.Rank.White` 固定映射到 `prize.id=0`，
  所以"抽到白玉"= `item_gacha` 回 `{ticket:0}` + 客户端自动发 `item_redeem_prize{prize_id:0}` + 发券。

### 3.5 `Collection.json` → `CollectDB`（按 `id` 索引）· 62 行 —— 图鉴"收集品"

字段：`id, name, info, info2, place, type, img{src,index}`。
`type` 分布：`{1:35, 2:7, 3:20}`；样例 `id 0 = 牡丹花台 (place 云南地区, type 1)`。

- 消费点：`Tabikaeru.Game.prototype.collectionList` getter（`Object.defineProperty(t.prototype,"collectionList",` @440499）：
  ```js
  for (o=0; o<i.CollectDB.count(); o++){ t=i.CollectDB.index(o);
    n.indexOf(t.id)>=0 ? r.push({cfg:t,count:1}) : r.push({cfg:t,count:0}) }
  return r.sort((a,b)=> b.cfg.type-a.cfg.type || a.cfg.id-b.cfg.id)
  ```
  其中 `n = itemModel.getCollectionsList()` = `item_load_handbook.collections`。
- **所以 `item_load_handbook.collections` 装的是 `Collection.json` 的 `id`，不是 item id。**
- 客户端**从来不**在运行期往 `collectionsList` 里加东西：它只在 `ItemModel` 构造函数里初始化为 `[]`(@133121)，
  或在 `item_load_handbook`(@143969) 里被**整体赋值**；`occur.py collectionsList` 全文件仅 3 处
  （@133121 / @133750 / @144017），没有 push/Add。
  → **collections 完全由服务端掌握。**
  （对比：`specialtysList`(@133144) 会被 `doAddHouseItem`(@137225) push，见 §3.6。）
- `Collection.json` 的 `type` 是否就是 `Collection.Rare`（0..3）**未确认**：取值范围 1..3 与 `Rare` 的 0..3 不完全对齐，
  客户端只把它当排序键。**推测**：`type` 是稀有度，1=B/2=A/3=S。
- 解锁来源线索：`collection_id` 字符串只出现在 `museumData.json`（博物馆系统的 `collection_id.split(",")`，
  client@921546/@1055340），说明收集品是通过**博物馆**发放的。**属本子系统之外**，引擎暂时留空数组即可。

### 3.6 `Specialty.json` → `SpecialtyDB`（`ItemGetter`，键 `id` + `getItem(itemId)`）· 64 行

字段：`id, itemId, place, initialPoint, likePoint`（样例 `{"id":0,"itemId":3000,"place":"云南地区","initialPoint":8,"likePoint":11}`）。

注意 `work/cdn/v1021/.../Specialty.json` 只有 `id/itemId/place`（旧 build），**eab 里多两个数值字段**。

- 消费点 1 —— 图鉴：`Tabikaeru.Game.prototype.specialtyList` getter
  （`Object.defineProperty(t.prototype,"specialtyList",` @440879）：
  ```js
  var n = this.itemModel.getSpecialtysList();           // item_load_handbook.specialtys
  for (o=0; o<i.SpecialtyDB.count(); o++){ t=i.SpecialtyDB.index(o);
    n.indexOf(t.itemId)>=0 ? r.push(t) : r.push(-1) }
  ```
  → **`item_load_handbook.specialtys` 装的是 `Item.json` 的 id（= `Specialty.json.itemId`，即 3000+ 的特产道具 id）。**
  与 `collections` 不同：这里的 id 是**道具 id**。
- 消费点 2 —— 邻居口味：`Game.getFriendTaste(charId, itemId)` @441600 附近，用 `SpecialtyDB.list()` 找下标，
  再取 `CharaDB` 行里的 `taste[index]`。
- 客户端在**收到特产类 `item_update` 时也会自动**往 `specialtysList` 里塞（`doAddHouseItem`@137225 中，
  `n.type==ItemType.Specialty&&-1==this.specialtysList.indexOf(n.id)` → push + `updateHandbookList` 事件），
  所以推了 `item_update` 之后图鉴会即时更新；但**持久化仍要靠 `item_load_handbook` 在启动时下发**。

### 3.7 `GiftData.json` · 3 条 —— **本 build 中无消费者（推测为服务端用）**

```json
{ "5001": {"id":5001,"item_id":[10201,10202,10203,10204,10205],"item_num":[1,1,1,1,1]},
  "5002": {"id":5002,"item_id":[10001,10002,10003,10004,10005,10006,10007,10101],"item_num":[1,1,1,1,1,1,1,1]},
  "5003": {...} }
```
- `5001` = `Item.json#5001 工具套装`（type 5 Gift, sub_type 1），内容是 5 把"简易"家具工具（10201..10205）；
  `5002` = `5002 材料套装`（type 5, sub_type 1），内容是 7 种家具材料 + 1 种半成品；
  `5003` = `大袋种子`。
- `work/tools/find_table.py GiftData giftData` → **0 命中**。
  → **推测**：原服务端在"购买/使用礼包类道具"时用它把礼包展开成实际道具；客户端只负责显示。
  引擎若实现 `item_buy`/道具使用，可据此把 `5001/5002/5003` 展开（表已解出，`work/spec/data/giftData.json`）。

### 3.8 `lotteryData.json` —— 邻居送礼小游戏（`lottery_*`）的纯展示配置

```json
{ "extra_desc": { "1": {"0":"，对方不太接受这类美食", ... "5":"..."}, ... "4": {...} },
  "select_list": { "1": {"desc":"愁眉苦脸的困困…","desc2":"…","id":1,"name":"困困","pic":"neighbor_emote_0_0"}, ... "4": {...} },
  "settle_desc": { "0":"{0}很感谢你的帮忙，但还是看得出有点可惜", ... "5":"{0}觉得你很不可思议，竟然全是对方喜欢的" } }
```
只被 `LotteryModel.data` 之外的 UI 使用；**与抽奖券/`item_gacha` 无关**（别搞混）。

---

## 4. 状态设计建议（服务端 `state`）

现状（`index.js` `defaultState()`）已有：
```js
items: { house: [], bag: [-1,-1,-1,-1], desk: [-1]*8, bagCompleted: 0, bagConflict: 0, deskConflict: 0 },
gacha: { colorBall: 0 },
specialtys: [],  handbook: { collections: [], specialtys: [] },
```
建议改为（字段名不变以兼容存档，仅补缺）：
```js
items: {
  house: [],            // [{item_id, count}]  家里库存（含材料/工具/其他）
  bag:  [-1,-1,-1,-1],  // 4 格；值 = item_id
  desk: [-1]*8,         // 8 格；值 = item_id
  bagCompleted: 0,      // 对应 item_load_items.bag_completed（行李已锁）
  bagConflict: 0, deskConflict: 0,
},
gacha: { colorBall: -1 },        // ★ 必须是 -1 表示"无待领奖"，0..5 表示待领的 Prize.Rank
shop:  { purchased: {} },        // ★ 新增：shop_id(string) -> 已购次数
handbook: { collections: [], specialtys: [] },   // collections=Collection.id[]；specialtys=Item.id[]
specialtys: [],                  // 礼品盒：{item_id,count}（travel_load_gift 用）
giftCodes: {},                   // ★ 可选：已用礼包码 -> true
lottery: { phase: 0 },           // 保持关闭
```
- `gacha.colorBall` **默认值必须从 `0` 改成 `-1`**：`item_load_items` 里的 `color_ball` 直接
  `this.gachaColorBall = a.color_ball`（client@143330），而 `RaffleView.updateGachaColorBall`(@975178) 用
  `-1 == t` 判断"没有待领奖"；`RaffleController.open`(@971329) 会立刻
  `this.view.updateGachaColorBall(!0)`。当前引擎推 `color_ball: 0` 会被理解成"有一个 White 奖待领"，
  进抽奖界面就会直接弹白玉结果。**（推测为当前实现的 bug，建议顺手修掉。）**
- `shop.purchased` 的键是 **shop id 的字符串**（JS 对象键），与 `purchasedMap` 行为一致
  （client@136692 `this.purchasedMap[e]`，e 来自 `ShopDataDB.get(id)` 的调用方）。

---

## 5. 协议层事实（先看这个再读命令）

### 5.1 `send` 的参数装配（client@336282）

```js
t.prototype.send=function(t,i){ ... for(var n=[],r=2; r<arguments.length; r++) n[r-2]=arguments[r];
  var o=ProtocolList.protocolList[t], a=o[0], s=o[1];
  if(a.length!=n.length) return void e.Log.error("发送的协议："+t+" 参数与定义参数不匹配…");
  var c=t, l=c.indexOf("_"); if(l>=0){ var h=c.split(""); h.splice(l,1,"."), c=h.join("") }
  var u={}; if(s&&(this.sessionID++, u.session=this.sessionID), u.timestamp=..., u.cmd=c,
    a.length>0){ u.data={}; for(p=0;p<a.length;p++) u.data[a[p]]=n[p] }
  s && (i && (u.callbackFun=i), this.activateProtocol[u.session]=u); this._socket.send(JSON.stringify(u)) }
```
- **`send(cmd, callback, ...params)`**：第 3 个起按 `ProtocolList.protocolList[cmd][0]` 的**参数名顺序**填 `data`。
- **只有第一个下划线变点**（`h.splice(l,1,".")`）。→ 引擎的 `toWire()` 是对的。
- `ProtocolList.protocolList[cmd][1]`（`needResponse`）为真时才分配 `session`；否则是 fire-and-forget。

### 5.2 收包分发（`AnalysisProtocol` @337837）

```js
if(e.String.isNullOrEmpty(r.cmd))
  if(null!=r.session){ var o=this.activateProtocol[r.session];
    if(o){ delete this.activateProtocol[r.session];
      var a=o.cmd.replace(".","_"), s=o.callbackFun;
      this.HasEventListener(a)&&this.DispatchEvent(new Event(a,r.data,o.data));
      s && s.apply(r.data, o.data) } }
  else warn("返回协议失败，协议名未定义")
else { var a=r.cmd.replace(".","_");
       this.HasEventListener(a)?this.DispatchEvent(new Event(a,r.data)):warn("…未定义回调函数") }
```
- **带 `session` 的回包**：既触发 `addProtocolCallback` 注册的推送处理器，也调用请求回调。
- **不带 `session`、只带 `cmd` 的推送**：只触发 `addProtocolCallback` 处理器。
- 所以"request/response + push 两用"的命令（`item_buy` / `item_gacha`）**两种形态都要支持**。
- `ProtocolList` 里本子系统相关条目（client@375290，`.txt` 全量见 `work/spec/_protocollist.txt`）：
  ```
  item_load_items:[[],!0],        item_putin_bag:[["pos","item_id"],!0],
  item_takeout_bag:[["pos"],!0],  item_putin_desk:[["pos","item_id"],!0],
  item_takeout_desk:[["pos"],!0], item_load_handbook:[[],!0],
  item_buy:[["shop_id"],!0],      item_gacha:[["is_reward"],!0],
  item_redeem_prize:[["prize_id"],!1], item_set_bag_completed:[["completed"],!1],
  item_use_gift_code:[["gift_code"],!0], item_load_shop_info:[[],!0],
  item_update:[[],!0],            item_update_ticket:[[],!0],
  item_load_select_gift:[[],!0],  item_select_gift:[["index_list"],!0],
  lottery_load:[[],!0], lottery_open:[[],!0], lottery_select:[["list"],!0],
  lottery_confirm_reward:[[],!0],
  ```
- **纯净推送**（`who_sends.py` 命中 0 个 `send(` 调用点）：
  `item_load_items`, `item_load_shop_info`, `item_load_handbook`, `item_load_select_gift`,
  `item_gift_open`, `item_update`, `item_update_ticket`, `lottery_load`。
- **客户端主动发起**（命中 ≥1）：
  `item_buy`(1), `item_gacha`(3), `item_redeem_prize`(2), `item_set_bag_completed`(1),
  `item_use_gift_code`(1), `item_select_gift`(1), `lottery_open/select/confirm_reward`(各 1)。

### 5.3 `ItemModel.initModel()` 注册了哪些推送（client@133437）
```js
this.addProtocolCallback("item_load_items","item_load_handbook","item_gacha","item_buy",
  "item_load_shop_info","item_update","item_update_ticket","clover_update",
  "clover_notice_get","item_gift_open","item_load_select_gift")
```
→ 这 11 条都能以**无 session 推送**方式抵达客户端。

### 5.4 错误码（`errcode_json` = `config/MessageData/errcode.json`，47 条）

`MessageModel.getErrorInfo(code)` @148253 把它读成 `code -> {name,code,ok,desc,tid}` 字典。
本子系统相关：

| code | name | desc |
|---|---|---|
| 0 | `EJ_OK` | 成功 |
| 5 / 6 | `EJ_ILLEGAL_PARAMETER` / `EJ_ILLEGAL_OPERATION` | 参数非法 / 非法操作 |
| 7 | `EJ_DATA_MISMATCH` | 客户端数据与服务端不一致 |
| 41 | `EJ_BAG_FULL` | 空间不足 |
| 42 | `EJ_BAG_ITEM_NOT_ENOUGH` | 物品不足 |
| 61 | `EJ_RESOURCE_NOT_ENOUGH` | 资源不足（**买不起时最贴切的码**） |
| 100 / 101 / 102 | `EJ_GIFT_BOX_ALBUM_TO_BOX_FULL` / `…BOX_TO_ALBUM_FULL` / `…SPECIALTY_FULL` | 礼品盒相册已满 / 相册已满 / 礼品盒特产满 |
| 419 / 10604 / 430 / 10026 / 84 / 85 / 86 / 87 / 88 / 89 | 礼包码系列 | 礼包码不可用 / 已使用 / 奖励类型不存在 / 奖励已领取 / 已兑换过该奖励 / 发奖失败 / 类型不存在 / 使用频率过高 / 无效礼包码 / 活动已结束 |

注意：**`200` 不在 errcode 表里**，它是 `item_use_gift_code` 专属的"成功"哨兵码（见 §6.13）。

---

## 6. 逐命令规格

> 记法：`→回包` 表示 handler 的返回值；`⇢推` 表示需要 `ctx.push` 的主动推送。
> "无 session 推送" = 消息体 `{cmd:"item.update", data:{...}}`，不带 `session`。

### 6.1 `item_load_items`（推送 · boot）

**回包（实际是推送体，字段全必填）**
```js
{
  house: [{item_id:Number, count:Number}, ...],   // 家里库存
  bag:   [item_id|-1, ×4],                        // 长度必须 4
  desk:  [item_id|-1, ×8],                        // 长度必须 8
  bag_completed: 0|1,        // 行李已锁
  bag_conflict: 0|1,         // 与 bag 的冲突标记（客户端只存不用，见 @143330）
  desk_conflict: 0|1,
  gacha: { color_ball: Number }   // ★ -1 = 无待领奖；0..5 = Prize.Rank
}
```
依据（client@143330，`_itemmodel_rest.txt` L17-26）：
```js
prototype.item_load_items=function(e,t){
  this.itemDataAll.Clear(), this.itemDataList.Clear();
  for(var i,n=e.house,r=0,o=n.length; o>r; r++) i=n[r], i&&this.doAddHouseItem(i.item_id,i.count,!1);
  this.bagDataList=e.bag, this.deskDataList=e.desk,
  this.bagLock=e.bag_completed||!1, this.bagConflict=e.bag_conflict||!1, this.deskConflict=e.desk_conflict||!1;
  var a=e.gacha; null!=a ? null!=a.color_ball&&(this.gachaColorBall=a.color_ball)
    : core.Log.warning("返回的协议 client_load_role 中的 gacha 属性不存在，请检查协议参数是否已修改");
  core.ModelManage.getInstance().getModel(HandCraftModel).updateComposeRedot(),
  this.dispatchEvent(new core.Event(ItemEventType.updateAllItemInfo)) }
```
陷阱：
- `house` 若为 `undefined` → `e.house.length` 抛 `Cannot read properties of undefined (reading 'length')`（**无 length 守卫**）。
- `gacha` 缺了只会 warning，`color_ball` 缺了则忽略（有 `null!=` 守卫）。
- `house` 里的 `RESOURCE` 类道具会被折叠成货币、**不进库存**（§2.2），所以引擎不要把 200000/200001 放进 `house`。
- `count=0` 的行会被 `doAddHouseItem(id, 0)` 建成 0 条记录，建议引擎过滤掉 `count<=0`。

**引擎现状**：字段齐全，唯一问题是 `gacha.color_ball` 取了 `state.gacha.colorBall`（默认 0）。**建议默认 -1。**

### 6.2 `item_update`（推送）—— 全系统最重要的一条

**推送体**
```js
{ item: { item_id: Number, count: Number } }
```
依据（client@141518，`_itemmodel_rest.txt` L131-141）：
```js
prototype.item_update=function(e){
  if(e){
    var t=this.getHouseItemCount(e.item.item_id);          // 当前数量
    0==e.item.count ? this.doConsumeHouseItem(e.item.item_id,t)      // count==0 → 清空该道具
                    : this.doAddHouseItem(e.item.item_id, e.item.count-t);  // 否则 count 是"新的绝对数量"
    var i=Tabikaeru.DataManager.instance().ItemDB.get(e.item.item_id);
    if(i.type==Tabikaeru.DataType.ItemType.COMPOSE){ ... } } }
```
- **`count` 是"新的绝对持有量"，不是增量**（`e.item.count - t` 才是 delta）。
- **`count === 0` 是特例：表示"把该道具清零"**（`doConsumeHouseItem(id, t)` 传入当前数量）。
- `doAddHouseItem(item_id, 0)` 是幂等的（`core.Dictionary.Add` 是 upsert，client@349875
  `Add=function(e,t){var i=this._keyList.indexOf(e); -1==i?push:this._valueList.splice(i,1,t)}`）。
- `ItemDB.get(item_id)` **没有 null 守卫**：`i.type` 会抛异常 → **只推真实存在于 `Item.json` 的 id**。
- 一次 `item_update` 只能改一个道具。批量改动要连推多条（或改用 `item_load_items` 全量刷）。
- `item_update` **不会**改 `bag`/`desk` 里的格子；那些只由 `item_putin_bag`/`item_takeout_bag` 等维护。

**必须触发 `item_update`（或 `item_load_items`）的场景**（因为 `addHouseItem` 是空函数，§0.2）：
`item_buy` 成功、`item_redeem_prize`、`travel_gift_to_bag`、`item_select_gift` 领取、`item_gift_open` 开礼包、
以及旅行归来 `travel.load_gift`（现状已用 `specialtys` 独立承载）。

### 6.3 `item_update_ticket`（推送）

**推送体** `{ ticket: Number }`；客户端 `UserModel.setTicket(e.ticket)`（handler @140968）。
`setTicket` 非空实现：`this.ticket=e; dispatchEvent(updateTicket)`（client@213652）。

### 6.4 `item_load_shop_info`（推送 · boot）

**推送体**
```js
{ purchased: [ { item_id: <ShopDataDB.id>, count: Number }, ... ] }
                                     ^^^^^^^^^^^^^^ 是商店条目 id，不是道具 id！
```
依据（client@140663）：
```js
prototype.item_load_shop_info=function(e,t){
  if(e&&e.purchased){
    this.purchasedMap={};
    for(var i=(Tabikaeru.DataManager.instance().ShopDataDB, Array.isArray(e.purchased)?e.purchased:[]), ...){
      var o=r[n]; this.purchasedMap[o.item_id]=o.count }
    console.log(JSON.stringify(this.purchasedMap)) } }
```
- 外层 `if(e&&e.purchased)` → **`purchased` 缺失时整个 handler 什么也不做**（`purchasedMap` 保持 `{}`），不会崩。
- 消费者：`getShopItemBuynums(shopId)`（@136692）与 `isShopItemBuyLimit(shopId)`（@136828）：
  ```js
  isShopItemBuyLimit=function(e){
    var i=ShopDataDB.get(e); if(i.limit>0){
      var n=ItemDB.get(i.itemId);
      return 1!=n.spend&&n.own_num>0
        ? (this.purchasedMap[e]||0)>=i.limit || this.getModel(t).getHaveItem(i.itemId)>=n.own_num
        : (this.purchasedMap[e]||0)>=i.limit }
    return!1 }
  ```
- **不推这条，重启后所有限购道具（玉佩/纸伞/睡垫/相册扩容…）都会重新亮起来。**
- 推送内容应与 `state.shop.purchased` 一致；含 0 次的行可省略（客户端 `||0` 兜底）。

**引擎现状**：`item_load_shop_info: () => ({ purchased: [] })` → 需要改成由 `state.shop.purchased` 生成。

### 6.5 `item_load_handbook`（推送 · boot）

**推送体**
```js
{ collections: [Collection.id, ...],   // Collection.json 的 id
  specialtys:  [Item.id, ...] }        // 特产道具 id（= Specialty.json.itemId）
```
依据（client@143969）：
```js
prototype.item_load_handbook=function(e,t){
  this.collectionsList=Array.isArray(e.collections)?e.collections:[],
  this.specialtysList=Array.isArray(e.specialtys)?e.specialtys:[],
  this.dispatchEvent(new core.Event(ItemEventType.updateHandbookList)) }
```
- 两个字段都有 `Array.isArray` 守卫 → 缺了不崩，只是图鉴全灰。
- 消费点见 §3.5 / §3.6；`collections` 用 `Collection.id`，`specialtys` 用 `Item.id`，**两套 id 空间不同，别混。**
- 引擎现状 `{collections:[], specialtys:[]}` 安全但图鉴全空。要"有内容"就得在发奖/旅行时往
  `state.handbook.specialtys` 追加特产 id（`rollTripRewards()` 已经在发 `SPECIALTY_IDS`，顺手记录即可）。

### 6.6 `item_gift_open`（推送 · 开礼包）

**推送体**
```js
{ items: [ { item_id: Number, count: Number }, ... ] }
```
依据（client@142032 / `_dumps_item.txt` L81-96）：
```js
prototype.item_gift_open=function(e){ if(e&&e.items){
  for(var t=[],i=0,n=e.items;i<n.length;i++){ var r=n[i]; t.push({item_id:r.item_id,count:r.count}) }
  var o=core.PageManage.getInstance().getControl(CapsuleViewControl,core.ViewLayerType.WindowLayer);
  if(o)return void o.view.setGiftItems(t);
  core.PageManage.getInstance().addViewControl(GiftPackageViewController,core.ViewLayerType.NoticeLayer,null,t) } }
```
- 只读 `item_id` / `count`；`items` 缺失则什么都不发生（无守卫问题）。
- `CapsuleViewControl` 在场时改成"胶囊机内部展示"（`setGiftItems` 只存不渲染，client@541579）。
- 这是**展示层推送**，不改变库存；真正的入库仍要配 `item_update`。

### 6.7 `item_load_select_gift`（推送 · 让玩家从一堆礼物里挑 N 个）

**推送体**
```js
{ list: [ { num: Number, items: [ { item_id: Number, count: Number }, ... ] }, ... ] }
```
依据（client@142432 / `_capsule_setgift.txt`）：
```js
prototype.item_load_select_gift=function(e){
  var t=this.selectGiftList;
  this.selectGiftList=Utils.convertArray(e.list);              // convertArray = Array.isArray(e)?e:[]
  t.length<=0 && core.PageManage.getInstance().getControl(MainOutController, core.ViewLayerType.SceneLayer)
    && this.check_select_gift() }
prototype.check_select_gift=function(){
  if(this.selectGiftList.length>0){
    var e=this.selectGiftList[0];
    core.DisplayManage.getInstance().popup(new GiftSelectView(e.num,e.items)) } }
```
- `Utils.convertArray` = `function v(e){return Array.isArray(e)?e:[]}`（client@300344，导出 @308086）
  → `list` 缺失是安全的（空数组）。
- **`list` 是一个队列**：`req_select_gift`(@142860) 里先 `this.selectGiftList.shift()`，处理完再
  `GiftPackageViewController` 的 `onClose` 调 `check_select_gift()`(@142681) 弹下一个。
- 关键点：**只有当 `selectGiftList` 之前为空时才会立刻弹窗**（`t.length<=0`），
  且必须 `MainOutController`（主场景）存在。→ 启动阶段推太早会被忽略，**建议在 `hall.enter_game` 之后
  延迟一次 tick 再推**（或挂在 `travel.load_gift`/某个后续推送之后）。
- `GiftSelectView(num, items)`：`num` = 必须选几个，`items` = 候选（渲染只用 `item_id`/`count`，
  client@648526 `ItemDB.get(this.data.item_id)`）；选中结果以 **1-based 下标** 数组回传
  （client@650091 `this.selectList.push(e.itemIndex+1)`）。

### 6.8 `item_buy`（客户端请求 · 商店购买）

**请求**：`data = { shop_id: Number }`（`ProtocolList.item_buy=[["shop_id"],!0]`；
由 `Game.buyItem(shopId, itemId, cb)` @439380 发出）。

客户端完整链路（client@439380 + @1072696 + @1075424）：
```js
// Tabikaeru.Game.prototype.buyItem(shopId, itemId, cb)
t.prototype.buyItem=function(t,i,n){
  var o=DataManager.instance(), a=getModel(UserModel), s=o.ShopDataDB.get(t);
  return null===s ? !1
    : this.itemModel.isShopItemBuyLimit(t) ? !1
    : a.getClover()-s.price<0 ? !1
    : ( getModel(RoleModel).syncHarvestClover(!1, new core.Action(function(){
          core.SocketManage.getInstance().send("item_buy", new core.Action2(function(e,o){
            e && (r.itemModel.purchasedMap[t]=(r.itemModel.purchasedMap[t]||0)+1,
                  r.itemModel.addHouseItem(i,1),       // ← 空函数！
                  n.apply(e,o)) }), t) })),
        a.consumeClover(s.price),                       // ← 只是检查，不扣
        !0) }
```
```js
// ShopView.buy → 回调
Tabikaeru.Game.instance().buyItem(e,t,new core.Action2(function(e,i){
  if(n.updateShop(), e.is_free){ ...走广告/分享免单... } else r() }))
// r(): 弹 "成功购买了{0}" → 关掉后 hintBuySucceed=!0, showGetTicket()  → 若 item_buy handler 派发过
//      ItemEventType.getTicket 就弹"获得抽奖券"
```

**回包（服务端 → 客户端）**
```js
{
  ticket:   Number,   // 可选，本次购买附赠的抽奖券数；>0 会触发客户端"获得抽奖券"弹窗
  ads_id:   "",       // 可选；非空且是有效广告位 → 客户端走广告奖励流程
  share_id: "",       // 可选；ads_id 无效时回落到分享奖励流程
  is_free:  false     // true → 客户端弹"免单"广告/分享 UI
}
```
字段依据（client@144353 `prototype.item_buy=function(e,t)`，`_dumps_item.txt` L6-11）：
```js
prototype.item_buy=function(e,t){
  if(null!=e.ticket && (this.getModel(UserModel).addTicket(e.ticket),
        e.ticket>0 && this.dispatchEvent(new core.Event(ItemEventType.getTicket))),
     e.ads_id && e.ads_id.length>0){ var i=this.getModel(AdsModel).getAdsPlace(e.ads_id);
       i&&this.getModel(AdsModel).isValidAds(i) || (e.share_id=e.ads_id, e.ads_id="") }
  e.ads_id&&e.ads_id.length>0 ? this.dispatchEvent(new core.Event(ItemEventType.ads_id,e.ads_id))
    : e.share_id&&e.share_id.length>0 && this.dispatchEvent(new core.Event(ItemEventType.share_id,e.share_id)) }
```
- **回包对象必须"真值"**（客户端 `e && (…)`）——`{}` 即可；**但注意**：若回 `undefined`/`null`，
  客户端不会 `purchasedMap++`，界面不会刷新成"已售罄"。
- `ads_id` / `share_id` 都留空字符串最安全（否则会弹广告/分享未实现的 UI）。
- `is_free` 留 `false`/缺省（`undefined` 即 falsy）。
- 当前引擎的 `item_buy: () => ({ code: 0, conflict: 0 })` 是**真值对象**，因此"能买到"，
  但**既没扣三叶草也没给道具**。

**服务端必须做的（依据 §0.2/§0.3/§3.2）**
1. 从 `state.shop.purchased` 与 `shopData[shop_id].limit` 校验限购（`limit<=0` 不限购）；
   超限 → 建议回 `{}` 之类**真值但什么都不给**（客户端没有错误码分支，回真值即"已购"），
   或严格点回 `{code:61}` 也无害（`code` 未被读取）。**推荐：真值空对象 + 不发货。**
2. 校验 `state.clover >= shopData[shop_id].price`；不足 → 同样回真值空对象（不要扣、不要发货）。
3. `state.clover -= price`；`state.shop.purchased[shop_id] = (…||0) + 1`；`save()`。
4. 发货：按 `shopData.itemId` 给道具（`house` 计数 +1）。**若 itemId 属于 `GiftData` 展开礼包
   （5001/5002/5003），可改用 `giftData` 展开成多条**（§3.7，推测）。
5. **推送**：
   - `clover_update` `{clover: state.clover}` ← 必须，否则 UI 三叶草不变（`addClover`/`consumeClover` 都不改数）。
   - `item_update` `{item:{item_id,count}}` ← 必须，否则道具不出现。
   - `item_update_ticket` `{ticket}` ← 若发放了附赠券（见下）。
   - （可选）`item_load_shop_info` `{purchased:[…]}` ← 让其它客户端的限购态一致；本客户端自己会 `purchasedMap++`。
6. 附赠抽奖券：`Define.SHOP_TICKET_PER: 15`（=15%）在客户端**只有定义、无使用点**（`occur.py SHOP_TICKET_PER`=1 hit）
   → **推测**：这是原服务端的"购买赠券概率"。要实现就：
   `if (Math.random()*100 < 15) { state.ticket += 1; reply.ticket = 1; push item_update_ticket }`。
   回包里给 `ticket>0` 才会弹"获得抽奖券"窗口（`ItemEventType.getTicket`）。

### 6.9 `item_gacha`（客户端请求 · 抽奖开奖）

**请求**：`data = { is_reward: Boolean }`
- 普通抽奖：`send("item_gacha", null, !1)` → `{is_reward:false}`（client@974262 `RaffleView.raffle`）。
- "奖励抽奖"模式：`send("item_gacha", null, !0)` → `{is_reward:true}`
  （client@974628 `reward_raffle` / @975023 `nextReward`；`RaffleController.open` 的 `getParam(0)` 决定是否进该模式）。
- 普通模式下客户端已本地检查 `consumeTicket(RAFFEL_NEEDTICKETS=5)`（**同样只是检查**，
  `consumeTicket` 在 client@213774）→ **服务端要自己扣 5 张券**。

**回包**
```js
{ ticket: <Prize.Rank> }        // 0=White 1=Blue 2=Purple 3=Green 4=Red 5=Gold
```
依据（client@144215）：
```js
prototype.item_gacha=function(e,t){
  this.gachaColorBall=e.ticket,
  this.dispatchEvent(new core.Event(ItemEventType.updateGachaColorBall)) }
```
然后 `RaffleView.updateGachaColorBall()`（client@975178）：
```js
var t=this.itemModel.getGachaColorBall();
-1==t ? (this.drawBtn.touchEnabled=!0, return)          // 没有奖 → 按钮恢复
: (e?…:await this.playRaffleAnm(t), await this.showResult(t));
switch(t){
  case Prize.Rank.White:                                 // rank 0
    // 弹 GetTicket 窗 → 关掉后 nextReward()
    for(o=0;o<i.length;o++) if(i[o].rank==t){
      this.itemModel.cleanGachaColorBall();               // 本地把 colorBall 置 -1
      this.userModel.addTicket(i[o].stock);               // 空函数！
      core.SocketManage.getInstance().send("item_redeem_prize",null,i[o].id); break }
    break;
  default:                                                // rank 1..5
    for(a=[],o=0;o<i.length;o++) if(i[o].rank==t) a.push(i[o]);
    s=new PrizeSelector(a,this.isReward);                 // 玩家自己挑一个
    ... }
```
- `i = Tabikaeru.Game.instance().prizelist` = **`PrizeDB` 全部行**（getter @441399）。
- **rank 0（White）自动领**：选 `PrizeDB` 中第一个 `rank==0` 的行（= `prize.id 0`，`itemId -1`），
  发 `item_redeem_prize{prize_id:0}`（send 调用点 @976028），并且 `addTicket(stock)` 是**空函数** →
  **服务端必须自己加券并推 `item_update_ticket`**。
- **rank 1..5 要玩家选**：弹 `PrizeSelector`，选中后（`PrizeSelector.selectItem` @981836）：
  ```js
  e.itemModel.cleanGachaColorBall();                       // 本地 colorBall = -1（cleanGachaColorBall @135398）
  var t=e.list.selectedItem.info;                          // 选中的 Prize 行
  e.itemModel.addHouseItem(t.itemId,t.stock);              // 空函数！
  core.SocketManage.getInstance().send("item_redeem_prize",null,t.id);   // send 调用点 @982120
  var i=new PrizeShare(t.itemId,t.rank,e.isReward); e.parent.addChild(i); e.close()
  ```
  `PrizeSelector` 只列同 rank 的行（`_prizesel2.txt` L16-21，`info` 存整行、`name` 取 `ItemDB.get(itemId).name`）。

**服务端逻辑建议（高置信）**
```js
// PrizeBalls 权重（client@420578，总 100）
const PRIZE_BALLS = { 0:40, 1:25, 2:22, 3:9, 4:3, 5:1 };
// 1) is_reward===false → 校验 state.ticket >= RAFFEL_NEEDTICKETS(5)，扣 5，推 item_update_ticket
// 2) 加权抽 rank；把 state.gacha.colorBall = rank；save()
// 3) reply = { ticket: rank }   （字段名叫 ticket，装的却是 rank —— 别写错）
// 4) 若 colorBall 本来就 != -1（上次没领），客户端不会再发 item_gacha，直接进领奖流程；
//    服务端应把"已有待领奖"视作拒绝再抽（避免券白扣）。
```
**注意**：服务端**不能**在这里就把道具发出去——玩家还要在 `PrizeSelector` 里选、
或者 rank0 走自动流，真正的发奖在 `item_redeem_prize`。

### 6.10 `item_redeem_prize`（客户端通知 · 领取已抽中的奖）

**请求**：`data = { prize_id: Number }`；`needResponse: false` → **不分配 session，服务端不要回包**
（`send(...,null,id)` 第 2 参是 `null` 回调；`ProtocolList.item_redeem_prize=[[\"prize_id\"],!1]`）。

**服务端必须做的**
1. 校验 `state.gacha.colorBall` 与 `PrizeDB.get(prize_id).rank` 相符（防改包）；不符则只清 `colorBall`。
2. 发奖：
   - `Prize.Rank.White(0)`（`prize_id=0`，`itemId=-1`）：`state.ticket += prize.stock(1)`，
     推 `item_update_ticket {ticket}`。
   - 其它：`house[prize.itemId] += prize.stock`，推 `item_update {item:{item_id:prize.itemId, count:<新数量>}}`。
   - 若 `itemId` 为特产（type 3），同时把它并入 `state.handbook.specialtys`（可选，也可留待 `item_load_handbook`）。
3. `state.gacha.colorBall = -1`（客户端已本地 `cleanGachaColorBall()`，服务端必须跟上，否则下次启动又出现"待领奖"）。
   注意：客户端**不会**推任何"我领了"的状态，服务端只能靠这条包来复位。
4. `save()`。**没有回包**（回包也不会被消费）。

### 6.11 `item_select_gift`（客户端请求 · 从候选里选 N 件）

**请求**：`data = { index_list: [1-based 下标, ...] }`
依据（client@142860，`_reqselectgift2.txt`）：
```js
t.prototype.req_select_gift=function(e,t){                  // e = selectList（1-based）
  var i=this;
  this.selectGiftList.shift();                              // 把队首弹掉
  core.SocketManage.getInstance().send("item_select_gift", new core.Action2(function(e){
    if(e.items&&e.items.length>0){
      for(var n=[],r=0,o=e.items;r<o.length;r++){ var a=o[r]; n.push({item_id:a.item_id,count:a.count}) }
      core.PageManage.getInstance().addViewControl(GiftPackageViewController, core.ViewLayerType.NoticeLayer,
        null, { items:n, onClose:function(){ i.check_select_gift() } });   // 展示所得 → 关闭后弹下一个
      t&&t.apply() } }), e) }
```
**回包**
```js
{ items: [ { item_id: Number, count: Number }, ... ] }   // 玩家实际获得的东西，用于"开箱"展示
```
- 回包 `items` 为空/缺失时什么都不弹，但队列已经 `shift()` 掉 → 该次选择**静默作废**。
- **回包只是展示**；入库仍需 `item_update`（`GiftPackageViewController` 不写库存）。
- `index_list` 的元素是**1-based 下标**（`GiftSelectView.onItemTap` 里 `push(e.itemIndex+1)`，
  client@650091），服务端需用 `-1` 还原为 `list[0].items` 的下标。

### 6.12 `item_set_bag_completed`（客户端通知 · 锁定/解锁行李）

**请求**：`data = { completed: Boolean }`；`needResponse: false` → 无回包。
依据（client@140216）：
```js
t.prototype.setBagLock=function(e){
  this.bagLock!=e && (this.bagLock=e, core.SocketManage.getInstance().send("item_set_bag_completed",null,e)) }
```
- 触发点：`Bag.prototype.setImageLock`（client@434343，`lock()` @433653），玩家在行李界面点"锁定"。
  锁定前会检查 `bagDataList[BagItem.LunchBox(0)] !== -1`，否则弹"请准备便当"。
- 服务端：`state.items.bagCompleted = completed ? 1 : 0; save();`。
  之后**任何一次 `item_load_items` 都带 `bag_completed`** 回给客户端（`e.bag_completed||!1`，client@143330）。
- 与旅行出发的联动（`bagLock` 是否解除、是否影响 `frog.status`）**客户端里没有直接证据** → 未确认（§8）。

### 6.13 `item_use_gift_code`（客户端请求 · 兑换礼包码）

**请求**：`data = { gift_code: String }`
**回包**
```js
{ code: 200 }                      // ★ 200 = 成功；其它值 → getErrorInfo(code) 取文案，取不到则"礼包码无效"
{}                                 // 或任何 code != 200 → 失败
```
依据（client@544284，`CdkeyView`）：
```js
core.SocketManage.getInstance().send("item_use_gift_code", new core.Action2(function(e,i){
  t.btn_yes.touchEnabled=!0; var n;
  if(200==e.code) core.PageManage.getInstance().removeControl(CdkeyViewController, t.control.getViewLayerType()),
                  n=_("礼包码兑换成功");
  else { var r=t.getModel(MessageModel).getErrorInfo(e.code); n=r?r.desc:_("礼包码无效") }
  GuideHelpView.getInstance().show(n,null,core.DisplayManage.getInstance().getNoticeLayer()) }), i)
```
- `getErrorInfo`(@148253) 读 `errcode_json`（§5.4）。**推荐失败码**：
  `88 EJ_GIFT_INVALID_TICKET(礼包码无效)`、`10604 EJ_GIFT_ALWAYS_ACTIVED(礼包码已使用)`、
  `84 EJ_GIFT_ACTIVE_CODE_NOT_EXIST(已兑换过该类奖励)`、`89 EJ_GIFT_ACTIVITY_END(该礼包码活动已结束)`。
- **客户端没有 `ticket`/`code` 的大小写兜底**，必须精确 `200`。
- 发奖同样要靠 `item_update` / `item_update_ticket` / `clover_update` 推送。
- 服务端需自己维护"已用过的码"集合（`state.giftCodes`），客户端不做去重。

### 6.14 `item_putin_bag` / `item_takeout_bag` / `item_putin_desk` / `item_takeout_desk`（已有实现，补充校验点）

依据（client@133836 `setBagData` / @134491 `setDeskData`）：
```js
// setBagData(pos, itemId)
send("item_takeout_bag", Action2(function(e){ n.bagConflict=e.conflict; i&&i.apply() }), pos+1)   // pos 是 1-based
send("item_putin_bag",   Action2(...), pos+1, itemId)
```
- **`pos` 是 1-based**（`e+1`，e 为 0-based 数组下标）→ 引擎里 `Number(d.pos)-1` 的换算正确。
  越界时客户端**不会发**（`this.bagDataList.length>e` 守卫），服务端仍需自保。
- 回包 **`conflict` 被直接赋给 `bagConflict`/`deskConflict`**：
  ```js
  var o=new core.Action2(function(e){ n.bagConflict=e.conflict; i&&i.apply() });
  ```
  → **回包对象必须存在且含 `conflict`（0/1）**，否则 `e.conflict` 会抛
  `Cannot read properties of undefined`（当 `e` 为 undefined 时）。现有实现返回 `{code:0, conflict:0}` 是对的。
- `conflict` 的 UI 含义**未在客户端找到消费点**（`bagConflict`/`deskConflict` 只在
  `item_load_items` 赋值、在回调里赋值），**推测**是"该格发生了服务端修正"的提示标记。
  服务端在"请求的格位与自己的记录不一致"时置 1 更贴合原意。

### 6.15 `lottery_*`（邻居送礼小游戏）—— **建议保持关闭**

`LotteryModel`（`var LotteryModel=function` @145271）：
```js
t.data={ last_phase:0, phase:0, state:0, select_list:[], answer:[],
         extra_item:{item_id:0,count:0}, right_flag:[], egg_num:0, reward:[] }
t.prototype.initModel=function(){ this.addProtocolCallback("lottery_load") }
t.prototype.lottery_load=function(e){
  e.phase && ( this.data=e,
    this.data.select_list=Utils.convertArray(this.data.select_list),
    this.data.answer=Utils.convertArray(this.data.answer),
    this.data.right_flag=Utils.convertArray(this.data.right_flag),
    this.data.reward=Utils.convertArray(this.data.reward) ) }
```
- **`lottery_load` 只在 `e.phase` 为真时才生效**（`e.phase && (…)`）。引擎现在的 `() => ({})`
  等于"永远不开启"，**安全且推荐保持**。
- 若要开启，推送体必须是：
  ```js
  { last_phase, phase, state, select_list:[…], answer:[…],
    extra_item:{item_id,count}, right_flag:[…], egg_num, reward:[…] }
  ```
  `answer` / `right_flag` / `reward` 缺了会被 `convertArray` 兜成 `[]`（安全），
  但 `extra_item` 没兜底（`LotteryModel.data.extra_item.item_id` 在多处被直接读，client@776370）。
- 请求/回包：
  ```
  lottery_open            → { open_item:{item_id,count}, extra_item:{item_id,count} }   // 两个字段都要有
  lottery_select(list)    → { code: 0 }        // 客户端只认 code==0
  lottery_confirm_reward  → { code: 0 }        // 同上
  ```
  依据 client@145964 / @146470 / @146700：
  ```js
  send("lottery_open", Action2(function(i){
    i.open_item&&i.extra_item && (… ItemRewardViewControl …, t.data.state=Select, t.data.extra_item=i.extra_item, e&&e.apply()) }))
  send("lottery_select", Action2(function(n){ 0==n.code && (i.data.answer=e, i.data.state=Complete, …) }), e)
  send("lottery_confirm_reward", Action2(function(i){ 0==i.code && (t.data.state=Open, t.data.answer=[], …) }))
  ```
- 小游戏内容表 `lotteryData.json`（§3.8）纯展示，服务端只需在 `lottery_load` 里按它填 `select_list`
  （4 个邻居，`id` 1..4，`name`/`desc`/`pic`），`num` 由 `select_list` 决定（UI 里固定选 5 个，
  client@774509 `selectList.length<5`）。**属可选功能，任务范围外。**

### 6.16 相关但相邻的：`travel_bag_to_gift` / `travel_gift_to_bag`（礼品盒）

- `travel_gift_to_bag(item_id)`（`gift_to_bag` @116236，send 调用点 @116348）：成功后客户端 `addHouseItem(e,1,!0)`
  （**空函数**），只把 `specialityList` 里的条目移除。
  → **服务端必须从 `state.specialtys` 减 1 并推 `item_update`**（以及必要时的 `travel_load_gift` 刷新）。
- `travel_bag_to_gift(item_id)`（`moveItemToGiftBox` @138980，send 调用点 @139163）：成功后客户端只做局部 UI 刷新，
  并把一条 `{item_id:l.id,count:1}` 加进 `GiftBoxModel`（`onMoveItem`）。
  → **服务端要从 `house` 减 1、往 `state.specialtys` 加 1，并推 `item_update`（house 侧）与
  `travel_load_gift`（礼盒侧）**。
- 错误码：`102`（礼品盒特产满）会触发"要更换保存的特产吗"确认框（@139163），
  `101`（相册满）会触发删除照片确认（`gift_to_album` @116931）。
  引擎若实现容量限制，用这两个码。
- 上面的 `state.specialtys` 就是 `travel_load_gift.specialtys`（`[{item_id,count}]`），
  已被 `TravelGiftModel.travel_load_gift` 消费（@118657）：`count>1` 会被客户端拆成多条 count=1。

---

## 7. 端到端时序（三张最关键的图）

### 7.1 商店购买
```
[客户端] 点商品 → ShopView.buy(shopId,itemId,name)
   ├ isShopItemBuyLimit(shopId)?            ← 由 item_load_shop_info.purchased 决定
   ├ shopData[shopId].price > getClover()?  ← 由 clover_update 决定；不足则本地弹"三叶草不足"
   └ send "item_buy" {shop_id}
[服务端] 校验 limit / clover
   ├ state.clover -= price;  state.shop.purchased[shopId]++
   ├ 按 shopData.itemId 发货（可能按 GiftData 展开）
   └ 推: clover_update{clover}  item_update{item:{item_id,count}}
          [可选] item_update_ticket{ticket} + 回包 ticket>0
          [可选] item_load_shop_info{purchased:[…]}
   回包 { ticket:0|1, ads_id:"", share_id:"", is_free:false }
[客户端] e 为真 → purchasedMap[shopId]++ → updateShop() → 弹"成功购买了X"
```

### 7.2 抽奖（消耗 5 券）
```
[客户端] RaffleView.raffle → consumeTicket(5) 检查 → send "item_gacha" {is_reward:false}
[服务端] ticket>=5 ? (ticket-=5, 推 item_update_ticket{ticket}) : 回 {ticket:-1}
         rank = 加权抽(PrizeBalls) ; state.gacha.colorBall = rank
         回包 { ticket: rank }
[客户端] item_gacha handler → gachaColorBall=rank → updateGachaColorBall(事件)
   ├ rank==-1 → 恢复按钮，结束
   ├ rank==0(White) → 播放白玉动画 → 弹"获得抽奖券" → cleanGachaColorBall() 本地置 -1
   │                 → send "item_redeem_prize" {prize_id:0}
   └ rank 1..5      → 播放对应玉动画 → 弹 PrizeSelector(同 rank 的 Prize 行)
                     玩家选一个 → cleanGachaColorBall() 本地置 -1
                     → send "item_redeem_prize" {prize_id:<选中行.id>} → 弹 PrizeShare
[服务端] 校验 colorBall==PrizeDB[prize_id].rank
   ├ rank0: ticket += prize.stock; 推 item_update_ticket{ticket}
   ├ 其它 : house[prize.itemId] += prize.stock; 推 item_update{item:{item_id,count}}
   └ state.gacha.colorBall = -1 ; save()      （无回包）
```

### 7.3 启动推送（现 BOOT_PUSH 已包含前 4 条）
```
hall.enter_game → client_load_role (含 res.clover_point / res.ticket / gacha.color_ball)
                → weather.load
                → item_load_items      {house, bag[4], desk[8], bag_completed, bag_conflict,
                                        desk_conflict, gacha:{color_ball:-1}}
                → item_load_shop_info  {purchased:[{item_id:<shopId>, count}]}
                → item_load_handbook   {collections:[Collection.id…], specialtys:[Item.id…]}
                → … 其余 BOOT_PUSH
                → （延迟一 tick）item_load_select_gift {list:[…]}  ← 客户端要求"原本为空"才弹窗
```
注意 `client_load_role` 里 **`gacha.color_ball`** 也要给对（`rolePayload()`；client@143330 内的 warning
文案就是抱怨 `client_load_role` 里 `gacha` 缺失）：引擎 `rolePayload()` 用的是
`{ color_ball: state.gacha.colorBall }`，与 `defaultState()` 一起把默认值改成 `-1` 即可。

---

## 8. 不确定 / 未验证（**明确标注为推测**）

1. **`SHOP_TICKET_PER: 15` 的具体口径**：客户端只有常量定义、无使用点。
   推测是"每次购买有 15% 概率获得 1 张券"（与回包 `ticket` 字段、`ItemEventType.getTicket` 弹窗吻合）。
   真实的触发语义（是否每位玩家每日上限、是否只在某些 shop 生效）**无依据**。
2. **`GiftData.json` 的触发时机**：客户端 0 引用。推测是服务端在"购买/使用 `Item.type==Gift` 的道具"时展开。
   也可能原服务端根本不用它（而是把内容直接写死在发奖逻辑里）。
3. **`Shop.json` 是否真的完全废弃**：本 build 无引用；`fixPos_Y` 像 UI 坐标。
   推测为老版本货架布局表。
4. **`Collection.json.type`（1/2/3）与 `Collection.Rare`（0..3）的对应关系**：客户端只拿它排序。
   推测 1=B / 2=A / 3=S。
5. **收集品（collections）的解锁来源**：`collectionsList` 在客户端运行期从不被写入，
   `collection_id` 字段只出现在 `museumData.json`。推测由**博物馆系统**发放，与本子系统无关。
   引擎可以安全地长期保持 `collections: []`，或自定义规则（例如"到达某旅行目的地解锁某 Collection"）。
6. **`Prize.Rank.FURNITURE(6)` 的来源**：`Prize.json` 无 rank 6 的行。
   推测是家具抽奖（`WXShareType.Furniture/Gacha`）用的、在别的奖池里。**引擎不要产出 6。**
7. **`item_set_bag_completed` 与旅行出发的联动**：客户端只把 `completed` 存成 `bagLock` 并推给服务端，
   没找到"锁行李 → 服务端开始旅行"的直接代码。推测出发由服务端定时器决定（与现有 `tick()` 一致）。
8. **`conflict` 字段的语义**：客户端只存不读。推测是"服务端修正了客户端本地乐观状态"的标记。
9. **`Item.json.effects[]` 是否要参与旅行结算**：现有引擎完全没用。本文档范围内不影响；
   若要还原原版手感，需要另做一份"旅行数值"规格。
10. **`item_gacha` 的 `is_reward` 语义**：`reward_raffle` 路径（`is_reward=true`）由
    `RaffleController.open` 的 `getParam(0)` 决定，未找到调用方传 true 的位置。
    推测是某些活动/邮件奖励的"免费抽奖"入口。引擎可暂时对 `is_reward===true` 走"不扣券"分支。
11. **`work/cdn/v1021/.../config/**` 与 eab 的版本差**：cdn 的 `Item.json`(108 KB)/`shopData.json`(34 条)/
    `Specialty.json`(3 字段) 都是**旧 build**；`work/run/web/.../config.eab` 才是运行时用的。
    **任何字段级实现都必须以 eab 为准。**

---

## 9. 依据索引（结论 → 客户端证据）

| 结论 | 客户端依据（函数 / 偏移，均为**字符偏移**） |
|---|---|
| 价格表本地、`ShopDataDB=i("shopData")` | DataManager 构造函数 @406685；`IdGetter` 类定义 @405844 起 |
| `CollectDB=i("Collection")` / `SpecialtyDB=n("Specialty")` / `PrizeDB=n("Prize")` / `ItemDB=i("Item")` | @405844 / @405875 / @405935 / @405959 |
| EAB 加密变体 + XXTEA 密钥 | `eab.decode` @231428；`xxtea` 模块 @227568；`Utils.simpleEncrypt`(`k`) @301862 |
| `ItemType` 全枚举 | 值块 @408520，枚举体 @409013 |
| `ItemAmuletType` / `ItemResourceType` / `DropType` | @409061(体@409087) / @409147(体@409265) / 体@409529 |
| `ItemID` / `Gift` / `BagItem` / `DeskItem` / `LotteryState` | @417045(体@417223) / @417287 / 体@417560 / @417626(体@417854) / @417902 |
| `Prize.Rank` 全枚举 | @413348..@413430 |
| `Collection.Rare` / `ShowType` / `Item.Type` | @411115 / @411250 / @411407 |
| `Define` 常量 | RAFFEL_NEEDTICKETS @419653、SHOP_TICKET_PER @420150、PRIZE_WHITE_ID @420561、PrizeBalls @420578、PrizeBallName @420756、PrizeClover @420926、ItemPutDesc @421100；整块 @418000..423600 |
| `send` 参数装配 + 首个下划线变点 | @336282 |
| `AnalysisProtocol` 分发（session / 无 session） | @337837 |
| `ProtocolList` 全表 | @375290 |
| `ItemModel` 构造函数（`bagDataList=[-1×4]`、`deskDataList=[-1×8]`、`gachaColorBall=-1`、`collectionsList=[]`、`specialtysList=[]`、`bagLock=false`、`selectGiftList=[]`、`purchasedMap={}`） | @132961 起（成员初始化 @133067..@133150） |
| `ItemModel.initModel` 注册的推送集合 | @133481 附近 |
| `item_load_items` | @143330 |
| `item_load_shop_info` | @140663 |
| `item_update` | @141518 |
| `item_update_ticket` / `clover_update` / `clover_notice_get` | @140966 / @141055 / @141139 |
| `item_load_handbook` | @143969 |
| `item_gift_open` | @142032 |
| `item_load_select_gift` / `check_select_gift` / `req_select_gift` | @142432 / @142681 / @142860 |
| `addHouseItem` 空函数 | @137164（全局唯一） |
| `doAddHouseItem`（含 RESOURCE 分流、Specialty→图鉴） | @137225 |
| `doConsumeHouseItem` | @138569 |
| `addClover`/`setClover`/`consumeClover`/`addTicket`/`setTicket` | @213035 / @213071 / @213242 / @213616 / @213652 |
| `getShopItemBuynums` / `isShopItemBuyLimit` | @136692 / @136828 |
| `setBagLock` → `item_set_bag_completed` | @140216（send 调用点） |
| `Bag.lock` / `Bag.setImageLock` | @433653 / @434343 |
| `Game.buyItem` → `item_buy` | @439380（函数）.. @439747（send 调用点） |
| `ShopView.selectItem`（价格二次校验、`t.buy(...)` 回调） | @1072696；价格比较 @1073270；`t.buy(i.id,i.itemId,i.name)` @1073351 |
| `ShopView.buy` / `getAllItem` / `getTicket` / `showGetTicket` / `checkShopItemHideBefore` / `updateInfo` / `updateShop` / `checkIsFristTimeBuyTool` | @1075424 / @1077683 / @1073300 附近 / @1073400 附近 / @1078631 / @1077485 / @1078892 / @1077177 |
| `item_buy` 推送处理器（ticket/ads_id/share_id） | @144353（`_dumps_item.txt` L6-11） |
| `item_gacha` 推送处理器 | @144215 |
| `RaffleView.raffle` / `reward_raffle` / `nextReward` / `updateTicket` / `updateGachaColorBall` / `playRaffleAnm` / `showResult` / `checkIsFristTimeEnterRaffle` | @974262 / @974628 / @975023 / @974170 / @975178 / @976325 / @977031 / @977482 |
| `PrizeSelector.selectItem` → `item_redeem_prize` | @981836（send 调用点 @982120） |
| White 分支自动领 → `item_redeem_prize(prize.id)` | send 调用点 @976028 |
| `cleanGachaColorBall` | @135398 |
| `prizelist` getter（= PrizeDB 全量） | @441399 |
| `collectionList` / `specialtyList` getter | @440499 / @440879 |
| `Game.getFriendTaste`（SpecialtyDB 下标 → Chara.taste） | @441600 附近 |
| `GiftSelectView`（num/items） / `GiftSelectItem` / `onItemTap` 1-based 下标 | @648400 前后 / @650091 |
| `capsule.setGiftItems` | @541579 |
| `CdkeyView` → `item_use_gift_code`（code==200） | @544284 |
| `MessageModel.getErrorInfo`（errcode_json） | @148253 |
| `LotteryModel`（data 形状 / `lottery_load` 受 `phase` 门控） | @145271 起 |
| `lottery_open` / `lottery_select` / `lottery_confirm_reward` 回包消费 | @145964 / @146470 / @146700 |
| `travel_gift_to_bag`(`gift_to_bag`) / `travel_bag_to_gift`(`moveItemToGiftBox`) | @116236（send @116348） / @138980（send @139163） |
| `TravelGiftModel.travel_load_gift`（`{pictures,specialtys:[{item_id,count}]}`） | @118657 |
| `gift_to_album`（101 相册满） | @116931 |
| `core.Dictionary.Add` 是 upsert | @349875 |
| `Utils.convertArray` = `Array.isArray?e:[]` | 函数 @300344，导出 @308086 |

工具：
`work/tools/eab_decode.js`（EAB 解密，本次新增）、`work/tools/dump_chars.py`（按字符偏移导出，本次新增）、
`work/tools/find_table.py`（找配置表引用点，本次新增）、`work/tools/defoffset.py`（函数定义偏移）、
`work/tools/offof.py`（字面量偏移批量查询），
以及既有的 `dump_handlers.py` / `occur.py` / `where_literal.py` / `who_sends.py` / `findstr_tree.py`。
