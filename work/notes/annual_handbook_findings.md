# 手工品（HandCraftView）两条玩家反馈取证

- 日期：2026-09-12
- 工作目录：`H:\AI\frog`
- 客户端（发行物，只读）：`work/run/web/js/main.min.js.clean`（`main.min.js` 的还原文本；单行压缩，
  行号无意义，本文一律给出 `@byte` 偏移，可用 `work/probe/x_ctx.js` / `x_slice.js` 复核）
  - 布局/皮肤：`work/run/web/js/default.thm.js`（有行号）
  - 引擎源码：`work/run/engine/index.js`
  - 浏览器实际运行的引擎：`work/run/web/__offline-engine.js`（打包产物）
- **未修改** `dist/**`、未重新打包、未编辑 `work/run/engine/index.js`。新增探针在 `work/probe/`。

## 0. 复核工具

```
node work/probe/x_ctx.js <file> <regex> [before] [after] [maxHits]   # 正则命中点 + 字节偏移 + 上下文
node work/probe/x_slice.js <file> <start> <len>                      # 按字节区间 dump
node work/probe/x_offsets.js                                          # 本文引用的所有符号地址
node work/probe/x_annual_region.js                                    # 年度回顾区段里到底有没有图/日期

# 真页面复核（静态服务器必须在 work/run/web 下、端口 8187）
python -m http.server 8187 --bind 127.0.0.1          # 后台任务，结束必须杀
node work/tools/cdp_drive.js --url http://127.0.0.1:8187/index.html --port 9243 \
  --profile work/shots/p-annual --fresh --wait 26000 --settle 2000 \
  --step in:work/probe/<probe>.js --step shot:work/shots/handcraft/<x>.png
```

探针（全部为「IIFE 表达式、结尾不加分号」）：

| 探针 | 作用 |
| --- | --- |
| `work/probe/handcraft_live.js` | 打开真实手工品窗口，读两页的文字/图片源。（**方法上有坑**：它用 `__engine.dispatch` 造数据，而 `dispatch` 只回值、**不会把 payload 送进 `HandCraftModel`**，页面因此渲染的是启动时那份数据。第一版结论就是这样读出来的——数字仍可信（NaN 日期、state 4），但"我种的行有没有进 UI"不可信。后续探针一律改用客户端真实链路。) |
| `work/probe/handcraft_live2.js` | 改用 `core.SocketManage.send('pray_load_grays')`（客户端真实链路），复核日期与印章图 |
| `work/probe/handcraft_live3.js` | 三枚印章（finished #109 / state3 #4 / state1 #207）逐行对照，并逐一开详情卡片 |
| `work/probe/handcraft_detail_shot.js` | 在「已完成印章」的第一张卡上停留，供截图取证 |
| `work/probe/handcraft_fix_check.js` | **只改内存**（包装 `HandCraftModel.pray_load_grays`）验证两条修法；落盘文件一律不动 |
| `work/probe/handcraft_date_shot.js` | 把「已完成祈愿木牌」的详情卡留在屏幕上，供日期格截图 |
| `work/probe/x_craft_tables.js` | `stampData`/`prayData`/`prayBodyData`/`prayNoteData`/`Word`/`Collection`/`Item` 的字段普查 + **图片资源覆盖率**（表里每个 `index` 是否真有对应资源） |
| `work/probe/annual_view_shot.js` | 打开真年度回顾，逐页扫「有没有印章/祈愿物 的图」 |
| `work/probe/annual_chats.js` | 同上，另读 `chats`（回顾自己的文案数组） |
| `work/probe/annual_payload_probe.js` | 隔离实验：`__engine.state` 是不是活的、裸 `send` 与 `AnnualReviewModel.request()` 的差别 |
| `work/probe/annual_request_probe.js` | **走客户端自己的 `AnnualReviewModel.request()`** 复核 `stamp_num`/`wish_num`，并逐页读回顾的全部文案/图片/结构 |
| `work/probe/annual_craft_page_shot.js` | 停在含「…雕刻了N个印章，完成了N个祈愿物。」那一页，供截图对照 |

截图（**注意**：`--profile work/shots/p-annual` 配 `--fresh` 会把该目录整个删掉，
所以截图另存到 `work/shots/handcraft/`）：`stamp_blank_card.png`（空白卡）、`wish_date_nan.png`（NaN 日期）、
`stamp_list_wrong_art.png`（分页列表错图）、`stamp_fixed_card.png`（修法生效后）、
`tab1_1.png`、`tab2_1.png`、`top_craft.png`（标签/标题图裁切）、
`annual_craft_page.png`、`annual_review_page.png`、`annual_review_chat.png`（年度回顾对照）。

---

## 结论一：玩家看的是哪个界面

**判定：`HandCraftView`（手工品窗口），tab1 = 祈愿物（`PrayCraftPageView`），tab2 = 印章（`StampCraftPageView`）。
不是年度回顾、不是图鉴/手账、不是许愿池。**

> **第二轮补充**：年度回顾那条假设（「手工品是统称，所以可能是回顾里那一段」）已在真页面上逐页推翻——
> 回顾里 `craftArt: []`（没有任何手工品图）、`reviewToggleButtons: 0`（没有栏）、
> `reviewDateLikeTexts: []`（没有日期）。三样东西一个都不存在，所以那三条抱怨不可能落在它上面。
> 完整数据与截图对照见文末「第二轮补充线索」的线索 2 一节。

### 证据 1：窗口标题与两个分页标签是**图片**，OCR 直接读出「手工品 / 祈愿物 / 印章」

