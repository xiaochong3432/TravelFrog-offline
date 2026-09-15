# 家具 / 庭院 / 花盆 / 堆肥 / 口袋 / 不倒翁 / 装饰 —— 字段级实现规格

> 目标读者：要在 `work/run/engine/index.js` 里实现这一子系统的同学。
> **本文只写规格，不改引擎代码。**
>
> 判定规格的唯一准绳是客户端原始代码 `work/base/assets/game/js/main.min.js`。
> 所有结论都注明依据（`main.min.js@<字符偏移>` + 使用的工具）。**没有依据的推测一律标 `【推测】`。**

---

## 0. 证据来源与工具约定（先读这一节，否则偏移会对不上）

| 事实 | 依据 |
|---|---|
| `main.min.js` 共 1 315 383 字节 / 1 261 092 字符 | 直接统计 |
| `work/tools/occur.py`、`where_literal.py`、`rx.py` 报的是**字符偏移** | 实测：`furniture_replace_fur` char=109100 / byte=110890 |
| `work/tools/dump_range.py` 用的是**字节偏移**，会漂移 | `dump_range.py` 源码第 10 行 `raw[start:end]` |
| **要按偏移导出代码，必须用 `work/tools/dump_chars.py`** | 本次新增/已有：`dump_chars.py`（字符偏移，和 occur.py 一致） |

本次新增的两个工具（不改引擎）：
* `work/tools/dump_chars.py` —— 按**字符**偏移导出 `main.min.js` 片段。
* `work/tools/rx.py <out> <regex> [before] [after] [maxhits]` —— 正则搜索并把结果写文件（绕开 GBK 控制台编码报错）。
* `work/tools/eab_dec.py` —— **解密** `config.eab`（见下节），`list` / `get` 两个子命令。

### 0.1 数据表已解出（重要）

`flowerpotData / compostData / pocketData / tumblerData / decoration / benchData` 这些表**不在**明文 CDN 目录里，
它们在 `resource/China/eab/config.eab` 里，而该包是 **XXTEA 加密**的（魔数第 6 字节 `0x1b` 而非 `0x1a`）。

我已按客户端自己的算法解密并导出到 `work/specdata/`：

* 客户端解密逻辑：`main.min.js@231700`（`eab.decode`）
  ```js
  var i=[137,69,65,66,13,10,26,10], n=[137,69,65,66,13,10,27,10];   // 明文 / 密文魔数
  if(t[6]==n[6]){ var s=xxtea.decrypt(new Uint8Array(e,8), Utils.simpleEncrypt("r]|lnf\u0080X\u0081U\u0082aq_r",13)); ... }
  ```
* 密钥变换：`Utils.simpleEncrypt(k)`（`main.min.js@301862`）= 偶数下标 `-13`、奇数下标 `+13`。
* XXTEA 标准实现：`main.min.js@227200` 起。

导出结果（**这些是设计数据表，实现时直接抄 id**）：

| 导出文件 | 内容 |
|---|---|
| `work/specdata/flowerpotData_json` | `{"flowerpot":{...},"plant":{...}}` —— **全表只有 1 个花盆**：`23001 陶瓷花盆 {pic:"flowerpot_1_1", pos_list:[[-30,-40],[27,28]], type:1}`；`plant` 35 种（id `2010101`…`2011103`，每种 `pic:[苗,株,花]` 三阶段） |
| `work/specdata/compostData_json` | 15 个堆堆：`21000 木头堆堆 / 21001-21004 榛果堆堆 / 21011-21014 网栅堆堆 / 21021-21024 栏栅堆堆 / 21031 石器堆堆 / 21041 露营堆堆`，字段 `{bg,res,name,desc}` |
| `work/specdata/pocketData_json` | 6 个挂兜：`22001 小挂兜 / 22011-22013 绳编挂兜 / 22021 雨林挂兜 / 22031 海洋挂兜`，字段 `{res,none_pic,have_pic,full_pic,name,desc}` |
| `work/specdata/pocketCommonData_json` | **`{"base_info":50}`** —— 挂兜存满阈值 50 |
| `work/specdata/tumblerData_json` | 数组 **36 项**，`{id,name,info,bg,mask}`，id 从 `20011` 起（`bg:"bdw_1_base"`, `mask:"bdw_1_mask"`） |
| `work/specdata/tumblerPathData_json` | 数组，68 项 `{adorn,id,res}`，id 从 `1001` 起（眼睛/饰件） |
| `work/specdata/decoration_json` | 31 项 `{id,name,desc,desc_handbook,icon,pic, pic_growth,achieve}`，id `100/101/102-105`（蜡梅/木槿…）、`1001-1005`（野草）、`10011-10063`（**花盆种出来的花**：角堇/葡风/风信子/鸢尾/郁金香/铃兰） |
| `work/specdata/furnitureData_json` | 294 件家具 `{id(1001…10103), type(1-27), style(1-10,100,101), res[], animation[], drawing, icon, name, info}` —— 这是客户端 `FurnitureDB` |
| `work/specdata/furnitureShopData_json` | 170 条商店条目 `{id(shop_id), item_id, price, limit, shop_limit, has_item, sign, type, order, name, info}` —— 客户端 `FurnitureShopDB` |
| `work/specdata/furnitureCommon_json` | id→名字：`1 墙壁/2 地面/…/10 花瓶/…/27 杂物`（`type`），`1001 素风格…`（`style`，显示时用 `1000+style`） |
| `work/specdata/Item_json` | 410 件物品（客户端 `ItemDB`），字段 `{id,name,type,sub_type,img,price,own_num,spend}` |
| `work/specdata/shopData_json` | **食物/道具商店**（`ShopDataDB`），和家具商店无关，见 §12 |

> 客户端把 `flowerpotData_json` 里的 `flowerpot` 当**字典**用、`plant` 当字典用；`tumblerData/tumblerPathData/benchData` 当**数组**用（`DataManager.TumblerData=i("tumblerData")`，`main.min.js@407153`）。

---

## 1. 客户端状态模型：`FurnitureModel`（一切字段要求的源头）

依据：`main.min.js@102292`–`113700`（`work/out_fm_a.txt` / `out_fm_b.txt` / `out_fm_c.txt` / `out_furnbook.txt`）。

```js
// initModel：注册的推送回调（这就是"必须由服务端推"的那 8 条）
this.addProtocolCallback("furniture_load_furniture","furniture_buy_shop","furniture_putin_bench",
  "furniture_takeout_bench","furniture_load_tumbler","furniture_load_pocket",
  "furniture_load_compost","furniture_load_flowerpot");

// 默认值（各字段的"官方"默认，服务端推送缺字段时不会回落到这些值，而是 undefined）
this.serverData    = { shop:{start_time:0,leave_time:0,shop_list:[]}, mood:0, bench_lock:false,
                       bench:[], put_fur:[], has_fur:[], mate_list:[], replace_fur:[] };
this.tumblerData   = { show_index:0, replace_index:0, tumbler_list:[] };
this.compostData   = { show_index:0, replace_index:0, compost_list:[], state:0, box_index:0, box_list:[] };
this.pocketData    = { show_index:0, replace_index:0, list:[], clover:0 };
this.flowerpotData = { show_list:[], list:[], plant_list:[] };
this.replaceData   = { fur:{}, other:{tumbler:-1,compost:-1,pocket:-1} };
```

**要点 1：`furniture_load_*` 的处理函数是整对象覆盖，不是字段合并。**
```js
furniture_load_tumbler(e){ e && (this.tumblerData = e, this.tumblerData.tumbler_list = Utils.convertArray(e.tumbler_list), ...) }
furniture_load_compost(e){ e && (this.compostData = e, this.compostData.box_list = Utils.convertArray(e.box_list),
                                  this.compostData.compost_list = Utils.convertArray(e.compost_list), ...) }
furniture_load_pocket (e){ e && (this.pocketData  = e, this.pocketData.list  = Utils.convertArray(e.list), ...) }
furniture_load_flowerpot(e){ e && (this.flowerpotData = Utils.convertArrayAll(e)) }
furniture_load_furniture(e){ if(e){ this.serverData = e; this.serverData.shop.shop_list = Utils.convertArray(e.shop.shop_list);
                                    this.serverData.replace_fur = Utils.convertArray(e.replace_fur); ... } }
```
所以**每次推送都要给全字段**，不能只推变化的那一项。

**要点 2：`Utils.convertArray` / `convertArrayAll` 不做任何"智能转换"**（`main.min.js@300344`）：
```js
function v(e){ return Array.isArray(e) ? e : [] }            // convertArray
function _(e){ var t={}; for(var i in e) "object"==typeof e[i] ? t[i]=v(e[i]) : t[i]=e[i]; return t }  // convertArrayAll
```
* 传对象 `{"0":…}` **不会**变成数组，会直接变 `[]`。
* `convertArrayAll` 只复制**已存在**的键：缺失的键在结果里仍然缺失 → 后续 `.length` 抛
  `Cannot read properties of undefined (reading 'length')`（这正是 README §协议备忘 里记的那个坑）。
