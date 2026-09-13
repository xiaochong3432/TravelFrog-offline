# 玩家反馈两条 bug 的取证笔记：回家行李错位 / 旅行时帽子还在家

调查时间：2026-09-12 22:0x–22:2x（本机）
调查范围：只读 + 真页面实测；**没有**改 `dist/**`、**没有**改 `work/run/engine/index.js`、**没有**重新打包。

> ⚠️ 过程中的重要发现：`work/run/engine/index.js` 在我调查期间被**另一个进程改动过**
> （22:15:16 343270 B → 22:19:36 347568 B；read 工具报的总行数 7516 → 7627 → 7714）。
> 本笔记引用的行号是 22:2x 时点的值，且每处都附了**代码原文**，以原文为准。
> 会话中还有别的 msedge（`--user-data-dir=H:\AI\frog\work\shots\p-annual`）在跑，不是我的，我没有碰。

---

## 1. 结论速览

| # | 玩家反馈 | 判定 | 根因所在层 |
|---|----------|------|-----------|
| 1 | 回家时行囊里"食物格是水壶、护身符格是雨伞"，和桌面上的东西对不上 | **属实** | 引擎（`returnFrog` 回填行李格时不看槽位类型） |
| 2 | 蛙蛙旅行时帽子还在家里 | **属实** | 客户端（`MainInView.updateFlogStatus` 没有 else；`MainInController` 不订阅 `RoleEventType.loadRole`）；引擎**无法**修，只能改客户端 |

---

## 2. 条 1：回家行李错位

### 2.1 客户端读法（唯一可靠依据：槽位类型是写死的，贴图只看数组下标）

`work/run/web/js/main.min.js.clean:12 col 26228` —— 4 格行囊的槽位语义（`Tabikaeru.BagItem`）：

```js
e[e.NONE=-1]="NONE",e[e.LunchBox=0]="LunchBox",e[e.Amulet=1]="Amulet",
e[e.Tool_1=2]="Tool_1",e[e.Tool_2=3]="Tool_2",e[e.MAX=4]="MAX"}(n=e.BagItem||(e.BagItem={}))
```

同处 `col 26522` —— 8 格桌子 `DeskItem`：`LunchBox_1=0, LunchBox_2=1, Amulet_1=2, Amulet_2=3, Tool_1..Tool_4=4..7`。

`work/run/web/js/main.min.js.clean:13 col 6004` —— `Bag.renderItem`（4 格行囊，`Bag.exml`）：

```js
this.items=[
  {type:Tabikaeru.DataType.ItemType.LunchBox,image:this.item0},   // slot0 = 便当
  {type:Tabikaeru.DataType.ItemType.Amulet,  image:this.item1},   // slot1 = 护身符
  {type:Tabikaeru.DataType.ItemType.Tools,   image:this.item2},   // slot2 = 道具
  {type:Tabikaeru.DataType.ItemType.Tools,   image:this.item3}];  // slot3 = 道具
...
this.itemModel.getBagDataList().forEach(function(t,i){
  if(-1!==t){
    var n=Tabikaeru.DataManager.instance().ItemDB.get(t);
    if(!n)return;
    ...
    e.items[i].image.source=Tabikaeru.path.formatPathImage(n.img)   // ← 只按下标取图，无类型校验
  }
})
```

→ 槽位 0/1 的**语义**恒为"便当/护身符"，画什么**只看 `bagDataList[0]/[1]` 里是哪个 item id**。
（`Bag.renderItem` 只被 `Bag.onAddToStage` 调一次，故必须重开界面才看得到新内容。）

`work/run/web/js/main.min.js.clean:5 col 15166` —— `ItemModel.item_load_items`：

```js
this.bagDataList=e.bag,this.deskDataList=e.desk,this.bagLock=e.bag_completed||!1,...
```

`work/run/web/js/main.min.js.clean:13 col 1141` —— 4 格行囊页**只在 isHome 时**才建（`BagTable.onComplete`）：
`if(t||e.getModel(DrawingModel).data.state==DrawingState.visit){var c=new Bag(...),e.bag=c,...}`（`t=Tabikaeru.Game.instance().isHome`）。

### 2.2 引擎写法

`work/run/engine/index.js:2240-2265`（`provisionTrip`，出门时结算）：