`HandCraftViewSkin` 的标题是一条图片 `top_craft_png`，两个分页按钮是纯图片皮肤
（`label = ""`，所以从字符串上永远搜不到「祈愿物」「印章」——这正是最初全树搜
`小问答/伴蛙前行/小插曲/周末` 与 `祈愿物/印章` 都落空的原因）：

- `work/run/web/js/default.thm.js:24400-24425` —— `albumBtn0`（skin `HandCraftViewSkin$Skin244`，图 `craft_type1_*`）、
  `specialtyBtn0`（skin `HandCraftViewSkin$Skin245`，图 `craft_type2_*`），二者 `t.label = ""`
- `work/run/web/js/default.thm.js:24435-24444` —— 标题图 `t.source = "top_craft_png"`
- `work/run/web/js/default.thm.js:24252/24266` —— `craft_type1_1_png` / `craft_type1_2_png`
- `work/run/web/js/default.thm.js:24294/24308` —— `craft_type2_1_png` / `craft_type2_2_png`
- 这四张图在 `resource/China/sheet/tab.json` 的图集帧里（不是 `default.res.json` 的 `resources[]`，
  所以按文件名搜 `craft_type*` 会误判为「素材缺失」——**实测 `RES.hasRes` 为 true，纹理 191x70，标签图正常**）。

把这四张帧和标题图裁出来用视觉提供方 OCR（`work/probe` 之外的 `work/tools/crop.py`）：

```
craft_type1_1.png -> "祈愿物"
craft_type2_1.png -> "印章"
top_craft.png     -> "手工品"
```

真页面截图（`work/shots/handcraft/stamp_blank_card.png`）复核同一件事：顶部标题「手工品」，
左下按钮「祈愿物」，右下按钮「印章」。

### 证据 2：这个窗口的唯一数据源是 `pray_load_grays`

- `work/run/web/js/main.min.js.clean` @byte 738666 `HandCraftView=function…`
  同段：`this.pageContainer.setPages([{render:PrayCraftPageView},{render:StampCraftPageView}])`、
  `this.c_typeGroup.setSelected(0)`
- @byte 131863 `HandCraftModel.pray_load_grays(e,t){ … this.prayCraftList=Utils.convertArray(e.wishs),
  this.stampCraftList=Utils.convertArray(e.stamps), this.boxCraftList=Utils.convertArray(e.boxes),
  this.makingPraycraft=e.wish_new, this.makingStampcraft=e.stamp_new … }`
- 即：**`祈愿物` 与 `印章` 是同一个窗口的两个分页，各自渲染 `wishs` / `stamps` 两份行数据。**

### 候选排除

- **候选 A（年度回顾）排除。** `work/probe/x_annual_region.js` 对年度回顾区段
  `main.min.js.clean 510468..521000` 全量扫描：
  - `.source = "…"` 赋值：**0 处**；`stamp_pic|pray_pic|wood[0-9]|paper[0-9]` 图名：**0 处**
    → 该视图里「印章 / 祈愿物」**只是一句文案**（@byte 515220 / 515258），没有图、没有条目、没有分页栏
  - 该区段唯一的日期是 @byte 514701 `DateFormat.format(1e3*t.create_time, "YYYY年MM月DD日")`，
    说的是「第一次旅行」，**与手工品日期无关**
  - 读到的载荷字段只有 `travel_num/pic_num/page_num/stamp_num/wish_num/fur_num/note_num/spe_num/
    col_num/first_col/story_num/first_story/visit_num/first_guest/clover/create_time/login_day`
    —— 没有 `time/date/make_time/stamp_time` 之类的手工品时间字段
  - 玩家说的是「栏」+「图片空白」，年度回顾两者都不成立 → 排除。
- **候选 B（手账/图鉴/每日任务）排除。** `手工品` 在 `Item`/`shopData`/`taskData` 里是**物品名/材料名/任务名**
  （如 `手工品制作工具`、`手工品材料`、任务 `手工品`），对应的是图鉴物品类型与任务列表；
  那里既没有 `祈愿物` 行，也没有 `stamp_time` 日期。玩家的「祈愿物/印章」在本客户端**只**出现在
  (a) 手工品窗口两个分页（图片标签）与 (b) 年度回顾文案，二者取其一只能是 (a)。
- **候选 C（许愿池）排除。** 许愿池的产物走 `wishingpool_load/wishingpool_wish`，界面是 `WishingPoolView`；
  手工品的 `祈愿物` 来自 `pray_load_grays.wishs`（`PrayCraftDB` / `PrayCraftBodyDB` / `PrayCraftNoteDB`）。
  两者只有 `wish` 这个英文词重合，**不是同一功能**（引擎里把 `wish_num` 取许愿池计数确实是错的，
  但那影响的是年度回顾，见 §3 附注）。

---

## 结论二：「祈愿物」的名称/日期问题

**判定：属实（日期错）——而且不是「偶发错值」，是这一格永远渲染 `NaN.NaN.NaN`。
玩家对「名字出错」的自我更正也成立：该卡片没有名字字段，出错的是日期格。**

### 证据 A：客户端读法（读的是 `stamp_time`，不是 `make_time`）

`PrayCraftDetailRender.dataChanged`（该类定义 @byte 740995），关键三行：

- `main.min.js.clean` @byte 741450：
  ```js
  this.l_date.text = core.DateFormat.format(1e3 * this.data.data.stamp_time,
                                             core.DateFormater["YYYY.MM.DD"]);
  ```
- @byte 741740：`this.data.data.stamp && 0 != this.data.data.stamp_time && (… i_stamp.source …)`
- @byte 741891：`var n = i.state.indexOf(this.data.data.stamp_state); …`