* `typeof null === "object"`，所以 `null` 字段会被吃成 `[]`。

**要点 3：事件名与刷新路径**（`FurnitureEventType`，`main.min.js@1177001` 附近）
```
UPDATE="FURNITUREEVENTTYPE_UPDATE"          ← furniture_load_furniture 触发
UPDATE_TUMBER="…_UPDATE_TUMBER"             ← furniture_load_tumbler 触发（见下方陷阱）
UPDATE_BENCH="…_UPDATE_BENCH"               ← putin_bench / takeout_bench 触发
UPDATE_COMPOST="…_UPDATE_COMPOST"           ← furniture_replace_compost 触发
UPDATE_POCKET="…_UPDATE_POCKET"             ← furniture_load_pocket / replace_pocket 触发
```
`MainOutController.totalCustomEvents`（`main.min.js@832219` / `833112`）：
```js
case RoleEventType.loadRole: this.view.reset(); break;              // ← 万能刷新
case FurnitureEventType.UPDATE:        this.view.updateFurniture(); break;
case FurnitureEventType.UPDATE_TUMBER: this.view.update_tumber();   break;
case FurnitureEventType.UPDATE_COMPOST:this.view.update_compost();  break;
case FurnitureEventType.UPDATE_POCKET: this.view.update_pocket();   break;
```
`MainOutView.reset()`（`main.min.js@822889`）会顺序调用
`updateFurniture / update_tumber / update_compost / update_pocket / update_flowerpot …`。

> ⚠️ **陷阱（客户端 bug，实现时必须知道）**：`furniture_load_compost` 派发的是 **`UPDATE_TUMBER`**（复制粘贴错误）：
> `main.min.js@104259`，`work/out_fm_a.txt:107`。因此推送 `furniture_load_compost` **不会**刷新堆肥窗口
> （`CompostViewControl` 只监听 `UPDATE_COMPOST`，`main.min.js@561549`）。
>
> ⚠️ **`update_flowerpot()` 没有任何事件绑定**，只在 `reset()` 里被调用一次（`rx.py update_flowerpot` 仅 2 处命中：`@822889` 与函数定义 `@875078`）。
>
> **结论：要让花盆/堆肥的界面立刻变化，最稳的推送是 `client_load_role`**（它触发 `RoleEventType.loadRole` → `view.reset()`；
> 引擎现在的 GM `refresh()` 已经在用这招）。定向推送只对 tumbler / pocket / bench 有效。

**要点 4：客户端发命令时会校验参数个数**（HTTP 分支 `main.min.js@323753`）：
```js
if(r.length != i.length) return void Log.error("发送的协议参数与定义参数不匹配")
for(var a=0;a<r.length;a++) o.params[r[a]] = i[a];
```
即 `ProtocolList` 里的参数表就是硬约束，本文的参数表直接抄自它（`main.min.js@378000`–`380000`，`work/out_ptab2.txt`）。
线上报文格式见 `work/run/README.md` §协议备忘（第 785-804 行）：`{"session":N,"timestamp":…,"cmd":"furniture.putin_bench","data":{"pos":1,"id":10211}}`，
**只有第一个下划线变点**。

---

## 2. 请求 → 应答 → 推送 总表

`needResponse` 全部为 `true`（`main.min.js@378733`…`379196`）。**11 条命令都必须回包。**

| # | 命令（canonical） | 线上名 | 参数（顺序） | 回包字段 | 客户端随后动作 | 应推送 |
|---|---|---|---|---|---|---|
| 1 | `furniture_buy_shop` | `furniture.buy_shop` | `shop_id` | `{code:0}` | `shop_list` 里同 shop_id 的 `num--`；`addHouseItem(FurnitureShopDB[shop_id].item_id,1)`；`consumeClover(price)` | `furniture_load_furniture` + `clover_update` + `item_load_items` |
| 2 | `furniture_putin_bench` | `furniture.putin_bench` | `pos`,`id` | `{code:0}` | `bench[pos-1]=id`，派发 `UPDATE_BENCH` | 无（可选 `furniture_load_furniture`） |
| 3 | `furniture_takeout_bench` | `furniture.takeout_bench` | `pos` | `{code:0}` | `bench[pos-1]=-1`，派发 `UPDATE_BENCH` | 无（可选 `furniture_load_furniture`） |
| 4 | `furniture_putin_box` | `furniture.putin_box` | `pos`,`id` | `{code:0}` | `box_list[pos-1]=id`，派发 `UPDATE_COMPOST` | `furniture_load_compost`（注意上面的陷阱） |
| 5 | `furniture_takeout_box` | `furniture.takeout_box` | `pos` | `{code:0}` | `box_list[pos-1]=0`，派发 `UPDATE_COMPOST` | 同上 |
| 6 | `furniture_replace_fur` | `furniture.replace_fur` | `id`（**家具 id，不是 type**） | `{code}`：`-1` 忽略 / `1` 特殊 / `0` 成功 | 见 §3.6 | `furniture_load_furniture`（+ `client_load_role` 让房间重画） |
| 7 | `furniture_replace_tumbler` | `furniture.replace_tumbler` | `index`（**1 基**） | `{code}`：`-1` 忽略 / `1` 失败 / `0` 成功 | `show_index=index`，成功时 `replace_index=index` | `furniture_load_tumbler` |
| 8 | `furniture_replace_compost` | `furniture.replace_compost` | `index`（1 基） | 同上 | 同上（compostData） | `furniture_load_compost` |
| 9 | `furniture_replace_pocket` | `furniture.replace_pocket` | `index`（1 基） | 同上 | 同上（pocketData） | `furniture_load_pocket` |
| 10 | `furniture_flowerpot_harvest` | `furniture.flowerpot_harvest` | `type`,`index` | **`{item_list:[{item_id,num}]}`（无 code）** | 移除对应 `plant_list` 条目 + 弹奖励 | `furniture_load_flowerpot` + `item_load_items` + `client_load_role` |
| 11 | `furniture_pocket_get` | `furniture.pocket_get` | 无 | `{code:0}` | `pocketData.clover=0`，弹 `ItemID.CLOVER × 旧值` | `clover_update` + `furniture_load_pocket` |

静置推送 5 条（客户端只注册回调、**从不主动请求**，唯一例外见 §11）：

| 推送 | 载荷 | 触发的事件 |
|---|---|---|
| `furniture_load_furniture` | `{shop:{start_time,leave_time,shop_list[]}, mood, bench_lock, bench[], put_fur[], has_fur[], mate_list[], replace_fur[]}` | `UPDATE` → `updateFurniture()` |
| `furniture_load_flowerpot` | `{show_list[], list[], plant_list[]}`（**必须三个都在**） | 无 |
| `furniture_load_compost` | `{show_index, replace_index, state, box_index, box_list[], compost_list[]}` | `UPDATE_TUMBER`（客户端 bug） |
| `furniture_load_pocket` | `{show_index, replace_index, list[], clover}` | `UPDATE_POCKET` → `update_pocket()` |
| `furniture_load_tumbler` | `{show_index, replace_index, tumbler_list[]}` | `UPDATE_TUMBER` → `update_tumber()` |

> `furniture_load_flowerpot` **不在**客户端的 `ProtocolList` 里（`work/out_ptab2.txt` 可见其余 `furniture_*` 都在，唯独没有它），
> 但 `FurnitureModel.initModel` 注册了它的回调，所以**能收、不能用 `send()` 发**。它只能由服务端推。

---

## 3. 逐条命令：字段级规格

### 3.1 `furniture_buy_shop`（家具商店购买）

**请求**：`{shop_id}`。发送点 `main.min.js@103186`（`FurnitureModel.requestBuy`）：
```js
requestBuy(e, t){                                   // e = shop_id
  var i=this, n=DataManager.instance().FurnitureShopDB.get(e);
  n && getModel(RoleModel).syncHarvestClover(!1, new core.Action(function(){
    SocketManage.getInstance().send("furniture_buy_shop", new core.Action2(function(r){
      if(r && 0==r.code){                           // ← 回包必须有 code，且 0 才算成功
        for(var o=0,a=i.serverData.shop.shop_list; o<a.length; o++){ var s=a[o]; if(s.shop_id==e){ s.num--; break } }
        var c=DataManager.instance().ItemDB.get(n.item_id);
        c.type==ItemType.Gift || getModel(ItemModel).addHouseItem(n.item_id,1,!0);
        c.type==ItemType.FURNITURE_PAPER && PageManage…addViewControl(FurnitureItemTipsController, …, {img,title,area,info});
        getModel(UserModel).consumeClover(n.price);  // ← 客户端自己扣三叶草
        t.apply(r);
      }
    }), e);
  }));
}
```
**服务端必须做**：
1. 校验 `shop_list` 里有该 `shop_id` 且 `num>0`（客户端买按钮在 `num<=0` 时 disable，`@634056`），否则回 `{code:1}`。
2. 扣 `FurnitureShopDB[shop_id].price` 三叶草（**必须扣**，因为客户端扣的是本地值，你随后推 `clover_update`/`client_load_role` 会覆盖成你的值）。
3. 给玩家发 `FurnitureShopDB[shop_id].item_id` 这件**物品**（进 `items.house`，不是 `has_fur`）。
4. `shop_list` 里该条 `num--`。
5. 回 `{code:0}`；推送 `furniture_load_furniture` + `clover_update` + `item_load_items`。

