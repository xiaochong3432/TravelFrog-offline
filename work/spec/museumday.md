# 博物馆冒险（`museumday_*`）—— 字段级实现规格（**常开版**）

> **English TL;DR** — The event window is decided *only* by the `end_time` field of the
> `museumday_load` reply (`isOpen()` = `serverTime >= 1 && serverTime <= end_time`); `start_time`,
> `museumDayCommon.open_time`, `mail_str` and the `inspire` row are **never read** by the client,
> and there is **no hardcoded date range** anywhere in `main.min.js`. Sending a future `end_time`
> therefore makes the event permanently open — but `Utils.convertArrayAll()` then *replaces* the whole
> model payload, so the same reply must also carry **all 16 model keys**, or the client throws
> (`path.length` of undefined) and hits its global `window.onerror` → "呱呱吃坏肚子了" → page reload loop.

> 目标读者：要在 `H:\AI\frog\work\run\engine\index.js` 里实现 `museumday_*` 的实现者。
> 本文只写规格，不改引擎代码，也不改任何素材。
>
> **唯一判定准绳**：`H:\AI\frog\work\run\web\js\main.min.js`（下称 **client**）。
> 皮肤/EXML 编译产物：`H:\AI\frog\work\run\web\js\default.thm.js`（下称 **thm**）。
> 数据表：`work\run\engine\data\tables\*`、`work\run\engine\data\define.json`、`work\run\engine\data\gamedata.json`。
>
> **偏移约定（两套都给）**：本文所有 `@N` 均为 **字符偏移**（Python `open(...,encoding='utf-8').read()` 的下标），
> 复核用 `work/tools/jsfind.py --win ... <regex>`（打印的就是字符偏移）。
> 该文件 `1315423` 字节 / `1261132` 字符（UTF-8），所以 **字节偏移 > 字符偏移**，别混用。
> 每个引用的锚点都给了「字符偏移 / 字节偏移」两列，见 §0.2 表。
>
> **可信度标记**：无标记 = 客户端代码/数据表直接得出；`【推测】` = 只有客户端结构支持、原服务端规则不可考的推断；
> `【自设计】` = 原服务端规则**不可复原**、必须我们拍板的数值。

---

## 0. 证据来源与工具

| 事实 | 依据 |
|---|---|
| `museumday_*` 在协议表里共 **10** 条 | `protocol.js` 第 871–914 行；client 内嵌协议表 `@379480` |
| 客户端**实际会发**的只有 7 条 | `work/tools/cb_show.py museumday_load museumday_refresh museumday_random_compass museumday_dir_compass museumday_get_items museumday_arrive museumday_start_advance museumday_load_path museumday_info museumday_inspire` → `museumday_load_path` / `museumday_info` **send sites = 0**；`museumday_dir_compass` 的 `dirCompass()` 方法**定义了但全 bundle 无调用点**（唯一命中就是定义处 `@153636`） |
| `museumday_info` 是**服务端推送**（不是请求） | 协议表 `museumday_info:[[],!1]`（`needResponse=false`，`@379686`），且 `addProtocolCallback("museumday_load","museumday_arrive","museumday_info")` `@150061` |
| 回包 → 模型回调的调用约定 | `AnalysisProtocol` `@337865`：`s&&s.apply(r.data,o.data)`（arg0=回包, arg1=请求参数）；推送分支只 `DispatchEvent(new e.Event(a,r.data))` |
| 模型按「命令名 = 方法名」分发 | `core.Model.protocolCallback` `@11902`：`var i=this[t.getEventType()]; i.apply(this,t.getParams())` |
| 全局异常 → 弹「呱呱吃坏肚子了」→ 刷新页面 | `window.onerror=function(){...removeControlAll(WindowLayer/LoaderLayer/NoticeLayer); popupLayer.removeChildren(); NetworkControl.getInstance().reloading(Reload.JSError)}` `@233265`（`reloading(...)` 在 `@233625`）；文案 `呱呱吃坏肚子了，请重启一下游戏~` `@1252604` |
| **代码块排版说明** | `main.min.js` 全文只有 **38 个换行符**（基本是单行）。本文代码块里的换行都是**排版加的**，缩进也是我加的；带 `...` 的是节选。除此之外字符内容与原文一致（可用 §0.2 的偏移回查）|
| 博物馆冒险的**全部**素材 63 个 | `run\web\resource\China\images\Scene\MuseumDay\`（递归计数 63），且 63/63 都注册在 `run\web\resource\China\default.res.json` 里，`name = <文件名>_png` |

### 0.1 复现命令（照抄即可）

```powershell
# 回调源码
python H:\AI\frog\work\tools\cb_show.py museumday_load museumday_refresh museumday_random_compass `
       museumday_dir_compass museumday_get_items museumday_arrive museumday_start_advance `
       museumday_load_path museumday_info museumday_inspire     # → work\logs\cb_show.txt
# 任意符号的上下文（字符偏移）
python H:\AI\frog\work\tools\jsfind.py --win 900 "MuseumDayCommonData.get"
# 素材清单
Get-ChildItem H:\AI\frog\work\run\web\resource\China\images\Scene\MuseumDay -Recurse -File   # 63
```

### 0.2 偏移表（字符 / 字节）

| 锚点 | 字符偏移 | 字节偏移(UTF-8) |
|---|---|---|
| `MuseumDayModel` 类声明 | 149735 | 151831 |
| `initModel`（注册 3 个回调） | 150061 | 152157 |
| `museumday_info` 回调 | 150216 | 152312 |
| `museumday_load` 回调 | 150400 | 152496 |
| `this.data=Utils.convertArrayAll(e)` 调用点 | 150450 | 152546 |
| `closeActivity` | 150752 | 152848 |
| `request()` | 151544 | 153654 |
| `request_start_advance` | 151631 | 153741 |
| `getItems` | 152132 | 154242 |
| `refresh` | 152900 | 155010 |
| `arrive` | 153103 | 155213 |
| `randomCompass` | 153248 | 155358 |
| `dirCompass` | 153636 | 155746 |
| `req_inspire` | 153864 | 155974 |
| `getActivityTime` | 154235 | 156345 |
| `isOpen` | 154335 | 156445 |
| `canInspire` | 154475 | 156585 |
| `checkRedot` | 154600 | 156710 |
| `MuseumDayExploreDir` 枚举 | 154979 | 157089 |
| `MuseumDayEventType` 枚举 | 1201731 | 1255294 |
| `updateMuseumDay`（入口按钮可见性） | 862864 | 913433 |
| `on_btnMuseumDay_tap` | 878260 | 929113 |
| MainOut `childrenCreated` 里调 `updateMuseumDay()` | 842103 | 892636 |
| MainOut `reset()` 里调 `updateMuseumDay()` | 872402 | 923150 |
| `Utils.convertArray`（`v`） | 300384 | 344001 |
| `Utils.convertArrayAll`（`_`） | 300427 | 344044 |
| client 内嵌协议表 `museumday_load:[[],!0]` | 379480 | 424409 |
| `SocketManage.send` | 336322 | 380661 |
| `SocketManage.AnalysisProtocol` | 337865 | 382418 |
| `core.Model.protocolCallback` | 11902 | 12032 |
| `ItemModel.doAddHouseItem` | 137223 | 139177 |
| `GiftPackageViewController` | 648184 | 697263 |
| `GiftPackageView.setData` | 647904 | 696983 |
| `ExploreView.updateRewards` | 932195 | 983882 |
| `ExploreView.updateData` | 930981 | 982640 |
| `ExploreView.childrenCreated`（8 个进度点） | 930093 | 981752 |
| `ExploreView.refresh` | 930616 | 982275 |
| `updateTasks` / `updateOverDate` / `updateCompass` | 931725 / 931809 / 932017 | 983396 / 983480 / 983698 |
| `updatePath` / `updateLog` / `setupMap` / `loadResource` | 933677 / 934285 / 934721 / 934668 | 985364 / 985972 / 986408 / 986355 |
| `btnInspire` 点击体（"每吃8个饼干…"） | 929862 | 981473 |
| `on_btnPlan_tap`（randomCompass） | 935224 | 986923 |
| `on_btnTips_tap` / `on_btnRefresh_tap` / `on_btnHistory_tap` | 935140 / 935938 / 936174 | 986839 / 987653 / 987921 |
| `MuseumDayExploreMap` 类（`COLS=5,ROWS=7,TILESIZE=54`） | 938313 | 990064 |
| `indexToMap` / `setTarget` / `render` | 940033 / 939243 / 940934 | 991784 / 990994 / 992685 |
| `CardItem.dataChanged`（`end_<id>_<desc_id>_png`） | 924778 | 976351 |
| `CardItem.on_btnGet_tap` / `CardView.onGet`（`arrive`） | 925626 / 923973 | 977199 / 975546 |
| `HistoryView.update`（`base.v4`） | 944303 | 996054 |
| `switchTips`（`base.v3`） | 945329 | 997080 |
| `on_listTask_tap`（`restart_clover` + `start_advance`） | 945920 | 997707 |
| `HistoryListItem.dataChanged`（`arrival_seal_N`） | 947699 | 999496 |
| `updatCompass` | 945743 | 997530 |
| `MuseumDayPopupViewControl`（写 cookie） | 948724 | 1000521 |
| `MuseumDayUtils.getTileResource` | 949968 | 1001765 |
| `Mail.EvtId.Explor=12` | 413192 | 458481 |
| `MailModel.revice_mails` 里 `setEmail(!0)` | 203115 | 205847 |
| `MailView` 里 `setEmail(!1)` + `museumDay_popup` cookie | 795528 / 795637 | 845897 / 846006 |
| `ExploreView` 里 "活动结束后，按1:{0}回收为三叶草" | 945549 | 997300 |
| `window.onerror` → `Reload.JSError` | 233265 | 236282 |
| "呱呱吃坏肚子了" 文案 | 1252604 | 1306496 |

---

## 1. 入口 / 开窗逻辑 —— **这是「常开」的全部关键**

### 1.1 客户端唯一的开窗判定（**只有回包 `end_time`，`start` 是硬编码常量 1**）

`@154235`（`MuseumDayModel.getActivityTime` / `isOpen`，逐字）：

```js
t.prototype.getActivityTime=function(){var e=this.getModel(t).data.end_time;return e>0?[1,e]:[0,0]},
t.prototype.isOpen=function(){var e=this.getActivityTime(),t=e[0],i=e[1];
  return core.Time.getServerTime()>=t&&core.Time.getServerTime()<=i},
```

结论（**逐条**）：

1. 窗口 = `[1, end_time]`；下界是**字面量 `1`**，不是回包的 `start_time`。
2. `data.start_time` 全 bundle **没有任何读取点**（它只出现在 `MuseumDayModel` 默认对象字面量
   `{end_time:0,inspire_num:0,inspire_time:0,...,path:[]}` `@149832` 里）。**回包给不给都无所谓。**
3. `end_time <= 0` → 永久关闭；`end_time > 0` → 只要 `serverTime <= end_time` 就算开着。

### 1.2 **硬编码日期审计：没有**（这一节决定了「是否 payload 能独立开窗」）

对 `main.min.js` 全文正则检索，命中数如下：

| 检索 | 命中 | 说明 |
|---|---|---|
| `1700615100` / `1702828799`（=`museumDayCommon.open_time` 的 v1/v2） | **0** | 客户端里没有这段日期 |
| `1701360000`（=`museumDayCommon.inspire.v2`） | **0** | 同上 |
| 字符串 `open_time` | **0** | 该行是纯服务端数据 |
| 字符串 `mail_str` | **0** | 该行也是纯服务端数据 |

`museumDayCommon` 的**全部**读取点是（穷举，共 4 处）：

```js
@151822  MuseumDayCommonData.get("restart_clover")   // request_start_advance 里的价格
@944465  MuseumDayCommonData.get("base").v4          // HistoryView.update   → 是否显示「开始一次新冒险」按钮
@945493  MuseumDayCommonData.get("base").v3          // HistoryView.switchTips → "活动结束后，按1:{0}回收为三叶草"
@946202  MuseumDayCommonData.get("restart_clover")   // on_listTask_tap 里的价格
```

→ **`base.v1`(8) / `base.v2`(1.0) / `inspire` 整行 / `mail_str` 整行 / `open_time` 整行，客户端都不读。**
→ **客户端里没有任何针对本活动的硬编码日期区间**；唯一的时间闸门是回包 `end_time`。

### 1.3 入口按钮怎么看出来的（`isOpen()` 是唯一谓词）

三个地方，全部依赖 `MuseumDayModel.isOpen()`：

**(a) 按钮元素的可见性** `@862864`：

```js
t.prototype.updateMuseumDay=function(){var e=this.userModel.getClientSettings().guideStep;
  e==GuideStep.Complete?this.btnMuseumDay.visible=this.btnMuseumDay.includeInLayout=this.getModel(MuseumDayModel).isOpen()
                      :this.btnMuseumDay.visible=this.btnMuseumDay.includeInLayout=!1},