`l_date` 这个控件本身见 `default.thm.js:24569-24580`：
`t.text = "yyyy.m.d"`（皮肤占位文案），`t.y = 275`，宽 219，居中——就是玩家眼里的「那一行日期」。

字段出现次数（`main.min.js.clean` 全文）：

| 字段 | 出现次数 | 出现位置 |
| --- | --- | --- |
| `stamp_time` | **2** | 均在 `PrayCraftDetailRender.dataChanged`（@741450 / @741740） |
| `stamp_state` | **1** | @741891 |
| `make_time` | 8 | 全部在 `HandCraftModel`（红点/cookie，@130725、@131357…）与
`PrayCraftPageView.updateList` 的**排序**（@744482、@744655），**没有任何一处把它显示成日期** |

即：`make_time` 只用于排序与红点，**日期格读的是 `stamp_time`**。

### 证据 B：引擎写法（只发 `make_time`，从不发 `stamp_time`）

`work/run/engine/index.js:6777-6794`（`pray_load_grays`；行号会随并发编辑漂移，
**以代码文本为锚**）：

```js
pray_load_grays: () => {
  if (advanceCraft(nowSec())) save();
  const c = state.craft || {};
  const wishes = (c.wishes || []).slice();
  const stamps = (c.stamps || []).slice();
  const done = (list) => list.filter((r) => r.state > 3);
  ...
  return { wishs: wishes, stamps, boxes: ..., wish_new: ..., stamp_new: ... };
},
```

wish 行的构造在 `work/run/engine/index.js:1608-1620`（新开工）与 `1592`（完成时）：

```js
1592:      w.make_time = t;                       // finished now
1610:    c.wishes.push({ id: …, state: 1, body: '', paper: '',
1615:                    content: …, make_time: t + CRAFT_STAGE_SEC, u_id: c.seq });
```

**wish 行字段全集 = `{id, state, body, paper, content, make_time, u_id}`——没有 `stamp_time`。**
（引擎同处的注释 @6769-6774 也自认「`wish_new` 读作 `{make_time, u_id}`」「stamp 那个字段名是 `time`」，
说明作者核对过 `wish_new`/`stamp_new`，但漏掉了详情卡片真正显示的 `stamp_time`。）

### 证据 C：实测输出

`work/probe/handcraft_live2.js`（数据经客户端真实链路 `core.SocketManage.send('pray_load_grays')`
送入 `HandCraftModel`），种子：已完成祈愿木牌 `make_time = 1700000000`：

```
"wish0_fields": ["id","state","body","paper","content","make_time","u_id"]
"dateIf_make_time": "2023.11.15"          <- 若读 make_time，本应显示这个
"detail_found": true
"detail_l_date": "NaN.NaN.NaN"            <- 实际渲染
"detail_images": ["frame_small_png","pray_show_png","pray_line_png","null",
                  "wood1_0_png","paper1_1_png","word_405_png", ...]
```

`work/probe/handcraft_live.js`（另一条链路）同样得到 `"detail_l_date": "NaN.NaN.NaN"`，
并且 `DateFormat.format(1e3 * undefined, "YYYY.MM.DD") === "NaN.NaN.NaN"`、
`DateFormat.format(1e3 * 1700000000, "YYYY.MM.DD") === "2023.11.15"`（同一探针内对照）。
机制：`core.DateFormat.format` = `cache.setTime(t)` 后套格式化器（`main.min.js.clean` @byte 347200），
`setTime(NaN)` → Invalid Date → 逐段输出 `NaN`。

截图取证 `work/probe/handcraft_date_shot.js` → `work/shots/handcraft/wish_date_nan.png`
（已完成木牌、`make_time = 1700000000`，探针回读 `"l_date":"NaN.NaN.NaN"`、
`"expectedIfReadMakeTime":"2023.11.15"`）。视觉复核原文：卡内日期位**就是** `NaN.NaN.NaN`，
木牌图（木桩+绿叶）正常显示，下方两排图标旁是空的下划线文字位。
`l_date` 的皮肤占位文案是 `"yyyy.m.d"`（`default.thm.js:24573`），
即屏幕上那串乱码是运行时算出来的，不是皮肤占位没被替换。

### 根因

引擎下发的手工品行缺 `stamp_time` 字段，而 `PrayCraftDetailRender` 的日期格只读 `stamp_time`；
`1e3 * undefined = NaN`，日期格因此恒为 `NaN.NaN.NaN`。引擎手里其实有时间源（`make_time`，
完成时被赋成「完成那一刻」，`work/run/engine/index.js:1592`），只是没以客户端要的字段名发出。

（附带同源缺口，同一张卡片：`stamp` / `stamp_state` 也从不下发，所以
`i_stamp` 永远不赋值 → 木牌上「盖的印章图案」一栏为空，见实测 `"detail_i_stamp_source": "null"`、
`detail_images` 里的 `"null"`。这一条**我判为「同因但未确认是玩家所指」**：玩家只提了日期。）

### 修法（补丁建议，未落盘）

目标文件：`work/run/engine/index.js`。唯一改动点是 `pray_load_grays` 下发前的行整形
（当前 6777-6794）；建议在 `const wishes = …` 之后插入一次映射，**不动持久化字段**：