**商店数据**（`furnitureShopData_json`，170 条，`type` 分组，`work/specdata/`）：
| type | 含义 | 例子 | 价格/限制 |
|---|---|---|---|
| 1 | 二级工具升级（`has_item` = 需先拥有的 1 级工具） | `1001 → item 10211 实用锯子, has_item 10201` | 750, limit 1 |
| 9999 | 三级工具升级 | `1006 → item 10221 精制锯子, has_item 10211` | 1200, limit 1 |
| 2 | 基础材料（ItemType 10 `FURNITURE_RESOURCE`） | `2001 → 10001 松木` | 20, 不限量 |
| 3 | 高级材料（ItemType 11 `FURNITURE_ITEM`） | `3001 → 10101 岩纹石` | 200 |
| 4 | 图纸/图册（ItemType 13 `FURNITURE_PAPER`，`sub_type` = 家具 type） | `4001 → 10301 墙壁粉刷图册` | 500, limit 1 |
| 5 | 特殊材料 | `5001 → 11001 植物果实` | 150, `shop_limit 1`, `sign 1` |
| 6 | 肥料（ItemType 15 `Courtyard`，`sub_type 1`） | `6001 → 20001 一号水溶肥` | 100/200/300 |
| 8 / 999 | 食物（ItemType 0） | `8001 → 101 枣花酥` | 350, `sign 1/2` |
| 9 | 显影液（ItemType 8） | `9001 → 8002 单色显影液` | 500 |
| **998** | **看广告/分享免费领**（走 `FurnitureAdsView`，不扣三叶草） | `7003 → 20101 种子·角堇` | 客户端分支 `if(998==i.type)`，`@634501` |

`has_item` 在客户端 JS 里**完全没有被读取**（`rx.py has_item` → 0 命中），是纯服务端字段：用来实现"必须先有简易锯子才能买实用锯子"的升级链。
`limit`/`shop_limit`：`shop_limit>0` 时列表显示"仅{n}件"（`@638833`）。**这些限制都由服务端在 `shop_list` 的 `num` 上体现。**

### 3.2 `furniture_putin_bench` / `furniture_takeout_bench`（工作台上的 5+5 格）

**请求**：`putin {pos,id}`、`takeout {pos}`，`pos` **1 基，范围 1..10**。
依据（`main.min.js@107267` / `@107935`，`work/out_fm_b.txt:51-69`）：
```js
setBenchTool(e,t){                       // e:0..4（工具位），t:item_id 或 -1
  var n=new core.Action2(function(n,r){ n && 0==n.code && (i.serverData.bench[e]=t, i.updateRedot(),
                                       i.dispatchEvent(new Event(FurnitureEventType.UPDATE_BENCH))) });
  -1==t ? send("furniture_takeout_bench", n, e+1)
        : (-1!=this.serverData.bench[e] ? send("furniture_takeout_bench", new Action2(…send("furniture_putin_bench", n, e+1, t)…), e+1)
                                        : send("furniture_putin_bench", n, e+1, t));
}
setBenchItem(e,t){ … send("furniture_takeout_bench", n, e+1+5) / send("furniture_putin_bench", n, e+5+1, t) }  // e:0..4 → pos 6..10
```
* 读取：`getBenchTools() = bench.slice(0,5)`（`@107150`）、`getBenchItems() = bench.slice(5)`（`@107820`）。
* **槽位内容语义**：工具位放 `ItemType.FURNITURE_TOOL(12)`（`getHouseItemsByType(FURNITURE_TOOL)`，`@609844`），
  杂物位放 `ItemType.FURNITURE_ITEM(11)`（`FURNITURE_ITEM`）。空位是 `-1`。
* **回包**：`{code:0}` 才会更新本地 `bench` 并派发 `UPDATE_BENCH`。
* **换位**：目标槽非空时，客户端会先 `takeout` 再 `putin`（两个包），服务端两次都要回 `{code:0}`。
* **`bench_lock`**：`isLockBench() = (serverData.bench_lock==1)`；为真时点格子提示"呱~不许动"，不能改（`@609385`）。
* **红点**：`updateRedot()`（`@110816`）在 `isOpen()` 为真时会看"工具位全空"或"杂物位全空且家里有 ≥2 件 FURNITURE_ITEM" → 亮红点。
  这暗示**工作台的产出 = 工具 + 杂物（材料）组合**，具体配方在服务端。
* `mate_list`：`getMateList()` 用于家具界面里扣减"被客人占用的材料"（`@611713`、`@640276`），
  所以它是**正在被客人使用的物品 id 数组**。

### 3.3 `furniture_putin_box` / `furniture_takeout_box`（堆肥箱的格位）

**没有独立的"收纳箱"系统** —— `box_*` 是 `compostData` 的字段。
请求 `putin {pos,id}` / `takeout {pos}`，`pos` **1 基，范围 1..6**（`CompostView.itemGrids = [itemGrid0..itemGrid5]`，`main.min.js@562457`）。
依据 `FurnitureModel.setCompostItem`（`main.min.js@111645`，`work/out_fm_c.txt:20-29`）：
```js
setCompostItem(e,t){                 // e: 1..6（界面格号+1），t: item_id，0 表示清空
  var n=new core.Action2(function(n,r){ n && 0==n.code && (
      o = i.compostData.box_list[e-1], i.compostData.box_list[e-1]=t,
      o>0 && getModel(ItemModel).addHouseItem(o,1),      // 取出旧物品还回家
      0!=t && getModel(ItemModel).consumeHouseItem(t,1), // 放入的新物品从家里扣掉
      i.updateRedot(), i.dispatchEvent(new Event(FurnitureEventType.UPDATE_COMPOST))) });
  0==t ? send("furniture_takeout_box", n, e)
       : (this.compostData.box_list[e-1]>0 ? send("furniture_takeout_box", new Action2(…send("furniture_putin_box", n, e, t)…), e)
                                           : send("furniture_putin_box", n, e, t));
}
```
* 空位用 **`0`**（不是 -1）。`box_list[i]||-1` 只在渲染时兜底（`@564253`）。
* 可放入的物品 = `ItemType.Courtyard(15) sub_type 1`（即肥料 `20001-20006`）+ `ItemType.Specialty(3)`（特产 `3000+`）。
  依据 `CompostView.on_item_tap`（`main.min.js@562993`）：
  ```js
  r = i.getHouseItemsByType(ItemType.Courtyard, 1);
  o = i.getHouseItemsByType(ItemType.Specialty).concat();
  r = r.concat(o); …（按 type 再按 id 排序）
  ```
* 再次点击同一格且选中同一物品 → 视为清空（`e.item_id==n.item_id?0:e.item_id`）。

### 3.4 `furniture_replace_tumbler` / `_compost` / `_pocket`（选择展示哪个）

**请求**：`{index}`，**1 基**（界面里的 `replaceSelection` 是 0 基，发送时 `+1`）。
依据 `FurnitureModel.replaceFurniture`（`main.min.js@108730`，`work/out_fm_b.txt:108-111` / `out_fm_c.txt:1-4`）：
```js
var r = Object.keys(e.fur).filter(t=>2==e.fur[t]).map(Number),   // 要替换的家具 id
    o = e.other, a = r.length;                                   // o = {tumbler,compost,pocket} 0基 或 -1
o.tumbler>=0 && send("furniture_replace_tumbler", new Action2(function(e){
   -1!=e.code && (1==e.code ? n.tumblerData.replace_index=0 : 0==e.code && (n.tumblerData.replace_index=o.tumbler+1),
                  n.tumblerData.show_index=o.tumbler+1);
   …dispatch(UPDATE_TUMBER)}), o.tumbler+1);
… compost / pocket 同构
```
**回包语义（三条完全一致）**：

| `code` | 客户端行为 | 建议 |
|---|---|---|
| `-1` | 什么都不做（不认这次请求） | 不要用 |
| `0` | `replace_index=index`（标记"刚换上的这件"用于高亮/动画）+ `show_index=index` | **成功用这个** |
| `1` | `replace_index=0` + `show_index=index` | 表示"切换了但没有'新'标记"，可用作"内存不足/仅切换"分支 |

* `show_index` 是 **1 基下标**，指向 `tumbler_list` / `compost_list` / `list`；`0` = 不展示该物件。
* 客户端自己的 `replaceSelection` 是 0 基、`-1` 表示"不修改"（`FurnitureCargoPage`，`main.min.js@618374`）：
  ```js
  t.replaceSelection = { tumbler: tumblerData.replace_index-1, compost: compostData.replace_index-1,
                         pocket: pocketData.replace_index-1 }
  … onCompostTap(e){ this.replaceSelection.compost = e.index; (e.replacing||e.using) && (this.replaceSelection.compost=-1) }
  ```
  即：点当前已展示/刚换上的那件 → `-1`（不发包）；点别的 → 发 `index+1`。