```js
2240:  function provisionTrip() {
2251:    if (!take(state.items.bag, 'bag')) take(state.items.desk, 'desk');
2253:    const carried = state.items.bag.filter((id) => id !== -1);   // ← 丢掉槽位下标
2254:    const amulet = carried.find((id) => isType(id, ITEM_TYPE_AMULET));
2255:    const tools = carried.filter((id) => isType(id, ITEM_TYPE_TOOLS)).length;
2256:    const carryBack = carried.filter((id) => {
2257:      const it = ITEM_BY_ID.get(id);
2258:      return !it || it.spend !== 1;            // keep durable gear(spend=0 的耐用品)
2259:    });
2260:    state.items.bag = state.items.bag.map(() => -1);
2261:    return {
2262:      lunch, lunchFrom, amulet: amulet === undefined ? -1 : amulet,
2263:      tools, carryBack, stray: lunch === -1, at: nowSec(),
2264:    };
2265:  }
```

`work/run/engine/index.js:2352-2366`（`returnFrog`，回家时回填）：

```js
2359:    // durable gear comes home; consumables were used up at departure
2360:    if (plan && plan.carryBack) {
2361:      for (const id of plan.carryBack) {
2362:        const slot = state.items.bag.indexOf(-1);   // ← 从 0 开始找第一个空格
2363:        if (slot === -1) break;
2364:        state.items.bag[slot] = id;                 // ← 不看槽位类型
2365:      }
2366:    }
```

行囊给客户端的两处：`work/run/engine/index.js:4824-4826`（`item_load_items` 的 `bag`/`desk`）、
`4866-4871`（`item_putin_bag` 直接 `bag[pos-1]=item_id`，也无类型校验）。

### 2.3 根因

`carryBack` 是"按行囊下标顺序的裸 id 列表"，回家时又用 `indexOf(-1)` 从 0 号格开始塞。
道具（`type=2`）本来在 2/3 号格，回家后落在 0/1 号格 —— 而 0/1 号格在客户端是**便当格/护身符格**：

* 0 号格 = 便当槽 → 画成道具（水壶）→ 玩家说"食物那里是水壶"
* 1 号格 = 护身符槽 → 画成道具（纸伞）→ 玩家说"护身符那里是雨伞"
* 2/3 号格空着（原位置）→ 行囊和出发前摆的、以及和桌子上摆的都对不上

物品 id 对照（`work/run/engine/data/gamedata.json`）：
`2002 水壶 type=2 spend=0`、`2003 朴素纸伞 type=2 spend=0`（2000 竹筒/2001 葫芦/2004 自然纸伞/2005 水墨纸伞都是 type=2 spend=0）；
便当 type=0 spend=1、四叶草 1000 type=1 spend=1（会被吃掉，不回填）。

### 2.4 实测（真页面）

引擎单测脚本等价复现（`node work/tools/_bagslot_check.js`，用临时副本对比，不改仓库文件）：

```
=== 现状 (work/run/engine/index.js) ===
行李摆好     : 0=LunchBox(便当)=3  1=Amulet(护身符)=-1  2=Tool_1(道具)=2002  3=Tool_2(道具)=2003
出门后       : 0=-1  1=-1  2=-1  3=-1   plan.lunch=3 carryBack=[2002,2003]
回家后       : 0=LunchBox(便当)=2002  1=Amulet(护身符)=2003  2=-1  3=-1
判定         : 道具被塞进了 0/1 号格（便当格/护身符格）—— 复现玩家反馈
```

浏览器实测（`work/probe/baghat_*.js`，静态服务 127.0.0.1:18085，CDP 19285，profile `work/shots/p-baghat`）：
出门用客户端自己的路径 `ItemModel.setBagLock(true)` → `item_set_bag_completed`（走 `__probe.js` loopback，引擎 push 真推回客户端），
回家用引擎自己的 5s tick（把 `state.travel.returnAt` 置 0）。关键输出：