```

**(b) 调用时机**：`MainOutController` 的 `childrenCreated` `@842103` 与 `reset()` `@872402` 都会调用它；
以及对 `MuseumDayEventType.LOAD` 的响应（`@833217` `case MuseumDayEventType.LOAD:this.view.updateMuseumDay()`）。

**(c) 按钮本体（皮肤，不是脚本）**：`thm@769684`

```js
_proto.btnMuseumDay_i = function () {
    var t = new Button();  this.btnMuseumDay = t;  t.label = "";
    t.x = 2104;  t.y = 108;  t.skinName = $exmlClass302$Skin313;  return t;
};
```

`$exmlClass302$Skin313`（`thm@730472`，属于 `resource/China/skins/MainOut/MainOut.exml`）：

```js
_proto._Image1_i = function () { var t = new eui.Image(); t.source = "explore_84_88_png"; ... };
_proto._Redot1_i  = function () { var t = new Redot(); t.redot = "MUSEUMDAY"; t.touchEnabled = false;
                                  t.x = 10; t.y = 10; t.skinName = $exmlClass302$Skin313$Skin314; return t; };
```
（`$Skin314` 里是 `DragonbonesUI` + `source="tips_xhd"` —— 就是那个红点动画。）

**注意**：皮肤里**没有** `visible=false`，所以按钮默认可见，由 `updateMuseumDay()` 在 `childrenCreated` 时纠正。

**(d) 点击行为** `@878260`（引子）：

```js
t.prototype.on_btnMuseumDay_tap=function(){
  var e=this.getModel(MuseumDayModel).data, t=this.getModel(MuseumDayModel).getActivityTime();
  this.getModel(MuseumDayModel).isOpen()
    ? ( core.String.getCookie("museumDay_popup")!=String(t[1])
        ? addViewControl(MuseumDayPopupViewControl,...)            // 首次：邀请函弹窗
        : ( 0==e.cur_museum ? addViewControl(MuseumDayHistoryViewControl,...)   // 没在冒险 → 记录页
                            : addViewControl(MuseumDayExploreViewControl,...) ) ) // 在冒险中 → 地图页
    : (GuideHelpView.getInstance().show(_("春游活动已结束")), this.updateMuseumDay())},
```

**(e) 红点**：`checkRedot()` `@154600`

```js
t.prototype.checkRedot=function(){var e=this.isOpen()&&this.data.path.length!=this.data.next&&this.data.compass>0?1:0;
  Tabikaeru.RedotManager.instance().setRedotValue(Tabikaeru.RedotType.MUSEUMDAY,e)},
```

`Redot` 组件（`RedotManager.getRedotValue` `@445389`，组件 `updateRedot` `@1232509`）：
`this.visible = this._enabled && e>0`。
→ **常开 + 有罗盘 + 没走到终点 = 入口按钮一直挂红点**（这正是我们想要的效果）。
→ 但这一行也是**最大的崩溃源**：`isOpen()` 一旦为真，`this.data.path.length` 就会被求值（见 §8 地雷 1）。

### 1.4 第二个入口：邮件（`Mail.EvtId.Explor = 12`）

* `Mail.EvtId.Explor=12`（`@413192`）。
* `TravelModel.revice_mails` `@203115`：`t.type==Mail.EvtId.Explor&&1!=t.opened&&this.getModel(MuseumDayModel).setEmail(!0)`
  → 只要邮箱里有一封 `type=12` 且未打开的邮件，主界面邮箱图标就换成 `MainOut_mail_explore_png`。
* 点开这封邮件 `@795528`：

```js
else if(this.mailInfo.type==Mail.EvtId.Explor){
  core.ModelManage.getInstance().getModel(MuseumDayModel).setEmail(!1);
  var s=core.ModelManage.getInstance().getModel(MuseumDayModel).getActivityTime();
  core.String.getCookie("museumDay_popup")!=String(s[1]) ? addViewControl(MuseumDayPopupViewControl,...)
    : 0==...data.cur_museum ? addViewControl(MuseumDayHistoryViewControl,...)
                            : addViewControl(MuseumDayExploreViewControl,...);
  ...}
```

**这条路径不看 `isOpen()`！** 也就是说：只要有 type=12 的邮件，即使窗口关着也能进活动页 —— 而
`MuseumDayHistoryViewControl.open()` 会立刻 `request()`（发 `museumday_load`），见 §8 地雷 2。

### 1.5 常开需要什么 payload 值（**明确回答**）

**两个条件，缺一不可：**

**条件 1（时间闸门）· payload**：

```json
{ "end_time": 4102444800 }
```
（`4102444800` = 2100-01-01T00:00:00Z，`【自设计】`；任何 `>= now` 的正数都行，越大越久。）
`start_time` 不必给（给了也不读）。

**条件 2（新手引导闸门）· 不是 payload，是玩家存档**：`updateMuseumDay` 的一级判断是
`this.userModel.getClientSettings().guideStep == GuideStep.Complete`，**不满足就直接 `visible=false`**，
跟 `end_time` 完全无关（`@862864`，见 §1.3(a)）。离线引擎必须让存档里的 `guideStep` 处于
`Complete`（引擎 state.settings.guideStep；`client_load_role`/`client_set_client` 同步给客户端）。
→ **测试「常开」前先确认引导已完成**，否则会误判成「payload 没生效」。
（引擎里已有同一结论的注记：`run/engine/index.js` 第 2902–2906 行 —— 主界面在
`guideStep != 'Complete'` 时会隐藏 4 个活动按钮和活动红点。）

**另有 3 个必须一起处理的副作用，否则「常开」会自己咬自己：**

**(A) 关闭定时器（`museumday_load` 里，`@150400`）**

```js
t.prototype.museumday_load=function(e){var t=this;
  this.data=Utils.convertArrayAll(e),
  this.dispatchEvent(new core.Event(MuseumdayEventType.LOAD)),        // 注意：先派发 LOAD
  this.isOpen()&&(egret.clearTimeout(this.timerActivity),
     this.timerActivity=egret.setTimeout(function(){t.closeActivity()},this,
        1e3*(this.getActivityTime()[1]-core.Time.getServerTime()+1))),
  this.checkRedot()},
```
（上面 `MuseumdayEventType` 实为 `MuseumDayEventType`，此处按原样缩排。）

`closeActivity()` `@150752`：把 Explore/History/Popup 三个 WindowLayer 控件移除，
**只要移除了任意一个**就 `GuideHelpView.getInstance().show(_("春游活动已结束"))`，然后派发 `LOAD`。

延迟 = `1000*(end_time - now + 1)` 毫秒。取值影响：

| `end_time - now` | 延迟(ms) | 会发生什么 |
|---|---|---|
| 20 天 | 1.728e9 | **< 2^31-1**，任何引擎都不会截断 → 定时器在 20 天后精确触发（每次 `museumday_load` 都会重设，所以只要 20 天内有任意一次 load 就永不触发）|
| 365 天 | 3.15e10 | 超过 32 位有符号整数上限；HTML 定时器会把 delay 当 `long`/int32 处理，**各引擎行为不同**：要么截断到 2147483647 ms(≈24.8 天)，要么按溢出当 0 → 立刻触发 |
| 到 2100 年 | 2.3e12 | 同上，更可能在 `museumday_load` 返回后**立刻** `closeActivity()` |

* 若「截断到 2^31-1」：`closeActivity` 会在开始后约 24.8 天触发一次（游戏会话几乎不可能连续那么久）。
* 若「溢出当 0」：**每次 `museumday_load` 之后立刻 `closeActivity()`**。此刻如果玩家正开着
  History/Explore 窗口（`HistoryViewControl.open()` 就自己发了一次 `museumday_load`），
  窗口会被立刻关掉并弹「春游活动已结束」→ **功能性 bug**。
  ⚠️ 原始活动窗口是 `open_time` = `1700615100`→`1702828799`，**跨度 25.6 天**，其
  `1000*(end-start+1)` = 2.2137e9 也 > 2^31-1。原版能正常上线，说明真实运行环境**不是**
  「溢出当 0」（大概是截断）。但这是在 APK/WebView 里量出来的事实，不是静态可证的。
  本仓库离线和浏览器版本都可能不同 → **必须实测**（打法见 §10 验收清单）。

**推荐做法（`【自设计】`）**：
* 想要「永不关闭」且**完全不碰定时器**：`end_time = now + 20*86400`（滚动窗口），每次 `museumday_load` 重新计算。
  1.728e9 ms < 2^31-1，无截断、无溢出 → 定时器总是在 20 天后，而每次 load 都会重置它。
* 想要「固定日期」：`end_time = 4102444800` 常量，接受 (A) 的不确定性；若实测出现「打开记录页立刻被关掉」，
  就换成滚动窗口。
* 两种做法**都能保证入口按钮常开**（按钮只看 `isOpen()`，`closeActivity` 不改 `isOpen`）。

**(B) cookie `museumDay_popup` 的键就是 `end_time`** `@948724`：

```js
var MuseumDayPopupViewControl=function(e){function t(){return e.call(this,MuseumDayPopupView)||this}
  return __extends(t,e),t.prototype.open=function(){e.prototype.open.call(this);
    var t=this.getModel(MuseumDayModel).getActivityTime();
    core.String.setCookie("museumDay_popup",t[1])},t}(WindowController);