* **推送时序提醒**：引擎是"先回包、后推送"。客户端在回包里设 `replace_index=index`，若你紧接着推 `load_*` 且里面 `replace_index=0`，
  那个"刚换上"的高亮会立刻消失。建议服务端也记住 `replace_index = 最后一次成功的 index`。

### 3.5 `furniture_flowerpot_harvest`（收花）

**请求**：`{type, index}` —— `type` = 花盆类型（花盆表 `type`，全表就 1 个 → `1`），`index` = 花盆内位置，**1 基**。
发送点 `main.min.js@112569`（`FurnitureModel.req_flowerpot_harvest`），**调用方是点击花盆**（`main.min.js@875822`）：
```js
flowerpotTouchEvents(e){
  var i=function(i){
     if(n.plantList[i].info.sprite<3) return "continue";        // ← 只有 stage>=3 才能收
     if(!n.plantList[i].hitTestPoint(e.stageX,e.stageY)) return "continue";
     var r=Number(i);                                           // r = 10*type + index
     return n.getModel(FurnitureModel).req_flowerpot_harvest(Math.floor(r/10), r%10, function(){ … }), "break" };
  …}
```
**回包（这条最特殊：没有 `code`，只认 `item_list`）**：
```js
req_flowerpot_harvest(e,t,i){                                   // e=type, t=index
  send("furniture_flowerpot_harvest", new Action2(function(r){
    if(r.item_list){                                            // ← 没有 item_list 就什么都不发生
      for(var o=0;o<n.flowerpotData.plant_list.length;o++){ var a=n.flowerpotData.plant_list[o];
        if(e==a.type && t==a.index){ n.flowerpotData.plant_list.splice(o,1); break } }
      if(r.item_list.length>0){
        for(var s=[],c=0,l=r.item_list;c<l.length;c++){ var o=l[c];
          s.push({ item_id:o.item_id, count:o.num, type:DataType.DropType.ITEM }) }   // ← 注意字段名是 num
        PageManage…addViewControl(GiftPackageViewController, …, s) }
      i() }                                                     // ← 回调只在 item_list 存在时执行
  }), e, t)
}
```
**规格**：回 `{ item_list:[ {item_id, num} , … ] }`。
* 字段名是 **`num`**（不是 `count`）；写成 `count` 会让奖励数量变 `undefined`。
* `item_list` 必须存在（空数组也行）：否则花不会从 `plant_list` 里消失。
* 服务端还应推 `item_load_items`（奖励进了家）、`furniture_load_flowerpot`、`client_load_role`（否则花盆画面不刷新，见 §1 要点 3）。

### 3.6 `furniture_replace_fur`（把家具摆进小屋）

**请求**：`{id}` —— **家具 id**（`furnitureData` 的 key，如 `10001`），不是 `type`。
发送点 `main.min.js@108730`（同一个 `replaceFurniture`）：
```js
var r = Object.keys(e.fur).filter(function(t){ return 2==e.fur[t] }).map(Number);  // ← 只发"状态=2"的
…
core.SocketManage.getInstance().send("furniture_replace_fur", new core.Action2(function(t){
   var r = c.get(e).type;                        // c = FurnitureDB
   if(-1 != t.code){                             // -1：完全忽略
      if(1==t.code){ var o=n.serverData.replace_fur.indexOf(r); -1!=o && n.serverData.replace_fur.splice(o,1) }
      else 0==t.code && n.serverData.replace_fur.push(r);
      for(var l=n.serverData.put_fur.length-1; l>=0; l--) n.serverData.put_fur[l].type==r && n.serverData.put_fur.splice(l,1);
      n.serverData.put_fur.push({type:r, id:e});         // ← 本地把新家具挂上去
   }
   …dispatch(FurnitureEventType.UPDATE)}), e)
```
**回包语义**：

| `code` | 客户端行为 |
|---|---|
| `-1` | 完全忽略（连 `put_fur` 都不改）→ 用来表示硬失败 |
| `0` | 更新 `put_fur`（移除同 type 旧的、加入 `{type,id}`）+ 把该 type 记入 `replace_fur` |
| `1` | 更新 `put_fur`，但把该 type 从 `replace_fur` 里移除 |

**`replace_fur` 是什么**：一个**家具 type 数字数组**，只影响家具图鉴 UI 的高亮。
`getReplaced()`（`main.min.js@113608`）= `put_fur` 里 `type ∈ replace_fur` 的那几件 id；
`FurnitureBookPage.update()`（`@614410`）把它们设成 `replaceSelection[id]=3`，而 `3` 在列表渲染里等价于 `replacing`（`FurnitureBookListItem.dataChanged`，`@618002`）。
**最省事的正确做法：回 `{code:0}`，`replace_fur` 推 `[]`**（不亮"正在替换"角标，其它一切正常）。

**`replaceSelection` 取值语义**（`FurnitureBookPage.selectReplace`，`main.min.js@616191`）：
`1 = using`（当前已摆放，来自 `getHomeFurnitures()` 的 id）、`2 = replacing`（新选中要摆的，**会被发送**）、`3 = 选中但就是当前那件**（不发）。
所以**只有"真正要换的"才发包**，服务端不需要处理"取消"。

**服务端要做**：`put_fur` 是 `[{type, id}, …]` 数组，**每种 type 最多一件**（同一 type 换新 → 删旧加新）；
`has_fur` 是**拥有的家具 id 数组**（图鉴列表数据源，`getOwnedFurnitures()`，`@106658`）。
家具摆放后小屋贴图由 `loadFurnitureRes()` 预加载（`@105729`：`Furniture.getFurnitureSlot(type)` → `res[i]+"_png"` → `RES.createGroup("furniture_home")`），
**所以 `id` 必须在 `furnitureData` 里存在**，否则图鉴/贴图会静默缺失。

### 3.7 `furniture_pocket_get`（收口袋）

**请求**：无参数。发送点 `main.min.js@112326` / 交互 `@880517`：
```js
request_pocket_get(e){                                              // e(code, oldClover)
  var t=this, i=this.pocketData.clover;                             // ← 记住收之前的数量
  send("furniture_pocket_get", new Action2(function(n,r){
        0==n.code && (t.pocketData.clover=0, t.updatePocketRedot(), e(n.code,i)) }))
}
// on_pocket_tap：
0==t.pocketData.clover ? 弹「呱~里面空空的」
  : request_pocket_get(function(t,i){
      addViewControl(ItemRewardViewControl, …, [{ item_id: Tabikaeru.ItemID.CLOVER, count: i }]), e.update_pocket() })
```
**规格**：回 `{code:0}` 表示成功。
**服务端必须**把 `clover` 加到玩家三叶草上**并推 `clover_update`**（弹窗只是展示，客户端不会自己加钱；
`ItemID.CLOVER = 200000`，`main.min.js@417137`）。随后推 `furniture_load_pocket`（`clover:0`）。
红点阈值 = `pocketCommonData.base_info = 50`（`updatePocketRedot`，`main.min.js@111401`）。

---

## 4. 静置推送：逐条字段要求（最关键的一节）

### 4.1 `furniture_load_furniture`

处理函数（`main.min.js@104833`，`work/out_fm_a.txt:113-119` + `out_fm_b.txt:1-24`）：
```js
furniture_load_furniture(e,t){
  if(e){
    this.serverData = e;
    this.serverData.shop.shop_list = Utils.convertArray(e.shop.shop_list);   // ← e.shop 必须存在且是对象
    this.serverData.replace_fur   = Utils.convertArray(e.replace_fur);
    var n = core.Time.getServerTime();
    this.serverData.shop.start_time<n && this.serverData.shop.leave_time>n && ( … 定时器：到 leave_time 时关掉商店窗口并弹「嘟嘟已经收拾回家了」… );
    this.dispatchEvent(new core.Event(FurnitureEventType.UPDATE));
    this.updateRedot();
    this.loadFurnitureRes();
  }
}
```

| 字段 | 类型 | 必需 | 缺失后果（依据） |
|---|---|---|---|
| `shop` | object | **必需** | `e.shop.shop_list` → `TypeError: Cannot read properties of undefined (reading 'shop_list')`（`@104833` 处理函数第 4 行） |
| `shop.start_time` | int 秒 | **必需** | 见下方"工作台开关" |
| `shop.leave_time` | int 秒 | **必需** | `isOpenShop()` 与关店定时器 |
| `shop.shop_list` | 数组 | **必需**（可为 `[]`） | `convertArray` 会兜成 `[]`，安全 |
| `mood` | int | 建议给 | 缺失 → `undefined==Furniture.Mood.very_angry(5)` 为假 → 用正常图（不崩） |
| `bench_lock` | 0/1 | 建议给 | 缺失 → `1==undefined` 假 → 不锁（不崩） |
| `bench` | 数组 | **`start_time>0` 时必需** | 缺失 → `updateRedot()` 内 `getBenchTools()` 调 `serverData.bench.slice(0,5)` 抛异常（`@110816` / `@107150`）；`start_time==0` 时 `isOpen()` 为假，提前 return，所以现在不崩 |
| `put_fur` | 数组 | **必需** | `loadFurnitureRes()` 遍历它 → `undefined.length` 崩（`@105729`） |
| `has_fur` | 数组 | 必需 | 打开家具图鉴时 `getOwnedFurnitures()` 的 `for…of` 在 `undefined` 上抛异常（`@106658`） |
| `mate_list` | 数组 | 打开工作台界面时必需 | `FurnitureBenchView.update()` 遍历（`@611713`） |
| `replace_fur` | 数组 | 必需（`[]` 即可） | `convertArray` 兜 `[]` |

`shop_list` 每条的形状（`FurnitureShopController.update`，`@636546`；列表渲染 `@638833`）：
```js
{ shop_id: <furnitureShopData 的 id>, item_id: <Item id>, num: <剩余件数> }
```
* 列表按 `FurnitureShopDB[shop_id].order` 排序；`num<=0` 时购买按钮变灰（`@634056`）。
* `item_id` 用于列表图标（`ItemDB.get(this.data.item_id)`）；**真正发到手的是 `FurnitureShopDB[shop_id].item_id`**。

**工作台 / 嘟嘟（商店）开关**（`MainOutView.updateFurniture`，`main.min.js@848695`）：
```js
var t = isOpenShop(),              // start_time < now < leave_time → 场地里出现"嘟嘟"商人 Spine
    i = isOpen();                  // start_time > 0 → 工作台可见（imgFurnitureBench）、并显示"进入工作台"按钮