```
plan: { lunch: 3, carryBack: [2002, 2003], tools: 2 }      // 出门
engineBag / clientBag 回家后 = [2002, 2003, -1, -1]
model 层：slot0=LunchBox(便当) → 水壶 type=2 spend=0 | wouldDraw=item_6_png
          slot1=Amulet(护身符) → 朴素纸伞 type=2 spend=0 | wouldDraw=item_10_png
UI 层（真 Bag 组件，BagTable -> bt.bag.items[i]）：
  slot0 slotType=0 LunchBox  drawnSource=item_6_png   modelItemId=2002 itemName=水壶
  slot1 slotType=1 Amulet    drawnSource=item_10_png  modelItemId=2003 itemName=朴素纸伞
  slot2 slotType=2 Tool_1    drawnSource=frame_empty_png  modelItemId=-1
  slot3 slotType=2 Tool_2    drawnSource=frame_empty_png  modelItemId=-1
bagSlotMisplaced: ["slot0: LunchBox(便当) 里画的是 item 2002", "slot1: Amulet(护身符) 里画的是 item 2003"]
桌子对照（同一时刻）：engineDesk/clientDesk = [3,4,-1,-1,2000,-1,-1,-1]
```

截图：`work/shots/baghat_7_bag_page.png`（背包面板：标题"背包"，左格标签"便当"里画的是**绿色水壶**，
右格标签"护身符"里画的是**褐色折起的纸伞**，剩下两格空）——与玩家原话逐字吻合。

### 2.5 修法与验证

补丁（`work/run/engine/index.js`，两处；`_bagslot_check.js` 已把这两片段打进临时副本验证过）：

`provisionTrip`（2240-2265）把 `carried`/`carryBack` 改成带槽位的对象数组：

```js
    const carried = [];
    state.items.bag.forEach((id, slot) => {
      if (id !== -1) carried.push({ slot, id });
    });
    const amulet = carried.find((c) => isType(c.id, ITEM_TYPE_AMULET));
    const tools = carried.filter((c) => isType(c.id, ITEM_TYPE_TOOLS)).length;
    const carryBack = carried.filter((c) => {
      const it = ITEM_BY_ID.get(c.id);
      return !it || it.spend !== 1;            // keep durable gear
    });
```
（同一 `return` 里 `amulet: amulet === undefined ? -1 : amulet` 要改成 `amulet.id`）

`returnFrog`（2359-2366）按原槽位回填，槽位被占则退到同类型空格，再不行进"家"：

```js
    const BAG_SLOT_TYPE = [ITEM_TYPE_LUNCHBOX, ITEM_TYPE_AMULET, ITEM_TYPE_TOOLS, ITEM_TYPE_TOOLS];
    if (plan && plan.carryBack) {
      for (const entry of plan.carryBack) {
        const id = (entry && typeof entry === 'object') ? entry.id : entry;   // 兼容旧存档
        const want = (entry && typeof entry === 'object') ? entry.slot : -1;
        let slot = (want >= 0 && want < state.items.bag.length
                    && state.items.bag[want] === -1) ? want : -1;
        if (slot < 0) {
          const type = isType(id, ITEM_TYPE_LUNCHBOX) ? ITEM_TYPE_LUNCHBOX
            : isType(id, ITEM_TYPE_AMULET) ? ITEM_TYPE_AMULET
              : isType(id, ITEM_TYPE_TOOLS) ? ITEM_TYPE_TOOLS : -1;
          for (let i = 0; i < state.items.bag.length; i++) {
            if (state.items.bag[i] === -1 && BAG_SLOT_TYPE[i] === type) { slot = i; break; }
          }
        }
        if (slot < 0) { addHouseItem(id, 1); continue; }
        state.items.bag[slot] = id;
      }
    }
```

`travel.plan` 是**会存盘**的（`state.travel.plan = provisionTrip(); ... save()`），
所以 `carryBack` 形状从"数字数组"变成"对象数组"后必须容忍旧值 —— 上面 `typeof entry === 'object'` 就是为此。

验证（已实跑，输出见 2.4 的对照）：

```
=== 打了建议补丁的副本 ===
回家后       : 0=LunchBox(便当)=-1  1=Amulet(护身符)=-1  2=Tool_1(道具)=2002  3=Tool_2(道具)=2003
判定         : 道具回到原来的 2/3 号格，0/1 号（便当/护身符）保持空 —— 修好了
```