```
点按钮时：`getCookie("museumDay_popup") != String(end_time)` → 先弹邀请函。
* **固定 `end_time`** → 邀请函只弹一次（之后每次点按钮直接进记录页/地图页）；
* **滚动 `end_time`** → cookie 每次都变 → **每次点按钮都先弹邀请函**（多一次点击，不是死局，但要知情）。

**(C) `updateOverDate` / `switchTips` 会把 `end_time` 显示出来** `@931809` / `@945329`：

```js
this.lblLimitDate.text=_("活动截止至 {0}",core.DateFormat.format(1e3*Number(e[1]),core.DateFormater["YYYY/M/D hh:mm"]));
```
固定 2100 年时这条 UI 会写「活动截止至 2100/1/1 08:00」；滚动窗口会写「now+20天」。
（`Number(e[1])` 说明字符串也吃得下，但**仍然建议给数字**。）

---

## 2. 命令总表（10 条）

| 命令 | 声明参数（`protocol.js` / client `@379480`） | 客户端真会发？ | 谁读回包、读哪些字段 | 玩家看到的状态变化 | 引擎必须回什么 |
|---|---|---|---|---|---|
| `museumday_load` | `[]`，needResponse **true** | ✅ `request()` `@151544` | **没有 Action**；由 `MuseumDayModel.museumday_load(e)`（SE 分发）读，`Utils.convertArrayAll(e)` **整体替换 data** | 主界面按钮显隐、红点、记录页/地图页刷新 | **§4.1 的 16 个键全给**（尤其 `path` 必须是非空数组） |
| `museumday_refresh` | `[]`，true | ✅ 地图页「重新开始」`@935938`；记录页 times==0 的行 `@945920` | `Action2`: 只读 `i.left_num` | `data.left_num=…`；随即再发一次 `museumday_load`；回调打开地图页 | `{left_num:<int ≠ -1>}`；另需真正换一条新路线（并保证 `cur_museum>0`、`path` 非空）|
| `museumday_random_compass` | `[]`，true | ✅ 「尝试规划」`@935224` | `Action1`: 读 `i.next`、`i.inspire` | `inspire_num=i.inspire`；`next=i.next`；罗盘指针转 3 秒；`PATH_UPDATE`；新格子淡入 | `{next:<int>, inspire:<int>}` 且 **`next` 必须 ≠ 当前 `next`**；服务端扣 1 罗盘并推 `museumday_info` |
| `museumday_dir_compass` | `["dir"]`，true | ❌ **全 bundle 无调用点**（`dirCompass()` `@153636` 是死代码，`MuseumDayExploreCompass.enableSelect` `@937142` 也无人调用） | `Action1`: 只读 `e.code` | 只派发 `COMPASS` | 可选：`{code:0}`。语义不可复原（见 §7.2） |
| `museumday_get_items` | `[]`，true | ✅ 自动：`updateRewards()` 发现有未领物品时 | `Action2`: **只读 `i.code`**；物品完全取 `model.data.items` / `model.data.get_items` | `items` 并入 `get_items`（同行 `num` 相加）→ `data.items=[]`；`COMPASS`+`REWARD` 事件；`ItemModel.addHouseItem(item_id,num)`（**跳过 200002 罗盘**） | `{code:0}`，并且**服务端必须同时把这些物品从"待领取"移到"已领取"**，否则死循环（§8 地雷 5） |
| `museumday_arrive` | `[]`，true | ✅ 结算卡「领取」`@923973` | **无任何读取**（`museumday_arrive(){}` 空函数，且 `send` 不带 Action） | 关掉卡片→移除地图页→打开记录页（记录页随后自己发 `museumday_load`）| 任意对象（建议 `{code:0}`）；服务端要把本次冒险结算进 `museum_list`、`cur_museum=0` |
| `museumday_start_advance` | `["id"]`，true | ✅ 记录页「explore」态选馆 `@945920` | `Action1`: 只读 `e.code` | 本地 `consumeClover(s)`（**只做判断不减值**，见 §8 地雷 6）→ 再发 `museumday_load` → 回调打开地图页 | `{code:0}`；服务端扣 `restart_clover` 里那一档三叶草并推 `clover_update`；`id` **可能是 0**（占位行）|
| `museumday_load_path` | `[]`，true | ❌ **send sites = 0** | 无 | 无 | 不可复原（§7.2）。随便回 `{}` 也不会被调用 |
| `museumday_info` | `[]`，needResponse **false** | ❌ 不是请求，**只能服务端推** | `MuseumDayModel.museumday_info(e)`: 读 `e.compass`、`e.task_num` | `data.compass`/`data.task_num`；`COMPASS` 事件→地图页 `updateData()`（罗盘数、鼓舞按钮）；`checkRedot()` | 推 `{compass:<int>, task_num:<int>}`（推送不带 `session`）|
| `museumday_inspire` | `[]`，true | ✅ 鼓舞按钮 `@929862` | `Action1`: 只读 `i.next` | `inspire_num--`；`next=i.next`；罗盘动画；`PATH_UPDATE` | `{next:<int>}` 且 **`next` 必须 ≠ 当前 `next`** |

> 协议参数个数校验：`SocketManage.send` `@336322`
> `if(a.length!=n.length) return void e.Log.error("发送的协议：... 参数与定义参数不匹配...")` —— 所以
> `museumday_start_advance` 必须且只能带 1 个参数 `id`，`museumday_dir_compass` 必须且只能带 `dir`。

---

## 3. 逐命令的客户端源码（逐字引用）

### 3.1 模型骨架 `@149735`–`@154660`

```js
var MuseumDayModel=function(e){function t(){var t=null!==e&&e.apply(this,arguments)||this;
 return t.data={end_time:0,inspire_num:0,inspire_time:0,museum_list:[],cur_museum:0,compass:0,task_num:0,
                frog:0,next:0,left_num:0,desc_id:0,pic_id:0,items:[],get_items:[],log_list:[],path:[]},
 t.hasExploreEmail=!1,t}
 return __extends(t,e),
 t.prototype.initModel=function(){this.addProtocolCallback("museumday_load","museumday_arrive","museumday_info")},
 t.prototype.museumday_arrive=function(){},
 t.prototype.museumday_info=function(e){e&&(this.data.compass=e.compass,this.data.task_num=e.task_num,
      this.dispatchEvent(new core.Event(MuseumDayEventType.COMPASS)),this.checkRedot())},
 t.prototype.museumday_load=function(e){var t=this;this.data=Utils.convertArrayAll(e),
      this.dispatchEvent(new core.Event(MuseumDayEventType.LOAD)),
      this.isOpen()&&(egret.clearTimeout(this.timerActivity),
         this.timerActivity=egret.setTimeout(function(){t.closeActivity()},this,
             1e3*(this.getActivityTime()[1]-core.Time.getServerTime()+1))),
      this.checkRedot()},
```

> ⚠️ `this.data` 默认值里有 `start_time` 吗？**没有** —— 上面这份默认值里没有 `start_time`，
> `{end_time:0,start_time:0}` 只是当前引擎 stub 自己编的。默认对象里 `frog:0` 也**不是**合法的运行时值
> （`setForg` 用 `frog-1` 当下标）。

**事件类型枚举** `@1201731`：

```js
var MuseumDayEventType=function(){function e(){}return e.LOAD="MuseumDayEventType_load",
  e.PATH_UPDATE="MuseumDayEventType_PATH_UPDATE",e.REWARD="MuseumDayEventType_REWARD",
  e.COMPASS="MuseumDayEventType_COMPASS",e}();
```

**方向枚举** `@154979`：

```js
var MuseumDayExploreDir;!function(e){e[e.UP=1]="UP",e[e.DOWN=2]="DOWN",e[e.LEFT=3]="LEFT",
  e[e.RIGHT=4]="RIGHT"}(MuseumDayExploreDir||(MuseumDayExploreDir={}));
```

### 3.2 `museumday_refresh` `@152900`

```js
t.prototype.refresh=function(e){var t=this;
  core.SocketManage.getInstance().send("museumday_refresh",new core.Action2(function(i){
    -1!=i.left_num&&(t.data.left_num=i.left_num,t.request(),e&&e.apply())}))},
```
* `left_num == -1` 被当成「服务端不允许刷新」的哨兵值：**回调体跳过 → 调用方的 `e.apply()` 永不执行**。
  从 `ExploreView.on_btnRefresh_tap` 调时传了 `new core.Action(...)`，那个 Action 是放在
  `ModalConfirm(...,function(){e.getModel(MuseumDayModel).refresh()})` 里的**无参**回调，所以那里没有后续；
  但从 `HistoryView.on_listTask_tap`（times==0 分支）调用时，传入的 Action **负责把它自己关掉并打开地图页**：
  ```js
  }else if(0==i.times)this.getModel(MuseumDayModel).refresh(new core.Action(function(){
      core.PageManage.getInstance().addViewControl(MuseumDayExploreViewControl,...,core.RemoveViewType.Retain,{}),
      egret.setTimeout(function(){return t.close()},t,200)}));
  ```
  → 若 `left_num==-1`，**玩家卡在记录页，什么都不会发生**（死局，不崩）。

### 3.3 `museumday_random_compass` `@153248`

```js
t.prototype.randomCompass=function(e){var t=this;
  core.SocketManage.getInstance().send("museumday_random_compass",new core.Action1(function(i){
    i.next!=t.data.next ? ( t.dispatchEvent(new core.Event(MuseumDayEventType.COMPASS)),
                            t.data.inspire_num=i.inspire,
                            t.data.next=i.next,
                            e&&e.apply(i.next),
                            t.dispatchEvent(new core.Event(MuseumDayEventType.PATH_UPDATE)),
                            t.checkRedot() )
                       : e&&e.apply(0)}))},
```
调用方（`on_btnPlan_tap` `@935224`）：

```js
=function(){var e=this;
  if(this.modelData.path.length==this.modelData.next)GuideHelpView.getInstance().show(_("找到啦！正在赶路~"));
  else if(this.modelData.compass>0){
    this.groupCompassa.visible=!0;
    var t=this.modelData.path[this.modelData.next-1];
    this.getModel(MuseumDayModel).randomCompass(new core.Action1(function(i){
      var n=e.map.getTileDir(t.grid,e.modelData.path[i-1].grid);
      e.compassa.roll(n,!1,function(){e.groupCompassa.visible=!1,e.updatePath(!0)})}))
  } else { /* 罗盘没了：缩放提示 + groupTip 打开 */ }},
```
→ `i==0`（服务端返回的 `next` 与当前相同）时 `e.modelData.path[0-1]` 是 `undefined`，`.grid` 直接抛
`TypeError`。**这是本项目「呱呱吃坏肚子了」崩溃循环的最典型来源。**

### 3.4 `museumday_dir_compass` `@153636`（死代码，留档）

```js
t.prototype.dirCompass=function(e,t){var i=this;
  core.SocketManage.getInstance().send("museumday_dir_compass",new core.Action1(function(e){
    0==e.code&&i.dispatchEvent(new core.Event(MuseumDayEventType.COMPASS)),t&&t.apply()}),e)},
```

### 3.5 `museumday_inspire` `@153864`

```js
t.prototype.req_inspire=function(e){var t=this;
  core.SocketManage.getInstance().send("museumday_inspire",new core.Action1(function(i){
    i.next!=t.data.next ? ( t.data.inspire_num--,
                            t.dispatchEvent(new core.Event(MuseumDayEventType.COMPASS)),
                            t.data.next=i.next, e&&e.apply(i.next),
                            t.dispatchEvent(new core.Event(MuseumDayEventType.PATH_UPDATE)),
                            t.checkRedot() )
                       : e&&e.apply(0)}))},
```
调用方 `@929862`（`btnInspire` 点击）：

```js
this.btnInspire.addEventListener(egret.TouchEvent.TOUCH_TAP,function(){
  if("btn_inspire_on_png"==t.btnInspire.source&&t.modelData.inspire_num>0){
    if(t.modelData.path.length==t.modelData.next)GuideHelpView.getInstance().show(_("找到啦！正在赶路~"));
    else{ t.groupCompassa.visible=!0;
          var e=t.modelData.path[t.modelData.next-1];
          t.getModel(MuseumDayModel).req_inspire(new core.Action1(function(i){
            var n=t.map.getTileDir(e.grid,t.modelData.path[i-1].grid);
            t.compassa.roll(n,!1,function(){t.groupCompassa.visible=!1,t.updatePath(!0)})}))}
  } else { var i=core.DateFormat.format(1e3*t.modelData.inspire_time,core.DateFormater["M月D日h点"]),
                 n="已经积攒了 "+t.modelData.inspire_num+" 次鼓舞\n\n";
           n+="每吃8个饼干就会积攒1次鼓舞\n"+i+"后就能用鼓舞帮蛙蛙前进啦"; t.addChild(new ModalAlert(n))}},this),
```
**`inspire_num` 与 `inspire_time` 的门槛**（`btnInspire.visible` / `source`，`@931400`）：

```js
this.lbInspire.text=String(this.modelData.inspire_num),
this.btnInspire.visible=this.modelData.inspire_time>0,
this.btnInspire.source=core.Time.getServerTime()<this.modelData.inspire_time?"btn_inspire_off_png":"btn_inspire_on_png",
this.lbInspire.visible="btn_inspire_on_png"==this.btnInspire.source},
```
模型侧 `canInspire()` `@154475`（**视图没调用它**，但说明服务端语义）：

```js
t.prototype.canInspire=function(){return this.data.inspire_num<=0?!1:
  core.Time.getServerTime()<this.data.inspire_time?!1:!0},
```
→ **`inspire_time` 必须 > 0**（否则按钮整条 `visible=false`，功能永久消失）；
想要「立刻可用」→ 给一个**过去**的时间戳（例如 `1`）；给未来时间戳则会显示「M月D日h点 后就能用…」。
`museumDayCommon.inspire.v2 = 1701360000`（2023-12-01 00:00 CST）`【推测】`就是原版的解锁时刻。

### 3.6 `museumday_get_items` `@152132`（**一个字都不读回包，除了 code**）

```js
t.prototype.getItems=function(e){var t=this;
  core.SocketManage.getInstance().send("museumday_get_items",new core.Action2(function(i){
    if(0==i.code){
      for(var n={},r=0,o=0,a=t.data.items;o<a.length;o++){var s=a[o];
        n[s.item_id]=s,n[s.item_id].index=r++,
        200002==s.item_id||t.getModel(ItemModel).addHouseItem(s.item_id,s.num)}
      for(var c=0,l=t.data.get_items;c<l.length;c++){var s=l[c];
        n[s.item_id]&&(s.num+=n[s.item_id].num,delete n[s.item_id])}
      var h=[];for(var s in n)h.push(n[s]);
      h.sort(function(e,t){return e.index-t.index});
      for(var u=0,p=h;u<p.length;u++){var s=p[u];t.data.get_items.push({item_id:s.item_id,num:s.num})}
      t.data.items=[];
      t.dispatchEvent(new core.Event(MuseumDayEventType.COMPASS)),
      t.dispatchEvent(new core.Event(MuseumDayEventType.REWARD)),
      e&&e.apply()}}))},