if(i){ imgFurnitureBench.visible=true; imgFurnitureBenchEmpty.visible=false; btn_enterFurnitureBench.visible=true;
       serverData.mood==Furniture.Mood.very_angry ? 图=_gzt_strike_png : 图=_gzt_png }
else { imgFurnitureBench.visible=false; imgFurnitureBenchEmpty.visible=true; btn_enterFurnitureBench.visible=false }
if(t){ …加载 shop_dragonbones（drummer / 特殊彩蛋 egg_101_rain_dd）… 定时到 leave_time 再刷新隐藏 }
```
* `Furniture.Mood = {verry_happy:1, happy:2, calm:3, angry:4, very_angry:5}`（`main.min.js@113958`）。`mood==5` 时工作台用"罢工"图。
* `start_time=0` ⇒ **工作台与家具商店入口全部消失**（`isOpen()=false`），这也是当前引擎能侥幸不崩的原因。
* 另外 `main.min.js@833112`：`onSyncComplete` 里若 `isOpen()` 且 `guideFurnitureNotice` 未设过，
  会推一条 `notify_new_event {evt_type:1022 (FurnitureVersion)}` —— 也就是"庭院变了"的提示。

### 4.2 `furniture_load_flowerpot`

```js
furniture_load_flowerpot(e){ e && (this.flowerpotData = Utils.convertArrayAll(e)) }     // main.min.js@104734
```
`convertArrayAll` 只复制存在的键 → **三个字段都必须给**：

| 字段 | 类型 | 必需 | 用途（依据） |
|---|---|---|---|
| `show_list` | 数组，元素 `{type,id}` | **必需** | `update_flowerpot`（`@875078`）遍历 → `flowerpotList[r.type].source = flowerpotTable[r.id].pic+"_png"`，并用 `t[r.id].pos_list` 定位每个种位 |
| `plant_list` | 数组，元素 `{type,index,id,stage}` | **必需** | 同函数遍历 → 槽位 key = `10*type + index`；`CloverInfo.element=4`、`clover_id=id`、`sprite=stage`；**`stage==3` → 隐藏"种下"按钮（btnPot1）** |
| `list` | 数组 | 建议给（实际未被读取） | 默认值里有；全代码未发现消费点。缺失不崩，但按"整对象覆盖"原则建议一起给 `[]` |

* `type` 的取值就是 `flowerpotData.flowerpot[id].type`（真实表里只有 `23001, type:1`），同时是 `FlowerPotViewSkin` 里 `flowerpotList[type]` 的下标 → **只能是已存在的槽位下标**。
* `index` 是 1 基，范围 `1..pos_list.length`（真实表 `pos_list` 长度 = 2）。
* `id` 必须在 `flowerpotData.plant` 里（`s[r.id]` 判空，`@875705`）。
* 渲染器复用 `CloverInfo`（`main.min.js@449734` case 4：`flowerpotData.get("plant")[clover_id].pic[sprite-1]`）——
  **所以花盆和三叶草地共用一套渲染器，但数据完全独立**（见 §5）。

### 4.3 `furniture_load_compost`

```js
furniture_load_compost(e){ e && (this.compostData=e,
    this.compostData.box_list=Utils.convertArray(e.box_list),
    this.compostData.compost_list=Utils.convertArray(e.compost_list),
    this.dispatchEvent(new core.Event(FurnitureEventType.UPDATE_TUMBER))) }    // main.min.js@104259（注意事件名是 TUMBER）
```

| 字段 | 类型 | 必需 | 含义/依据 |
|---|---|---|---|
| `show_index` | int | 必需（1 基） | `compost_list[show_index-1]` = 当前展示的堆堆 id；`>0` 才渲染（`update_compost`，`@874071`） |
| `compost_list` | 数组 | 必需 | **已拥有的堆堆 id 列表**（`compostData_json` 的 id，如 `21000`）；标题显示"堆肥箱({已拥有}/{全表})"（`@620003`） |
| `state` | int | 必需 | 进度/阶段：`pgb.value = state`，且进度条刻度在 `2/3/4`（`CompostView.onComplete`，`@562694`：`pgb.setItems([{value:2},{value:3},{value:4}])`）；主场景地面贴图：`>=3 → _td_fw_png`、`==1 → _td_pj_png`、其余 `→ _td_zc_png`（`@874071`） |
| `box_index` | int | 必需（1 基） | **当前正在处理的那一格**：`o = (i+1 != box_index)`，该格 `state="disabled"` 且加灰、不可点（`@564253`） |
| `box_list` | 数组，长度 6 | 必需 | 6 个格位的物品 id，空位 = `0`（`itemGrid0..5`，`@562457`） |
| `replace_index` | int | 建议给 | 同 §3.4 |

### 4.4 `furniture_load_pocket`

```js
furniture_load_pocket(e){ e && (this.pocketData=e, this.pocketData.list=Utils.convertArray(e.list),
    this.updatePocketRedot(), this.dispatchEvent(new core.Event(FurnitureEventType.UPDATE_POCKET))) }   // main.min.js@104522
```

| 字段 | 类型 | 必需 | 含义/依据 |
|---|---|---|---|
| `list` | 数组 | 必需 | **已拥有的挂兜 id**（`pocketData_json` id，如 `22001`）；标题"挂兜({已有}/{全表})"（`@620003`） |
| `show_index` | int | 必需（1 基） | `list[show_index-1]` → `pocketData[id]`；`>0` 才画挂兜（`update_pocket`，`@874616`） |
| `clover` | int | 必需 | 挂兜里已囤的三叶草数。`>= base_info(50)` → 用 `full_pic`、亮红点；`>=1` → `have_pic`；否则 `none_pic` |
| `replace_index` | int | 建议给 | 同 §3.4 |

### 4.5 `furniture_load_tumbler`

```js
furniture_load_tumbler(e){ e && (this.tumblerData=e, this.tumblerData.tumbler_list=Utils.convertArray(e.tumbler_list),
    this.dispatchEvent(new core.Event(FurnitureEventType.UPDATE_TUMBER))) }     // main.min.js@104053
```

| 字段 | 类型 | 必需 | 含义/依据 |
|---|---|---|---|
| `tumbler_list` | 数组 | 必需 | 拥有的不倒翁实例；`update_tumber`（`@873824`）取 `tumbler_list[show_index-1]` → `new TumblerToy().setData(t)` |
| `show_index` | int | 必需（1 基） | `>0` 才画；`0` = 庭院里没有不倒翁 |
| `replace_index` | int | 建议给 | 同 §3.4 |

**`tumbler_list` 单个元素的形状**（`TumblerLoader.load`，`main.min.js@900709`）：
```js
{ id: 20011,                                   // 必须在 tumblerData_json 里（提供 bg / mask）
  layers: [ { layer: [pathId, x, y, rotation, mirror] }, … ] }   // pathId → tumblerPathData_json（眼睛/饰件）