建议同时把已有单测 `work/tools/engine_test.js:291-304`
（`travel: a packed lunch box is consumed but durable gear comes home`，现在只断言
`bag.indexOf(tool) !== -1`，"道具回来了"就算过）收紧成断言**槽位**：

```js
  const bag = engine.state.items.bag;
  eq(bag[2], tool, 'the tool comes home to the Tool slot it left from, not slot 0');
  eq(bag[0], -1, 'slot 0 is the LunchBox slot and must stay empty');
```
（该断言在现状下**失败**：`bag[0] === tool`。）

浏览器验证（每轮都要新开页面 + 重新进屋，因为 `Bag.renderItem` 只在界面创建时跑一次）：
`node work/tools/cdp_drive.js --url http://127.0.0.1:<静态端口>/index.html --port <CDP端口> --profile work/shots/p-baghat --fresh --wait 26000 --settle 2000 --step in:work/probe/baghat_a_dismiss.js --step in:work/probe/baghat_b_house_enter.js --step in:work/probe/baghat_d_depart.js --step in:work/probe/baghat_h_forcereturn.js --step wait:9000 --step in:work/probe/baghat_l_bagpage.js --step shot:work/shots/check.png`
期望：`bagSlots[0].slotType===0 && modelItemId===-1`、`bagSlots[2].modelItemId` = 原道具 id。

### 2.6 顺带发现（另一件事，不是本条 bug 的成因）

`tripPrepared()`/`provisionTrip()` 只从**行囊**取行李，桌子（`state.items.desk`）除了 1 个便当以外
既不消耗也不计入 `tools`。而客户端唯一的文案（`tables/zh-CN.json` 键 `{0}首次打开背包`）说的是
"如果在**桌子**上放好了东西……{0}也会自己挑选东西出门旅行"。所以"我明明在桌上摆了东西、它却没用"
是真实现象，但**它不会**把道具塞进便当格 —— 本条 bug 的水壶/纸伞来自玩家自己放进行囊 2/3 号格的耐用品。
两条建议分开处理。

---

## 3. 条 2：旅行时帽子还在家里

### 3.1 帽子是什么

皮肤里就有一个节点叫 `frogCap`（cap = 帽子），资源是 `bousi_ie_png`（bousi = ぼうし = 帽子）。
`work/run/web/js/default.thm.js:28727`（MainIn/MainIn.exml 编译产物，缩进已还原）：

```js
_proto.frogCap_i = function () {
    var t = new eui.Image();
    this.frogCap = t;
    t.source = "bousi_ie_png";
    t.visible = false;        // 皮肤默认不显示
    t.x = -278;
    t.y = 151;
    return t;
};
```

资源清单 `work/run/web/resource/China/default.res.json`：
`{"url":"first_eab","type":"eab_asset","name":"bousi_ie_png"}` 与
`{"url":"animation/MainIn/bousi_ie.anm.bytes","type":"bin","name":"bousi_ie.anm_bytes"}`。
（画面里它画的是"挂在炉子旁边小木架上的一顶带红帽箍的绿帽子"。）

### 3.2 客户端读法（判定依据）

`work/run/web/js/main.min.js.clean:25 col 4114` —— `MainInView.updateFlogStatus`（节选，`col 4639` 是关键行）：

```js
t.prototype.updateFlogStatus=function(){
  var e=Tabikaeru.Game.instance().isHome;
  if(this.player&&(...this.player.destroy();this.player=null)),
  this.c_player_desk_mc.visible&&(...),
  this.i_guideFood.visible=!1,
  e){                                   // ← 只有 if，没有 else
    this.frogCap.visible=!0;            // ← 帽子只在 isHome 时被置 true
    ... 重建屋里那只蛙(this.player) ...
  }
}
```

`work/run/web/js/main.min.js.clean:13 col 13551` —— `isHome` 的来源：

```js
Object.defineProperty(t.prototype,"isHome",{get:function(){return 0==this.roleModel.getFrogStatus()},...})
```

`work/run/web/js/main.min.js.clean:25 col 11703` —— `MainInView.reset()` 里会调 `updateFlogStatus()`（`col 11777`）：

```js
t.prototype.reset=function(){this.updateRedpoint(),this.updateClover(),this.updateFlogStatus(),this.updateFurnitureAni(),...}
```