```js
pray_load_grays: () => {
  if (advanceCraft(nowSec())) save();
  const c = state.craft || {};
  /* 客户端的祈愿木牌详情卡（PrayCraftDetailRender.dataChanged）日期格读的是 `stamp_time`，
     而我们从没发过它 —— 1e3*undefined = NaN，日期格恒为 "NaN.NaN.NaN"。
     我们手里唯一的时间源是 `make_time`（完成那一刻被赋成 nowSec()，见 advanceCraft）。
     注意：`stamp`/`stamp_state`（同一张卡上的印章图案）同样缺失，本补丁不发它们，
     于是 i_stamp 保持空白(而不是错图)，与今天行为一致、不引入回归。 */
  const wishRows = (c.wishes || []).map((w) => (w.stamp_time == null
    ? { ...w, stamp_time: Number(w.make_time) || 0 }
    : w));
  const wishes = wishRows;
  const stamps = (c.stamps || []).slice();
  ...
```

要点/风险（必须由代码所有者裁决）：

1. `stamp_time` 与 `make_time` 的**原始语义差别无法从快照恢复**——客户端只在日期格和
   `data.stamp && 0 != stamp_time` 的守卫里用到 `stamp_time`，没有第二处可反推。
   取「完成时间」是**我们的判断**，应像其他自设计项一样在 `dist/README.txt` 里披露。
2. 未完成的行也会发 `stamp_time = make_time`（= 预计完成时刻）。**不要发 0**：
   `0 != stamp_time` 的守卫会失败（木牌印章栏永远空白），且 `DateFormat(0)` 会显示 1970.01.01。
3. 若日后要补 `stamp`/`stamp_state`，必须先确认「木牌盖哪枚印章」的原版规则；快照里没有依据。

### 验证（已做，只改内存）

`work/probe/handcraft_fix_check.js` 包装 `HandCraftModel.pray_load_grays` 注入
`stamp_time = make_time`，其余不动：

```
"l_date_after_fix": "2023.11.15"          <- 由 NaN.NaN.NaN 变为正确日期
"modelWishes": [ { …, "make_time":1700000000, "u_id":9001, "stamp_time":1700000000 } ]
```

---

## 结论三：「印章」图片空白

**判定：属实——空白的是「印章」分页里点开的那张详情卡片（`StampCraftDetailView` 的 item 卡）。
另外同一根因还造成分页**列表**里的印章行永远是 1 号印章的图（错图，不是空白）。**

### 证据 A：客户端读法（图由 `row.state` 在 `stampData.state` 中的下标决定）

`StampCraftItemRender.dataChanged`（类定义 @byte 748445），关键一句 @byte 748739：

```js
var i = t.state || 0,
    n = Tabikaeru.DataManager.instance().StampCraftDB.get(t.id);
if (n) { var r = n.state.indexOf(i);
         r >= 0 && (this.i_layer0.source = Tabikaeru.path.formatPathImage(n.stamp_pic[r]),
                    this.i_layer1.source = Tabikaeru.path.formatPathImage(n.pattern_pic[r])); }
```

- `StampCraftDB` = `stampData` 表：`main.min.js.clean` @byte 406572 `this.StampCraftDB=i("stampData")`
- `stampData` 每一行声明 `state: [1,2,3]`，配 3 张 `stamp_pic` / 3 张 `pattern_pic`
  （`work/run/engine/data/gamedata.json` → `tables.stampData`，27 行 = 1..9/101..109/201..209，
  **每行都是 `[1,2,3]`，没有 state 4**）
- 所以 **`row.state` 一旦不在 `[1,2,3]` 内 → `r = -1` → 两个图层都不赋值。** 此时画面取决于皮肤有没有兜底：

| 皮肤 | 图层初值 | `r = -1` 的结果 |
| --- | --- | --- |
| 分页**列表**行 `StampCraftPageSkin$Skin253$Skin254`（`default.thm.js:25071` `t.source="stamp_pic1_1_png"`、`25082` `t.source="stamp1_1_png"`） | **硬编码成 1 号印章的图** | **不空白，但永远是 1 号印章的图（错图）** |
| 详情**卡片** `StampCraftItemSkin`（`default.thm.js:24856-24873`，`i_layer0`/`i_layer1` 无 `source`） | 空 | **空白（只剩 `item_back_png` 的纸）** |

详情卡的卡片皮肤绑定见 `default.thm.js:24931-24940`（`g_stamp = new StampCraftItemRender(); t.skinName = "StampCraftItemSkin"`），
外层列表见 `default.thm.js:24984-24991`。

进详情时卡片是**按 state 倒着铺**的——`StampCraftPageView.onItemTap`（@byte 750061）：

```js
for (var t = e.item, i = [], n = t.state; n >= 1; n--) { var r = Utils.createObejctBy(t); r.state = n; i.push(r); }
core.PageManage…addViewControl(StampCraftDetailViewController, …, { data: i })
```

即 `state = 4` 的印章 → 第一张卡就是 state 4 → **打开即空白**。

### 证据 B：引擎写法（把印章推到 state 4，而表只认到 3）

`work/run/engine/index.js:1599-1604`：

```js
for (const s of c.stamps) {
  if (s.state > 3 || t < s.time) continue;
  s.state += 1;
  s.time = s.state > 3 ? t : t + CRAFT_STAGE_SEC;
  changed = true;
}
```

完成判定用的哨兵是 `state > 3`（`work/run/engine/index.js:6782`
`const done = (list) => list.filter((r) => r.state > 3)`），所以**已完成的印章被留在 `state = 4`**。
对祈愿木牌这没问题（`prayData` 的 `state` 是 `[1,2,3,4]`，4 合法），对印章就是越界值。

### 证据 C：实测输出

`work/probe/handcraft_live3.js`（客户端真实链路喂数据；`stamp_pic`/`pattern_pic` 由**客户端自己的**
`StampCraftDB` 读出）：