```
* `layer[0]` → `TumblerPathData.get(pathId).res`（如 `1001 → "bdw_eye_1"`）
* `layer[1]/[2]` → x/y（默认 0）、`layer[3]` → rotation（默认 0）、`layer[4]==1` → `scaleX=-1`（镜像）
* `TumblerPathData` 的 `adorn`：`1` 进 `adorn` 层、`2` 进 `adornBack` 层、否则进被 `mask` 遮罩的 `paths` 层。
* ⚠️ **`layers` 整体缺失时 `if(e && e.layers)` 为假 → 整个绘制分支跳过 → 不倒翁完全不显示**（不报错）。
* 想省事：`tumbler_list: [{id:20011, layers:[]}]` 会画出"没有五官"的壳（`TumblerData` 的 `bg/mask` 仍然会贴）。

---

## 5. 花盆种植循环（Q3）

**核心结论：客户端没有"种花"命令。** 全协议表里与花盆相关的只有 `furniture_flowerpot_harvest`
（`work/out_ptab2.txt` 的 `furniture_*` 段；`Select-String protocol.js -Pattern "plant|seed|water"` 只命中
`animpicture_use_item`/`item_use_gift_code`/`pray_compose`/`recharge_water`，均与本子系统无关）。
`btnPot1` 在主场景里只是个提示按钮（`main.min.js@839733`）：
```js
btnPot1.addEventListener(TOUCH_TAP, function(){
   for(var e in t.plantList) if(t.plantList[e].info.sprite>0) return void t.addChild(new ModalAlert("呱~再等等"));
   t.addChild(new ModalAlert("呱~空的")) })