`work/run/web/js/main.min.js.clean:24 col 21617` —— `MainInController.open()`（唯一的重算入口）：

```js
t.prototype.open=function(){var e=!1;null==this.view&&(this.view=new MainInView,e=!0),
  this.getParent().addChild(this.view),e||this.view.reset()}
```

`work/run/web/js/main.min.js.clean:24 col 20867` —— `MainInController` 构造里的订阅表（**没有** `RoleEventType.loadRole`）：

```js
t.addEventListeners(t.totalCustomEvents,t,UserEventType.updateClover,TravelEventType.updateRedpoint,
  ItemEventType.updateDesk,ItemEventType.updateBag,TravelNoteEventType.checkNoteGuide,
  FurnitureEventType.UPDATE,DrawingEventType.ITEM_CHANGE,RoleEventType.updateDecoration)
```

对照 `work/run/web/js/main.min.js.clean:25 col 20985` —— `MainOutController`（庭院）**订阅了**：

```js
case RoleEventType.loadRole:this.view&&this.view.reset();break;
```

`work/run/web/js/main.min.js.clean:25 col 22057` 区域 —— `MainInController.totalCustomEvents` 的 switch 里也没有 loadRole
（只有 updateClover/updateRedpoint/updateDesk/updateBag/ITEM_CHANGE/checkNoteGuide/FurnitureEventType.UPDATE/updateDecoration）。

→ 结论：`status` 0→1（出门）时 **屋里这个视图完全不会被重算**；
而任何一次"进屋/重进屋"带来的 `reset()` 会先**无条件拆掉蛙**（`this.player.destroy()`），
却因为 `if(e)` 没有 else 而**不会**把 `frogCap` 关掉 —— 于是"蛙没了、帽子还在"。

（客户端自己知道要关它：教程分支 `main.min.js.clean:25 col 545`
`case GuideStep.CloseBag:...this.frogCap.visible=!1,...`；复活节彩蛋 `col 5684` 也有 `=!1`。
正常游戏流程里没有这条路径。）

### 3.3 引擎侧

`work/run/engine/index.js:4251`（`rolePayload()`）：`status: state.frog.status,` —— 字段名与客户端 `frog.status → getFrogStatus()` 一致，**没有错位**。
`work/run/engine/index.js:4903-4913`（`item_set_bag_completed`）在玩家按下"准备完成"的**那一刻**就 `departFrog()`，
`departFrog`（2319-2350）随即 `ctx.push('client_load_role', rolePayload())` + `item_load_items` + `notify_new_event`。
即"玩家正盯着屋里/行囊界面时，status 变成 1"，正好落在上面那个不会被重算的窗口里。

### 3.4 实测（真页面）

```
进屋（蛙在家，status 0）:
  frogCap_visible: true   frogCap_source: "bousi_ie_png"   player_alive: true   isHome: true
出门（status 1，玩家仍站在屋里）:
  isHome: false   status_engine: 1   frogCap_visible: true   player_alive: true     // 整个视图没被刷新
出屋到庭院，再进屋（蛙仍在旅行）:
  isHome: false   frogCap_visible: true   player_alive: false   curAnimName: "sitaku_ie"
  ↑ "蛙没了、帽子还在" —— 玩家看到的就是这个
强制回家（引擎 tick 走 returnFrog），玩家仍站在屋里:
  isHome: true    frogCap_visible: true   player_alive: false   // 反方向也一样：蛙不会自己出现
frogCap 节点坐标/贴图: x=-278  y=151  source=bousi_ie_png
```

像素归属对照（同一状态，只翻 `frogCap.visible`）：
* `work/shots/baghat_5_hat_on.png`（visible=true）→ 画面里"炉子旁小木架上挂着一顶带红帽箍的绿帽子"；
* `work/shots/baghat_6_hat_off.png`（visible=false）→ 同一位置变成"插在盆里的一根光秃树枝"，帽子消失。
两图唯一差别就是这个节点，所以玩家说的"帽子"= `frogCap`。
另：`work/shots/baghat_3_away_hat_only.png` 里画面横幅是"呱呱精力充沛地出去旅行了"（蛙在旅行），
而帽子仍在 —— 与玩家反馈逐字一致。

### 3.5 根因与修法