```
"tableShape": [ { "id":109, "state":[1,2,3], "stamp_pic":["stamp109_1","stamp109_2","stamp109_3"],
                  "pattern_pic":["stamp_pic109_1", …] }, { id:4 … }, { id:207 … } ]

分页列表（同一段代码、只有 state 不同 → 差异完全由 state 决定）
 { "i":0, "id":109, "state":4, "expectedIndex":-1,
   "rendered_stamp_art":["stamp_base_png","stamp_place_png","stamp_pic1_1_png","stamp1_1_png"] }   <- 错图（1 号的图）
 { "i":1, "id":4,   "state":3, "expectedIndex":2,
   "rendered_stamp_art":["stamp_base_png","stamp_place_png","stamp_pic4_3_png","stamp4_3_png"] }   <- 正确
 { "i":2, "id":207, "state":1, "expectedIndex":0,
   "rendered_stamp_art":["stamp_base_png","stamp_place_png","stamp_pic207_1_png","stamp207_1_png"] } <- 正确

详情卡片
 { "id":109, "cards":[
     { "card":0, "dataState":4, "i_layer0":"null", "i_layer1":"null", "i_layer0_hasTexture":false,
       "allImages":["frame_small_png","item_back_png","null","null"] },      <- 空白
     { "card":1, "dataState":3, "i_layer0":"stamp109_3_png", "i_layer1":"stamp_pic109_3_png",
       "i_layer0_hasTexture":true, "allImages":[…,"stamp109_3_png","stamp_pic109_3_png"] } ] }
 { "id":4, "cards":[ {dataState:3, stamp4_3_png …}, {dataState:2, stamp4_2_png …} ] }             <- 无空白
```

`work/probe/handcraft_detail_shot.js` 复现同一空白并留下截图
`work/shots/handcraft/stamp_blank_card.png`；视觉复核结论：标题「手工品」，左下「祈愿物」，
右下「印章」，**中央卡片只有一个空白的白色方块（四周是卡片边框），卡内没有任何印章图**。
分页列表那三行的实际外观另见 `work/shots/handcraft/stamp_list_wrong_art.png`
（`handcraft_live3.js` 末尾的实景；该截图里能看到「1 号印章的图」与「自己的图」并排出现，
正好对照上表的错图/正确两行）。

对照 `work/shots/handcraft/stamp_fixed_card.png`（同一场景 + 下面那条修法）：卡内出现木质印柄与
蓝色印纹，确认空白就是这一格。

### 为什么「空白」只能在详情卡这一处（而不是分页列表）

`StampCraftDB` 在整个客户端只有 4 处使用（@406572 注册、@741809 木牌印章栏、@748704 印章 item 渲染、
@821907 `MainIn.checkHandCraft` 桌面 `desk_pic` 图标）；其中 `desk_pic` 在 `stampData` 里恒有值、
且桌面图标走的是 `stamp_new`。**能出现「空图」的只有详情卡片**——分页列表因皮肤硬编码 1 号图，
只会「错」不会「空」。所以玩家这句「图片为空白」与实测唯一的空白位置一致。

### 根因

引擎把印章完成的哨兵值写成 `4`，而 `stampData` 的 `state` 只有 `[1,2,3]`；
客户端用 `state.indexOf(row.state)` 取图，`-1` 时**什么都不设**：详情卡皮肤没有兜底图 → 空白；
分页列表皮肤把 `stamp1_1`/`stamp_pic1_1` 写死成初值 → 恒显 1 号印章的图。

### 修法（补丁建议，未落盘）

**首选：在 `pray_load_grays` 下发时把印章 state 夹到表内**（当前 6777-6794 一段内完成，
既修新存档也修已有存档，不需要迁移持久化数据）：

```js
pray_load_grays: () => {
  if (advanceCraft(nowSec())) save();
  const c = state.craft || {};
  /* stampData 每行只声明 state [1,2,3]（3 张 stamp_pic / 3 张 pattern_pic），
     但 advanceCraft 用 state > 3 当完成哨兵，于是已完成的印章被留成 4。
     StampCraftItemRender 用 n.state.indexOf(row.state) 取图，-1 时两个图层都不赋值：
     详情卡皮肤无兜底图 -> 卡片空白；分页列表皮肤硬编码了 1 号图 -> 恒显 1 号印章。
     夹到表内取值即可，不动持久化（advanceCraft 的 state>3 哨兵继续有效）。 */
  const STAMP_MAX = Math.max.apply(null, (gamedata.tables.stampData
    && Object.values(gamedata.tables.stampData)
      .reduce((a, r) => a.concat(r.state || []), [])) || [3]);
  const stamps = (c.stamps || []).map((s) => (Number(s.state) > STAMP_MAX
    ? { ...s, state: STAMP_MAX } : s));
  ...
```

（`STAMP_MAX` 应像 `CRAFT_STAGE_SEC` 一样提成模块级常量只算一次，别放在每次下发里重算。）

**备选（更“正统”但牵连更多，需同时改三处，务必一起改）**：让 `advanceCraft` 在 3 就收工，
并在 `pray_load_grays` 里给印章单独用 `>= 3` 判定完成：

- `1599-1604`（印章循环）：`if (s.state >= 3 || t < s.time) continue;` → `s.state += 1;
  s.time = s.state >= 3 ? t : t + CRAFT_STAGE_SEC;`
- `1621`（现 @1621 附近，`if (atHome && stampIds.length && …)`）：新开工守卫
  `!c.stamps.some((s) => s.state <= 3)` 要改成 `!c.stamps.some((s) => s.state < 3)`