```
要点：
1. **只用 `code`**，物品来自 `data.items` / `data.get_items`（上一次 `museumday_load` 的内容）。
2. `item_id == 200002`（罗盘）**故意不加进背包**（`||` 短路）。
3. 领完后 `data.items=[]`；`REWARD` 事件 → 地图页 `updateRewards()` 显示结算卡。

### 3.7 `museumday_arrive` `@153103`

```js
t.prototype.arrive=function(){core.SocketManage.getInstance().send("museumday_arrive")},
```
发送时**没有 Action**（第 2 参缺省 → `send(t,i)` 里 `i=null` → `u.callbackFun=null`），
回包只走 SE 分发到 `museumday_arrive(){}`（空）。**回包内容完全不影响客户端。**

### 3.8 `museumday_start_advance` `@151631`

```js
t.prototype.request_start_advance=function(e,i){var n=this,
  r=this.getModel(t).data.museum_list.length-Tabikaeru.DataManager.instance().MuseumDayData.length,
  o=Tabikaeru.DataManager.instance().MuseumDayCommonData.get("restart_clover"),
  a=o.v1.split(",").map(function(e){return Number(e)}),
  s=a[Math.max(0,Math.min(a.length-1,r))];
  core.SocketManage.getInstance().send("museumday_start_advance",new core.Action1(function(e){
    0==e.code&&(n.getModel(UserModel).consumeClover(s),n.request(),i&&i.apply())}),e)},
```
* 价格 = `restart_clover.v1.split(",") = [100,200,200]` 取 `clamp(0, len-1, museum_list.length - 4)` 下标：
  `museum_list.length ≤ 4` → **100**；`5` → **200**；`≥6` → **200**。
* `UserModel.consumeClover` `@213252` 是**纯判断、不改值**：
  ```js
  t.prototype.consumeClover=function(e){return this.clover>=e?!0:!1},
  ```
  同时 `addClover=function(e){}`、`addTicket=function(e){}` 都是**空函数** → 三叶草/门票的数字**只能靠服务端推送**更新。

### 3.9 `museumday_info`（推送）`@150216`

```js
t.prototype.museumday_info=function(e){e&&(this.data.compass=e.compass,this.data.task_num=e.task_num,
  this.dispatchEvent(new core.Event(MuseumDayEventType.COMPASS)),this.checkRedot())},
```
推送格式（`run/server/main.js` 第 168–171 行）：`{cmd:"museumday.info", data:{compass,task_num}}`，
**不带 `session`**；客户端的推送分支 `@338450` 只要求 `ServiceDispatcher` 里有同名监听，
而 `MuseumDayModel` 已注册 → 一定会被处理。

### 3.10 `museumday_load`（请求 / 也可推送）

`request()` `@151544`：`send("museumday_load")` —— 无 Action、`needResponse=true`。
调用点只有 3 处（全 bundle 检索 `MuseumDayModel).request()`）：

| 调用点 | 偏移 | 触发条件 |
|---|---|---|
| `ExploreViewControl.open` | 927239 | 打开地图页时 `data.path.length==0` → `request()`（并把 `data` 上报 jf_commit 当 warning）|
| `HistoryViewControl.open` | 942827 | **每次打开记录页都 request()** |
| `request_start_advance` / `refresh` 的回包内 | 151631 / 152900 | 动作成功后 |

`ExploreViewControl.open` `@927239`（逐字）：

```js
t.prototype.open=function(){e.prototype.open.call(this),
  this.addEventListeners(this.onEvent,this,MuseumDayEventType.LOAD,MuseumDayEventType.REWARD,
                          MuseumDayEventType.COMPASS,MuseumDayEventType.PATH_UPDATE),
  this.getModel(MuseumDayModel).data.path.length>0 ? this.view.refresh()
    : (BaseChannel.getInstance().jf_commit(!0,"js.error",
         {reason:"warning",message:"MuseumDayModel.data.path==0",info:this.getModel(MuseumDayModel).data}),
       this.getModel(MuseumDayModel).request()),
  Utils.FpsManager.instance().boost()},
```
> 也就是说：**`path` 为空数组不会崩，只会打一条 warn + 重新 load**（但还是别让它为空：
> 空 path → `setupMap()` 走 `GuideHelpView.show("地图数据错误")` 分支，永远进不了地图）。

### 3.11 事件 → 视图的映射 `@927117`

```js
t.prototype.onEvent=function(e){switch(e.getEventType()){
  case MuseumDayEventType.LOAD:this.view.refresh();break;
  case MuseumDayEventType.REWARD:this.view.updateRewards();break;
  case MuseumDayEventType.COMPASS:this.view.updateData();break;
  case MuseumDayEventType.PATH_UPDATE:this.view.updatePath()}},
```

---

## 4. 回包形状（**含「缺字段就抛」的精确分析**）

### 4.0 为什么「少给一个键」= 崩溃：`Utils.convertArrayAll` `@300427`

```js
function v(e){return Array.isArray(e)?e:[]}                                          // Utils.convertArray  @300384
function _(e){var t={};for(var i in e)"object"==typeof e[i]?t[i]=v(e[i]):t[i]=e[i];return t}   // convertArrayAll @300427
```

逐字结论：

1. **它返回一个全新对象，只含回包里出现过的键** —— 不是把回包 merge 进默认值！
   `MuseumDayModel.museumday_load` 里是 `this.data = Utils.convertArrayAll(e)`（**整体替换**）。
2. 值 `typeof === "object"` 的键（数组、对象、**`null` 也是 object**）→ 强制成数组：是数组就原样，否则 `[]`。
3. 标量（number/string/bool）原样；**缺失的键 = `undefined`**。
4. 所以 `{end_time: 4102444800}`（只给一个键）会让 `data.path === undefined`、`data.items === undefined`……
   然后 `checkRedot()` 里的 `this.data.path.length` **立刻抛 `TypeError`** →
   `window.onerror` → 移除所有窗口 → 「呱呱吃坏肚子了，请重启一下游戏~」→ 页面 reload。
   **这就是「上一个类似活动因为数组/对象形状搞错导致崩溃循环」在博物馆冒险里的具体版本。**

> 对「**数组 of id 还是 数组 of 行对象**」的明确回答：
> 本活动**四个数组全部是"行对象数组"**，没有任何一处是 id 数组：
> `path:[{grid,type,style}]`、`museum_list:[{id,desc_id,time}]`、
> `items/get_items:[{item_id,num}]`、`log_list:[{desc,item_id,item_num,time}]`。
> （对比：别处的 `misc_moment_load` 的 `list`、`EncyModel.unlock_list` 才是 **id 数组** —— 别把那个习惯带过来。）

### 4.1 `museumday_load` —— 必须全给的 16 个键

| 键 | 类型 | 谁读 / 读法 | 缺失/类型错的后果 |
|---|---|---|---|
| `end_time` | int 秒 | `getActivityTime()` → `end_time>0?[1,end_time]:[0,0]`；`isOpen()`；`closeActivity` 定时器；cookie 值；`updateOverDate` 显示 | 缺失 → `undefined>0` false → **窗口关闭**（按钮消失）。这就是常开的开关 |
| `path` | **数组 of `{grid,type,style}`** | `path.length`（`checkRedot` / `updatePath` / `updateData` / `setupMap` / `open`）、`path[next-1].grid`、`path[frog-1].grid`、`render()` 的 `r.grid/r.type/r.style` | 缺失 → **`Cannot read properties of undefined (reading 'length')` @checkRedot**；空数组 → 地图报「地图数据错误」；`grid` 非法 → 图块丢在 (NaN,NaN) |
| `next` | int（1 基，= 已揭示格数） | `path.length!=this.data.next`（红点）、`updatePath` 的 `n+1<=next`、`path[next-1]` | 缺失 → 红点计算 `[]!=undefined` → 红点常亮；`path[NaN-1]` → `undefined.grid` **抛** |
| `frog` | int（1 基，蛙所在格） | `setForg(path[frog-1].grid)`、`frog==next`、`n+1<=frog`、`cur_museum>0&&frog==path.length` 触发结算 | 缺失 → `path[NaN-1].grid` **抛** |
| `compass` | int | `updateCompass()`、红点条件 `compass>0`、`btnPlan` 分支 | 缺失 → `undefined>0` false（不崩，但按钮点了只弹提示）|
| `cur_museum` | int（0 或 1..4） | `0==cur_museum` 决定进记录页还是地图页；`MuseumDayData.get(cur_museum).name`；`updateRewards` 的 `cur_museum>0` | **>0 但不在 1..4 → `MuseumDayData.get()` 返回 undefined → `.name` 抛**；给 0 却打开地图页 → 报「地图数据错误」并自动关窗 |
| `museum_list` | 数组 of `{id,desc_id,time}` | `HistoryView.update` 遍历、`MuseumDayData.length` 比较、`restart_clover` 档位、`CardView` 里 `filter(id==…)` | 缺失 → `update` 里 `a.length` **抛**（`for(var o=0,a=e.museum_list;o<a.length;...)`）|
| `items` | 数组 of `{item_id,num}` | `getItems()`、`updateRewards()` | 缺失 → `o<a.length` **抛** |
| `get_items` | 数组 of `{item_id,num}` | 同上（历史已领） | 同上 |
| `log_list` | 数组 of `{desc,item_id,item_num,time}` | `updateLog()`（取最后一条）、`on_btnLogs_tap`（全量） | 缺失 → `log_list.length` **抛**（`this.modelData.log_list[...]`）|
| `inspire_num` | int | `lbInspire.text`、`btnInspire` 分支 | 缺失 → 显示 "undefined"（不崩）|
| `inspire_time` | int 秒，**>0** | `btnInspire.visible=inspire_time>0`、`source`、`canInspire`、Alert 文案 | 缺失/0 → **鼓舞按钮消失** |
| `task_num` | int 0..8 | `updateTasks()`/`updatCompass()` → `listProgress.value` | 缺失 → 进度点全灭（不崩）|
| `left_num` | int | `btnRefresh.visible=next<=1&&left_num>0`；重开确认框文案 | 缺失 → 按钮消失（不崩）；**但 `-1` 会卡死记录页（见 §3.2）** |
| `desc_id` | int，**401 或 402** | 结算卡 `"end_"+id+"_"+desc_id+"_png"` 与 `MuseumDayDescData.get(desc_id)`→`imageDesc.source` | 取 401/402 以外 → 图片 404 → **空白卡**（不崩）|
| `pic_id` | 任意 | 只被透传进结算卡对象；客户端**不读** | 无所谓 |

> `frog`/`next` 的合法范围：`1 <= frog <= next <= path.length`（`frog` 是 1 基下标，
> `0` 会变成 `path[-1]`）。`next==path.length` 表示「路线已全部揭示」。

### 4.2 `museumday_refresh` 回包

```json
{ "left_num": 2 }
```
* **`left_num` 不能是 `-1`**（`-1!=i.left_num` 是「允许刷新」的判据）；给了 `-1` → 记录页点「下一座博物馆」后**什么都不会发生**。
* 另外服务端要真的换线：回调随后 `request()`，所以紧接着的 `museumday_load` 必须给出新的 `path`
  并且 `cur_museum>0`（否则地图页会「地图数据错误」自动关掉）。
* 语义归属：`【推测】` `left_num` = 本次冒险还能「重新开始」的次数（文案：`是要重新开始新冒险么？\n还能更换{0}次~`）。

### 4.3 `museumday_random_compass` 回包

```json
{ "next": 3, "inspire": 1 }
```
* `next` **必须 ≠ 模型当前的 `next`**（否则调用方拿到 `0`，`path[-1].grid` **抛**）。
* `next` 必须 `<= path.length`（`path[next-1]` 必须在数组里，否则同样 **抛**）。
* `inspire` 是**覆盖赋值**（`data.inspire_num=i.inspire`），所以必须回当前真实值 ——
  只回 `next` 会让 `inspire_num` 变 `undefined`（不崩，但鼓舞数显示 "undefined"）。
* **罗盘数不在回包里**：客户端不会因为这次调用减 `compass`。服务端扣完必须推
  `museumday_info{compass,task_num}`（模型收到会 `COMPASS` → `updateData()` 刷新罗盘数字与按钮）。
  `【推测】`一次随机罗盘 = 揭示 1 格（`next += 1`）——见 §7.2。

### 4.4 `museumday_inspire` 回包

```json
{ "next": 4 }
```
* 同 §4.3：`next` 必须 ≠ 当前值且 `<= path.length`。
* 罗盘数不变；`inspire_num` 由**客户端自己减 1**（`t.data.inspire_num--`），所以服务端也要减 1，
  但**不要再推送 `inspire_num` 回去**（否则与客户端本地减法叠加；`museumday_load` 除外，
  因为 load 会整体替换 data —— 这也是为什么「用 load 推送来同步」比「用 info 推送」安全）。
* 若 `inspire_num` 不足或 `now < inspire_time`，客户端按钮已经拦住（不会发）；
  引擎侧仍建议返回非 0 code（此时客户端只是什么都不做，不会弹任何提示）。

### 4.5 `museumday_get_items` 回包

```json
{ "code": 0 }
```
* 只读 `code`；`0` 才进分支（**不给 `code` 就什么都不会发生**：`0==undefined` 为 false）。
* 服务端在此**必须**把 pending 物品并入"已领取"（`get_items`），否则下一次 `load` 仍报 `items` 非空
  → `updateRewards()` 又弹礼包 + 又发 `get_items` → 无限循环（§8 地雷 5）。

### 4.6 `museumday_arrive` 回包

```json
{ "code": 0 }
```
* 无读取。`needResponse=true`，引擎会给回包（`dispatch()` 里 `reply===undefined → {}`），
  所以返回 `undefined` 也能跑，但建议显式 `{code:0}` 便于日志。

### 4.7 `museumday_start_advance` 回包

```json
{ "code": 0 }
```
* 只读 `code`；非 0 → 客户端**静默什么都不做**（连"三叶草不足"都不弹，那句提示是客户端本地判断的）。
* 服务端要做：校验 `id`（**0 = 自动挑一座**）、校验/扣三叶草（`restart_clover` 档位）、
  生成新 `path`、置 `cur_museum`、`frog=next=1`、清空 `items`，然后**主动推一次 `clover_update`**
  （因为客户端 `consumeClover` 只判断不减、`addClover` 是空函数）。

### 4.8 `museumday_info` 推送

```json
{ "compass": 7, "task_num": 3 }
```
* 只需这两个字段（`museumday_info` 不替换 data，是逐字段赋值，所以这里**少字段是安全的** ——
  唯一的例外是如果在此之前从未有过成功的 `museumday_load`：`checkRedot()` 会求值
  `this.data.path.length`，而此时 `isOpen()` 为假（`end_time` 还是默认 0）→ `&&` 短路 → 安全。
  **但一旦常开生效（`end_time>0` 且已经过一次 load），`path` 一定存在 → 也安全。**

### 4.9 引擎回包的通用约定（`run/engine/index.js`）

```js
// dispatch() 第 5307-5314 行
let reply;
try { reply = h(data || {}, ctx); } catch (e) { ... reply = def && def.needResponse ? {} : undefined; }
if (reply === undefined && def && def.needResponse) reply = {};      // ← 没有 handler / 抛异常 = 回 {}
```
* **没写 handler 或 handler 抛异常 → 回 `{}` → `convertArrayAll({})` → `data={}` →
  `checkRedot()` 抛 → 崩溃循环。** 所以 `museumday_load` 的 handler 必须是第一个写的、且不能抛。
* 回包到客户端的形态由 `run/server/main.js` 第 160–167 行决定：
  有 `session` → `{session, data}`；无 `session` → `{cmd, data}`（推送）。

---

## 5. 数据表

### 5.1 `museumDayData`（4 行，**KeyGetter**：`src[key]` 直取）

`DataManager.MuseumDayData = t("museumDayData")` `@407155`，其中
`function t(e){return new o(e,RES.getRes(e+"_json"))}`（`o` = `KeyGetter`，`@403700` 起）。
**所以 `.get("1")` / `.get(1)` 都行（JS 属性名会转字符串），`.length` = `Object.keys().length`。**
> 注意 `t()`（KeyGetter）和 `i()`（IdGetter）不是一回事：**只有 KeyGetter 有 `.length` 属性**
> （`Object.defineProperty(o.prototype,"length",{get:...})` `@404033`），IdGetter 只有 `.count()`。
> 客户端对这三张表用的都是 `t()`（`MuseumDayDescData=t(...)` `@407067`、`MuseumDayCommonData=t(...)` `@407109`），
> 正因为要 `.length`。→ **引擎必须照原样返回"以 id 字符串为键的对象"**（返回数组其实也巧合能用，
> 但别改）。

```json
{ "1": { "id": 1, "name": "江西省博物馆" },
  "2": { "id": 2, "name": "山东博物馆" },
  "3": { "id": 3, "name": "南越王博物院" },
  "4": { "id": 4, "name": "吴文化博物馆" } }