**根因在客户端**，而且不能从引擎绕过去：客户端在 `status` 变化时只让 `MainOutController` 重算视图，
屋里视图的 `frogCap.visible` 是上一次"在家"渲染留下的残留值；`updateFlogStatus` 又没有 else 把它关掉。
引擎能做的只有"在什么时候推 status=1"，怎么推都改不了这个残留 —— 除非改客户端。

建议补丁（客户端；`work/run/web/js/main.min.js` 与其可读副本 `main.min.js.clean`；改完需要重新打包，本次没做）：

1. 让 `MainInController` 也订阅 `RoleEventType.loadRole`（构造 + `destroy` 两个事件表都加），
   并在 `totalCustomEvents` 里加上（与 `MainOutController:25 col 20985` 对称）：
   ```js
   case RoleEventType.loadRole: this.view && this.view.updateFlogStatus(); break;
   ```
   用 `updateFlogStatus()` 而不是整个 `reset()`：`reset()` 会连带刷新家具/成就/料理弹窗/收藏，
   而 `updateFlogStatus()` 正好只干"按 isHome 显示/隐藏蛙与帽子"这一件事，顺带修好反方向
   （蛙回家时玩家站在屋里，蛙不会自己出现）。
2. 防御性地给 `updateFlogStatus` 的 `if(e){...}` 补 else（`main.min.js.clean:25 col 4639`）：
   ```js
   } else { this.frogCap.visible = !1; }
   ```

**验证方法**：
1. 纯客户端：进屋（蛙在家，帽子在）→ 引擎把 `status` 置 1（`__engine.dispatch('client_gm',{cmd:'travel_now'})` 或点"准备完成"）
   → 读 `core.PageManage.getInstance().getControl(MainInController, core.ViewLayerType.SceneLayer).getView().frogCap.visible`
   应为 `false`（补丁前是 `true`）。
2. 反方向：站在屋里让蛙回家 → 屋里应立刻出现蛙（`view.player` 非空），补丁前为空。
3. 截图对照：`work/shots/baghat_5_hat_on.png` / `baghat_6_hat_off.png` 的差别区（炉子旁木架）。
   注意：`core.PageManage.getControl(Class)` **不传层会直接报错返回 undefined**，必须带 `core.ViewLayerType.SceneLayer`；
   `SceneLayer` 过场是 300+300ms 的 tween，视图要等（我的探针是轮询等的）。

---

## 4. 本次用到的探针/工具（都在 work/ 下，未改动发行物）

探针（`work/probe/`，都是无尾分号的 IIFE）：
`baghat_a_dismiss.js`（关声明遮罩）、`baghat_b_house_enter.js`（进屋+等视图）、
`baghat_c_read_house.js`、`baghat_d_depart.js`（客户端 `setBagLock(true)` 出门）、
`baghat_e_read_after_depart.js`、`baghat_f_leave.js`、`baghat_g_reenter.js`、
`baghat_h_forcereturn.js`（置 `returnAt=0` 让引擎 tick 回家）、`baghat_i_bagui.js` / `baghat_l_bagpage.js`（读真 Bag 组件每格）、
`baghat_j_hat_on.js` / `baghat_k_hat_off.js`（帽子像素归属对照）。

工具（`work/tools/`）：`_bagslot_check.js`（现状 vs 补丁副本对照，跑完自删临时文件）、
`_ctxfind.js` / `_win.js` / `_slice.js` / `_owner.js`（在巨型单行文件里按 offset/列号取上下文）。

截图（`work/shots/`）：`baghat_1_home_with_hat.png`（在家）、`baghat_2_away_whole_frog.png`（出门瞬间屋里没刷新）、
`baghat_3_away_hat_only.png`（蛙在旅行、帽子还在）、`baghat_5_hat_on.png` / `baghat_6_hat_off.png`（帽子节点对照）、
`baghat_7_bag_page.png`（便当格画着水壶、护身符格画着纸伞）。

进程卫生：我起的静态服务（127.0.0.1:18085）已关（`18085` 端口已不可连接），
我起的 msedge（`--user-data-dir=...\p-baghat`）已全部结束（`msedge.exe` 命令行里已无 `p-baghat`）。
会话里另有 `p-annual` 的 msedge 在跑，**不是我起的，我没有动**。