- `const done = …`（现 @6782）：`done` 现在祈愿与印章共用。**印章必须换成 `state >= 3`**，否则
  `stamp_new` 恒为 `false`，会连带打断两处：
  - `HandCraftModel.updateRedot()`（@byte 131357 读 `getMakingStampCraft().time` 点红点）
  - `MainIn.checkHandCraft()`（@byte 821806 `StampCraftDB.get(e.id).desk_pic` → 桌面印章图标）

  所以 `done` 应拆成 `doneWish = r => r.state > 3` / `doneStamp = r => r.state >= 3`。

**改客户端是不可能的**（`main.min.js` 是发行物），所以只能是引擎侧夹值。

### 验证（已做，只改内存）

`work/probe/handcraft_fix_check.js` 包装 `HandCraftModel.pray_load_grays`，把印章
`state` 夹到 `min(3, state)`：

```
"modelStamps": [ { "id":109, "state":3, "time":1700000000, "u_id":9101, "stateRaw":4 }, … ]
"detailCards": [ { "card":0, "dataState":3, "i_layer0":"stamp109_3_png", "i_layer1":"stamp_pic109_3_png",
                   "hasTexture":true },
                 { "card":1, "dataState":2, "i_layer0":"stamp109_2_png", "i_layer1":"stamp_pic109_2_png",
                   "hasTexture":true } ]
"rowArt": [ { "id":109, "state":3, "art":[…,"stamp_pic109_3_png","stamp109_3_png"] },     <- 由 1 号的图变为自己的图
            { "id":203, "state":1, "art":[…,"stamp_pic203_1_png","stamp203_1_png"] } ]
```

截图 `work/shots/handcraft/stamp_fixed_card.png`：卡片出现印章图，不再空白。

---

## 附注 / 未确认项（不要当结论用）

1. **「名字出错」**：玩家已自我更正为日期。复核结果一致——该卡片没有名字控件；
   祈愿物的「名字」是 `content` 指向的 `prayNoteData.info`（`PrayCraftPageItemRender` 定义 @byte 745419，
   其 `dataChanged` @byte 745707 读 `PrayCraftNoteDB.get(this.data[0].content)`；详情卡 @byte 741592
   读进 `l_note`，实测渲染出 `word_405_png`…等字图），
   引擎全程下发的是合法 `prayNoteData` id（`work/run/engine/index.js:1615`），**未复现名字错**。
   不排除原版按阶段换文案而我们只用一张表；快照内无依据，**判为无法确认，已到此为止**。
2. **木牌上「盖的印章」图始终空白**（`stamp` / `stamp_state` 未下发，实测 `detail_i_stamp_source:"null"`）：
   机制已确认，但是否属于玩家所指**未确认**（玩家只说日期）。
3. **祈愿木牌缩略图的 `i_layer0` 永远是空**：全文只有一处给 `i_layer0` 赋值
   （@748739，即印章那个），`PrayCraftItemSkin`（`default.thm.js:24464`）的 `i_layer0` 无人赋值。
   木牌三层里第 1 层空、`i_layer1`(body=`wood1_0_png`)、`i_layer2`(paper=`paper1_1_png`) 正常，
   实测卡片能正常显示木牌。**是否算缺陷无法确认**（可能该层本就留给未实现的效果）。
4. **年度回顾的 `stamp_num` / `wish_num` 是另一处真实缺陷，但与这两条反馈无关**：
   它只影响年度回顾文案「…一共雕刻了{0}个印章，完成了{0}个祈愿物」，
   而该视图没有图也没有手工品日期。取证期间此文件被另一写入方并发修改，
   现已改为 `stamp_num: finished(craft.stamps)` / `wish_num: finished(craft.wishes)`
   （`work/run/engine/index.js:3518-3519`）。**第二轮已端到端功能验证通过**
   （`AnnualReviewModel.request()` → `stamp_num: 2 / wish_num: 2`，页面原文明文正确），
   详见文末「第二轮补充线索」线索 1。**本条不重复修**；仅剩一处旧注释待清（约 `:6361`）。
5. **并发写入警告（重要）**：`work/run/engine/index.js` 在本会话期间被改动多次
   （22:15:16 → 22:19:36，7516 行 → 7643 行；`pray_load_grays` 从 6587 → 6690 → 6777 一路下移）。
   最后一次核对（22:19:36 版）的锚点：`advanceCraft` @1558、`w.make_time = t;` @1592、
   印章循环 @1599-1604、`pray_load_grays` @6777、`const done = …` @6782。
   这三处**至今仍是未修状态**（本文两条缺陷仍然存在）。行号会继续漂移，
   落地补丁前请以代码文本重新定位，别照抄行号。
6. **打包产物已被并发写入方重建，缺陷复核仍成立**：`work/run/web/__offline-engine.js`
   在我实测期间被重建过（21:55 → **22:23:14**，1,716,774 → 1,727,792 字节，内含别人修好的
   `stamp_num: finished(craft.stamps)` @71927）。对**这一份最新产物**重新核对：
   - `s.state += 1;` @70039、`s.time = s.state > 3 ? …` @70040 → 印章**仍**被推到 `state = 4`
   - `pray_load_grays` @75215、`const done = …` @75220、`wishs: wishes,` @75224
   - 全文 `stamp_time` 出现次数 = **0** → 祈愿行仍不带该字段
   即**本文两条缺陷在最新产物里都还没修**。（产物按行号定位；它是有缩进的打包文本，行号可用。）
   注意：改 `work/run/engine/index.js` 后**必须重新打包**才会在页面上生效（本次按要求未打包）。