```
* 只有 4 家 → `MuseumDayData.length == 4`，这就是价格公式里的「4」。
* 全表**只有 `{id,name}`**（没有 `pic`）—— `CardItem.dataChanged` 里 `formatPathImage(t.pic)` 恒得 `""`，
  随后被 `"end_"+id+"_"+desc_id+"_png"` 覆盖。**不要指望这张表给图片。**

### 5.2 `museumDayDesc`（22 行，KeyGetter；值是**字符串**）

`DataManager.MuseumDayDescData = t("museumDayDesc")` `@407067`。**值是文案本身，不是对象。**

| key | 值 | 用途 |
|---|---|---|
| 1 | 好运得到了{0}个{1}，冒险都快乐起来啦~ | 拾取日志（`{0}`=数量, `{1}`=物品名）|
| 2 | 绕了下道，与惊喜碰了个正着，发现了{0}个{1} | 同上 |
| 3 | 看了会风景，竟然还见着{0}个{1} | 同上 |
| 4 | 一阵大风刮过，没想到抓住了{0}个{1} | 同上 |
| 5 | 眼皮底下摇摆，原来是{0}个{1} | 同上 |
| 101 | 遇见备货的嘟嘟，送来{0}个{1}，怪不好意思的 | 同上（NPC 送）|
| 102 | 帮蚂蚁搬个家，收到了{0}个{1}作为谢礼 | 同上 |
| 103 | 捡到的酷石子，与别的蛙换了{0}个{1} | 同上 |
| 104 | 把碰倒的松果堆好，探出头的小松鼠递来了{0}个{1} | 同上 |
| 105 | 帮忙送了几封信，信差递了{0}个{1}过来 | 同上 |
| 201 | 打个盹休息一下~ | **无物品**的过场（无占位符）|
| 202 | 找个地方躲避一下袭来的大风 | 同上 |
| 203 | 回过神来，盯着眼前的景色好久了 | 同上 |
| 204 | 顺着鸟儿们指的路，走了一会又回来了 | 同上 |
| 205 | 不小心栽倒，所幸被几只鸟拉了一把 | 同上 |
| 301 | 神情诡异的双面神人，…了解后获得了1张江西省博物馆门票 | 剧情+门票（对应 museum 1）|
| 302 | 别看我现在是萌萌的亚丑钺，…认识后获得了1张山东博物馆门票 | 剧情+门票（museum 2）|
| 303 | 差点被这小小的铜虎节吓到，…知晓后获得了1张南越王博物院门票 | 剧情+门票（museum 3）|
| 304 | 从一把铜镜开始探吴中，…体会后获得了1张吴文化博物馆门票 | 剧情+门票（museum 4）|
| 305 | 遇见了冒险家兔兔，…冒险次数增加1次 | 剧情+**增加一次冒险** |
| 401 | **end_text_1** | 结算卡右上文案图（`imageDesc.source = 值+"_png"` → `end_text_1_png`）|
| 402 | **end_text_2** | 同上 → `end_text_2_png` |

> 这张表**本身就是奖励事件表**：四个族（1–5 / 101–105 / 201–205 / 301–305）+ 两个结算图键（401/402）。
> `log_list[].desc` 必须取上面的 key；`desc_id`（当前冒险）必须取 **401 或 402**。

### 5.3 `museumDayCommon`（5 行，KeyGetter；**只有 3 个字段被客户端读**）

`DataManager.MuseumDayCommonData = t("museumDayCommon")` `@407109`。

```json
{ "base":           { "v1": "8",        "v2": 1.0,  "v3": 10.0, "v4": 1.0 },
  "inspire":        { "v1": 8.0, "v2": 1701360000.0, "v3": "", "v4": "" },
  "mail_str":       { "v1": "博物馆给你发来了邀请函", "v2": "冒险中未领走的物品", "v3": "回收剩余的罗盘", "v4": "" },
  "open_time":      { "v1": "1700615100", "v2": "1702828799", "v3": "", "v4": "" },
  "restart_clover": { "v1": "100,200,200", "v2": 200.0, "v3": 200.0, "v4": "" } }
```

| 行 | 客户端读？ | 值的意思 |
|---|---|---|
| `base.v4` | ✅ `@944465` | `1==i && museum_list.length>=4 && 0==cur_museum` → 显示「新的一次冒险」按钮（值 `1.0`，`1==1.0` 为真）|
| `base.v3` | ✅ `@945493` | `活动结束后，按1:{0}回收为三叶草` → **回收比率 1:10** |
| `restart_clover.v1` | ✅ `@151822`/`@946202` | `"100,200,200"` 三档三叶草价 |
| `base.v1` = `"8"` | ❌ | `【推测】`每周罗盘上限 / 进度点数量（客户端把 8 个点**硬编码**在 `childrenCreated` 里，见 §7.1）|
| `base.v2` = `1.0` | ❌ | 未知（`【推测】`每次消耗 1 个罗盘）|
| `inspire.v1` = `8.0` | ❌ | `【推测】`与「每吃 8 个饼干积攒 1 次鼓舞」的 8 对应（文案是硬编码在 js 里的）|
| `inspire.v2` = `1701360000` | ❌ | `【推测】`鼓舞解锁时刻（2023-12-01 00:00 CST）|
| `mail_str.v1/v2/v3` | ❌ | **服务端专用**：邀请函标题 / 「冒险中未领走的物品」/「回收剩余的罗盘」|
| `open_time.v1/v2` | ❌ | `1700615100`(2023-11-22 09:05 CST) → `1702828799`(2023-12-17 23:59:59 CST)，**原版活动窗口（跨度 25.6 天）**。客户端不读，但这是我们最接近"原版日期"的证据 |

### 5.4 `item`（`Item.json`，410 行的 **list**，`ItemDB = i("Item")` 按 `id` 建字典）

本活动唯一必需的物品：

```json
{ "id": 200002, "name": "罗盘", "type": 14, "sub_type": 3,
  "info": "跟随罗盘的指引 一起去冒险", "price": "",
  "img": { "index": "goods_58", "src": "Icon/goods" }, "own_num": "", "spend": "" }