```
`FlowerPotView`（`@603090`+）是**花瓶/插花**界面，不是花盆。

**所以整条循环由服务端驱动：**

1. **种**：服务端决定 `plant_list` 里出现 `{type, index, id, stage:1}`（`show_list` 声明哪些花盆/哪些位置存在）。
   花的种类 `id` 取自 `flowerpotData.plant`（35 种，`2010101`…`2011103`）。
   【推测】上游可能是消耗 `ItemType.Courtyard sub_type 2` 的种子/种球（`20101 种子·角堇`…`20111 种球·铃兰`）、
   并且需要 `ItemType.Courtyard sub_type 1` 的肥料（`20001-20006`）——
   依据是这两类物品**只出现在家具商店的货架上**（`furnitureShopData` type 6 肥料、type 998 免费领种子），
   以及堆肥箱的放入过滤恰好接受 `Courtyard(sub_type 1)+Specialty`。**客户端没有任何代码消费它们**，无法从客户端证实。
2. **长**：`stage` 1→2→3 随时间推进（服务端计时）。渲染规则：`CloverInfo.sprite = stage`，
   `stage>=3` 才能收（`flowerpotTouchEvents` 里 `if(sprite<3) continue`）。`stage` 只用 1..3（`pic` 数组长度 3）。
3. **收**：客户端点成熟的花 → `furniture_flowerpot_harvest {type,index}` → 服务端删掉该 `plant_list` 条目并回
   `{item_list:[{item_id,num}]}`，客户端弹礼包并在本地删掉该条目；服务端推 `furniture_load_flowerpot`
   （+`client_load_role`，因为花盆只在 `reset()` 里重画）。
4. **产出什么**：
   * 蔬菜类 → `ItemType.Specialty(3)`：`4101 拇指萝卜 / 4102 樱桃萝卜 / 4103 樱桃番茄 / 4104 迷你南瓜`（真实表里对应的种子是 `20103/20107/20108/20110`），
     以及 `4006 草莓`（种子 `20109`）。这些进礼物盒/特产系统。
   * 花类（角堇/葡风/风信子/网脉鸢尾/郁金香/铃兰）→ `ItemType.RESOURCE(14) sub_type 6`：
     `202211 角堇·火龙果`、`202231 风信子·白珍珠`、`202261 铃兰·原生白` …（共 17 个，`work/item 表`）。
     注意 `doAddHouseItem` 对 `RESOURCE` 只特判 `sub_type` 1/2/3/4/5（`CLOVER/TICKET/COMPASS/WATER/CHANGE`），
     **`sub_type 6` 没有特判 → 就是普通家居物品**（`main.min.js@137225` 的 `doAddHouseItem`，只特判 `CLOVER/TICKET/COMPASS/WATER/CHANGE`）。
   * 【推测】花材与 `decoration_json` 的 `10011-10063`（同名花，`icon` 形如 `icon_chahua_zhongzhi_jiaojin_1`）配对，
     通过 `notify_new_event {evt_type:13 Decoration, evt_id:<decorationId>}` 通知获得装饰
     （依据 `main.min.js@890323`：`case TimerEvent.Type.Decoration: … new DecorationGetView(RoleModel.getDecorationInfo(evt_id))`）。
     **"花材→花瓶装饰"这一步客户端看不到，纯服务端规则。**
5. **和三叶草/四叶草的关系**：**两套独立系统**。
   * 三叶草地：`clover_load_clovers` / `clover_harvest`，字段 `{clover_id, element, sprite, last_harvest, rebirth_span}`；
     `element 0 = 三叶草（加 clover 计数）`、`element 1 = 四叶草（变成 `Define.FourLeafCloverID` 物品）`、`element 2 = 其他`（`main.min.js@172141` 的 `syncHarvestClover`）。
   * 花盆：`CloverInfo` **渲染器**复用，但 `update_flowerpot` 里写死 `h.element = 4`（`@875705`），
     走 `flowerpotData.plant` 表。**花盆不产三叶草，也不影响 `clover` 计数。**

---

## 6. 堆肥（Q4）

| 字段 | 是什么 | 依据 |
|---|---|---|
| `compost_list` | **已拥有的堆堆 id 列表**（装饰物种类），id 见 `compostData_json`（`21000` 木头堆堆 … `21041` 露营堆堆） | `FurnitureCargoPage.update` 遍历它渲染列表；`CompostData.get(id).res/bg` 取图（`@619358`、`@873824`） |
| `show_index` | **当前摆在庭院里的那一个堆堆**，1 基下标进 `compost_list`；`0` = 不摆 | `update_compost`：`compost_list[show_index-1]`（`@874071`） |
| `state` | **堆肥进度/阶段**，`pgb.value = state`；刻度 2/3/4；主场景地面图 `>=3 _td_fw_png` / `==1 _td_pj_png` / 其余 `_td_zc_png` | `@562694`（`pgb.setItems`）、`@874071` |
| `box_list` | **6 个格位**的物品 id，空 = `0` | `itemGrid0..5`（`@562457`）、`@564253` |
| `box_index` | **正在处理的那一格**（1 基）：该格 `disabled`+加灰+不可点，其余可点可改 | `@564253` |
| `replace_index` | 刚切换到的那个堆堆（1 基），仅 UI 高亮 | `@110169` |

**产生与消耗**（可从客户端确证的部分）：
* 放入：`furniture_putin_box {pos(1..6), id}`；取出：`furniture_takeout_box {pos}`；`id=0` 等价清空（走 takeout）。
  可放入**肥料（`ItemType.Courtyard 15 sub_type 1`）+ 特产（`ItemType.Specialty 3`）**（`@562993` 的 `itemsGetter`）。
* 客户端**没有任何"收取产物"的界面**：`CompostView` 只有 `on_item_tap`（改格子内容），没有收获按钮。
  ⇒ 产物由服务端结算，并推 `furniture_load_compost`（更新 `box_list`/`state`）+ `item_load_items`；
  【推测】可用 `notify_new_event {evt_type:21 FurnitureFinish, evt_id:<compost id>}` 让客户端弹"新物件完成了"
  （依据 `@887217` 的 `CompostData.get(Q)` 分支）。
* 【推测】上游语义：格内物品在 `state` 推进到 4 后变成产物（大概是肥料类），`box_index` 指向正在发酵的那一格。

---

## 7. 口袋（挂兜，Q5）

| 字段 | 是什么 | 依据 |
|---|---|---|
| `list` | **已拥有的挂兜 id 列表**（`22001 小挂兜`…`22031 海洋挂兜`） | `@620003` 标题"挂兜({list.length}/{全表})"；`pocketData.get(id)` 取图 |
| `show_index` | 当前挂在庭院里的那一个，1 基下标；`0` = 不挂 | `update_pocket`：`list[show_index-1]`（`@874616`） |
| `clover` | **已囤的三叶草数量**（模型里只有一个计数器，属于 `show_index` 指向的那个挂兜）。`>=1` 用 `have_pic`，`>= base_info(50)` 用 `full_pic` 并亮红点 | `@874616`、`@111401`、`pocketCommonData.base_info=50` |
| `replace_index` | 刚切换到的挂兜（1 基），仅 UI 高亮 | `@110547` |

**`furniture_pocket_get` 干什么**：把挂兜里的三叶草**取出来**。
`on_pocket_tap`（`@880517`）→ `clover==0` 时弹「呱~里面空空的」；否则发包，成功后
`pocketData.clover=0` + 弹 `ItemRewardViewControl [{item_id:200000(CLOVER), count:旧值}]`。
**服务端要加三叶草并推 `clover_update`**（弹窗不加钱）。
【推测】挂兜的"囤草"来源是服务端规则（大概率与旅行结算挂钩）。

---

## 8. 不倒翁 / 长椅(工作台) / 收纳箱 的作用（Q6）

* **不倒翁（tumbler）**：纯庭院摆件，会摇。`TumblerToy`（`@903339`）监听触摸 → 按按压时长算 `bounce_force` → 帧循环里做钟摆摆动。
  只有一个展示位：`tumbler_list[show_index-1]`。它的本体（`bg/mask`）来自 `tumblerData`，五官/饰件由服务端在 `layers` 里指定
  （见 §4.5）。家具图鉴/货架页里用 `FurnitureItemTipsController` 展示它为 3D 预览（`@622783`）。
* **长椅 = 工作台（bench / `gzt`）**：由 `shop.start_time>0` 解锁（`isOpen()`），庭院里出现工作台贴图与"进入"按钮；
  `mood` 决定贴图（5 = 罢工版），`bench_lock=1` 时禁止改动。台面 10 格：**5 格工具（ItemType 12 FURNITURE_TOOL）+ 5 格杂物（ItemType 11 FURNITURE_ITEM）**，
  界面还会列出材料库存（`ItemType 10 FURNITURE_RESOURCE`）并扣掉 `mate_list` 里被占用的数量。
  ⇒ **工作台是家具/摆件的"制作台"**，配方与产出完全在服务端（客户端只收发 `putin/takeout` 与 `load_furniture`）。
* **收纳箱（box）**：**没有独立系统**，`furniture_putin_box` / `furniture_takeout_box` 操作的是 `compostData.box_list`
  （堆肥箱的 6 个格位）。别为它单开一份状态。

---

## 9. `client_change_decorate`（更换花瓶插花，Q7）

**请求**：`{id}`（`decoration_json` 的 id，如 `10011`；`ProtocolList`：`client_change_decorate:[["id"],!0]`，`main.min.js@375920`）。
发送点 `RoleModel.changeDecoration`（`main.min.js@175397`）：
```js
changeDecoration(e){
  send("client_change_decorate", new core.Action2(function(i){
    if(0==i.code){
      for(var n=0;n<t.decorationList.length;n++){ var r=t.decorationList[n];
        if(r.id==t.decorationPutID){ r.num--, r.num<=0 && t.decorationList.splice(n,1); break } }   // ← 旧的那枝被消耗
      t.decorationPutID=e; t.decorationStatus=1;                                                     // ← 新插上，成长阶段=1
      t.dispatchEvent(new core.Event(RoleEventType.updateDecoration))
    }}), e)
}
```
* **状态**：`decorationList:[{id,num}]`（= `client_load_decorate.has_list`）、`decorationPutID`（当前插的那枝）、`decorationStatus`（成长阶段）。
* **回包**：`{code:0}` 才算成功（客户端自己扣旧的 `num`、设 `putID/status`）。
* **推送**：`client_load_decorate`（**权威覆盖**，建议在回包后推，且服务端也要扣掉旧的那枝的 `num`，
  否则客户端的本地扣减和你的推送会打架）；同时推 `client_load_role`（`frog.decoration` 也承载 `[{id,num}]`，`@174949`）。
* UI 依据：`FlowerPotView.onItemTap`（`@604676`）确认文案"确定把 **{name}** 插入花瓶中吗？\n(若瓶中有花，则丢弃原花材)"，
  且 `FlowerDecorationRender` 显示 `num`；`isLock` = 这就是当前插着的那枝（不可重复选）。
* `decorationStatus` 的用途：主场景花瓶贴图取 `decorationDB[id].pic[Math.max(status-1,0)]`（`updateDecoration`，`main.min.js@825472`），
  即 `pic` 是"成长/开放"各阶段的图。**阶段推进也是服务端推 `client_load_decorate` 来实现的。**
* `client_load_decorate` 的完整字段（`RoleModel.client_load_decorate`，`main.min.js@174949`）：
  `{has_list:[{id,num}], put_id, status}` —— `has_list` 走 `Utils.convertArray`，缺失即 `[]`。

---

## 10. 家具从哪来（Q8）

1. **不是 `ShopDataDB`**。`ShopDataDB = RES.getRes("shopData_json")` 是**食物/道具商店**，走
   `item_buy` / `item_load_shop_info`（服务端用 `purchased:[{item_id,count}]` 告诉客户端已买次数，
   `ItemModel.item_load_shop_info`，`main.min.js@140663`）。和家具无关。
2. **家具商店是 `FurnitureShopDB = furnitureShopData_json`（170 条）**，配合服务端推送的 `shop.shop_list`：
   **服务端决定"这次嘟嘟带了什么货、各多少件"**（`num`），客户端只负责展示与发 `furniture_buy_shop`。
   货架内容是**工具/材料/图纸/肥料/食物**（§3.1 表），**不直接卖家具**。
3. **家具本体（`furnitureData` 的 294 件）**：客户端只从服务端推送的 `has_fur`（拥有）/ `put_fur`（已摆放）里读，
   自己不会"生成"家具。相关线索：
   * `furnitureData[].drawing` 指向一张图（如 `10327`），`icon.src = "Icon/drawing"` ⇒ 家具与"绘图/图纸"绑定；
   * `ItemType.FURNITURE_PAPER(13)` 的物品是图纸（`10301 墙壁粉刷图册`，`sub_type = 家具 type`），
     在商店买图纸后客户端会弹 `FurnitureItemTipsController`（`@103186` 里 `c.type==FURNITURE_PAPER` 分支）；
   * `DrawingModel.isOpen() = 家里有 ItemID.DRAWING_BOOK(7001)`（`@97958`）⇒ 有"画册"才出现绘图入口。
   ⇒ 【推测】上游流程：**商店买图纸 → 绘图/工作台制作 → 服务端把家具 id 加进 `has_fur`**，
     并用 `notify_new_event {evt_type:21, evt_id:<furnitureId>}` 通知；客户端收到后会**自己再发一次
     `furniture_load_furniture`**（`main.min.js@887217`：`var ot=new r; SocketManage…send("furniture_load_furniture")`）。
     ⚠️ **这条是唯一一处客户端主动请求 `furniture_load_furniture`**，引擎的 `furniture_load_furniture`
     处理器必须是"随时可被请求的实时快照"，不能只在 `hall_enter_game` 推一次。
   * `Client_load_role.frog.decoration` 与 `client_load_decorate` 是两处装饰来源，见 §9。
4. 【推测】`has_fur` 的另一种来源是**旅行带回**（`furnitureData.info` 如"买回来的小铁蛙 是小伙伴外出找灵感发现的"、"与绘纸上的形象相差无几"）。

---

## 11. 与本子系统相关的事件推送（`notify_new_event`）

`evt_type` 取自 `TimerEvent.Type`（`main.min.js@416072`），处理分支在 `MainOutController`（`main.min.js@887217`）：

| `evt_type` | 名称 | 客户端行为（证据） | 建议用途 |
|---|---|---|---|
| `21` | `FurnitureFinish` | `evt_id` → 依次在 `FurnitureDB / TumblerData / CompostData / pocketData` 里查；命中家具 → 弹"获得新家具"并 **主动 `send("furniture_load_furniture")`**；命中不倒翁/堆肥/挂兜 → 弹"新物件完成了" | **工作台/花盆产出通知**（`evt_id` = 产出物的 id） |
| `22` | `FurniturePut` | 弹提示"小屋好像发生了一点变化" | 有人摆好了家具 |
| `1022` | `FurnitureVersion` | 弹"庭院好像发生了一点变化"；主场景在 `onSyncComplete` 里对首次解锁工作台也会自造这条 | 庭院摆件变化 |
| `13` | `Decoration` | `new DecorationGetView(RoleModel.getDecorationInfo(evt_id))`（"获得礼物"） | **获得花瓶装饰**（花盆收获的花） |
| `2` `3` `7` `11` 等 | BackHome / Picture / Gift / Visitor | 旅行子系统 | 见 README |

`evt_id` 必须在对应的数据表里能查到，否则客户端走 `else p()`（静默什么都不弹）。

---

## 12. 引擎侧实现清单（现状差距 + 建议）

### 12.1 当前引擎的差距（`work/run/engine/index.js@710-725`）

```js
furniture_load_furniture: () => ({ shop:{shop_list:[],start_time:0,leave_time:0}, replace_fur:[], put_fur:[], has_fur:[], fur_list:[], tumbler_list:[] }),
furniture_load_flowerpot: () => ({ show_list: [], plant_list: [] }),
furniture_load_compost:   () => ({ show_index: 0, state: 0, box_list: [], compost_list: [] }),
furniture_load_pocket:    () => ({ show_index: 0, clover: 0, list: [] }),
furniture_load_tumbler:   () => ({ tumbler_list: [] }),
```

| 问题 | 说明 |
|---|---|
| `furniture_load_furniture` 缺 `mood` / `bench_lock` / `bench` / `mate_list` | `start_time==0` 时不崩；**一旦把 `start_time` 设成 >0 去解锁工作台，`bench` 必需**（`updateRedot` 会 `bench.slice`） |
| `furniture_load_compost` 缺 `replace_index` | 不崩（`replace_index` 只影响高亮），但按"整对象覆盖"建议补齐 |
| `furniture_load_tumbler` 缺 `show_index`/`replace_index` | 不崩；但 `show_index` 缺失 = 永远不显示不倒翁 |
| `furniture_load_pocket` 缺 `replace_index` | 同上 |
| 11 条命令**全部未实现** | `dispatch()` 会走 `UNKNOWN` 分支，回 `{}`（因为 `needResponse`），客户端会因为读 `code`/`item_list` 拿不到而静默失败 |

### 12.2 建议的存档状态（可直接落到 `state`，id 都能在 `work/specdata/` 里查到）

```js
state.furniture = {
  shop:  { start_time: 0, leave_time: 0, offers: [ {shop_id:2001,num:10}, … ] },  // offers = 服务端自己维护的货架
  mood: 3, bench_lock: 0,
  bench: [-1,-1,-1,-1,-1, -1,-1,-1,-1,-1],        // 0..4 工具(ItemType 12)，5..9 杂物(ItemType 11)
  has_fur: [10001, 10002],                        // 拥有的家具 id (furnitureData)
  put_fur: [ {type:27,id:10001}, {type:15,id:10002} ],   // 同 type 只能一件
  replace_fur: [], mate_list: [],
  tumbler: { list:[{id:20011,layers:[]}], show_index:0, replace_index:0 },
  compost: { list:[21000], show_index:0, replace_index:0, state:0, box_index:1, box:[0,0,0,0,0,0] },
  pocket:  { list:[22001], show_index:0, replace_index:0, clover:0 },
  flowerpot: {
    show_list: [ {type:1, id:23001} ],
    plant_list: [ {type:1, index:1, id:2010101, stage:3} ],   // stage 1..3；3 = 可收
  },
};
state.decoration = { hasList: [], putId: 0, status: 0 };       // 已有
```

推送给客户端的映射（**注意字段名/数组化**）：

| 推送 | 载荷表达式 |
|---|---|
| `furniture_load_furniture` | `{shop:{start_time,leave_time,shop_list: offers.map(o=>({shop_id:o.shop_id, item_id: FurnitureShop[o.shop_id].item_id, num:o.num}))}, mood, bench_lock, bench, put_fur, has_fur, mate_list, replace_fur}` |
| `furniture_load_flowerpot` | `{show_list, list: [], plant_list}` |
| `furniture_load_compost` | `{show_index, replace_index, state, box_index, box_list: box, compost_list: list}` |
| `furniture_load_pocket` | `{show_index, replace_index, list, clover}` |
| `furniture_load_tumbler` | `{show_index, replace_index, tumbler_list: list}` |

### 12.3 让这几个屏幕"真的能玩"的最小配置

1. **解锁工作台 + 商店**：`shop.start_time = now-1`、`shop.leave_time = now+86400`，
   并**同时**给全 `mood/bench_lock/bench/mate_list`（否则 `updateRedot` 崩）。
   否则 `isOpen()` 为假，工作台与商店入口在庭院里根本不出现。
2. **货架**：`offers` 里至少放 `2001..2007`（材料，20 草）、`6001..6006`（肥料）、`4001..4013`（图纸，500 草）。
   `furnitureShopData_json` 里 `type:998` 的条目走"看广告免费领"，离线环境建议不放。
3. **花盆**：`show_list:[{type:1,id:23001}]` + `plant_list` 若干个 `{type:1,index:1..2,id:<plant>,stage:1..3}`；
   tick 里推进 stage，收成时把 `stage>=3` 的条目删掉、回 `item_list` 并推 `client_load_role`。
4. **摆件**：`compost.list=[21000]`、`pocket.list=[22001]`、`tumbler.list=[{id:20011,layers:[]}]`，
   把对应 `show_index` 设成 1 就能在庭院里看到它们。
5. **提醒**：任何一次改动后推 `client_load_role`（→ `view.reset()`）是最省心的"全量重画"，
   因为 `flowerpot` 没有事件、`compost` 的推送事件名错了（§1 要点 3）。

---

## 13. 不确定项 / 需要实测或进一步取证的地方

| # | 不确定 | 现状与依据 |
|---|---|---|
| 1 | 花盆**怎么种**（消耗什么、谁能种、种到哪个槽） | 客户端**无种植协议**（协议表已全查）。服务端自由决定。种子/肥料只在商店货架上出现 ⇒ 大概率是服务端消耗，但**无法从客户端证实** |
| 2 | 花盆生长**时长** | `plant_list` 只有 `stage`，没有时间字段（`update_flowerpot` 只读 type/index/id/stage）⇒ 时长纯服务端 |
| 3 | 花盆收获**具体给什么** | 客户端只展示 `item_list`。`4101-4104/4006`(特产) 与 `2022xx`(RESOURCE sub6 花材) 是最合理的对应物【推测】 |
| 4 | 花材 → 花瓶装饰的**转换动作** | 客户端没有任何"把花放进花瓶"的协议；`client_change_decorate` 只吃 `decoration id` ⇒ 服务端直接授予【推测】 |
| 5 | 堆肥 `state` **各值的语义**与推进时长 | 可确证：`pgb` 刻度在 2/3/4；地面贴图 `>=3`/`==1`/其余。`state` 具体 = 什么阶段**无客户端证据** |
| 6 | 堆肥**产物**是什么 | 客户端无收取界面、无产物协议 ⇒ 服务端结算【推测：肥料类】 |
| 7 | `box_index` 是"正在发酵的那格"还是"当前选中的那格" | 可确证：该格 `state="disabled"` + 加灰 + 不可点，**其余格可编辑**（`@564253`）⇒ 更像"正在处理中" |
| 8 | 挂兜的 `clover` 是**每个挂兜各算**还是全局一个数 | 模型里**只有一个** `pocketData.clover`，且 `show_index` 决定显示哪个 ⇒ 只能按 `show_index` 那个算 |
| 9 | 挂兜怎么囤草（时间？旅行？） | 客户端无相关代码；`pocketData.desc` 只说"还能囤点草" |
| 10 | `mood` 如何变化、影响什么功能 | 客户端只用于工作台贴图（`very_angry` → 罢工图），无逻辑分支 |
| 11 | `replace_fur` 的**真正**上游语义 | 客户端只用作图鉴里的"正在替换"高亮（state 3）；`code 0/1` 的差别仅是加/不加这个 type。建议推 `[]` |
| 12 | `mate_list` 的元素含义 | 只在工作台界面用于扣减材料计数（`@611713`、`@640276`）⇒ 是"被客人占用的物品 id"【较有把握的推断】 |
| 13 | `TicketEvent`/`Decoration` 之外是否还有别的家具相关事件 | 已把 `TimerEvent.Type` 全表抄录（§11），21/22/1022/13 是与本子系统相关的全部 |
| 14 | `furnitureData.style` 与 `FurnitureBookPage` 的分组 | `modelType 0` 按 `type`（显示 `furnitureCommon[type]`）、`modelType 1` 按 `style`（显示 `furnitureCommon[1000+style]`）（`FurnitureBookPage.update`，`@614410`），已确证 |
| 15 | 客户端 `benchData`/`tumblerData_json` 是否被当数组 | `DataManager.TumblerData=i("tumblerData")`、`CompostData=t("compostData")`（`@407153`）；`TumblerLoader` 用 `TumblerData.get(e.id)`、`TumblerPathData.get(id)`，`CompostData.get(t)` ⇒ 前者是 list、后者是 dict，已在 `work/specdata/` 核实 |

---

## 14. 本次产出的可复现命令

```powershell
# 1) 导出任意客户端函数体（brace-balanced）
python work\tools\dump_handlers.py work\out_furn_spec1.txt furniture_putin_bench furniture_takeout_bench