7. **未复现项**：分页标签图 `craft_type*_png` 一度疑似「素材缺失」，已排除——
   它们是 `sheet/tab.json` 的图集帧，实测纹理 191x70 正常显示。

## 第二轮补充线索：逐条纳入（线索 1–4）

对方给的额外线索是：表里确实有 `stampData`/`prayData`/`prayBodyData`/`prayNoteData`/`Word`/`Collection`；
「手工品」是印章+祈愿物的统称，所以玩家可能在看**年度回顾**；日期要查表里的时间字段或
`core.Time.getServerTime()`；图片空白要查 `formatPathImage` 的入参与该资源是否存在。
下面逐条给出核实结果——**1、3、4 三条被证实（并修正了 1 的一句注释），2 条的方向被推翻。**

### 线索 1（表确实存在；`stamp_num` 的注释错）→ **证实，且已功能验证**

`work/probe/x_craft_tables.js` 的字段普查（`work/run/engine/data/gamedata.json` → `tables`）：

| 表 | 行数 | 字段 |
| --- | --- | --- |
| `stampData` | 27 | `id, type, dimension, state, stamp_pic, pattern_pic, desk_pic` |
| `prayData` | 7 | `id, type, state, wood_body, paper, desk_pic` |
| `prayBodyData` | 70 | `id, type, pray_pic` |
| `prayNoteData` | 35 | `id, info, show_pic` |
| `Word` | 197 | `id, img, type` |
| `Collection` | 62 | `id, type, name, info, info2, place, img` |
| `Item` | 411 | `id, type, sub_type, name, info, img, own_num, price, spend` |

- `state` 取值：**`stampData` 全部 27 行都是 `[1,2,3]`**（单一取值）；`prayData` 是 `[1,2,3,4]`。
- **没有「印章本 / 祈愿物图鉴」表**：`tables` 里含 `stamp|pray` 的只有上面四张；
  `Collection` 是纪念品图鉴（`name`/`place`），`Word` 是日记字图（`word_405` 这种），与印章无关。
  所以旧注释「这个包里没有印章本」**对了一半**（确实没有独立的印章本表），
  但结论错在把「没有印章本」当成「没有印章数据」——印章数据就是 `stampData` + `state.craft.stamps` 这份制作历史。
- `stamp_num`/`wish_num` **应该填什么**：客户端那句文案见 `main.min.js.clean` @byte 515094/515181/515220，
  它把两个数放在「认真做手工」的同一句里，语义就是**玩家做过多少枚印章 / 多少个祈愿物**，
  即 `state.craft.stamps` / `state.craft.wishes` 里 **`state > 3`（已完成）的行数**（与 `pray_load_grays`
  的完成口径一致，见 `work/run/engine/index.js` 的 `const done = …`）。
  不能取许愿池的计数：那是另一个功能（三叶草许愿），与「雕刻印章 / 完成祈愿物」无关。
- **实测（走客户端自己的路径）** `work/probe/annual_request_probe.js`：给存档塞 2 枚已完成印章 +
  2 个已完成祈愿物，然后调 `AnnualReviewModel.request()`：

```
"cacheBefore": { … "stamp_num": 0, "wish_num": 0 … }     <- 启动那一刻的真实值（当时确实没有成品）
"cacheAfter":  { … "stamp_num": 2, "wish_num": 2 … }     <- 刷新后
"craftLine": "一个人在家的时候，小青蛙也有在认真做手工，一共雕刻了2个印章，完成了2个祈愿物。有了这些，旅行好像不会再迷路了。"
```

  这条 `craftLine` 是**运行中页面读出来的玩家可见原文**，数字正确 → 该问题已由并发写入方修好
  （`annualPayload()` 现为 `stamp_num: finished(craft.stamps)` / `wish_num: finished(craft.wishes)`，
  `work/run/engine/index.js:3518-3519`），**判定为「已修复且验证通过」，本文不重复修**。
- **残留清理项**：同一文件里许愿池那处注释还是旧的
  （`W.wishes = (W.wishes || 0) + 1;   // counted for the 年度总结 wish_num`，约 `:6361`）——
  `wish_num` 现在已不来自许愿池，这句注释应当删掉/改写，否则下一个人会被它再带偏一次。
- **探针方法坑（重要）**：`AnnualReviewModel` **没有** `addProtocolCallback("annual_load")`，
  它只在自己的 `request()` 里 `send("annual_load", new core.Action2(t => this.cacheData = t))`
  （`main.min.js.clean` @byte 83536）。所以裸 `core.SocketManage.send('annual_load', …)`
  只会把回复给我的回调，**`cacheData` 仍是启动时那份**——我第一版探针就因此误得 `stamp_num: 0`。
  要复核这个视图必须调 `AnnualReviewModel.request()`（`work/probe/annual_payload_probe.js` 记录了这个隔离实验）。

### 线索 2（玩家看的是「年度回顾里那一段」）→ **推翻。已用运行页面坐实**

「手工品」确实是印章+祈愿物的统称，这一点判断是对的；但**统称的出处不是只有年度回顾文案**——
它是这个窗口的**标题图本身**：`top_craft.png` OCR = 「手工品」，同一窗口两个标签图 OCR = 「祈愿物」「印章」。
这才是玩家那句话的 1:1 对应物（标题 + 标签），而不是回顾里的一句散文。

把年度回顾打开来对照，证据是三方面的（`work/probe/annual_request_probe.js`，`craftArt` 一栏是关键）：