```
* `DataType.ItemType.RESOURCE = 14`、`ItemResourceType.COMPASS = 3`（`@409066`/`@409307`）。
* `ItemModel.doAddHouseItem` `@137223`：`type==RESOURCE` 时按 `sub_type` 分流 ——
  `TICKET(2)`→`UserModel.addTicket`、`COMPASS(3)`→`MuseumDayModel.data.compass+=t`、
  `CLOVER(1)`→`addClover`、`WATER(4)`/`CHANGE(5)`→充值页计数，**并且不再进背包**。
  但由于客户端在 `getItems` 里对 `200002` 直接短路，**这段 COMPASS 分流其实不会被触发**。
* 博物馆门票物品：`1017 江西省博物馆门票`、`1018 山东`、`1019 南越王`、`1020 吴文化`、`1021 山西`
  （`type:1`）——与 `museumDayDesc` 的 301–304 文案一一对应。`【自设计】`用它做 301–304 事件的奖励。

### 5.5 和本活动**无关**但要分清的表

* `museumData`（5 行，`IdGetter` by `id`）：属于**另一个**「博物馆/门票」子系统（`MuseumModel`、`MuseumDB`），
  有 `pic_id/collection_id/ticket/info_ticket/switch` 等字段。博物馆冒险**不读它**，别混用。
* `origin` / `gameplay` / `calendarData`：无关。

### 5.6 缺失的表

**没有**任何一张「博物馆冒险地图/路径/掉落」表：
`gamedata.json` 的 60 张表里没有任何 `museum*Path*`（对比 `tumblerPathData` 是有的）。
→ **路径形状、每格掉落、罗盘推进步数在原版就是服务端算的，本地数据表里查不到**（见 §7.2）。

---

## 6. 素材（**63 个文件**，全部在 `run\web\resource\China\images\Scene\MuseumDay\`）

```powershell
Get-ChildItem H:\AI\frog\work\run\web\resource\China\images\Scene\MuseumDay -Recurse -File
# → 63
```
三组（括号内为数量）：

**`Bg_ui\`（36）** —— 背景/UI 图
`arrival_seal_1.png arrival_seal_2.png arrival_seal_3.png back_line_head.png back_line_loop.png
bg_cell.png bg_event.png bg_little_compass.png bg_museum_day.png bg_plan.png bg_question.png
bg_record.png bg_reward.png compass1.png compass2.png end_1_401.png end_1_402.png end_2_401.png
end_2_402.png end_3_401.png end_3_402.png end_4_401.png end_4_402.png end_nail.png end_text_1.png
end_text_2.png little_blank.png little_compass.png little_line.png main_title.png
museum_invitation.png record_title.png text_arrive.png text_question.png text_record.png text_reward.png`

**`cell\`（16）** —— 地图格（`MuseumDayUtils.getTileResource(type,style)="md_cell_"+type+"_"+style+"_png"` `@949968`）
`md_cell_0_0 md_cell_0_1 md_cell_0_2 md_cell_0_3 md_cell_0_4 md_cell_1_1 md_cell_1_2 md_cell_1_3
 md_cell_2_1 md_cell_2_2 md_cell_3_1 md_cell_3_2 md_cell_3_3 md_cell_4_1 md_cell_4_2 md_cell_4_3`（.png）

**`museum_day_btn\`（11）**
`btn_end_explore.png btn_event_log.png btn_explore.png btn_goto_explore.png btn_inspire_off.png
btn_inspire_on.png btn_keep_explore.png btn_more_times.png btn_new_explore.png btn_other.png btn_try_plan.png`

### 6.1 素材 → UI 部件的对应（依据：`thm` 里 5 个博物馆冒险皮肤 + client 里动态拼的 source）

| 素材 | 用在哪（来源）|
|---|---|
| `md_cell_0_0_png` | **起点格**（格 0 号样式）；`$Skin424` 里 `targetimg.source` 初值也是 `md_cell_0_1_png` |
| `md_cell_0_1 … 0_4_png` | **目标格**：`setTarget(grid,museum_id)` → `"md_cell_0_"+cur_museum+"_png"`（`@939243`）→ **style = 博物馆 id（1..4）**|
| `md_cell_1_* (3)` | 草丛/灌木/树（装饰性地形）|
| `md_cell_2_* (2)` | 石板路 / 土路（**"路"的观感**）|
| `md_cell_3_* (3)` | 山 / 丘陵 / 雪山（装饰）|
| `md_cell_4_* (3)` | 水波 / 水纹 / 深水（装饰）|
| `end_<id>_<401\|402>_png`（8 个） | 结算卡大图：`CardItem` 里 `imgPicture.source="end_"+data.id+"_"+data.desc_id+"_png"`（`@924887`）——**运行时拼接，无字面引用** |
| `end_text_1_png` / `end_text_2_png` | 结算卡文案图：`imageDesc.source = MuseumDayDescData.get(desc_id)+"_png"`（值就是 `end_text_1/2`）——**运行时拼接** |
| `arrival_seal_1..3_png` | 记录页印章：`imgStamp.source="arrival_seal_"+Math.min(3,times)+"_png"`（`@947699`）；皮肤里只有 `arrival_seal_1_png` 字面量 |
| `little_compass_png` / `little_blank_png` | 8 个进度点（`setLabelFunction`：`e>=t?little_compass:little_blank`）；皮肤里各 8 个 `little_blank_png` 字面量 |
| `little_line_png` | 进度点之间的连线（Explore + History 皮肤各 1 处）|
| `btn_inspire_on_png` / `btn_inspire_off_png` | 鼓舞按钮；`source` 由 `serverTime<inspire_time` 决定（`@931400`）。皮肤初值 `btn_inspire_on_png`；`btn_inspire_off_png` **只出现在 js 字面量**里 |
| `btn_try_plan_png` | 「尝试规划」= `btnPlan`（消耗随机罗盘）|
| `btn_event_log_png` | 事件日志按钮 `btnLogs`（Explore 皮肤 `_Image1`）|
| `btn_more_times_png` | `btnTips`（提示开合）|
| `btn_other_png` | Explore 皮肤里的匿名按钮图（`_Image1`）|
| `btn_new_explore_png` | 记录页「新的一次冒险」`btnStartExplore`（`base.v4==1 && 4 家全逛过`）|
| `btn_keep_explore_png` | 记录页列表项的两个状态图（`_Image1`/`_Image2`）|
| `btn_goto_explore_png` | 邀请函弹窗的「出发」按钮 `btnStart` |
| `btn_end_explore_png` | 结算卡按钮（CardViewSkin `_Image1`）|
| `text_arrive_png` | 结算卡**「可领取」态**的标题图：CardViewSkin 的 `arrive` 状态里 `new eui.SetProperty("_Image2","source","text_arrive_png")`（`thm@929098`）——由 `CardItem.dataChanged` 的 `currentState="arrive"` 触发 |
| `text_record_png` | 结算卡**普通态**的标题图（`_Image2` 初值）|
| `museum_invitation_png` | 邀请函弹窗整张底图 `MuseumDayPopupView` 的 `cover`（PopupViewSkin `_Image1`）|
| `bg_museum_day_png` | 地图页大背景（ExploreViewSkin `_Image15`）|
| `bg_cell_png` | 地图区底板（ExploreViewSkin `_Image17`，紧邻 `map` 元素，`verticalCenter=-52` 与地图相同）|
| `bg_plan_png` | 罗盘/规划区底衬（Explore 2 处）|
| `text_question_png` | 提示层的「?」图（Explore/History 各 1 处，位于 8 个进度点旁）|
| `bg_reward_png` + `text_reward_png` | 奖励列表底衬/标题（Explore 3 处 / 2 处，History 各 1 处）|
| `bg_record_png` + `record_title_png` + `text_record_png` | 记录页底衬/标题（也用于结算卡 `group`）|
| `bg_event_png` | 日志单条底衬（`groupSingleLog` 的 `_Image20`）|
| `bg_little_compass_png` + `little_compass_png` | 记录页右上罗盘计数（`btnTip` 与 `btnTip._Image15`）|
| `compass1_png` / `compass2_png` | 罗盘底盘 / 指针（`MuseumDayExploreCompass` 子皮肤的 `bg` / `thumb`）|
| `main_title.png` | 地图页顶部标题（Explore 皮肤 `_Image2`，挂在 `btnClose` 上）|
| `end_nail.png` | 目标格上的图钉（`$Skin424` 的 `_Image1`）|
| **未使用**：`bg_question.png`、`btn_explore.png`、`back_line_head.png`、`back_line_loop.png` | `thm` 与 `main.min.js` 里**字面引用数都是 0**（也没有运行时拼接它们）→ 遗留素材，不参与本功能 |

### 6.2 资源注册方式（**没有 group 前提**）

* 63 个文件**全部**在 `run\web\resource\China\default.res.json` 的 `resources` 里，`name = basename+"_png"`
  （例：`{"url":"images/Scene/MuseumDay/cell/md_cell_0_0.png","type":"image","name":"md_cell_0_0_png"}`）。
* 它们属于名为 **`image`** 的资源组（1024 键，含这 16+18 个），但**启动时并不加载 `image` 组**
  （`loadGroups()` `@753493` 只加载 `["config","system","system2","mainout","sheet"]` + `music_App` + `seasonXX`）。
* 之所以仍能显示：`eui.Image.source` 的 setter → `parseSource()` → `eui.getAssets()` → 注册的自定义
  `AssetAdapter.getAsset` `@247345`：
  ```js
  e.prototype.getAsset=function(e,t,i){function n(n){t.call(i,n,e)}
    if(RES.hasRes(e)){var r=RES.getRes(e); r?n(r):RES.getResAsync(e,n,this)}
    else RES.getResByUrl(e,n,this,RES.ResourceItem.TYPE_IMAGE)};
  ```
  → 已注册但未加载 → 按 URL 异步取本地 png（离线可用）；**未注册的名字** → 当成 URL 去取 → 404 → 回调 `null`
  → `egret.is(null,"egret.Texture")` 为假 → **图块空白**（不崩，但控制台有 404）。
* 结论：**只能用上面 16 个已注册的 `(type,style)` 组合**；`md_cell_1_0_png`、`md_cell_5_1_png`
  之类会得到空白格。

### 6.3 逐文件审计（63/63 都已注册；`thm`/`cli` = 字面引用次数）

> 生成方式：遍历 `images\Scene\MuseumDay\` 下每个文件，把 `<basename>_png` 在
> `default.thm.js` / `main.min.js` 里的字面出现次数与 `default.res.json` 的注册名一起统计。
> `0/0` 且**没有运行时拼接**的 4 个文件才是真正的遗留素材（见 §6.1 最后一行）。

| 文件 | 资源名 | thm | cli |
|---|---|---|---|
| `Bg_ui\arrival_seal_1.png` | `arrival_seal_1_png` | 1 | 0 |
| `Bg_ui\arrival_seal_2.png` | `arrival_seal_2_png` | 0 | 0（运行时拼）|
| `Bg_ui\arrival_seal_3.png` | `arrival_seal_3_png` | 0 | 0（运行时拼）|
| `Bg_ui\back_line_head.png` | `back_line_head_png` | 0 | 0 ← **遗留** |
| `Bg_ui\back_line_loop.png` | `back_line_loop_png` | 0 | 0 ← **遗留** |
| `Bg_ui\bg_cell.png` | `bg_cell_png` | 1 | 0 |
| `Bg_ui\bg_event.png` | `bg_event_png` | 1 | 0 |
| `Bg_ui\bg_little_compass.png` | `bg_little_compass_png` | 1 | 0 |
| `Bg_ui\bg_museum_day.png` | `bg_museum_day_png` | 1 | 0 |
| `Bg_ui\bg_plan.png` | `bg_plan_png` | 2 | 0 |
| `Bg_ui\bg_question.png` | `bg_question_png` | 0 | 0 ← **遗留** |
| `Bg_ui\bg_record.png` | `bg_record_png` | 1 | 0 |
| `Bg_ui\bg_reward.png` | `bg_reward_png` | 3 | 0 |
| `Bg_ui\compass1.png` | `compass1_png` | 1 | 0 |
| `Bg_ui\compass2.png` | `compass2_png` | 1 | 0 |
| `Bg_ui\end_1_401.png` … `end_4_402.png`（8 个） | `end_<id>_<401\|402>_png` | 0 | 0（运行时拼 `"end_"+id+"_"+desc_id+"_png"`）|
| `Bg_ui\end_nail.png` | `end_nail_png` | 1 | 0 |
| `Bg_ui\end_text_1.png` / `end_text_2.png` | `end_text_1/2_png` | 0 | 0（运行时拼 `desc 值+"_png"`）|
| `Bg_ui\little_blank.png` | `little_blank_png` | 16 | 2 |
| `Bg_ui\little_compass.png` | `little_compass_png` | 2 | 2 |
| `Bg_ui\little_line.png` | `little_line_png` | 2 | 0 |
| `Bg_ui\main_title.png` | `main_title_png` | 1 | 0 |
| `Bg_ui\museum_invitation.png` | `museum_invitation_png` | 1 | 0 |
| `Bg_ui\record_title.png` | `record_title_png` | 1 | 0 |
| `Bg_ui\text_arrive.png` | `text_arrive_png` | 1 | 0 |
| `Bg_ui\text_question.png` | `text_question_png` | 2 | 0 |
| `Bg_ui\text_record.png` | `text_record_png` | 1 | 0 |
| `Bg_ui\text_reward.png` | `text_reward_png` | 2 | 0 |
| `cell\md_cell_0_1.png` | `md_cell_0_1_png` | 1 | 0 |
| `cell\` 其余 15 个 `md_cell_<t>_<s>.png` | `md_cell_<t>_<s>_png` | 0 | 0（运行时拼 `"md_cell_"+type+"_"+style+"_png"`）|
| `museum_day_btn\btn_end_explore.png` | `btn_end_explore_png` | 1 | 0 |
| `museum_day_btn\btn_event_log.png` | `btn_event_log_png` | 1 | 0 |
| `museum_day_btn\btn_explore.png` | `btn_explore_png` | 0 | 0 ← **遗留** |
| `museum_day_btn\btn_goto_explore.png` | `btn_goto_explore_png` | 1 | 0 |
| `museum_day_btn\btn_inspire_off.png` | `btn_inspire_off_png` | 0 | 1 |
| `museum_day_btn\btn_inspire_on.png` | `btn_inspire_on_png` | 1 | 3 |
| `museum_day_btn\btn_keep_explore.png` | `btn_keep_explore_png` | 2 | 0 |
| `museum_day_btn\btn_more_times.png` | `btn_more_times_png` | 1 | 0 |
| `museum_day_btn\btn_new_explore.png` | `btn_new_explore_png` | 1 | 0 |
| `museum_day_btn\btn_other.png` | `btn_other_png` | 1 | 0 |
| `museum_day_btn\btn_try_plan.png` | `btn_try_plan_png` | 1 | 0 |

（上表把同类行合并了；逐文件展开 63 行见 `Get-ChildItem ... -Recurse -File` 与
`default.res.json` 的 `resources` 交叉比对，两边都是 63 条、一一对应。）

> 补充：5 个博物馆冒险皮肤里还大量引用了**不在本目录**的通用素材，别误判为博物馆冒险美术：
> `explore_84_88_png`（主界面按钮图）、`record_84_88_png` / `back_84_88_png`（按钮框）、
> `frame_16_png` / `frame_10_png` / `frame_empty_png` / `frame_small_png`（通用框）、
> `back_museum_day_png` / `back_record_png`、`share_btn_png`、`goods_40_png`、`yes_png` / `no_png`、
> `new_title_png` / `maintain_bg_png` / `title_1_png` / `marquee_tuichu_png` / `special_notice_png`
> （后面这 5 个来自 `MuseumDayPopupViewSkin` —— 该皮肤是从通用弹窗/维护皮肤改的，皮肤里的
> `i_frog`/`i_pic`/`i_title`/`t_desc`/`t_error`/`c_msg` 等元素 `MuseumDayPopupView` **根本不用**，
> 该视图只 wire 了 `cover` 和 `btnStart`）。

---

## 7. 能复原的规则 / 不能复原的规则

### 7.1 客户端里能直接读到的规则（有依据）

| 规则 | 依据 |
|---|---|
| 开窗只看 `end_time`（`[1,end_time]`） | `@154235`/`@154335` |
| 罗盘就是物品 `200002`（`type 14 / sub_type 3`），领取时被跳过不进背包 | `@152132` + `Item.json` |
| 地图是 **7 列 × 5 行**，共 35 格；`grid = 1 + col + 7*row`；格子 54px，棋盘 378×270（组件 370×270） | `t.COLS=5,t.ROWS=7,t.TILESIZE=54` `@938394`；`indexToMap(e)` `@940033` = `Point((e-1)%7, (e-1)/7|0)` |
| 格子方向由相邻两格的坐标差决定（同列 → UP/DOWN，同行 → LEFT/RIGHT） | `getTileDir` `@940701` |
| 图块资源 = `md_cell_<type>_<style>_png`；目标格固定 `type=0,style=cur_museum` | `@949968` / `setTarget` `@939243` |
| 已揭示但蛙还没走到的格子 = 半透明（`alpha=.5`）；未揭示 = 不可见 | `render()` `@940934` `0==t.enabled?i.alpha=.5:i.alpha=1` |
| `next` = 已揭示格数；`frog` = 蛙所在格（1 基）；`frog!=next` 时蛙播跳跃动画，`frog==next` 播眨眼 | `updatePath` `@933677` + `setForgEffect` `@938835` |
| 8 个罗盘进度点 = `task_num` | `childrenCreated` `@930093`（`setItems([{value:1}..{value:8}])`）+ `updateTasks` `@931725` |
| **罗盘获取文案**（皮肤内文案，非 js）：`﹡每周一0点刷新数量` / `每日登录、分享可各得1个；每次旅行可得1个` | `thm`（ExploreViewSkin `listProgress` 附近的两个 Label）|
| 「每吃 8 个饼干就会积攒 1 次鼓舞」；`inspire_num>0` 且 `now>=inspire_time` 才能用；鼓舞让蛙前进 | `@929862`（Alert 文案）+ `@931400` + `canInspire` `@154475` |
| 重新开始的价格 = `[100,200,200]` 按 `clamp(museum_list.length-4, 0, 2)` | `@151822` / `@946202` |
| 活动结束后物品按 **1:10** 回收成三叶草 | `@945493` + `base.v3=10` |
| 记录页上限/按钮门槛：`museum_list.length>=4 && cur_museum==0 && base.v4==1` 才出现「新的一次冒险」 | `@944303` |
| 一个馆最多盖 3 个印章（`Math.min(3,times)`） | `@947699` |
| 结算卡的 desc 图只能是 401/402（见 §5.2） | `@924887` + `MuseumDayDescData` |
| 邀请函弹窗只会弹一次（cookie 以 `end_time` 为键） | `@948724` + `@878260` |
| 邮件入口：`Mail.EvtId.Explor=12` 且未打开 → 邮箱图标变样、点开进活动（**不看 isOpen**） | `@413192` / `@203115` / `@795528` |
| 「未领走的物品」/「回收剩余的罗盘」邮件标题 | `museumDayCommon.mail_str.v2/v3`（服务端用）|

### 7.2 **原服务端规则，客户端+数据表都查不到 —— 必须自设计并如实标注**

| 未知项 | 状态 | 我们只能怎么定 |
|---|---|---|
| 每家博物馆的**路径形状**（格序列、拐弯） | **不可复原**。没有路径表，`path` 完全由服务端生成 | `【自设计】`：从 35 格里生成一条**正交相邻**的走线，起点=左下图块、终点=`(type0, style=cur_museum)`，长度例如 10–14 格；装饰格随机取 `(1,*)`/`(3,*)`/`(4,*)`，路格取 `(2,1)`/`(2,2)` |
| 每次罗盘推进**几格** | 不可复原。客户端只把 `next` 换成回包值 | `【自设计】`：`+1`（与 `base.v2=1.0`、一次一个罗盘相配）|
| 罗盘的**初始数量**、每周上限 8 的刷新实现 | 不可复原（`base.v1="8"` 只是数据）| `【自设计】`：初始 8，周任务：每日登录 +1、分享 +1、每次旅行 +1，上限 8，周一 0 点重置（**文案在皮肤里，是原版 UI 文案**，所以这套规则最贴近原版）|
| 蛙**怎么前进**（`frog` 何时 +1） | 不可复原。客户端**从不**推进 `frog`，只能由服务端在 `museumday_load`（或推送）里给新值 | `【自设计】`：`frog` 随 `next` 一起前进（tick 或每次罗盘后 `frog=next`），并在变化后**推一次 `museumday_load`** |
| 每格**掉落**与概率 | 不可复原（表里没有）| `【自设计】`：用 `log_list[].desc` 的四个族做事件池（1–5/101–105 给物品、201–205 空手、301–304 给对应门票 `1017+id-1`、305 给 extra 次数）；概率自定 |
| 每格**触发几次**随机罗盘才到位；`next` 是否等于"已揭示"还是"目标" | 不可复原 | `【自设计】`：`next` = 已揭示格数，`next+1` 每用一个罗盘 |
| `museumday_dir_compass` 的语义（花罗盘指定方向？）| **不可复原 + 客户端根本不发**（无调用点）| 只留一个 no-op handler：`({code:0})`，或按 `dir`(1..4) 在棋盘上朝该方向找下一格。别投入 |
| `museumday_load_path` 的语义 | **不可复原 + 客户端根本不发** | `() => ({})` |
| `base.v2`、`inspire.v2` 的确切用途 | 表里在、客户端不读 | `【推测】`：`base.v2`=每次消耗罗盘数 1、`inspire.v2`=鼓舞解锁时刻 |
| `log_list[].time` 的语义 | 客户端按秒格式化（`1e3*s.time`，`YYYY.M.D` / `hh:mm`），并用 `core.Time.isSameDay` 分组 | 秒级时间戳（与全项目一致）|
| 活动结束后「回收」的执行时机 | 客户端只显示 1:10 的文案，**没有任何回收逻辑** | `【自设计】`：服务端在窗口关闭后把 `get_items`/`items` 按 1:10 折算三叶草并发邮件（标题用 `mail_str.v3`）|

---

## 8. 地雷清单（每条都是"会崩/会死局"的具体机制）

> 背景机制：任何未捕获异常 → `window.onerror` `@233265` → 清空 WindowLayer/LoaderLayer/NoticeLayer + 弹窗层
> → `reloading(Reload.JSError)` → `ModalConfirm("呱呱吃坏肚子了，请重启一下游戏~")` → `webReload()`。
> 如果坏 payload 会随每次启动再次取回，就是**崩溃-重载死循环**。

1. **【头号地雷】`museumday_load` 少给任何一个模型字段（尤其 `path`/`items`/`get_items`/`log_list`/`museum_list`）**
   —— 而它**只在 `isOpen()` 为真时才炸**：`checkRedot()` = `this.isOpen() && this.data.path.length!=this.data.next && ...`，
   `end_time<=0` 时 `&&` 短路，所以**现在的 stub（`{end_time:0,start_time:0}`）恰好不会崩**；
   一旦你为了"常开"把 `end_time` 设成未来值，`path` 缺失就 100% 抛 → 崩溃重载循环。
   * 触发点：`checkRedot` `@154600`；若地图页开着，`LOAD` 先触发 `refresh()` → `updateData`/`updateRewards`/`setupMap`/`updateLog` 里各有一处 `.length`/`.