# 2) 按【字符】偏移导出（和 occur.py/rx.py 报的偏移一致）
python work\tools\dump_chars.py 102500 114000 work\out_furniture_model.txt     # FurnitureModel 全量
python work\tools\dump_chars.py 873900 876200 work\out_mainview_furn.txt       # update_tumber/compost/pocket/flowerpot
python work\tools\dump_chars.py 848300 851200 work\out_benchscene.txt          # 工作台/嘟嘟/mood
python work\tools\dump_chars.py 633600 637200 work\out_shopctl.txt             # FurnitureShopController

# 3) 正则取证（结果写文件，避免 GBK 控制台报错）
python work\tools\rx.py work\out_r.txt "getFurnitureSlot|TumblerLoader|convertArray"

# 4) 解密 config.eab 并取表
python work\tools\eab_dec.py list work\run\web\resource\China\eab\config.eab
python work\tools\eab_dec.py get  work\run\web\resource\China\eab\config.eab flowerpotData_json work\specdata\flowerpotData_json
```

本次生成的中间产物（都在 `work/`，可随时重跑）：
`out_fm_a/b/c.txt`、`out_furnbook.txt`、`out_cargo.txt`、`out_cargo2.txt`、`out_mov.txt`、`out_compostv.txt`、
`out_mainview_furn.txt`、`out_benchscene.txt`、`out_shopctl.txt`、`out_tumbler.txt`、`out_tloader2.txt`、
`out_eab.txt`、`out_xxtea*.txt`、`out_rolemodel.txt`、`out_itemtype2.txt`、`out_itemid3.txt`、`out_fevt.txt`、
`out_conv4.txt`、`out_ufp.txt`、`out_ptab2.txt`、`out_config_idx.txt`，以及 `work/specdata/*_json`。