```
page 1（含手工品那句的那一页）
  chatLines: [ …共 12 条散文句… ]，其中第 3 条 = craftLine（上面那句）
  craftArt: []            <- 绑定到 stamp/pray/wood/paper 制作素材的图片：0 张
  nImages: 58             <- 全部是 UI/背景/纸张框，没有一件手工品图
page 0 / 2 / 3: craftArt 也全是 []

reviewListRows: 0          <- 全视图没有任何 eui.List 行（没有「一条一条的条目」）
reviewToggleButtons: 0     <- 全视图没有任何 ToggleButton（没有「栏」/分页标签）
reviewDateLikeTexts: []    <- 全视图没有任何 YYYY-MM-DD 形式的日期
```

静态侧也一致：`work/probe/x_annual_region.js` 扫 `main.min.js.clean 510468..521000`，
`.source = "…"` 赋值 **0** 处，`stamp_pic|pray_pic|woodN|paperN` **0** 处。

截图对照：
- `work/shots/handcraft/annual_craft_page.png`（年度回顾含手工品那句的那页）：视觉复核为
  「对话框 + 向上滑动」的**散文翻页**，无标签、无缩略图网格、无日期。
- `work/shots/handcraft/stamp_blank_card.png`（手工品窗口）：标题「手工品」，左下「祈愿物」，右下「印章」，
  中央卡片空白。

**判定的逻辑闭环**：玩家说「栏」+「图片空白」+「日期出错」。
年度回顾里 —— 没有栏（`toggleButtons: 0`）、没有图（`craftArt: []`）、没有日期（`reviewDateLikeTexts: []`），
三样东西**一个都不存在**，所以这三条抱怨不可能落在它上面；
手工品窗口里 —— 有栏（两个标签图）、有图（会空白）、有日期格（会 NaN），三样**全部**存在。

补充一句为什么文字上找不到「印章/祈愿物」：这两个词在手工品窗口里是**图片字**，
在年度回顾里是**散文里的一句话**，所以按字符串全树搜只能搜到后者
（`main.min.js.clean` @byte 515220/515258），这也是这个误会最初产生的原因。

### 线索 3（日期：查表里的时间字段 / `getServerTime()`）→ **证实「不是本地时间、不是表字段」**

- **表里没有任何日期字段**：`work/probe/x_craft_tables.js` 对上述七张表做 `/time|date|day|create|start|end/i`
  字段扫描 → `stampData / prayData / prayBodyData / prayNoteData / Word / Collection` **全部 NONE**
  （`Item` 只有 `spend`，那是售价）。而客户端读的字段名是 `stamp_time`
  （`main.min.js.clean` @byte 741450，全文只出现 2 次）。
  → 结论：**这个日期只可能来自服务端下发的行数据，不可能来自任何表、也不可能是本地时间。**
- **不是 `core.Time.getServerTime()`**：`getServerTime()` 在手工品这条链路上只出现 2 次，
  都在 `HandCraftModel.updateRedot()`（@byte 131150 / 131339），用途是
  `getServerTime() > n.time` / `> r.make_time`——**点红点的时间比较**，从不进入任何显示文本。
  显示日期的那一行只有 `DateFormat.format(1e3 * row.stamp_time, …)`（@741450）。
- 所以「字段名不对 / 恒为 0」这个假设方向是对的：**引擎就是没发这个字段**
  （实测 `wish0_fields` 无 `stamp_time`，日期格 `NaN.NaN.NaN`）。详见结论二。

### 线索 4（`formatPathImage` 入参 + 资源是否存在）→ **证实：资源不缺、字段名不错，错的是下标**

`formatPathImage` 的定义（`main.min.js.clean` @byte 1260778，`Tabikaeru.path`）：

```js
function i(e){
  return "string" == typeof e
    ? (-1==e.indexOf("_png") && -1==e.indexOf("_jpg") ? (e ? e+"_png" : "") : (e||""))
    : (e ? e.index + "_png" : "");
}
```

- 入参就是表里的对象：印章 `stampData[id].stamp_pic[r]` / `pattern_pic[r]`（各形如 `{"index":"stamp109_3","src":"Scene/Craft/Stamp"}`），
  祈愿物 `prayBodyData[body].pray_pic`（形如 `{"index":"wood1_0","src":"Scene/Craft/Pary"}`）。
  规则 = **`index + "_png"`**；入参为空时返回 `""`（=`eui.Image.source=""`，静默变空图，不抛错）。
- **资源覆盖率**（`work/probe/x_craft_tables.js`，同时查 `default.res.json` 的 `resources[]` **和** `sheet/*.json` 图集帧）：

```
stampData refs checked=189  missing=0
pray refs    checked=77   missing=0
```

  → **印章/祈愿物用到的每一个资源名在本包里都存在**（`desk_pic`、`stamp_pic`、`pattern_pic` 全类）。
  运行期也验证过：`stamp_pic109_1_png` / `stamp109_1_png` / `stamp_pic4_3_png` … 都成功加载（纹理 150x150 / 200x200）。
- 所以「图片空白」**不是素材缺失、也不是字段名写错**，而是
  `n.state.indexOf(row.state)` 返回 **-1** 时客户端**什么都不设**（`r >= 0 && (…)`），
  而详情卡皮肤的图层没有兜底 `source` → 空。详见结论三（含 state 4 越界的根因）。

## 环境清理（第二轮结束后复核）

- 两个 `python -m http.server 8187` 后台任务**均已杀**；`-State Listen` 计数为 0。
- 命令行含 `p-annual` 的 `msedge` 进程为 0；未触碰使用者的其余 msedge；未使用 8080。
- 未修改 `dist/**`；未重新打包；未编辑 `work/run/engine/index.js`。