2. **`museumday_load` 的 `cur_museum` 取 1..4 以外但 >0** → `MuseumDayData.get(cur_museum).name` `@931266` 抛
   （`MuseumDayData` 只有 1..4）。
   **`cur_museum==0` 时客户端会拒绝开地图页**（`updateData` → `GuideHelpView.show("地图数据错误")` + `this.close()`），
   所以「记录页选馆 → 地图页」这条路上服务端必须在 `refresh`/`start_advance` 里就把 `cur_museum` 定成 1..4。

3. **`randomCompass`/`req_inspire` 回包里 `next` 与当前 `next` 相同** → 模型走 `e.apply(0)` 分支 →
   调用方 `path[i-1].grid`（i=0）→ `undefined.grid` → **抛**。
   （注意：`next` 相同也包括"服务端没变、玩家又点了一次"。**必须每次调用都变**，或者干脆回 `next+0` 之外的推进。）

4. **`next` > `path.length`**（或 `frog` 越界/为 0）→ `path[next-1]`/`path[frog-1]` 为 `undefined` → `.grid` **抛**
   （`setupMap` 的 `setForg(path[frog-1].grid)`、`updatePath`、`on_btnPlan_tap` 都有）。

5. **`items` 领了不清** → `updateRewards()` 每次 `LOAD` 都发现待领物品 → 又弹 `GiftPackageViewController`
   + 又发 `museumday_get_items` → 弹窗刷屏/循环（不崩但完全废）。
   记住：`get_items` 的回包**只用于判断成功**，物品来源是模型里的 `items`。
   同时 `data.items` 会被客户端清成 `[]`，所以**下一次 `museumday_load` 必须回 `items: []`**。

6. **`museumday_start_advance` 的价格/扣费双记账**：客户端 `consumeClover(s)` 只是 `this.clover>=e` 的判断，
   **不会改数字**；`addClover`/`addTicket` 是空函数 → 三叶草/门票/罗盘**只能由服务端推送**更新。
   所以扣费后必须 `ctx.push('clover_update', {clover: state.clover})`，否则 UI 长期显示旧值。

7. **`museumday_refresh` 回 `left_num:-1`** → 记录页 times==0 的行点下去**永远打不开地图页**（死局，非崩溃）。
   想禁用刷新就把 `left_num` 给 0（`-1!=0` 为真，回调会执行）。

8. **`museumday_get_items` / `museumday_start_advance` / `museumday_dir_compass` 回包不给 `code`** →
   `0==undefined` 为 false → 回调体整段跳过 → 玩家点了没反应（死局）。**这三个必须显式 `code:0`。**

9. **`egret.setTimeout` 的延迟溢出**（§1.5 A）：`end_time` 太远（>24.8 天）时，
   `1e3*(end_time-now+1)` 超过 int32 → 不同引擎会导致定时器**立刻触发**（→ `closeActivity()` 把你正在看的
   记录页关掉并弹「春游活动已结束」）或截断到 ~24.8 天。**用滚动窗口（now+20 天）规避。**

10. **`museumday_info` 在没有任何 `museumday_load` 之前推送**：安全（`isOpen()` 假 → 短路）。
    但**反过来**：如果先推了一个只带 `end_time` 的畸形 `museumday_load`，再推 `museumday_info`，
    第二次 `checkRedot()` 就会抛。→ **不要用推送替代完整 load。**

11. **协议参数个数**：`museumday_start_advance` 必须恰好 1 个参数（`id`），
    `museumday_dir_compass` 必须恰好 1 个（`dir`）；个数不符时客户端**直接放弃发送**（`@336322` 的 `a.length!=n.length` 分支）
    → 看起来像"按钮坏了"。

12. **推送格式**：推送**不能带 `session`**（带了会被当成回包去查 `activateProtocol[session]`，查不到就整条丢弃，
    `@338450`/`@337865`）。命令名走 `toWire()`（**只把第一个 `_` 换成 `.`**）：`museumday_info → "museumday.info"`、
    `museumday_load → "museumday.load"`；客户端 `cmd.replace(".","_")` 还原。

13. **`desc_id` 必须 401/402**；`log_list[].desc` 必须是 §5.2 的键。取错只是 404/空白文案（不崩），
    但会让结算卡变成白板。

14. **`museumday_load` 里 `frog=0`【不要用】**：`setForg(path[frog-1].grid)` → `path[-1]` → 抛。最小值 1。

15. **`path` 非空但 `grid` 越界/重复**：`render()` 会为越界 grid 建图块（位置 `NaN`），
    `t[r.grid]=!0` 用 object key 去重 → 重复 grid 只画一个。不会崩，但棋盘会缺格。
    `grid` 只能是 **1..35**。

16. **记录页占位行显示垃圾日期**：`update()` 里 `n.push({id:0,times:0})` 没有 `time`，
    渲染时 `DateFormat.format(1e3*undefined)` → 类似 "NaN.NaN.NaN"。
    **这是客户端自身的显示问题，服务端无法修**（不要为了修它往 `museum_list` 里塞 `id:0` 的行——
    那会让 `MuseumDayData.get(0)` 为 undefined，`times>0` 时 `.name` **抛**）。

17. **模型里 `inspire_time` 给 0 或缺失** → 鼓舞按钮 `visible=false`，功能彻底消失（不是崩溃，但等于没做）。

18. **`items` 里给 `item_id` 不存在的值**：`getItems` → `ItemModel.addHouseItem` → `doAddHouseItem` 里
    `getItemInfo(e)` 为 undefined → 整段 `if(n){...}` 跳过（安全）；但礼包弹窗 `DropItemRender` 的
    `ItemDB.get()` 也是 undefined → 图标空（安全）。仍建议只用真实 id。

---

## 9. 建议实现骨架（数值里的 `【自设计】` 必须如实标注）

> 只是规格层面的伪代码，**不是**要改 `engine/index.js` 的补丁。

```js
/* --- 常开参数（【自设计】）--------------------------------------------- */
const MD_OPEN_MODE   = 'rolling';      // 'rolling'(推荐) | 'fixed'
const MD_ROLL_DAYS   = 20;             // rolling: end_time = now + 20d（1.728e9ms < 2^31-1）
const MD_FIXED_END   = 4102444800;     // fixed: 2100-01-01Z（注意 §8 地雷 9）
const MD_MUSEUMS     = [1,2,3,4];      // museumDayData 的 id
const MD_DESC_END    = 401;            // 结算卡 desc_id ∈ {401,402}
const MD_COMPASS_ID  = 200002;         // 罗盘（ItemDB, type14/sub_type3），不背包
const MD_TICKET_ID   = { 1:1017, 2:1018, 3:1019, 4:1020 };   // Item.json
const MD_INSPIRE_PER = 8;              // museumDayCommon.inspire.v1（"每吃8个饼干"）
const MD_WEEK_CAP    = 8;              // museumDayCommon.base.v1
const MD_RECYCLE     = 10;             // museumDayCommon.base.v3（1:10 回收）
const MD_RESET_PRICE = [100,200,200];  // museumDayCommon.restart_clover.v1
const MD_GRID_W      = 7, MD_GRID_H = 5, MD_GRIDS = 35;      // 客户端硬编码

/* --- 状态 ------------------------------------------------------------- */
// state.museumday = {
//   endTime, inspireNum, inspireTime, compass, taskNum, leftNum,
//   curMuseum, frog, next, path:[{grid,type,style}], items:[{item_id,num}],
//   getItems:[{item_id,num}], logList:[{desc,item_id,item_num,time}],
//   museums:[{id,desc_id,time}]        // 服务端自己的 museum_list
// }

/* --- museumday_load：**唯一不能出错的那一条** ------------------------- */
museumday_load: (d, ctx) => {
  const s = ensureMuseumday();
  s.endTime = openMode('rolling') ? nowSec() + MD_ROLL_DAYS*86400 : MD_FIXED_END;
  // 16 个键一个都不能少；4 个数组必须是"行对象数组"，不是 id 数组
  return {
    end_time:    s.endTime,                 // ← 常开的开关（>0 且 >= now）
    start_time:  0,                         // ← 客户端不读，留着可读性
    inspire_num: s.inspireNum|0,
    inspire_time: 1,                        // ← 【自设计】>0 且已是过去 → 按钮立刻可用
    museum_list: s.museums.map(m => ({id:m.id, desc_id:m.desc_id, time:m.time})),
    cur_museum:  s.curMuseum|0,             // 0 或 1..4（绝不给 5+）
    compass:     s.compass|0,
    task_num:    s.taskNum|0,               // 0..8
    frog:        s.curMuseum ? Math.max(1, Math.min(s.frog, s.path.length)) : 1,
    next:        s.curMuseum ? Math.max(1, Math.min(s.next, s.path.length)) : 1,
    left_num:    s.leftNum|0,               // 绝不回 -1
    desc_id:     MD_DESC_END,               // 401 / 402
    pic_id:      0,                         // 客户端不读
    items:       s.items.map(i => ({item_id:i.item_id, num:i.num})),
    get_items:   s.getItems.map(i => ({item_id:i.item_id, num:i.num})),
    log_list:    s.logList.map(l => ({desc:l.desc, item_id:l.item_id, item_num:l.item_num, time:l.time})),
    path:        s.curMuseum ? s.path.map(t => ({grid:t.grid, type:t.type, style:t.style})) : [],
  };
},

/* --- 其余命令（要点）-------------------------------------------------- */
museumday_refresh: (d, ctx) => {            // 换一条新路线（并可【自设计】地自动挑馆）
  const s = ensureMuseumday();
  s.leftNum = Math.max(0, (s.leftNum|0) - 1);
  if (!s.curMuseum) s.curMuseum = firstUnvisitedMuseum(s);   // 记录页点占位行时必须落馆
  s.path = buildPath(s.curMuseum); s.frog = 1; s.next = 1; s.items = []; s.descId = 401;
  save();
  ctx.push('museumday_info', {compass:s.compass|0, task_num:s.taskNum|0});
  return { left_num: s.leftNum };           // ≠ -1
},

museumday_random_compass: (d, ctx) => {
  const s = ensureMuseumday();
  if (s.compass <= 0 || !s.curMuseum) return { code: -1 };        // 非 0 → 客户端静默
  if (s.next >= s.path.length) return { code: -1 };               // 已到终点：不要回 next 相同！
  s.compass -= 1;
  s.next += 1;                              // 【自设计】一次 1 格
  rollTileLoot(s);                          // 【自设计】掉落 → items/logList
  s.frog = s.next;                          // 【自设计】蛙随之前进
  save();
  ctx.push('museumday_info', {compass:s.compass|0, task_num:s.taskNum|0});   // 罗盘数必须推
  return { next: s.next, inspire: s.inspireNum|0 };   // inspire 是"覆盖赋值"
},

museumday_inspire: (d, ctx) => {            // 消耗 1 次鼓舞，推进一/多格
  const s = ensureMuseumday();
  if (s.inspireNum <= 0 || s.next >= s.path.length) return { code: -1 };
  s.inspireNum -= 1;
  s.next += 1;  s.frog = s.next;  rollTileLoot(s);   // 【自设计】
  save();
  return { next: s.next };                  // 客户端自己已经 --inspire_num
},

museumday_dir_compass: () => ({ code: 0 }), // 客户端不发；留个 no-op 免得回 {}
museumday_load_path:  () => ({}),           // 客户端不发

museumday_get_items: (d, ctx) => {
  const s = ensureMuseumday();
  for (const it of s.items) {
    if (it.item_id !== MD_COMPASS_ID) grantItem(ctx, it.item_id, it.num);   // 罗盘另算
    mergeInto(s.getItems, it);              // ← 必须搬走，否则弹窗循环
  }
  s.items = [];
  save();
  return { code: 0 };                       // 只认 code
},

museumday_start_advance: (d, ctx) => {
  const s = ensureMuseumday();
  const idx = Math.max(0, Math.min(MD_RESET_PRICE.length-1, s.museums.length - MD_MUSEUMS.length));
  const price = MD_RESET_PRICE[idx];
  if (state.clover < price) return { code: -1 };
  let id = Number(d.id) || 0;
  if (!MD_MUSEUMS.includes(id)) id = firstUnvisitedMuseum(s);    // id=0 占位行 → 自动挑
  if (!id) return { code: -1 };
  state.clover -= price; save();
  s.curMuseum = id; s.path = buildPath(id); s.frog = 1; s.next = 1;
  s.items = []; s.leftNum = 2;                                   // 【自设计】每次新冒险给 2 次重开
  ctx.push('clover_update', { clover: state.clover });            // 客户端不会自己扣
  return { code: 0 };
},

museumday_arrive: (d, ctx) => {             // 结算：进历史 + 清空当前
  const s = ensureMuseumday();
  if (s.curMuseum) {
    s.museums.push({ id:s.curMuseum, desc_id:MD_DESC_END, time:nowSec(), items:s.items.concat(s.getItems) });
  }
  s.curMuseum = 0; s.path = []; s.items = []; s.frog = 1; s.next = 1;
  save();
  ctx.push('museumday_load', /* 与上面同形的完整 payload */);   // 记录页紧接着会自己 load，推一次更稳
  return { code: 0 };
},

museumday_info: () => ({ compass: 0, task_num: 0 }),   // 引擎侧不需要它做请求；用 ctx.push 推
```

**路径生成建议（`【自设计】`）**：`grid = 1 + col + 7*row`。
起点取一条从 1（左下）或 1..7 里随机一格的**单调走线**（只向右/向上，避免回头），
终点格写 `{type:0, style:cur_museum}`，起点格写 `{type:0, style:0}`，
其余格在 `(2,1)/(2,2)`（路）里轮换，两侧随机点缀 `(1,*)`/`(3,*)`/`(4,*)`。
必须保证：`grid ∈ [1,35]`、**前后相邻（正交）**、无重复、`path.length` 在 8–16 之间
（罗盘 8 个 + 鼓舞若干刚好够走到终点附近）。

---

## 10. 验收清单（跑一遍就知道有没有踩雷）

0. **先确认 `guideStep == 'Complete'`**（用引擎的 GM 控制台改存档 / 或者用一个已经过完引导的存档）。
   否则按钮永远不出现，会让你误以为 `end_time` 没生效（§1.5 条件 2）。
1. `museumday_load` 只回 `{end_time: 未来值}` → **必须**复现「呱呱吃坏肚子了」重载循环（反向确认地雷 1）。
2. 回全 16 键、`path` 非空、`cur_museum=1` → 主界面出现博物馆冒险按钮 + 红点。
3. 点按钮：第一次弹邀请函（`museumday_popup` cookie），关闭后再点直接进记录页。
4. 记录页：能看到 `museum_list`；`museum_list.length<4 && cur_museum==0` 时列表末尾有「下一座」占位行；
   点它 → `museumday_refresh` → 应直接进地图页（若 `left_num==-1` 会卡住，验证地雷 7）。
5. 地图页：图块出现（`md_cell_2_1` 等），蛙在起点，终点是 `md_cell_0_<cur_museum>`；
   连点「尝试规划」直到 `next==path.length`，每次罗盘数都要 +1 变化（验证 §4.3 的推送）。
6. 鼓舞按钮：`inspire_time=1` 时应为 `btn_inspire_on_png` 且可点；点一次 `inspire_num` 减 1、蛙前进。
7. `frog==path.length` 时地图页弹出礼包 + 结算卡；点「领取」→ `museumday_arrive` + 记录页
   **只弹一次**礼包（若反复弹 → 地雷 5）。
8. 三叶草：点「新的一次冒险」选馆，确认扣费与显示一致（地雷 6）。
9. **定时器实测**（§1.5 A）：用固定远未来 `end_time`，
   打开记录页后停留 ≥1 分钟，看是否立刻冒出「春游活动已结束」并把窗口关掉。
   若出现 → 换成滚动窗口（now+20 天）重测。
10. 控制台应无 `Cannot read properties of undefined`、无 `md_cell_*` 404（除非故意给非法 style）。
11. `museumday_info` 推送：`{"cmd":"museumday.info","data":{"compass":N,"task_num":M}}`（**无 `session`**）。

---

## 附：本规格未确定的事项（诚实清单）

* 定时器溢出在各运行环境（APK WebView / Chromium / Firefox / WebKit）到底是**截断**还是**当 0** —— 静态不可证，必须实测（§10.9）。
* `base.v1/base.v2`、`inspire.v1/inspire.v2` 的确切用途（客户端不读）。
* 原版每家博物馆的路径形状、每格掉落、罗盘推进步数、`dir_compass` 与 `load_path` 的语义。
* `log_list` 里 `time` 的时区/精度细节（客户端按本地时区格式化）。
* 记录页占位行的 "NaN.NaN.NaN" 日期（客户端 bug，服务端无法修）。
