# IMPLEMENTATION SPEC — 春节贺卡 / 祝福贺卡(中秋) / 生日蛋糕

Three always-open (常开) event families for the offline re-implementation:

| family | client model | protocol prefix | declared cmds | sent by client |
|---|---|---|---|---|
| 春节贺卡 (SpringCard) | `SpringCardModel` | `springcard_*` | 12 | 11 |
| 祝福贺卡 / 中秋节贺卡 (GreetCard) | `GreetCardModel` | `greetcard_*` | 14 | 14 |
| 生日聚会蛋糕 (PartyCake) | `PartyCakeModel` | `partycake_*` | 12 | 10 direct (2 more are push-only) |

> Naming warning: the client's own user-facing strings call `greetcard` **中秋节贺卡**
> (`_("中秋节贺卡活动已结束")`, moon-cake art, `mooncake_another.png`) and `partycake`
> **聚会蛋糕** (`_("聚会蛋糕活动已结束")`). The task's "祝福贺卡" / "生日蛋糕" are our
> labels; every identifier, string and asset in the code is `GreetCard` / `PartyCake`.

## 0. Offset convention

All `@N` offsets below are **character indices into the UTF-8-decoded
`work/run/web/js/main.min.js`** (file is 1 315 423 bytes, 1 261 132 decoded chars).
Reproduce any quote with:

```bash
python -c "import io;C=io.open(r'work/run/web/js/main.min.js',encoding='utf-8',errors='replace').read();print(C[START:END])"
```

Evidence sources used (all read-only):

* `work/run/web/js/main.min.js` — the shipped client (models, views, callbacks, ProtocolList).
* `work/run/web/js/default.thm.js` — the compiled EXML skins (`generateEUI.paths[...]`),
  1 371 303 chars.
* `work/run/engine/protocol.js` — declared params / `needResponse` (identical to the
  client's own `ProtocolList.protocolList`, verified for all 38 wire names below).
* `work/run/engine/data/gamedata.json` — `tables.springCard`, `tables.greetCard`,
  `tables.PartyCakeData`, `tables.Item`.
* `work/run/engine/data/define.json`, `work/logs/errcode_out/errcode.json`,
  `work/run/engine/index.js`, `work/spec/eab_Item_json`,
  `work/run/web/resource/China/default.res.json`, `work/run/web/resource/China/`.

`work/spec/museumday.md` does **not** exist, so this document defines its own structure.

---

## 0.1 Cross-family client contract (read this first)

### 0.1.1 send / reply plumbing (already established, re-quoted because it decides everything)

`core.SocketManage.send` — `@336321`:

```js
send=function(t,i){void 0===i&&(i=null);for(var n=[],r=2;r<arguments.length;r++)n[r-2]=arguments[r];
...
var o=ProtocolList.protocolList[t],a=o[0],s=o[1];
if(a.length!=n.length)return void e.Log.error("发送的协议："+t+" 参数与定义参数不匹配，...");
var c=t,l=c.indexOf("_");if(l>=0){var h=c.split("");h.splice(l,1,"."),c=h.join("")}
var u={};if(s&&(this.sessionID++,u.session=this.sessionID),u.timestamp=Math.floor(e.Time.getServerTime()),u.cmd=c,a.length>0){u.data={};for(var p=0;p<a.length;p++)u.data[a[p]]=n[p]}
s&&(i&&(u.callbackFun=i),this.activateProtocol[u.session]=u),this._socket.send(d)}
```

* wire `cmd` = the command with the **first** `_` turned into `.`
  (`springcard_send` → `springcard.send`).
* `needResponse:false` ⇒ **no `session`, no callbackFun**; a reply to it is treated as a
  *push* (see below) — send nothing back.
* **Argument-count validation is client-side and fatal-to-the-click**: if the handler
  passes a different number of args than `ProtocolList.protocolList[cmd][0].length`,
  the client logs an error and *never sends*. The engine's `protocol.js` does not need
  this check, but the engine's own *outgoing* pushes must not rely on it either.

Dispatch — `AnalysisProtocol` `@337851`:

```js
var r=JSON.parse(n);if(e.String.isNullOrEmpty(r.cmd))if(null!=r.session){var o=this.activateProtocol[r.session];
if(o){delete this.activateProtocol[r.session];var a=o.cmd.replace(".","_"),s=o.callbackFun;
this.HasEventListener(a)||null!=s?(this.HasEventListener(a)&&this.DispatchEvent(new e.Event(a,r.data,o.data)),s&&s.apply(r.data,o.data)):...}
else{var a=r.cmd.replace(".","_");this.HasEventListener(a)?this.DispatchEvent(new e.Event(a,r.data)):...}}
```

Consequences that matter here:

1. A **reply** = `{"cmd":"","session":<n>,"data":{...}}`; a **push** =
   `{"cmd":"springcard.load","data":{...}}` (no session).
2. `addProtocolCallback(name)` (`@11730`) registers a ServiceDispatcher listener; the
   push path calls `model[name].apply(model, [replyData])`. **`springcard_load`,
   `springcard_load_task_item`, `greetcard_load`, `greetcard_get_task_item`,
   `partycake_load`, `partycake_load_mate`, `partycake_load_task` and
   `partycake_load_qa` all go through this listener path.**
3. `req_load()` sends **with no Action** (`send("springcard_load")`), so the *only*
   way the load payload reaches the model is this listener. Both a real reply (with
   the matching session) and a bare push work; the engine's existing `BOOT_PUSH`
   mechanism (`index.js@24446`, `ctx.push` `@241193`) already uses the push form.
4. **A load command must never be answered with an empty body.** `{"code":0}` alone
   would run e.g. `springcard_load({})`, which sets `end_time = undefined` and
   *closes* the feature, or `greetcard_load({})`, which makes `task_item` undefined
   and then throws inside `checkRedot` (crash-and-reload). See §1.7 / §2.7.

### 0.1.2 Error codes

None of the 38 callbacks in these three families calls
`MessageModel.getErrorInfo` (verified: `getErrorInfo` occurs only at `@116436`,
`@117183`, `@139251`, `@169550`, `@195263`, `@195848`, `@197636`, `@198191`,
`@198497`, `@544573`, plus its definition `@148263` — all other features). They
compare `code` **directly**, so `errcode.json` is irrelevant *except* that:

* `0 == reply.code` is the success test in most of them; a **missing or non-zero
  `code` silently skips the whole success branch** (the click looks dead),
* `springcard_get_share_tags` uses codes `1,2,3,4` as its own private vocabulary and
  prints its own strings, and `0/1/2/3/4` all exist in `errcode.json` anyway
  (`0=成功, 1=服务器通用错误码, 2=连接第三方平台网络错误, 3="", 4=版本不兼容`), so
  returning them is safe.

Rule for the engine: **always include `code: 0` on success** for every
needResponse command in these families; use `code: 1` (or any errcode-table value)
for a refusal, and expect the click to do nothing visible when you do.

### 0.1.3 Entry buttons — the `guideStep` precondition

`MainOut` hides all three buttons unless the tutorial is finished
(`updateSpringCard @863426`, `updateGreetCard @863151`, `updatePartyCake @863970`):

```js
updateGreetCard=function(){var e=this.userModel.getClientSettings().guideStep;
e==GuideStep.Complete?this.btnGreetCard.visible=this.btnGreetCard.includeInLayout=this.getModel(GreetCardModel).isOpen():this.btnGreetCard.visible=this.btnGreetCard.includeInLayout=!1}
```

`SettingsInfo.guideStep` defaults to `GuideStep.New` (`@209523`), and
`GuideStep.Complete === "Complete"` (`@209496`). The buttons `btnGreetCard`,
`btnSpringCard`, `btnPartyCake` **do** exist in the compiled `MainOut.exml` skin
(`default.thm.js`), so the only gate is `guideStep` + `isOpen()`.

Tap handlers (`on_btnGreetCard_tap @878902` etc.) re-check `isOpen()` and otherwise
show `_("中秋节贺卡活动已结束")` / `_("春节贺卡活动已结束")` / `_("聚会蛋糕活动已结束")`
and call the matching `update*()` — i.e. an `isOpen()`→`false` flip makes the button
vanish, which is the "clickable dead end" the spec must avoid.

### 0.1.4 The always-open recipe (identical for all three)

All three models compute their window from **one number supplied by the payload**:

```js
// SpringCardModel @186898 / GreetCardModel @124070 / PartyCakeModel @164451 (byte-identical)
getActivityTime=function(){var e=this.data.end_time;return e>0?[1,e]:[0,0]}
isOpen=function(){var e=this.getActivityTime(),t=e[0],i=e[1];return core.Time.getServerTime()>=t&&core.Time.getServerTime()<=i}
```

* **there is no `start_time`** anywhere in the three models or their views: the start
  is the literal `1`. The `start_time: 0` field in the current engine stubs is inert
  and can be dropped.
* **always open ⇔ `end_time > core.Time.getServerTime()` and `end_time > 0`.** Nothing
  else in the client gates opening these features (no `ActivityModel`, no
  `client_load_events` entry, no date literal — see §0.1.5).
* Recommended values:
  * fixed: `end_time: 4102444800` (2100-01-01 UTC) — simplest, idempotent, safe for
    save/restore;
  * rolling: `end_time: now + 3650*86400` — the on-screen label reads naturally.
  Both are self-designed; the original values lived on the server and are unrecoverable.
* the client arms `egret.setTimeout(closeActivity, (end_time-now+1)*1000)`. `egret`'s
  own tick timer (`work/run/web/js/game.min.js @41190`) decrements `delay` per frame —
  it is **not** `window.setTimeout`, so a decade-long delay does not overflow or fire
  early. Verified:

  ```js
  // game.min.js @41190
  function e(...){var u={listener:e,thisObject:r,delay:h,params:c};...o[n]=u,n}
  function i(t){var e=t-a;a=t;for(var i in o){var n=i,s=o[n];s.delay-=e,s.delay<=0&&(r(n),s.listener.apply(s.thisObject,s.params))}return!1}
  ```

  Consequence: a far-future `end_time` never calls `closeActivity()`, so a session can
  never be kicked out of the feature and never loops through `closeActivity → req_load`.
* `closeActivity` (`SpringCardModel @187631`, `GreetCardModel @125826`,
  `PartyCakeModel @164679`) removes the three WindowLayer controls, shows the
  "活动已结束" toast, and calls `this.req_load()`. With a far-future `end_time` it is
  unreachable, but it is the failure mode to keep in mind: **any reply that lowers
  `end_time` below "now" hides the button for the rest of the session.**

### 0.1.5 Hardcoded date literals in the client (complete list for these families)

The only calendar literals that touch these three features:

| literal | where | decoded date | what it gates |
|---|---|---|---|
| `1675007999` | `@179493`, inside the share-text builder | 2023-01-29 15:59:59 UTC | **cosmetic share copy only** |
| `1654171200` / `1654430400` | `@851827` (`GuideStep.Named`) | 2022-06-02 / 06-05 | SDK `sdk.role.create/online` logging during the tutorial — not a feature gate |
| `1` | `getActivityTime()` return | — | hardcoded **start**; always satisfied |
| `1671379200` / `1671984000` / `1672588800` | **data table** `PartyCakeData.cake[2..5].time` | 2022-12-19 / 12-26 / 2023-01-02 (CST) | 制作解锁时间 for cake parts 2–5 (see §3.1.3) |

Share copy gate, `@179493`:

```js
if(core.Time.getServerTime()<=1675007999&&(l.message="#旅行青蛙中国之旅# 小青蛙的自制春节贺卡你收到了嘛~"),"wechat_share"==n){...}
```

Today the comparison is false, so the SpringCard share uses the generic message. This
is the *only* place a client date literal affects 春节贺卡 and it cannot close the event.

**Therefore: no payload needs to defeat a hardcoded window for these three families.**
The single data-side gate is `PartyCakeData.cake[].time` (§3.1.3), and the only
non-payload precondition is `guideStep == "Complete"` (§0.1.3).

### 0.1.6 ARRAY-OF-IDS vs ARRAY-OF-ROW-OBJECTS — the crash table

This is the single most dangerous thing in this spec. The previous
"呱呱吃坏肚子了" crash-and-reload loop came from feeding row *ids* where the client
wanted row *objects*. In these families the two shapes are mixed, and one of them has
**no null guard at all**:

| payload field | shape | proof |
|---|---|---|
| `springcard_load.items` | array of **objects** `{item_id, num}` | `changeItems @186724` reads `r.item_id`, `r.num`; `getTagsNum @187257` reads `n.item_id` |
| `springcard_load.task_item` | array of **tag ids** (numbers 101–112) | `req_get_task_reward @182640` does `e.changeItems(o,1)` and `i.push({item_id:o,count:1,...})` with `o` the element |
| `springcard_load.reward_list` | array of **objects** `{item_id, num}` | `SpringCardRewardView @1083940` reads `reward_list[i].item_id` and `.num` |
| `springcard_load_task_item.list` | array of **tag ids** | same code path as `task_item` |
| `greetcard_load.items` | array of **objects** `{item_id, num}` | `getItemNum @125185` |
| `greetcard_load.send_list` | array of **objects** `{bg, bless, tags[]}` | `GreetCardSendListItem @681090` → `createGreetCard(groupBg, this.data)` |
| `greetcard_load.get_list` | array of **objects** `{name, bg, bless, tags[], gift}` | `CardItem.setInfo @1109340` reads `t.gift`; `GreetCardUtils.createGreetCard` needs `bg/bless/tags`; `StoryView.renderCard @1104170` needs `get_list.indexOf(cardData)` |
| `greetcard_get_task_item.list` / `task_item` | array of **tag ids** (101–125) | `req_get_task_reward @122728` |
| `greetcard_get_reward.list` | array of **item ids** (numbers) | view `@672276`: `t.push({item_id:r,count:1})` where `r` is the element |
| `partycake_load.task_list` | array of **objects** `{id, count, is_done}` | view `@965586` reads `a.id/a.count/a.is_done` and indexes `partycakeData.get("task_list")[a.id]` |
| `partycake_load.layers` | array of **numbers** (layer keys) | `isMakeLayer @163540`; `req_make @161602` does `layers.push(e)` with `e` the layer key |
| `partycake_load.share_get` | array of **0/1**, 0-based | `req_reward_share @163033` uses `share_get[e-1]`; view `@959812` uses `share_get[e]` |
| `partycake_load_qa.answer` | array of **3 item ids** | view `@956961` loops `r=1..3` |
| `partycake_load_qa.reward` | array of **objects** `{item_id, count}` | view `@957864` reads `.item_id`/`.count` |
| `partycake_load.task_list[i].cfg` | **not sent** — the client builds it from `partycakeData.get("task_list")[a.id]` | view `@965586` |

The unguarded dereference (the exact shape of the earlier crash) is in
`DropItemRender.dataChanged @16062`:

```js
var r=this.data.type||Tabikaeru.DataType.DropType.ITEM;
if(this.data.item_id>=0){var o=Tabikaeru.DataManager.instance().ItemDB.get(this.data.item_id);
switch(r){...
case Tabikaeru.DataType.DropType.CARDTAGS:var a=GreetCardUtils.getTagsCfg(this.data.item_id);i=a.pic+"_png";break;
case Tabikaeru.DataType.DropType.SPRINGCARDTAGS:var a=SpringCardUtils.getTagsCfg(this.data.item_id);i=a.pic+"_png";break;
case Tabikaeru.DataType.DropType.ITEM:default:if(o&&(i=Tabikaeru.path.formatPathImage(o.img)),...
```

* `DropType.CARDTAGS = 100`, `DropType.SPRINGCARDTAGS = 101` (`@409529`).
* `getTagsCfg(id)` returns `undefined` for an id that is not in the table
  (`SpringCardUtils @1094009`, `GreetCardUtils @688340`), and the `CARDTAGS` /
  `SPRINGCARDTAGS` branches dereference `.pic` **with no guard**.
  ⇒ **`type: 100` must always carry an id from `greetCard.tags` (101–125);
  `type: 101` must always carry an id from `springCard.tags` (101–112).**
  This is fired from `GiftPackageViewController` / `ItemRewardViewControl` right after a
  successful `*_get_task_reward` / `*_get_share_tags` / `springcard_buy`, so a wrong id
  there is an immediate "呱呱吃坏肚子了" reload loop.

### 0.1.7 Where the data tables actually live (cannot be patched by a payload)

`DataManager` (`@406000`+) binds:

```js
this.greetCardData=t("greetCard"),... this.partycakeData=t("PartyCakeData"),this.springCardData=t("springCard"),...
// @403552: function t(e){return new o(e,RES.getRes(e+"_json"))}   // key getter: get(key) -> src[key]
// @403566: function i(e,t){void 0===t&&(t="id"),return new a(e,RES.getRes(e+"_json"),t)}  // id getter
```

and `resource/China/default.res.json` maps all four to the client bundle:

```json
{"url":"preload_eab","type":"eab_asset","name":"errcode_json"}
{"url":"config_eab","type":"eab_asset","name":"greetCard_json"}
{"url":"config_eab","type":"eab_asset","name":"Item_json"}
{"url":"config_eab","type":"eab_asset","name":"PartyCakeData_json"}
{"url":"config_eab","type":"eab_asset","name":"springCard_json"}
```

`config.eab` has magic `89 45 41 42 0D 0A 1B 0A` (note `1B`, not `1A`) and an index that
is not plain JSON at offset 8, and its payload does not contain the table text verbatim
(probed for `"l_name"`, `"buy_weight"`, `springcard_1`, `greetpaster_1`: 0 hits).
⇒ **the tables are client-side, inside an encrypted/repacked bundle.** A server payload
cannot change `PartyCakeData.cake[].time`, `bg_price`, `tags_price`, `share_reward`,
`send_reward`, `springCard.tags[].buy_weight`, etc. Changing any of those requires
rebuilding `config.eab` (repo tooling exists under `work/tools/`: `bundle_engine.py`,
`patch_bands.py`, `repair_engine_js.py`). Everything the engine *can* control must come
through the 38 commands below.

---

## 1. 春节贺卡 — `springcard_*`

### 1.1 Model + window

`SpringCardEventType` `@180520`, model class `@180722` … `@188438`.

Default `data` (`@180820`):

```js
var SpringCardModel=function(e){function t(){var t=null!==e&&e.apply(this,arguments)||this;
return t.data={end_time:0,card_info:{bg:0,bless:0,tags:[0,0,0]},items:[],task_harvest:0,buy_num:0,can_buy_num:0,task_item:[],share_num:0,share_get:0,box_id:0,share_code:"",reward_list:[],global_num:0},t}
```

Listeners (`@181071`):

```js
t.prototype.initModel=function(){this.addProtocolCallback("springcard_load","springcard_load_task_item")}
```

Note the asymmetry: the *push* name registered is `springcard_load_task_item`, while
`ProtocolList` declares `springcard_get_task_item` (`@381543`) — that command is
**dead**: no `send("springcard_get_task_item")` exists anywhere in the client
(0 hits). Do not implement it; push `springcard_load_task_item` instead.

Window logic (`@186898`, `@186990`):

```js
t.prototype.getActivityTime=function(){var e=this.data.end_time;return e>0?[1,e]:[0,0]}
t.prototype.isOpen=function(){var e=this.getActivityTime(),t=e[0],i=e[1];return core.Time.getServerTime()>=t&&core.Time.getServerTime()<=i}
```

Timer arming, inside `springcard_load` (`@181635`):

```js
this.isOpen()&&(this.checkRedot(),egret.clearTimeout(this.timerActivity),
this.timerActivity=egret.setTimeout(function(){t.closeActivity()},this,1e3*(this.getActivityTime()[1]-core.Time.getServerTime()+1))),
this.dispatchEvent(new core.Event(SpringCardEventType.CARD_CHANGE))) ,this.dispatchEvent(new core.Event(SpringCardEventType.LOAD))
```

Derived state used by the views:

```js
// @187126
getItemNum=function(e){for(var t=0,i=this.data.items;t<i.length;t++){var n=i[t];if(n.item_id==e)return n.num}return 0}
// @187257
getTagsNum=function(){for(var e=0,t=0,i=this.data.card_info.tags;t<i.length;t++){var n=i[t];n>0&&e++}
for(var r=0,o=this.data.items;r<o.length;r++){var n=o[r];n.item_id>100&&(e+=n.num)}return e}
// @187463  — the send button's enable() test
canSendCardid=function(){if(this.data.card_info.bg<=0)return!1;for(var e=0,t=this.data.card_info.tags;e<t.length;e++){var i=t[e];if(0>=i)return!1}return!0}
// @186097  — red dot
checkRedot=function(){var e=0;if(this.isOpen()&&(this.data.box_id>0&&(e=1),this.data.task_item.length>0&&(e=1),0>=e)){for(var t=[],i=function(e){var i=SpringCardUtils.getTagsCfg(e.item_id);e.num>0&&i&&t.filter(function(e){return e==i.type}).length<=0&&t.push(i.type)},n=0,r=this.data.items;n<r.length;n++){var o=r[n];i(o)}
for(var a=function(e){var i=SpringCardUtils.getTagsCfg(e);i&&t.filter(function(e){return e==i.type}).length<=0&&t.push(i.type)},s=0,c=this.data.card_info.tags;s<c.length;s++){var l=c[s];a(l)}
t.length>=3&&(e=1)}Tabikaeru.RedotManager.instance().setRedotValue(Tabikaeru.RedotType.SPRINGCARD,e)}
```

**Payload values that keep it permanently open:** `end_time` = any number greater than
the current server time (see §0.1.4). Everything else is orthogonal; the feature works
with all-zero content.

### 1.2 Command table

Wire names are `springcard.<verb>`.

| # | command | protocol.js params | needResponse | client send site | reply fields read | what the player sees | follow-up sent by the callback |
|---|---|---|---|---|---|---|---|
| 1 | `springcard_load` | `[]` | true | `req_load @182289` (`send("springcard_load")`, no Action) + BOOT_PUSH | `end_time, card_info, task_harvest, buy_num, can_buy_num, share_num, share_get, box_id, share_code, items, task_item, reward_list` | arms/finishes load, red dot, entry button, timer | none |
| 2 | `springcard_load_count` | `[]` | true | `@182396` | `count` | global counter text | none |
| 3 | `springcard_buy` | `[]` | true | `@183100` | `tags_id` | gift-package popup with 1 sticker; `buy_num++` | none |
| 4 | `springcard_change_bg` | `["id"]` | true | `@183526` | `code` | card background changes | none |
| 5 | `springcard_change_bless` | `["id"]` | true | `@183788` | `code` | blessing line changes | none |
| 6 | `springcard_put_tags` | `["pos","id"]` | true | `@184054` | `code` | sticker placed/removed in slot `pos` | none |
| 7 | `springcard_send` | `[]` | true | `@184404` | `box_id` | card is "sent", reward box appears | none |
| 8 | `springcard_get_reward` | `[]` | true | `@184647` | `id`, `num` | opens the box: item reward **or** a blessing line | none |
| 9 | `springcard_get_task_reward` | `[]` | true | `@182640` | `code` | gift-package popup with every `task_item` | none |
| 10 | `springcard_share_tags` | `["tags_id"]` | true | `@184964` | `share_code` | generates the player's share code, then **calls `req_get_task_reward()`** | `springcard_get_task_reward` |
| 11 | `springcard_get_share_tags` | `["share_code"]` | true | `@185345` | `tags_id`, `code` | redeems someone else's code; on failure shows one of 4 strings | none |
| — | `springcard_get_task_item` | `[]` | true | **never sent** | — | — | — |
| P | `springcard_load_task_item` | *(not in protocol.js — push only)* | — | server push | `task_harvest, share_num, list` | task rows light up | `springcard_load` (only from the model's own `task_item.length>0` branch via the view) |

Quoted callbacks:

`springcard_load` — `@181144` (note: **no `Utils.convertArrayAll`**; every scalar is
copied field-by-field, so a missing scalar becomes `undefined`, not a default):

```js
t.prototype.springcard_load=function(e){var t=this;this.data.end_time=e.end_time,this.data.card_info=e.card_info,this.data.task_harvest=e.task_harvest,this.data.buy_num=e.buy_num,this.data.can_buy_num=e.can_buy_num,this.data.share_num=e.share_num,this.data.share_get=e.share_get,this.data.box_id=e.box_id,this.data.share_code=e.share_code,this.data.items=Utils.convertArray(e.items),this.data.task_item=Utils.convertArray(e.task_item),this.data.reward_list=Utils.convertArray(e.reward_list),this.isOpen()&&( ... ),
this.dispatchEvent(new core.Event(SpringCardEventType.LOAD))}
```

`Utils.convertArray(e)` is `Array.isArray(e)?e:[]` (`@300384`), so the three array
fields are crash-safe; `card_info` and `end_time` are not.

`springcard_load_task_item` — `@181971`:

```js
t.prototype.springcard_load_task_item=function(e){this.data.task_harvest=e.task_harvest,this.data.share_num=e.share_num,this.data.task_item=Utils.convertArray(e.list),this.checkRedot(),this.dispatchEvent(new core.Event(SpringCardEventType.CARD_CHANGE))}
```

`req_load_count` — `@182380`:

```js
t.prototype.req_load_count=function(e){var t=this;core.SocketManage.getInstance().send("springcard_load_count",new core.Action2(function(i){i.count&&(t.data.global_num=i.count,t.checkRedot(),e&&e.apply())}))}
```

⚠ `i.count` is used **truthily** — `count: 0` leaves `global_num` untouched (harmless)
but the view then does `e.global_num.toString()` (`@1099602` → `updateCount`), so
`global_num` must still be a number in `springcard_load`. Send `count: 0` freely.

`req_get_task_reward` — `@182523`:

```js
t.prototype.req_get_task_reward=function(){var e=this;this.data.task_item.length<=0||core.SocketManage.getInstance().send("springcard_get_task_reward",new core.Action2(function(t){if(0==t.code){for(var i=[],n=0,r=e.data.task_item;n<r.length;n++){var o=r[n];e.changeItems(o,1),i.push({item_id:o,count:1,type:Tabikaeru.DataType.DropType.SPRINGCARDTAGS})}core.PageManage.getInstance().addViewControl(GiftPackageViewController,core.ViewLayerType.NoticeLayer,null,i),e.data.task_item=[],e.checkRedot()}}))}
```

`req_buy` — `@183025`:

```js
t.prototype.req_buy=function(e){var t=this;core.SocketManage.getInstance().send("springcard_buy",new core.Action2(function(i){if(i.tags_id&&i.tags_id>0){t.data.buy_num++,t.changeItems(i.tags_id,1);var n=[];n.push({item_id:i.tags_id,count:1,type:Tabikaeru.DataType.DropType.SPRINGCARDTAGS}),core.PageManage.getInstance().addViewControl(GiftPackageViewController,core.ViewLayerType.NoticeLayer,null,n),e&&e.apply()}}))}
```

`req_change_bg` / `req_change_bless` — `@183443` / `@183710`:

```js
t.prototype.req_change_bg=function(e,t){var i=this;core.SocketManage.getInstance().send("springcard_change_bg",new core.Action2(function(n){0==n.code&&(i.data.card_info.bg=e,i.dispatchEvent(new core.Event(SpringCardEventType.CARD_CHANGE)),t&&t.apply())}),e)}
t.prototype.req_change_bless=function(e,t){var i=this;core.SocketManage.getInstance().send("springcard_change_bless",new core.Action2(function(n){0==n.code&&(i.data.card_info.bless=e,i.dispatchEvent(new core.Event(SpringCardEventType.CARD_CHANGE)),t&&t.apply())}),e)}
```

⚠ Unlike `greetcard`, `springcard_change_bg` does **not** consume the sticker
inventory — it just sets `bg`. Only `put_tags` and `buy` touch `items`.

`req_put_tags` — `@183950` (note the wire param is `pos+1`, the local array index is
`pos`):

```js
t.prototype.req_put_tags=function(e,t,i){var n=this;core.SocketManage.getInstance().send("springcard_put_tags",new core.Action2(function(r){0==r.code&&(n.changeItems(t,-1),n.data.card_info.tags[e]>0&&n.changeItems(n.data.card_info.tags[e],1),n.data.card_info.tags[e]=t,n.dispatchEvent(new core.Event(SpringCardEventType.CARD_CHANGE)),i&&i.apply())}),e+1,t)}
```

`req_send` — `@184328`:

```js
t.prototype.req_send=function(e){var t=this;core.SocketManage.getInstance().send("springcard_send",new core.Action2(function(i){i.box_id&&i.box_id>0&&(t.data.box_id=i.box_id,t.data.card_info={bg:0,bless:0,tags:[0,0,0]},e&&e.apply())}))}
```

⚠ **must return `box_id > 0`** (200009 or 200010), otherwise the client's own success
callback never fires → the send overlay stays on screen and the card is never cleared.

`req_get_reward` — `@184565`:

```js
t.prototype.req_get_reward=function(e){var t=this;core.SocketManage.getInstance().send("springcard_get_reward",new core.Action2(function(i){t.data.box_id=0,t.checkRedot(),i.num>0&&(t.data.reward_list.push({item_id:i.id,num:i.num}),t.dispatchEvent(new core.Event(SpringCardEventType.CARD_CHANGE))),e&&e.apply(i)}))}
```

`req_share_tags` — `@184880` (⚠ chains a second request on success):

```js
t.prototype.req_share_tags=function(e,t){var i=this;core.SocketManage.getInstance().send("springcard_share_tags",new core.Action2(function(e){e.share_code&&(i.data.share_code=e.share_code,i.req_get_task_reward(),t&&t.apply())}),e)}
```

`req_get_share_tags` — `@185112` (the only callback in the family with a private code
vocabulary):

```js
t.prototype.req_get_share_tags=function(e,t){var i=this;if(this.isOpen())return this.data.share_get>=3?void core.DisplayManage.getInstance().getPopupLayer().addChild(new ModalAlert("今日兑换已达到上限啦")):void core.SocketManage.getInstance().send("springcard_get_share_tags",new core.Action2(function(e){if(e.tags_id){i.data.share_get++,i.changeItems(e.tags_id,1);var n=[];n.push({item_id:e.tags_id,count:1,type:Tabikaeru.DataType.DropType.SPRINGCARDTAGS}),core.PageManage.getInstance().addViewControl(GiftPackageViewController,core.ViewLayerType.NoticeLayer,null,n),core.PageManage.getInstance().removeControl(CdkeyViewController,core.ViewLayerType.LoaderLayer),GuideHelpView.getInstance().show("兑换成功",null,core.DisplayManage.getInstance().getNoticeLayer()),t&&t.apply()}else{var r="今日分享已达到上限啦";1==e.code?r="分享码无效或已被兑换过啦":2==e.code?r="分享码已被兑换过啦":3==e.code?r="不能兑换自己分享的哦":4==e.code&&(r="兑换码已过期"),GuideHelpView.getInstance().show(r,null,core.DisplayManage.getInstance().getNoticeLayer())}}),e)}
```

Note: `req_get_share_tags` takes a `share_code` param that the client *receives from
another player*, while `req_share_tags(tags_id)` *produces* the local `share_code`
stored in `data.share_code` and shared as `"code=" + data.share_code`
(`SpringCardSelectView @1089550`). A saved `share_code` must be a non-empty **string**;
`""` (or a number that is falsy) makes the whole redeem branch vanish silently.

### 1.3 Payload shapes

**Required — push/reply of `springcard_load` / `springcard.load`:**

```json
{
  "end_time": 4102444800,
  "card_info": { "bg": 0, "bless": 0, "tags": [0, 0, 0] },
  "task_harvest": 0,
  "buy_num": 0,
  "can_buy_num": 3,
  "share_num": 0,
  "share_get": 0,
  "box_id": 0,
  "share_code": "",
  "items": [ { "item_id": 101, "num": 2 } ],
  "task_item": [ 102, 105 ],
  "reward_list": [ { "item_id": 14, "num": 1 } ],
  "global_num": 0
}
```

Hard requirements, in order of danger:

1. `card_info` **must be a plain object** with `bg:int`, `bless:int`,
   `tags:[int,int,int]` — `SpringCardView.update @1100032` reads
   `this.data.card_info.bg` and `SpringCardUtils.createCard @1094516` indexes
   `o.tags[c]` / `n.tags[c]` with `c = o.tags[t]-1`. `card_info: {}` (the current
   stub!) or `null` throws `Cannot read properties of undefined (reading '0')`.
2. `end_time` must be a number > now (§0.1.4).
3. `global_num` must be a number — `updateCount` calls `.toString()`.
4. `items` / `task_item` / `reward_list` may be omitted only if you are happy with `[]`
   (they are passed through `Utils.convertArray`).
5. `tags` **must be length 3** and every entry an int; `0` means "empty slot".
   `createCard` maps slot `t` → card tag index `o.tags[t]-1` (springCard's `bg_list`
   `tags` arrays are `[0,1,2,3]`, so slot1→`card_info.tags[0]`, slot2→`[1]`,
   slot3→`[2]`).
6. `box_id` ∈ `{0, 200009, 200010}` — `showBox @1098380` does
   `200010==this.data.box_id?"big_box2_png":"big_box_png"`; `200010` is also the table's
   `big_box_id`, `200009` is `small_box_id`. `200008`/`200012`/`200013` are the sticker
   bag / toy mail items and must **not** be used as `box_id`.

**Replies (needResponse commands):**

| command | success reply | notes |
|---|---|---|
| `springcard_load_count` | `{"count": 0}` | truthiness-skipped when 0 — that is fine |
| `springcard_buy` | `{"tags_id": 103}` | random by `tags[].buy_weight`; `0`/absent ⇒ silent no-op, button does nothing |
| `springcard_change_bg` | `{"code": 0}` | |
| `springcard_change_bless` | `{"code": 0}` | |
| `springcard_put_tags` | `{"code": 0}` | |
| `springcard_send` | `{"box_id": 200009}` | **must be `>0`** |
| `springcard_get_reward` | `{"id": 7, "num": 0}` or `{"id": 14, "num": 1}` | see below |
| `springcard_get_task_reward` | `{"code": 0}` | |
| `springcard_share_tags` | `{"share_code": "A1B2C3"}` | **must be a non-empty string** |
| `springcard_get_share_tags` | `{"tags_id": 101}` or `{"code": 1}` | failure codes 1/2/3/4 |
| `springcard.load_task_item` (push) | `{"task_harvest":0,"share_num":1,"list":[102]}` | push only |

`springcard_get_reward` has two mutually exclusive forms, decided **entirely by
`num`**:

* `num == 0` → an "empty/blessing" box. The view then does
  `springCardData.get("bless_box")[e.id] || "好运就在下一刻"` (`@1097692`), i.e. `id` is
  a **key into `bless_box`, 7…15**, not an item id. The model pushes nothing into
  `reward_list`.
  View: `t.getModel(SpringCardModel).req_get_reward(new core.Action1(function(e){if(t.showBox(!1),0==e.num){var i=SpringCardData.get("bless_box"),n=i[e.id]||"好运就在下一刻";t.addChild(new ModalAlert(n))}else{var n="收到物品";SpringCardUtils.isToysItem(e.id)&&(n="请到邮箱查看中奖信息");var r=[{item_id:e.id,count:e.num}];core.PageManage.getInstance().addViewControl(ItemRewardViewControl,...,r,null,n)}}))`
  (@1097593).
* `num > 0` → a real item. `id` must exist in `Item.json` (410 rows) so
  `DropItemRender` can render it, and if `SpringCardUtils.isToysItem(id)` is true
  (`toys_list = {"200012":true,"200013":true}`) the copy changes to
  "请到邮箱查看中奖信息" and the engine is expected to deliver a mail instead.
  Do **not** return `{"id": 200012, "num": 1}` as a plain item grant: the client asks
  the player to look in the mailbox.

### 1.4 Data tables

`tables.springCard` (11 keys; the client reads it as an **object**, `get("bg_list")`):

| key | type | used by client? |
|---|---|---|
| `bg_list` | array, 5 rows | ✅ `SpringCardSelectView.update @1086992`, `SpringCardUtils.getBgCfg @1093866` |
| `tags` | array, 12 rows | ✅ `@1094009`, `@1087416`, `DropItemRender` |
| `bless` | array, 6 rows | ✅ `@1088050`, `@1094206` |
| `bless_box` | object, 8 keys `"7"…"15"` | ✅ `@185880`/`@1097692` (strings!) |
| `toys_list` | object `{"200012":true,"200013":true}` | ✅ `SpringCardUtils.isToysItem @1094311` |
| `tags_price` | `20` | ❌ client hardcodes `20` in the confirm text and the clover check |
| `tags_share_limit` | `3` | ❌ client hardcodes `>=3` (`share_get`, `share_num`) |
| `small_box_id` / `big_box_id` | `200009` / `200010` | ❌ client hardcodes `200010==` in `showBox` |
| `tags_box_id` | `200008` | ❌ never referenced |
| `global_reward` | 5 rows `{num,pic:""}` | ❌ never referenced (the SpringCard view has no moon/progress art) |

Representative rows, verbatim:

```json
// bg_list[0]
{"id":1,"layer":[1,3,4,5],"name":"新春赐福","pos":[[0,0],[22,-46],[169,-95],[-137,-86]],
 "res":["springcard_1","","",""],"style":[100,55,55,65],"tags":[0,1,2,3]}
// tags[0] and the two "rare" rows
{"buy_weight":100,"id":101,"index":1,"name":"青蛙1","pic":"springpaster_1","task_weight":100,"type":1}
{"buy_weight":65,"id":103,"index":3,"name":"青蛙3","pic":"springpaster_3","task_weight":40,"type":1}
// bless[0]
{"desc":"兔年好运到，好事来得早!","id":1,"type":1}
// bless_box (object, string keys)
{"7":"平安喜乐，万事胜意\n好运就在下一刻","8":"初春雪漫漫，蛙蛙祝你所求皆如愿","9":"新春大吉，蛙蛙为你好运蓄力中",
 "10":"不要着急，兔年好运正在路上","11":"呱！蛙蛙预感下个暴富就是你","12":"欢愉且胜意，好事皆可期",
 "13":"蛙蛙陪你等待好运降临","14":"蛙蛙播报：你与好运又靠近了一点","15":"新年呱呱送你三千万\n千万快乐、千万健康、千万幸福"}
```

Keying:

* `bg_list` / `tags` / `bless` — **arrays**, looked up linearly by `id`
  (`SpringCardUtils.getBgCfg/getTagsCfg`), and sorted client-side by `id`/`index`.
* `tags[].type` ∈ `{1,2,3,4}` with 3 stickers each (`101…112`); `canPutTags`
  (`@1094408`) forbids two cards in the same slot using the same `type`.
  `tags[].pic` = `springpaster_1…12`.
* `bg_list[].tags` is `[0,1,2,3]` for all 5 rows: 4 layers, layer 1 always a plain
  background, the other 3 are sticker slots. `layer` `[1,3,4,5]`/`[1,3,4,6]`/`[1,3,5,6]`
  /`[1,3,5,6]`/`[1,3,4,5]` map to skin z-order only — the client never validates it.
* `bg_list[].res` → `springcard_1…5_png` (loose files, verified present).
* `bless_box` is read with a **string** key built from the numeric `id`
  (`i[e.id]` — JS coerces, so both `7` and `"7"` work).

### 1.5 Assets

`images/Scene/SpringCard/` — **37 files**:

* `Bg_ui/` (17): `big_box.png`, `big_box2.png`, `server_card_spring.png`,
  `share_card_spring.png`, `spring_card.png`, `spring_card_bg.png`, `spring_shop.png`,
  `back_spring_card.png`, `back_spring_card_down.png`, `card_share_sent.png`,
  `myreward_decorate.png`, `no_springcard_tips.png`, `text_my_reward.png`,
  `text_open_box.png`, `tips_can_share.png`, `tips_spring_bg.png`,
  `tips_spring_paster.png`
* root (3): `btn_exchange_paster.png`, `btn_share_paster.png`,
  `btn_move_cardshop_spring.png`
* `Card/` (5): `springcard_1…5.png`
* `Paster/` (12): `springpaster_1…12.png`

Compiled skins in `default.thm.js` (**4**, compiled EXML — the `.exml` text files are
*not* in the tree, `glob **/*.exml` = 0 hits; they are baked into this JS file, which
is why `getSkinsPath("SpringCard/X.exml")` still resolves):

| skin | named children (extracted) |
|---|---|
| `SpringCardViewSkin.exml` | `labelDisplay btnRefreshTween lblLimitDate btnBg btnSend lblLimitDate0 btnShop taskBg1 taskBg2 lbTask1 lbTask2 taskCheck1 taskCheck2 groupCard imageBless lbBless btnHistory btnClose rabbit frog globalNum groupSend coverSend btnShare groupShareCard groupBox imageBox` |
| `SpringCardSelectSkin.exml` | `groupCard imageSelect groupTags imageTags imageBuy imageShare lbNum imageBg lbBless cover groupRoot svBg listBg svTags listTags svBless listBless groupShare btnLeft btnRight` |
| `SpringCardShopViewSkin.exml` | `labelDisplay btnRefreshTween moneyPanel payBtn cloverPoint btnClose groupPrice imagePrice imageFree svTags` |
| `SpringCardRewardViewSkin.exml` | `btnRefreshTween btnClose svTags` |

DragonBones: `23xinnian_wa` (frog) and `23xinnian_tu` (rabbit) are in
`default.res.json` (`23xinnian_wa_ske_json/_tex_json/_tex_png` etc.), matching
`SpringCardView @1096248`: `this.frog.source="23xinnian_wa:Armature"`,
`this.rabbit.source="23xinnian_tu:Armature"`.

**Known asset gap:** `SpringCardShopView @1092683` sets
`s.source="goods_201_png"` for the 福袋 icon, but `goods_201_png` has **no entry in
`default.res.json`** (nor has any `goods_*` item icon — the `Icon/goods/*` set was not
part of this extraction). `formatPathImage({index:"goods_201",src:"Icon/goods"})`
(`@1260818`) confirms `goods_201_png` is the expected resource name. Result: a blank
bag icon in the shop, no crash. Same for the item-reward icons.

### 1.6 Recoverable rules vs unrecoverable

**Recovered from tables / client (implementable verbatim):**

* price: `tags_price = 20` clover, **first purchase free** (`buy_num == 0`);
  the client itself checks `getClover() >= 20` and shows
  `0==this.data.buy_num?"首次购买免费":"确定花费20三叶草购买福袋吗？"` (`@1093110`).
* daily share cap = **3** (`share_num >= 3` blocks sharing, `share_get >= 3` blocks
  redeeming) — the number is hardcoded in the client (`@1088818`, `@185253`), the table
  field `tags_share_limit` is informational only.
* task conditions, both hardcoded strings + thresholds in `SpringCardView.update`
  (`@1100446`):
  * row 1 — `·收割三叶草送随机贴纸`, done when `task_harvest >= 1` (i.e. one clover
    harvest while the event is open);
  * row 2 — `·分享贴纸送随机贴纸(share_num/3)`, done when `share_num >= 3`.
  The reward is **every tag id in `task_item`**, one of each, granted by
  `springcard_get_task_reward`.
* sticker weights: `tags[].buy_weight` for paid bags, `tags[].task_weight` for task
  rewards (both in the table, 65/100 and 40/100) — these are the *only* probability
  numbers the client ships; using them is a restoration, not a guess.
* box sizes: `box_id` 200009 = `small_box_id` (小箱), 200010 = `big_box_id` (大箱).
  `showBox @1098380` only distinguishes big vs. not-big. **What determines small vs.
  big is not in any table or in the client — server rule, unrecoverable.**
* the empty-box blessing ids are 7…15 (`bless_box` keys) — restored exactly.
* `reward_list` is a **history** list (`btnHistory.visible = reward_list.length>0`,
  `@1100253`) rendered by `SpringCardRewardView` through `ItemDB` — so its entries must
  be real item ids with `num > 0` (a `num:0` entry would be pushed only by a
  hand-crafted reply, and would then render an empty icon).

**Unrecoverable (server-only) — must be labelled self-designed:**

* the acquisition rule for `can_buy_num` / `buy_num` (how many bags per period, what
  resets them). The client only knows `can_buy_num - buy_num` = remaining icons.
* `global_num` / `springcard_load_count.count` — a global counter feeding nothing that
  the client renders except the number itself (`globalNum.text`); the
  `global_reward` tiers `[300000,600000,1000000,3000000,6000000]` have **empty `pic`
  strings and are never read**, so their meaning and thresholds are lost.
* `share_code` format/generation, one-time-use semantics, expiry, "cannot redeem your
  own code" enforcement, and the `share_get` daily reset boundary (server-side).
* `task_harvest` increments ("收割三叶草" counting) — the client shows the row as done
  at `>= 1`, the server owned the counter.
* the small/big box decision and the box's content table.
* `springcard_send`'s own reward (the box) and the "send card" share flow
  (`CardShareView.share(card_info,"spring")`, `reportBlog("share.springcard")`) — pure
  client, no server state beyond `box_id`.

### 1.7 Landmines

1. **`card_info` missing/mistyped ⇒ view crash.** `card_info:{bg:0,bless:0,tags:[0,0,0]}`
   is the minimum; `card_info:{}` (current stub) throws at
   `createCard`/`update`. `tags` must be length 3.
2. **Never answer `springcard_load` with an empty body.** `{"code":0}` sets
   `end_time = undefined` → `isOpen()` false → the button hides on the next
   `updateSpringCard` (and the model re-arms nothing). Always send the full payload.
3. **`springcard_send` must return `box_id > 0`** or the client's success branch never
   runs: the "send" overlay stays visible, the card is not cleared, and the box never
   appears — a clickable dead end.
4. **`springcard_buy` must return `tags_id > 0`** for the same reason; the shop icon
   also only redraws inside `e&&e.apply()`.
5. **`type: DropType.SPRINGCARDTAGS(101)` with an id outside `springCard.tags`
   (101–112) crashes the client** (`DropItemRender`, §0.1.6) — the exact class of bug
   that produced the reload loop before. Applies to `req_get_task_reward`,
   `req_buy` and `req_get_share_tags`, all of which push `{item_id, count, type:101}`.
6. **`springcard_get_reward` with `num>0` and `id` outside `Item.json`** renders an
   empty icon (guarded), but with `id ∈ toys_list` the copy tells the player to check
   the mailbox — deliver a mail or avoid those ids.
7. **`share_code` must be a non-empty string** in `springcard_share_tags`, else the
   `req_get_task_reward()` chain and the share view's `"code="+share_code` both break
   silently (the whole code-execution branch is the truthiness test `e.share_code&&`).
8. **`springcard_get_share_tags` returning `code` 1/2/3/4 also lacks `tags_id`** — that
   is correct and intended (the `else` branch runs). Returning **both** means success
   wins. Returning a code outside 1–4 leaves the default message
   "今日分享已达到上限啦", which is misleading but not fatal.
9. `springcard_get_task_item` is declared but unreachable — implementing it changes
   nothing; pushing `springcard_load_task_item` is the only way to deliver task rows.
10. `pos` is **1-based** on the wire (`e+1`) but 0-based in `card_info.tags`. Out-of-range
    `pos` writes `tags[3] = id`, growing the array to length 4; `getTagsNum` would then
    count 4 slots and `canSendCardid` would still be satisfied — a silent state drift,
    not a crash. Clamp to 1..3.
11. `count: 0` in `springcard_load_count` is skipped (`i.count&&`), so `global_num`
    keeps its previous value; make sure `springcard_load` always carries a number so the
    very next `.toString()` cannot throw.
12. Cosmetic: `goods_201_png` (§1.5) is missing; the shop's bag icon is blank.

---

## 2. 祝福贺卡 (中秋) — `greetcard_*`

### 2.1 Model + window

`GreetCardEventType` `@119170`, model class `@119367` … `@126693`.

Default `data` (`@119464`):

```js
var GreetCardModel=function(e){function t(){var t=null!==e&&e.apply(this,arguments)||this;
return t.data={end_time:0,card_info:{bg:0,bless:0,tags:[0,0,0]},send_list:[],get_list:[],items:[],task_login:!1,task_share:!1,task_item:[],can_reward:!1,global_num:0,new_index:0,stock_num:0},t}
```

Listeners (`@119705`):

```js
t.prototype.initModel=function(){this.addProtocolCallback("greetcard_load","greetcard_get_task_item")}
```

Here the registered push name **is** the command the client also sends
(`req_get_task_item @122609` → `send("greetcard_get_task_item")`, no Action), so one
mechanism serves both; there is no double invocation (the reply carries a session but
`callbackFun` is `null`, so only the listener path runs).

Window (`@124070`, `@124158`) — byte-identical to SpringCard.

Timer arming inside `greetcard_load` (`@119940`):

```js
this.isOpen()&&(this.checkRedot(),egret.clearTimeout(this.timerActivity),this.timerActivity=egret.setTimeout(function(){t.closeActivity()},this,1e3*(this.getActivityTime()[1]-core.Time.getServerTime()+1))),this.dispatchEvent(new core.Event(GreetCardEventType.CARD_CHANGE))
```

GreetCard-only derived logic:

```js
// @124298  — stock / background economy
isFirstBuyBg=function(){if(this.data.stock_num>0)return!1;for(var e=0,t=this.data.items;e<t.length;e++){var i=t[e];if(i.item_id<100)return!1}return!0}
isBuyBg=function(e){for(var t=0,i=this.data.items;t<i.length;t++){var n=i[t];if(n.item_id==e)return!0}return!1}
// @124585
getCanStockNum=function(){var e=Tabikaeru.DataManager.instance().greetCardData.get("bg_price");return e.length-1-this.data.stock_num}
// @124731
canStock=function(){if(this.data.card_info.bg>0)return!1;if(this.getCanStockNum()<=0)return!1;
for(var e={},t=0,i=this.data.items;t<i.length;t++){var n=i[t];e[n.item_id]=n.num}
for(var r=Tabikaeru.DataManager.instance().greetCardData.get("bg_list"),o=0,a=r;o<a.length;o++){var n=a[o],s=e[n.id.toString()];if(null==s||s>0)return!1}return!0}
// @125081
isSendBg=function(e){for(var t=0,i=0,n=this.data.send_list;i<n.length;i++){var r=n[i];r.bg==e&&t++}return t>=this.data.stock_num+1}
// @125730  — the "new card" pointer into get_list
getNewCard=function(){return this.data.new_index>0?this.data.get_list[this.data.new_index-1]:void 0}
// @123691  — red dot
checkRedot=function(){var e=0;this.isOpen()&&(this.data.can_reward&&(e=1),this.data.task_item.length>0&&(e=1)),Tabikaeru.RedotManager.instance().setRedotValue(Tabikaeru.RedotType.GREETCARD,e)}
```

`getMoonPic` (`@688657`) maps `global_num` onto `global_reward`:

```js
function o(e){for(var t="server_card_1",i=Tabikaeru.DataManager.instance().greetCardData.get("global_reward"),n=0,r=i;n<r.length;n++){var o=r[n];e>=o.num&&(t=o.pic)}return""==t?"":t+"_png"}
```

`global_reward = [{num:100000,pic:"server_card_2"},{num:300000,pic:"server_card_3"},{num:660000,pic:"server_card_4"},{num:1000000,pic:""}]`
— so `global_num` below 100 000 shows `server_card_1_png` and ≥1 000 000 shows
nothing (`imageMoon.source=""`). All four `server_card_*.png` exist.

**Payload values that keep it permanently open:** `end_time` > now (§0.1.4). Nothing
else gates it.

### 2.2 Command table

| # | command | protocol.js params | needResponse | client send site | reply fields read | visible effect | follow-up |
|---|---|---|---|---|---|---|---|
| 1 | `greetcard_load` | `[]` | true | `req_load @120602` (no Action) + BOOT_PUSH | every field, wholesale | entry button, card, lists, red dot | none |
| 2 | `greetcard_load_count` | `[]` | true | `@120708` | `count` | global counter + moon art | none |
| 3 | `greetcard_buy` | `["id"]` | true | `@120902` | `code` | +1 of that bg/sticker in `items` | none |
| 4 | `greetcard_change_bg` | `["id"]` | true | `@121086` | `code` | consumes 1 bg, returns the previous one | none |
| 5 | `greetcard_change_bless` | `["id"]` | true | `@121426` | `code` | blessing changes | none |
| 6 | `greetcard_put_tags` | `["pos","id"]` | true | `@121690` | `code` | sticker placed/removed | none |
| 7 | `greetcard_send` | `[]` | true | `@122038` | `code` | card pushed to `send_list`, `can_reward=true`, share popup | none |
| 8 | `greetcard_get_reward` | `["id"]` | true | `@122384` | `code`, `list` | gift list of the chosen thank-you gift | none |
| 9 | `greetcard_get_task_item` | `[]` | true | `@122609` (also a push listener) | `list` | task rows; may chain | `greetcard_load` (+ `greetcard_get_task_reward` when the view is open) |
| 10 | `greetcard_get_task_reward` | `[]` | true | `@122728` | `code` | grants every id in `task_item` | none |
| 11 | `greetcard_stock` | `[]` | true | `@123183` | `code` | `stock_num++`, all bg items (`item_id<100`) removed | none |
| 12 | `greetcard_read_new` | `[]` | **false** | `@123496` | — | clears `new_index` locally | none |
| 13 | `greetcard_send_gift` | `["index","gift"]` | **false** | `@123651` (`send(...,null,e+1,t)`) | — | `get_list[index].gift = gift` locally | none |
| 14 | `greetcard_feedback_gift` | `["id"]` | **false** | `@791704` (from the mail UI) | — | thanks the sender | none |

Quoted callbacks:

`greetcard_load` — `@119775` (⚠ whole-object replace via `convertArrayAll`, then
`card_info` is re-assigned from the raw reply, and `task_item` is *kept from before*):

```js
t.prototype.greetcard_load=function(e){var t=this,i=this.data.task_item||[];this.data=Utils.convertArrayAll(e),this.data.card_info=e.card_info,this.data.task_item=i,this.isOpen()&&( ... timer ... ),this.dispatchEvent(new core.Event(GreetCardEventType.LOAD))}
```

`Utils.convertArrayAll(e)` (`@300427`):

```js
function v(e){return Array.isArray(e)?e:[]}
function _(e){var t={};for(var i in e)"object"==typeof e[i]?t[i]=v(e[i]):t[i]=e[i];return t}
```

⇒ every **own property whose `typeof` is `"object"` is replaced by `[]`** — this includes
`card_info` (which is why the next statement re-assigns it) but **also any nested
object you invent**. Do not put objects in this payload except `card_info`; nested
objects inside arrays survive (`convertArrayAll` is shallow), which is why
`send_list: [{...}]` is fine.

`greetcard_get_task_item` — `@120274` (⚠ no guard on `e.list`):

```js
t.prototype.greetcard_get_task_item=function(e){this.data.task_item=e.list,this.checkRedot(),this.data.task_item.length>0&&(this.req_load(),core.PageManage.getInstance().getControl(GreetCardViewControl,core.ViewLayerType.WindowLayer)&&this.req_get_task_reward())}
```

`req_load_count` — `@120626`:

```js
t.prototype.req_load_count=function(e){var t=this;...send("greetcard_load_count",new core.Action2(function(i){null!=i.count&&(t.data.global_num=i.count,e&&e.apply())}))}
```

`req_buy` — `@120825`:

```js
t.prototype.req_buy=function(e,t){var i=this;core.SocketManage.getInstance().send("greetcard_buy",new core.Action2(function(n){0==n.code&&(i.changeItems(e,1),t&&t.apply())}),e)}
```

`req_change_bg` — `@121070` (⚠ consumes and refunds background items):

```js
t.prototype.req_change_bg=function(e,t){var i=this;core.SocketManage.getInstance().send("greetcard_change_bg",new core.Action2(function(n){0==n.code&&(i.changeItems(e,-1),i.data.card_info.bg>0&&i.changeItems(i.data.card_info.bg,1),i.data.card_info.bg=e,i.dispatchEvent(new core.Event(GreetCardEventType.CARD_CHANGE)),t&&t.apply())}),e)}
```

`req_change_bless` `@121390`, `req_put_tags` `@121670` — same shape as springcard's
(`0==code`, `changeItems(t,-1)` + refund of the previous sticker, `pos` sent as `e+1`).

`req_send` — `@122038` (⚠ the only greetcard success branch that requires `code==0`
*and* mutates state, then hands the card object to its caller):

```js
t.prototype.req_send=function(e){var t=this;core.SocketManage.getInstance().send("greetcard_send",new core.Action2(function(i){if(0==i.code){t.data.can_reward=!0;var n={bg:t.data.card_info.bg,bless:t.data.card_info.bless,tags:t.data.card_info.tags};t.data.send_list.push(n),t.data.card_info={bg:0,bless:0,tags:[0,0,0]},e&&e.apply(n)}}))}
```

`req_get_reward` — `@122300` (⚠ **`list` is an array of item IDs, not rows**):

```js
t.prototype.req_get_reward=function(e,t){var i=this;core.SocketManage.getInstance().send("greetcard_get_reward",new core.Action2(function(e){e.list.length&&e.list.length>0&&(i.data.can_reward=!1,i.checkRedot(),t&&t.apply(e.list))}),e)}
```

matched by the view `@672276`:

```js
t.getModel(GreetCardModel).req_get_reward(t.selectId,new core.Action1(function(e){for(var t=[],i=0,n=e;i<n.length;i++){var r=n[i];t.push({item_id:r,count:1})}core.PageManage.getInstance().addViewControl(GiftPackageViewController,core.ViewLayerType.NoticeLayer,null,t)}))
```

`req_get_task_reward` — `@122687`:

```js
t.prototype.req_get_task_reward=function(){var e=this;core.SocketManage.getInstance().send("greetcard_get_task_reward",new core.Action2(function(t){if(0==t.code){for(var i=[],n=0,r=e.data.task_item;n<r.length;n++){var o=r[n];e.changeItems(o,1),i.push({item_id:o,count:1,type:Tabikaeru.DataType.DropType.CARDTAGS})}core.PageManage.getInstance().addViewControl(GiftPackageViewController,core.ViewLayerType.NoticeLayer,null,i),e.data.task_item=[],e.checkRedot()}}))}
```

`req_stock` — `@123106`:

```js
t.prototype.req_stock=function(e){var t=this;core.SocketManage.getInstance().send("greetcard_stock",new core.Action2(function(i){if(0==i.code){t.data.stock_num++;for(var n=t.data.items.length-1;n>=0;n--)t.data.items[n].item_id<100&&t.data.items.splice(n,1);e&&e.apply()}}))}
```

`req_read_new` — `@123381`:

```js
t.prototype.req_read_new=function(){0!=this.data.new_index&&(this.data.new_index=0,core.SocketManage.getInstance().send("greetcard_read_new"))}
```

`req_send_gift` — `@123525` (⚠ `index` goes out **1-based**; `gift` is an item id):

```js
t.prototype.req_send_gift=function(e,t){this.data.get_list[e]&&(this.data.get_list[e].gift=t),core.SocketManage.getInstance().send("greetcard_send_gift",null,e+1,t)}
```

`greetcard_feedback_gift` — `@791704`, inside the mail popup
(`else if(this.mailInfo.type==Mail.EvtId.CardGift){var i=new ModalConfirm(_("是否感谢他的赠礼？"),function(){core.SocketManage.getInstance().send("greetcard_feedback_gift",null,t.mailInfo.id),...`

`Mail.EvtId.CardGift = 14` (`@413307`); the matching notifications are
`TimerEvent.Type.CardGift = 25`, `CardFeedback = 26`, `CardNew = 27` (`@416811`+), with
copy `_("{0}\n送来了礼物", g.evt_string[0])` (`@892512`) and
`_("{0}\n收到了你的赠礼")` (`@892620`). So the "receive a card" path is:
engine pushes a TimerEvent (25) + a mail row of type 14 → the player opens the mail →
`greetcard_feedback_gift`; and the card itself arrives in `greetcard_load.get_list` with
`new_index` pointing at it → `MainOut.checkStory @821170` shows `c_newStory` and
`StoryAlertView(...)`, then `req_read_new() @805561`.

### 2.3 Payload shapes

**`greetcard.load` (push or reply):**

```json
{
  "end_time": 4102444800,
  "card_info": { "bg": 0, "bless": 0, "tags": [0, 0, 0] },
  "send_list": [ { "bg": 1, "bless": 2, "tags": [101, 0, 0] } ],
  "get_list":  [ { "name": "困困", "bg": 3, "bless": 4, "tags": [107, 110, 0], "gift": 0 } ],
  "items": [ { "item_id": 1, "num": 1 }, { "item_id": 101, "num": 3 } ],
  "task_login": false,
  "task_share": false,
  "task_item": [],
  "can_reward": false,
  "global_num": 0,
  "new_index": 0,
  "stock_num": 0
}
```

Hard requirements:

1. `card_info` — **must be a real object** (re-assigned after `convertArrayAll`);
   missing ⇒ `this.data.card_info` is `[]` (convertArrayAll turned it into an array!) or
   `undefined`, and the view's `card_info.bg` / `createGreetCard` throw.
2. `end_time` numeric > now.
3. `global_num` numeric — `updateCount @692386` does
   `e.globalNum.text=e.data.global_num.toString()`.
4. `items` — array of `{item_id, num}`. Ids `<100` are the 5 backgrounds
   (`bg_list[].id` = 1…5) and ids `>100` are stickers (101…125). `isFirstBuyBg`
   (`stock_num==0` and **no** `item_id<100` present) drives the "首次购买免费" label.
5. `send_list` rows need `bg`, `bless`, `tags` — `GreetCardSendListItem @681090` passes
   the row straight into `GreetCardUtils.createGreetCard(groupBg, this.data)`.
   `send_list.length > 0` makes the history button visible (`@693220`).
   `isSendBg(bg) @125081` counts rows per `bg` and compares to `stock_num+1`.
6. `get_list` rows are opened as full cards: `CardItem.setInfo @1109340` reads
   `t.gift` (`0` = not yet gifted, `>0` = gifted item id), `.name` (title text), and
   `createGreetCard(groupCard, this.info)` needs `bg/bless/tags`.
   `StoryView.renderCard @1104170` iterates it and calls
   `t.indexOf(this.cardData)` — so the objects must be the **same array** the model
   holds (they are, since the view reads `getModel(GreetCardModel).data.get_list`).
7. `new_index` is **1-based** into `get_list` (`getNewCard` → `get_list[new_index-1]`);
   `0` disables the "new card" popup. A 1-based index past the end yields `undefined`
   → `checkStory` treats it as "no new card", no crash.
8. `stock_num` = how many background *batches* have been bought; `getCanStockNum()` =
   `bg_price.length-1-stock_num` = `2 - stock_num`.

**Replies:**

| command | success reply | notes |
|---|---|---|
| `greetcard_load_count` | `{"count": 0}` | only `null !=` is rejected |
| `greetcard_buy` | `{"code": 0}` | |
| `greetcard_change_bg` / `_bless` / `_put_tags` | `{"code": 0}` | |
| `greetcard_send` | `{"code": 0}` | must be `0` — the branch is `if(0==i.code)` |
| `greetcard_get_reward` | `{"code": 0, "list": [47]}` | **`list` = array of item ids**; must exist (`e.list.length` is unguarded) |
| `greetcard_get_task_item` | `{"list": [101, 107]}` | **`list` must be an array** (unguarded `.length` in `checkRedot`) |
| `greetcard_get_task_reward` | `{"code": 0}` | |
| `greetcard_stock` | `{"code": 0}` | |
| `greetcard_read_new` | *(nothing)* | needResponse false |
| `greetcard_send_gift` | *(nothing)* | needResponse false, `null` action |
| `greetcard_feedback_gift` | *(nothing)* | needResponse false |

### 2.4 Data tables

`tables.greetCard` (7 keys, read as an object):

| key | type | client use |
|---|---|---|
| `bg_list` | array, 5 rows | ✅ select view, shop, `createGreetCard` |
| `tags` | array, **25 rows** | ✅ select/shop/`getTagsCfg`; **not sorted by id** — the client sorts by `index` |
| `bless` | array, 6 rows | ✅ |
| `send_reward` | `{random_list:[11 ids], select_list:[47..53]}` | ✅ `GreetCardRewardView @672960` |
| `global_reward` | 4 rows `{num,pic}` | ✅ `getMoonPic` |
| `bg_price` | `[100,150,200]` | ✅ `getItemPrice`, `getCanStockNum` |
| `tags_price` | `20` | ✅ `getItemPrice` for `id>=100` |

Representative rows verbatim:

```json
// bg_list[0]
{"id":1,"layer":[1,2,3,4,5,6],"name":"荷塘月色",
 "pos":[[0,0],[0,0],[-13,86],[22,-15],[171,40],[0,0]],
 "res":["greetcard_1","greetcard_1_1","","","","greetcard_1_2"],
 "style":[100,100,53,53,53,100],"tags":[0,0,1,2,3,0]}
// tags: two rows showing both a low and a high index, and a "special" type
{"id":101,"index":1,"name":"青蛙1","pic":"greetpaster_1","type":1}
{"id":124,"index":8,"name":"月饼1","pic":"greetpaster_24","type":10}
// bless[0]
{"desc":"中秋节快乐~","id":1}
// send_reward
{"random_list":[1000,1,8001,5101,20001,102,1105,54,11001,56,10105],"select_list":[47,48,49,50,51,52,53]}
// global_reward
[{"num":100000,"pic":"server_card_2"},{"num":300000,"pic":"server_card_3"},
 {"num":660000,"pic":"server_card_4"},{"num":1000000,"pic":""}]
```

Keying:

* `bg_list` — linear lookup by `id` (1…5); `res[0]` is the background and
  `res[1..5]` are the optional layers. `createGreetCard` (`@688954`) iterates all 6
  entries of `res`, and for entry `t` with `tags[t] != 0` it draws the sticker
  `card_info.tags[tags[t]-1]`. Every row's `tags` is a 6-element array whose nonzero
  values are exactly `1,2,3` (e.g. row 1 `[0,0,1,2,3,0]`), i.e. three sticker slots →
  `card_info.tags[0..2]`, the same 3-slot layout as springcard. `pos`/`style` give the
  per-layer offset and scale in percent.
* `tags` — lookup by `id` only; `index` is the display order (1…25, out of id order:
  `123,124,125` are index 7,8,9 and `107` is index 10). `type` groups the "one per
  card" rule (`canPutTags @688846`): types 1,2,3,4,5,6,7,8,9,10,11 appear; identical
  `type` stickers cannot occupy two different slots.
* `send_reward.select_list` = the 7 mooncakes (items 47–53, all present in `Item.json`,
  `info` and `img` non-empty — `@673211` calls `c.info.toString()` **unguarded**, so any
  id in `select_list` without `info` is a crash).
* `send_reward.random_list` = the 11 ids the reward view spins through, all present.
* `bg_price[stock_num]` is the price of the *next* batch: `stock_num=0` → 100,
  `1` → 150, `2` → 200; `getCanStockNum() = 2 - stock_num`.

### 2.5 Assets

`images/Scene/GreetCard/` — **77 files**:

* `Bg_ui/` (30): `greetcard_bg.png`, `greetcard_decorate.png`, `greetcard_tips.png`,
  `no_greetcard_tips.png`, `share_greetcard_bg.png`, `text_greetcard_none.png`,
  `text_greetcard_sent.png`, `text_greetcard_using.png`, `server_card.png`,
  `server_card_1…4.png`, `cardshop_line.png`, `cardshop_line_clip.png`,
  `cardshop_paster_bg.png`, `card_quest_bg1.png`, `card_quest_bg2.png`,
  `card_quest_bg2_check.png`, `card_quest_line.png`, `mooncake_another.png`,
  `share_card_autumn.png`, `text_choice_mooncake.png`, `tips_greet_bg.png`,
  `tips_greet_paster.png`, `tips_greet_card_btn_buy.png`, `tips_greet_card_first.png`,
  `tips_greet_card1.png`, `tips_greet_card2.png`, `tips_greet_card3.png`
* root (8): `btn_card_change.png`, `btn_card_send.png`, `btn_greet_card_off.png`,
  `btn_greet_card_on.png`, `btn_greet_paster_off.png`, `btn_greet_paster_on.png`,
  `btn_move_cardshop.png`, `btn_paster_opt.png`
* `Card/` (14): `greetcard_1.png`, `greetcard_1_1.png`, `greetcard_1_2.png`,
  `greetcard_2.png`, `greetcard_2_1.png`, `greetcard_2_2.png`, `greetcard_3.png`,
  `greetcard_3_1.png`, `greetcard_3_2.png`, `greetcard_4.png`, `greetcard_4_1.png`,
  `greetcard_4_2.png`, `greetcard_5.png`, `greetcard_5_1.png`
* `Paster/` (25): `greetpaster_1…25.png`

Also present elsewhere: `images/Back/back_makecake.png` (shared cake background),
`Share/CardShareSkin.exml` + `Share/ShareSelector.exml` (compiled), the dragonbone
`zhongqiutuzi` (3 res entries) used by `GreetCardView @690670`
(`this.rabbit.source="zhongqiutuzi:Armature"`).

Compiled skins in `default.thm.js` (**9**):

| skin | named children |
|---|---|
| `GreetCardViewSkin.exml` | `labelDisplay btnRefreshTween btnHistory btnClose lblLimitDate btnBg btnSend lblLimitDate0 btnShop taskBg1 taskBg2 taskCheck1 taskCheck2 groupCard imageBless lbBless imageMoon globalNum rabbit groupSend actionSend` |
| `GreetCardSelectSkin.exml` | `groupCard imageSelect cover imageBuy groupTags imageTags lbNum imageBg lbBless groupRoot svBg listBg svTags listTags svBless listBless` |
| `GreetCardShopViewSkin.exml` | `labelDisplay btnRefreshTween moneyPanel payBtn cloverPoint btnClose groupPrice imagePrice groupStock lbNum imageFree lbTips svBg svTags btnBg btnTags` |
| `GreetCardShopBgSkin.exml` | `imageLine groupBg cover imageBuy` |
| `GreetCardShopTagsSkin.exml` | `imageTags` |
| `GreetCardSendViewSkin.exml` | `labelDisplay groupRoot groupBg btnClose listBg` |
| `GreetCardShareSkin.exml` | `cover btnShare groupCard` |
| `GreetCardRewardSkin.exml` | `image cover groupSelect groupCake iconSelect groupRandom iconRandom confirmBtn groupMoon cover1 lbBless scroller groupList cover2 listRandom` |
| `GreetCardBuyItemSkin.exml` | `cover imageBg label confirmBtn cancelBtn groupBg groupCard groupTags imageTags lbNum` |

Note `GreetCardShopViewSkin` has `groupStock`/`lbNum`/`btnBg`/`btnTags`, which is why the
stock UI (`getCanStockNum()+"次"`, `tips_greet_card{N}_png`) and the tab switching
(`onSelectTab`) only exist for GreetCard, not SpringCard.

### 2.6 Recoverable rules vs unrecoverable

**Recovered (use verbatim):**

* `GreetCardUtils.getItemPrice(id, stock_num)` (`@688023`):
  `id < 100 ? bg_price[stock_num] : tags_price` ⇒ backgrounds cost 100/150/200 clover
  by batch, stickers cost **20** flat.
* first purchase free: `isFirstBuyBg()` (no batch bought yet and no background owned)
  ⇒ the buy-item popup shows `首次购买免费` and the clover check is bypassed
  (`GreetCardBuyItemView @670247`: `if(t.getModel(GreetCardModel).isFirstBuyBg()&&(i=0)`).
* stock batches: `bg_price.length - 1 = 2` extra batches; each `greetcard_stock`
  increments `stock_num` and *destroys every owned background item*
  (`item.item_id<100 && splice`) — recovered exactly from `@123106`.
* `canStock()` (`@124731`) — all 5 backgrounds must be **owned with `num<=0`** and
  `card_info.bg == 0`; a strange but exact rule recovered from `@124731`. Note it also
  fails if a background id is *absent* from `items` (`null==s` ⇒ `return !1`).
* `isSendBg(bg)` — after `stock_num` batches you may send up to `stock_num+1` cards;
  the shop shows `text_greetcard_sent_png` when exhausted (`@678030`).
* task rows (hardcoded in `GreetCardView.update @693349`):
  row 1 `task_login`, row 2 `task_share`; each flips `card_quest_bg1_png` →
  `card_quest_bg2_png` and shows a check mark. **What counts as "login"/"share" and
  when the counters reset is server-side and unrecoverable.**
* thank-you gift pool: `send_reward.select_list` (7 mooncakes) is what the player picks
  from; `random_list` only drives the spin animation. `greetcard_get_reward` decides
  what actually lands in the gift package.
* moon art tiers: exact, from `global_reward` (100k/300k/660k/1M).
* sticker `type` grouping rule: exact, from `tags[].type` + `canPutTags`.
* gate between card and blessings: `bless.id == 6` is "不写祝福" (no blessing);
  the card's `bless` field may be 0 (nothing chosen) — `getBlessDesc` returns
  `"点击选择祝福语~"` for an unknown id.

**Unrecoverable (server-only) — label any implementation as self-designed:**

* how `can_reward` becomes true beyond the client's own `req_send` success; whether a
  received card also grants a reward; the anti-abuse/one-per-player rules of the card
  exchange.
* `global_num` growth ("祝福值"), the four thresholds' meaning, and whether the tiers
  grant anything (the client only swaps the moon art).
* the per-day cap on sending cards and on `greetcard_stock`.
* `new_index` lifecycle: what marks a card "new" (server), how long it stays new, and
  whether `greetcard_read_new` must also be acked in any way (the client sends it
  fire-and-forget with `needResponse:false`).
* what `stock_num` resets on (period boundary).
* whether `greetcard_get_reward` must return exactly the item the player selected —
  the client passes the selection as `id` and blindly renders whatever `list` comes
  back; nothing in the client enforces the mapping. (Strong hint: it *should* return
  `[selectedId]`, otherwise the PlayerBag picker is decoration.)

### 2.7 Landmines

1. **`convertArrayAll` destroys nested objects.** `greetcard_load`'s reply is passed
   through it, so `card_info` must be a plain object (it is re-read from the same reply
   immediately after) and **any other nested object becomes `[]`**. Keep the payload
   flat apart from `card_info`.
2. **`greetcard_get_task_item` without `list` crashes.**
   `this.data.task_item = e.list` then `checkRedot()` reads
   `this.data.task_item.length` → `TypeError: Cannot read properties of undefined
   (reading 'length')` → the client shows 呱呱吃坏肚子了 and reloads; because the view's
   `childrenCreated` re-sends `greetcard_get_task_item` every time it opens
   (`@692335`), this is a **loop**. Always send `list: []` at minimum.
3. **`greetcard_get_reward` without `list` crashes the same way** (`e.list.length` is
   unguarded at `@122384`). Always include an array.
4. **`task_item` / `list` are arrays of STICKER IDS**, and the callback immediately
   feeds them to `GiftPackageViewController` with `type: DropType.CARDTAGS (100)` →
   `GreetCardUtils.getTagsCfg(id).pic` **unguarded** (§0.1.6). Ids must be in
   `greetCard.tags` (101–125) — note this range is *not* contiguous with the display
   order, and includes 123/124/125.
5. **`greetcard_send` must return `code: 0`.** `if(0==i.code)` gates the *whole*
   success path: `can_reward`, `send_list.push`, card clearing and the `e.apply(n)`
   that opens `GreetCardShareView`. A non-zero/missing code leaves the card on screen —
   a dead button.
6. **`getNewCard()` indexes `get_list` 1-based.** `new_index` must be `0` or a valid
   1-based position; `new_index = index` (0-based) silently shows the *wrong* card.
7. **`greetcard_send_gift`'s `index` is 1-based** on the wire while `CardItem` passes a
   0-based array position (`CardItem.setInfo(index)`, then `req_send_gift(t.index,e)`
   → `send(...,e+1,t)`). The engine receives 1-based and must map back.
8. **`get_list` rows must carry `gift`** (`0` = ungifted, `>0` = the gifted item id).
   A missing `gift` is `undefined`, and `CardItem.setInfo @1109340` tests `0==t.gift`
   → false ⇒ the card renders as **already gifted** and the gift button is
   unreachable (`this.info.gift>0||` guard in `feedback @1110360`).
9. **`greetcard_stock` deleting items.** The client removes every `item_id<100` from
   `items`; the engine must do the same, or `canStock()` will still be false next time
   while the UI claims a new batch exists.
10. **`send_list` / `get_list` rows double as card-render input**: each needs
    `bg` (1…5, from `bg_list`), `bless` (0…6) and `tags` (3 ints or 0). A `bg` not in
    `bg_list` makes `createGreetCard` do nothing (guarded `if(null!=o)`) — an invisible
    card, not a crash.
11. **`global_num` must be a number**; `updateCount` calls `.toString()` directly.
12. **`select_list` item ids must have non-empty `info`** — `@673211` calls
    `c.info.toString()` with no guard, and `ItemDB.get()` returns `undefined` for an
    unknown id (`IdGetter.get=function(e){return this.dictSrc[e]}` `@404350`) ⇒
    `undefined.info` is an immediate crash when the reward view opens.

---

## 3. 生日聚会蛋糕 — `partycake_*`

### 3.1 Model + window

`PartyCakeEventType` `@159341`, model class `@159491` … `@165262`.

Default `data` (`@159588`):

```js
var PartyCakeModel=function(e){function t(){var t=null!==e&&e.apply(this,arguments)||this;
return t.data={end_time:0,cream:0,sugar:0,pre_cream:0,pre_sugar:0,cur_state:0,part:0,layers:[],task_list:[],guest:0,wrong:0,answer:[],reward:[],share_get:[]},t}
```

Listeners (`@159796`):

```js
t.prototype.initModel=function(){this.addProtocolCallback("partycake_load","partycake_load_mate","partycake_load_task","partycake_load_qa")}
```

`partycake_load_mate` and `partycake_load_task` **are push-only**: no `send(...)` for
them exists in the client (the table at `@380960` declares them because
`ProtocolList` also lists every push name; only `send` validates). `partycake_load_qa`
is both pushed-capable and sent by `req_load_qa @161295` (no Action).

Window (`@164451`, `@164539`) — same as the other two.

`PartyCakeState` (`@422798`):

```js
PartyCakeState:{making:0,make_reward:1,qa:2,qa_reward:3,light:4,light_reward:5,complete:6}
```

`checkMakePart` (`@163278`) — the part advance:

```js
t.prototype.checkMakePart=function(){var e=Tabikaeru.DataManager.instance().partycakeData.get("cake")[this.data.part];if(e){var t=0;for(var i in e.layers)t++;this.data.layers.length>=t&&(this.data.part++,this.data.layers=[]),this.checkRedot()}}
```

⚠ `this.data.part` must be **1…5** while the state is in `{making, make_reward, qa,
qa_reward}` — the view indexes `partycakeData.get("cake")[this.data.part]` and
dereferences `.time` / `.name` / `.layers[..]` with no guard (§3.1.3).

**Payload values that keep it permanently open:** `end_time` > now. `part` must be a
valid 1…5 (or ≥6 with `cur_state ∈ {4,5,6}`); `cur_state` must be one of 0…6.

#### 3.1.1 The state machine (client-side transitions, derived from code)

| state | where the client goes next | what the engine must return |
|---|---|---|
| `making(0)` | `btnMake` → `req_make(layer)` | `partycake_make` reply `{state: 1}` |
| `make_reward(1)` | `btnOpen` → `req_make_reward()`; also auto-opens the gift view | `partycake_reward_make` reply `{state: 2}` (quiz part) or `{state: 4}` (final part) |
| `qa(2)` | `PartyCakeQaView`, `btnOk` → `req_answer(index)` | `partycake_answer` reply `{state: 2}` = wrong (stay), `{state: 3}` = correct |
| `qa_reward(3)` | `btnOk` → `req_reward_qa()` | `partycake_reward_qa` reply `{state: 0}` (next part is makeable) — `checkMakePart()` then advances `part` |
| `light(4)` | `btnMake` becomes 点蜡烛 → `req_light()` | `partycake_light` reply `{state: 5}` |
| `light_reward(5)` | `btnOpen` → `req_reward_light()` | `partycake_reward_light` reply `{state: 6}` |
| `complete(6)` | `btnShare` → `PartyCakeShareView` | `partycake_reward_share(1|2)` reply `{code:0}` |

Evidence:

```js
// view @963220 — the light state reuses btnMake
if(t.data.cur_state==Tabikaeru.Define.PartyCakeState.light)return void t.getModel(PartyCakeModel).req_light(new core.Action(function(){t.updateCake(),t.openGiftView()}));
// view @963524 — cream/sugar check before making
return t.data.cream<e||t.data.sugar<i?(t.addChild(new ModalAlert(_("材料不够了~"))),void t.onTaskShow()):void t.getModel(PartyCakeModel).req_make(t.cur_selete,new core.Action(function(){...}))
// view @963705 — the make result test
return t.data.cur_state!=Tabikaeru.Define.PartyCakeState.make_reward?void t.addChild(new ModalAlert(_("制作失败~"))):(t.cur_selete=null,t.updateMakeBtn(),t.updateMate(),t.updateCake(),void t.openGiftView())
// view @963986 / @964248 — the open-box branch
return t.data.cur_state==Tabikaeru.Define.PartyCakeState.light_reward?void t.getModel(PartyCakeModel).req_reward_light(new core.Action(function(){t.groupGift.visible=!1,t.updateCake()})):void t.getModel(PartyCakeModel).req_reward_make(new core.Action(function(){return t.data.cur_state==Tabikaeru.Define.PartyCakeState.make_reward?void t.addChild(new ModalAlert(_("领取失败~"))):(t.groupGift.visible=!1,t.updateCake(),void(t.data.cur_state!=Tabikaeru.Define.PartyCakeState.qa||...popup(new PartyCakeQaView(...))))}))
// view @967437 updateView — which states auto-open what
this.data.cur_state==Tabikaeru.Define.PartyCakeState.make_reward||this.data.cur_state==Tabikaeru.Define.PartyCakeState.light_reward?this.openGiftView():(this.data.cur_state==Tabikaeru.Define.PartyCakeState.qa||this.data.cur_state==Tabikaeru.Define.PartyCakeState.qa_reward)&&core.DisplayManage.getInstance().popup(new PartyCakeQaView(function(){e.updateCake()}))
// view @956054 — the quiz button
t.getModel(PartyCakeModel).req_answer(t.cur_selete,new core.Action(function(){return t.data.cur_state==Tabikaeru.Define.PartyCakeState.qa?(t.cur_selete=null,t.imageSelect.visible=!1,void t.UpdateQa()):(t.groupAnswer.visible=!1,void t.UpdateReward())}))
```

⚠ Which step returns `qa(2)` vs `light(4)` is **not in any table** — the enum order
plus `checkMakePart` imply "quiz after each part, candle at the end", which is the
assignment above, but it is a **reconstruction**, not a recovered value. Note that the
model skips `checkMakePart()` exactly when the new state *is* `qa`
(`@162143`), which is only consistent with the table above if the part advance happens
in `req_reward_qa` (which calls `checkMakePart()` at `@162587`).

#### 3.1.2 Quoted model callbacks

`partycake_load` — `@159904`:

```js
t.prototype.partycake_load=function(e){var t=this;this.data=Utils.convertArrayAll(e),this.data.end_time=e.end_time,this.data.cream=e.cream,this.data.sugar=e.sugar,this.data.pre_cream=e.pre_cream,this.data.pre_sugar=e.pre_sugar,this.data.cur_state=e.cur_state,this.data.part=e.part,this.data.layers=Utils.convertArray(e.layers),this.data.task_list=Utils.convertArray(e.task_list),this.data.share_get=Utils.convertArray(e.share_get),(this.data.cur_state==Tabikaeru.Define.PartyCakeState.qa||this.data.cur_state==Tabikaeru.Define.PartyCakeState.qa_reward)&&this.req_load_qa(),this.isOpen()&&( ... timer ... ),this.dispatchEvent(new core.Event(PartyCakeEventType.LOAD))}
```

`partycake_load_mate` `@160745`, `partycake_load_task` `@160872`, `partycake_load_qa` `@160957`:

```js
t.prototype.partycake_load_mate=function(e){this.data.pre_cream=e.pre_cream,this.data.pre_sugar=e.pre_sugar,this.checkRedot()}
t.prototype.partycake_load_task=function(e){this.data.task_list[e.task.id-1]=e.task}
t.prototype.partycake_load_qa=function(e){this.data.guest=e.guest,this.data.wrong=e.wrong,this.data.answer=Utils.convertArray(e.answer),this.data.reward=Utils.convertArray(e.reward)}
```

`req_get_mate` — `@161322` (⚠ commits the pending cream/sugar):

```js
t.prototype.req_get_mate=function(e){var t=this;core.SocketManage.getInstance().send("partycake_get_mate",new core.Action2(function(i){0==i.code&&(e&&e.apply(),t.data.cream+=t.data.pre_cream,t.data.sugar+=t.data.pre_sugar,t.data.pre_cream=0,t.data.pre_sugar=0,t.checkRedot())}))}
```

`req_make` — `@161602`:

```js
t.prototype.req_make=function(e,t){var i=this;core.SocketManage.getInstance().send("partycake_make",new core.Action2(function(n){if(i.data.cur_state!=n.state){i.data.cur_state=n.state,i.data.layers.push(e);var r=Tabikaeru.DataManager.instance().partycakeData.get("cake")[i.data.part].layers[e];i.data.cream-=r.cream,i.data.sugar-=r.sugar,i.checkRedot()}t&&t.apply()}),e)}
```

⚠ `layers[e]` is dereferenced inside the callback — if `e` is not a key of the current
part the callback throws (`Cannot read properties of undefined (reading 'cream')`)
whenever the state actually changes. `partycake_make`'s `layer` param must be a real
layer key of part `data.part`.

`req_make_reward` — `@161974`:

```js
t.prototype.req_make_reward=function(e){var t=this;core.SocketManage.getInstance().send("partycake_reward_make",new core.Action2(function(i){t.data.cur_state!=i.state&&(t.data.cur_state=i.state,t.data.cur_state!=Tabikaeru.Define.PartyCakeState.qa&&t.checkMakePart()),e&&e.apply()}))}
```

`req_answer` `@162258`, `req_reward_qa` `@162450`, `req_light` `@162647`:

```js
t.prototype.req_answer=function(e,t){var i=this;core.SocketManage.getInstance().send("partycake_answer",new core.Action2(function(e){i.data.cur_state=e.state,i.checkRedot(),t&&t.apply()}),e)}
t.prototype.req_reward_qa=function(e){var t=this;core.SocketManage.getInstance().send("partycake_reward_qa",new core.Action2(function(i){t.data.cur_state=i.state,t.checkMakePart(),e&&e.apply()}))}
t.prototype.req_light=function(e){var t=this;core.SocketManage.getInstance().send("partycake_light",new core.Action2(function(i){t.data.cur_state=i.state,t.checkRedot(),e&&e.apply()}))}
```

`req_reward_share` — `@163033` (⚠ 1-based index, once per slot):

```js
t.prototype.req_reward_share=function(e,t){var i=this;1!=this.data.share_get[e-1]&&core.SocketManage.getInstance().send("partycake_reward_share",new core.Action2(function(n){0==n.code&&(i.data.share_get[e-1]=1,i.checkRedot(),t&&t.apply())}),e)}
```

Note the view grants the *displayed* reward before asking the server, and it is the
`ItemRewardView`'s confirm callback that fires `req_reward_share` (`@960863`):

```js
0==e.data.share_get[i]&&n[i]&&(r.push({item_id:n[i],count:1}),core.PageManage.getInstance().addViewControl(ItemRewardViewControl,core.ViewLayerType.WindowLayer,null,r,function(){core.ModelManage.getInstance().getModel(ShareModel).reportBlog("share.partycake_"+(i+1)),e.getModel(PartyCakeModel).req_reward_share(i+1,new core.Action(function(){e.updatePages()}))}))
```

⇒ the engine must grant `share_reward[i]` **when the reward popup is confirmed**
(`partycake_reward_share`), not when the share starts — otherwise the player is paid
twice (once by the popup, once by the engine) or not at all if they dismiss the share.

### 3.2 Command table

| # | command | protocol.js params | needResponse | client send site | reply fields read | visible effect | follow-up |
|---|---|---|---|---|---|---|---|
| 1 | `partycake_load` | `[]` | true | `req_load @161204` (no Action) + BOOT_PUSH | everything (wholesale) | entry button, cake, tasks, share badges | `partycake_load_qa` when `cur_state ∈ {2,3}` |
| 2 | `partycake_load_qa` | `[]` | true | `req_load_qa @161295` (no Action) + push | `guest, wrong, answer, reward` | quiz content | none |
| 3 | `partycake_get_mate` | `[]` | true | `@161402` | `code` | commits pending 奶油/翻糖, shows the reward popup | none |
| 4 | `partycake_make` | `["layer"]` | true | `@161680` | `state` | layer drawn on the cake, cost deducted | none |
| 5 | `partycake_reward_make` | `[]` | true | `@162057` | `state` | layer gift popup; may advance `part`; may pop the quiz | none |
| 6 | `partycake_answer` | `["index"]` | true | `@162338` | `state` | wrong → re-ask, right → reward view | none |
| 7 | `partycake_reward_qa` | `[]` | true | `@162531` | `state` | quiz closes, `checkMakePart()` advances `part` | none |
| 8 | `partycake_light` | `[]` | true | `@162724` | `state` | candle lit, gift popup | none |
| 9 | `partycake_reward_light` | `[]` | true | `@162917` | `state` | light gift popup → complete | none |
| 10 | `partycake_reward_share` | `["index"]` | true | `@163148` | `code` | share badge 1/2 marked as claimed | none |
| P | `partycake_load_mate` | `[]` | — | push only | `pre_cream, pre_sugar` | pending-material popup on next open | `partycake_get_mate` (from the view) |
| P | `partycake_load_task` | `[]` | — | push only | `task.id`, `task.count`, `task.is_done`, `task` (whole row) | one task row updates | none |

### 3.3 Payload shapes

**`partycake.load` (push or reply):**

```json
{
  "end_time": 4102444800,
  "cream": 12, "sugar": 9,
  "pre_cream": 0, "pre_sugar": 0,
  "cur_state": 0,
  "part": 1,
  "layers": [1],
  "task_list": [
    {"id": 1, "count": 0, "is_done": 0},
    {"id": 2, "count": 0, "is_done": 0},
    {"id": 3, "count": 0, "is_done": 0},
    {"id": 4, "count": 0, "is_done": 0},
    {"id": 5, "count": 0, "is_done": 0},
    {"id": 6, "count": 0, "is_done": 0}
  ],
  "share_get": [0, 0]
}
```

Hard requirements:

1. `part` — **must index `PartyCakeData.cake`**: 1…5 for playable states, or ≥6 only
   together with `cur_state ∈ {4,5,6}` (see §3.1.3). `part: 0` (the current stub!) plus
   `cur_state: 0` throws as soon as the view opens.
2. `cur_state` — integer 0…6. Out-of-range values silently kill both the make button
   and the gift button (`updateCake`'s switch has no `default`).
3. `layers` — array of **layer numbers already made in the current part**, e.g. `[1]`
   or `[1,2]` for part 1. `isMakeLayer(layer)` is a linear `==` scan
   (`@163540`). Missing ⇒ `[]` ⇒ every layer looks unmade (the player can re-make and
   re-charge them).
4. `cream` / `sugar` — the material counters (`lbCream` / `lbSugar` render the string
   `"x" + value`).
   The client also deducts the layer cost locally *when the make reply changes the
   state* (`req_make @161602`: `i.data.cream-=r.cream,i.data.sugar-=r.sugar`), so the
   engine must deduct exactly once in its own state and simply not contradict it: the
   client never re-reads cream/sugar from the make reply, but the next
   `partycake_load` (or a new session) will overwrite the counters from the payload.
   Deducting server-side and reporting the reduced total on the next load is
   consistent; pushing an extra `partycake_load` that still shows the old total makes
   the charge disappear.
5. `task_list` — array of **objects** with `id` (1…6), `count`, `is_done`.
   The client (a) renders `cfg.name + "(" + count + "/" + cfg.total + ")"` using the
   table row for `id`, and (b) **filters out ids 3 and 4 when the ads SDK is
   unsupported** (`@965586`). Ids must be the six table keys; an unknown id makes
   `cfg` undefined → `Uncaught TypeError: Cannot read properties of undefined
   (reading 'name')` in the item renderer's `dataChanged` → 呱呱吃坏肚子了.
   Row order is re-sorted by the client (`s.sort(function(e,t){return e.is_done-t.is_done})`).
6. `share_get` — array of `0|1`, **0-based**, length 2 (one entry per
   `share_reward` element). Shorter is survivable (`undefined != 1` ⇒ not claimed), but
   `partycake_reward_share(2)` then rebates endlessly, so send two entries.
7. `end_time` numeric > now.

**`partycake.load_qa` reply/push:** `{"guest":0,"wrong":0,"answer":[14,47,53],"reward":[{"item_id":200006,"count":1}]}`

* `guest` ∈ `0,1,2` → the client picks the name from a hardcoded array
  `["困困","胖胖","跳跳"]` and the art `neighbor_emote_{guest}_{0|1|2}_png`
  (`@956750`, `@957503`; all 10 emote pngs exist).
* `wrong` is **only** used to choose between `text_ask_answer_png` (`wrong <= 0`) and
  `text_answer_again_png`. It is *not* refreshed after a wrong answer inside the same
  session (the client never re-sends `partycake_load_qa`), so the retry title only
  changes after a reopen.
* `answer` — **exactly 3 item ids**; the view loops `for(var r=1;3>=r;r++)` and calls
  `ItemDB.get(answer[r-1]).img` with **no guard** (§0.1.6). Fewer than 3 entries or an
  id outside `Item.json` = instant crash.
* `reward` — 1 or 2 rows `{item_id, count}`; `reward.length > 1` selects the "correct"
  emote art and `text_answer_right_png`, otherwise `text_answer_wrong_png`
  (`@957503`). Only the first two rows are rendered (the view has exactly
  `groupReward` children 1..2).

**Replies:**

| command | success reply | notes |
|---|---|---|
| `partycake_get_mate` | `{"code": 0}` | `0==code` gates the commit + popup |
| `partycake_make` | `{"state": 1}` | `state` must **differ** from the current one for the layer to register |
| `partycake_reward_make` | `{"state": 2}` (or `4` on the last part) | |
| `partycake_answer` | `{"state": 3}` correct / `{"state": 2}` wrong | `state` is assigned unconditionally |
| `partycake_reward_qa` | `{"state": 0}` | after this the client calls `checkMakePart()` |
| `partycake_light` | `{"state": 5}` | |
| `partycake_reward_light` | `{"state": 6}` | |
| `partycake_reward_share` | `{"code": 0}` | |
| `partycake.load_mate` (push) | `{"pre_cream": 2, "pre_sugar": 1}` | |
| `partycake.load_task` (push) | `{"task": {"id": 1, "count": 1, "is_done": 0}}` | indexed as `task_list[task.id-1]` |

`partycake_load_qa` is the only command that is both pushed and sent; when the client
sends it (because `cur_state ∈ {2,3}` on load), reply with the full QA payload.

### 3.4 Data tables

`tables.PartyCakeData` (4 keys):

```json
{
  "cake": { "1": {...}, "2": {...}, "3": {...}, "4": {...}, "5": {...} },
  "light_reward": { "item_id": 204001, "item_num": 2 },
  "share_reward": [ 14, 204001 ],
  "task_list": { "1": {...}, ... "6": {...} }
}
```

`cake` — object keyed by the **string** part number; each row `{name, part, time,
layers:{...}}`, `layers` keyed by the **string** layer number. Representative rows,
verbatim:

```json
"1": { "name": "蛋糕胚", "part": 1, "time": 1,
       "layers": {
         "1": {"cream":8,"item_id":204001,"item_num":1,"l_name":"蛋糕胚1层","layer":1,
               "make_pic":"cake_make_1_1_on","pre_pic":"cake_make_1_1_off","sugar":1},
         "2": {"cream":8,"item_id":204001,"item_num":1,"l_name":"蛋糕胚2层","layer":2,
               "make_pic":"cake_make_1_2_on","pre_pic":"cake_make_1_2_off","sugar":1} } }

"2": { "name": "装饰", "part": 2, "time": 1671379200, "layers": {
         "1": {"cream":6,"sugar":4,"item_id":204001,"item_num":1,"l_name":"装饰2层","layer":1,
               "make_pic":"cake_make_2_1_on","pre_pic":"cake_make_2_1_off"},
         "2": {"cream":6,"sugar":4,"item_id":204001,"item_num":1,"l_name":"装饰1层","layer":2,
               "make_pic":"cake_make_2_2_on","pre_pic":"cake_make_2_2_off"} } }

"4": { "name": "翻糖", "part": 4, "time": 1671984000, "layers": { /* 8 layers,
         l_name 翻糖·青蛙/萤火虫/乌龟/刺猬/松鼠/猫头鹰/壁虎/嘟嘟, cream 4 sugar 3 each */ } }

"5": { "name": "蜡烛", "part": 5, "time": 1672588800, "layers": {
         "1": {"cream":3,"sugar":2,"item_id":204001,"item_num":1,"l_name":"蜡烛","layer":1,
               "make_pic":"cake_make_5_1_on","pre_pic":"cake_make_5_1_off"} } }
```

`task_list` — object keyed by the string task id:

```json
"1": {"cream":1,"name":"登录游戏","sugar":0,"total":3}
"2": {"cream":2,"name":"商店买买买","sugar":0,"total":2}
"3": {"cream":2,"name":"商店抽奖一次","sugar":2,"total":3}
"4": {"cream":2,"name":"看一次广告","sugar":2,"total":3}
"5": {"cream":2,"name":"完成一次分享","sugar":2,"total":3}
"6": {"cream":2,"name":"聚会或是旅行","sugar":1,"total":2}
```

Keying / totals:

* `cake` is keyed by part number **as a string**; the client does `get("cake")[this.data.part]`
  with `this.data.part` a **number** — JS coerces, so both work; the engine must use the
  same keys.
* layer count per part (also the skin's node count): part1 = 2, part2 = 2, **part3 = 1**,
  part4 = **8**, part5 = 1 → 14 layers total.
* total material to finish one cake (recovered by summing the table):
  **cream 68, sugar 41** (part1 16/2, part2 12/8, part3 5/5, part4 32/24, part5 3/2).
* task rewards (all six tasks): **cream 29, sugar 20** — i.e. the task list alone cannot
  pay for one cake, so either tasks repeat (per period) or another feature
  (聚会/旅行, `TimerEvent.Type.PartyGo=23` / `PartyResult=24`) supplies materials.
  **That regeneration rule is server-side and unrecoverable.**
* each completed layer pays `item_id 204001 × item_num 1` (周年庆·家具礼袋);
  `light_reward` pays `204001 × 2`; `share_reward` pays item `14` (苹果汁) then
  `204001`. All three are table values — implement them as written, but they look like
  leftovers from the anniversary event, so treat the *amounts* as restored-table data
  rather than as a designed economy.

`tables.Item` (410 rows, an **array**; the client's own `Item_json` is the same 410
rows with `img`/`info` added, `work/spec/eab_Item_json`). Verified present:
`14 苹果汁`, `200006 奶油`, `200007 翻糖`, `200008/200009/200010` 贴纸袋/宝箱,
`200012/200013` 周边, `204001 周年庆·家具礼袋`, `47…53` 月饼, `1000 四叶草`,
`1`, `54`, `56`, `102`, `1105`, `5101`, `8001`, `10001/11001`, `10105`, `20001`
(the greetcard `select_list` + `random_list` sets).

### 3.5 Assets

`images/Scene/MakeCake/` — **76 files** in 5 directories:

| folder | count | contents |
|---|---|---|
| (root) | 5 | `btn_cake_consume.png`, `btn_light_candle.png`, `btn_open.png`, `btn_receive.png`, `btn_week_task.png` |
| `Ask_cake/` | 15 | `neighbor_ask_bg.png`, `neighbor_answer_bg.png`, `neighbor_emote_{0,1,2}_{0,1,2}.png` (9), `text_ask_answer.png`, `text_answer_again.png`, `text_answer_right.png`, `text_answer_wrong.png` |
| `Bg_ui/` | 14 | `cake_item_bg.png`, `cake_stage_bg.png`, `make_stage_{1..5}_{on,off}.png` (10), `text_caketask_tips.png`, `text_frog_party.png` |
| `cake_make/` | 30 | `cake_make_0_1_on.png`, `cake_make_{1,2}_{1,2}_{on,off}.png` (8), `cake_make_3_1_{on,off}.png` (2), `cake_make_4_{1..8}_{on,off}.png` (16), `cake_make_5_1_{on,off}.png` (2), `cake_make_6_1_on.png` |
| `Share_cake/` | 12 | `share_cake_1.png`, `share_cake_2.png`, `share_cake_bg.png`, `share_cake_info_bg.png`, `share_cake_item_bg.png`, `share_cake_logo.png`, `text_cake_finish.png`, `text_cake_with_frog.png`, `text_noCake_share_tips.png`, `text_share_got.png`, `text_slide_left.png`, `text_slide_right.png` |

Plus `images/Back/back_makecake.png` (the room background).

Note `cake_make_0_1_on.png` (unused by the table — probably the empty/uncooked base)
and `cake_make_6_1_on.png`, which the view substitutes by hand when part 5 is done
(`@969392`: `5==n&&this.data.cur_state>Tabikaeru.Define.PartyCakeState.light&&(c.source="cake_make_6_1_on_png")`).
The `party cake` named children map 1:1 onto the table:

```
PartyCakeSkin.exml: labelDisplay imageBg lbTask imageDone groupGoods1 groupGoods2
  btnRefreshTween btnShare btnClose lblLimitDate groupPart imagePart1..imagePart5
  groupCake imageCake1_1 imageCake1_2 imageCake2_1 imageCake2_2 imageCake3_1
  imageCake4_1..imageCake4_8 imageCake5_1 lbCream lbSugar groupMake btnMake
  lbCreamMake lbSugarMake groupOpen lbOpen groupTask coverTask btnTask list
  groupGift cover lbGift groupItem btnOpen
```

(so `imageCake3_1` and `imageCake5_1` exist but `imageCake3_2`/`imageCake5_2` do not —
consistent with 1-layer parts 3 and 5).

Compiled skins in `default.thm.js` for this feature (**3**):

| skin | named children |
|---|---|
| `PartyCakeSkin.exml` | as above (31 nodes) |
| `PartyCakeQaSkin.exml` | `cover imageTitle imageGuest lbQue groupAnswer imageSelect groupReward btnOk` |
| `PartyCakeShareSkin.exml` | `labelDisplay imagePic textFrog btnRefreshTween groupTitle imageTitle groupTop btnShare btnClose groupItem imageGoods imageGet scroller list imageLeft imageRight groupShare lbShare` |

There is **no** `MakeCake*` skin — the cake UI is served by the `PartyCake*` skins; the
`MakeCake` name only survives as an image folder.

### 3.6 Recoverable rules vs unrecoverable

**Recovered:**

* layer costs and rewards — exactly `cream`/`sugar`/`item_id`/`item_num` per layer
  (§3.4); total 68 cream / 41 sugar per cake.
* the 点蜡烛→开礼物→完成 ordering, and the two share slots
  (`Utils.setArrayCollection(this.list,[1,2])`, `@959346`). Slot 2 is the
  "cake finished" share: `PartyCakeShareView.updatePages @959423` does
  `1==e&&this.data.cur_state!=Tabikaeru.Define.PartyCakeState.complete?(this.groupItem.visible=!1,this.btnShare.disable()):(this.groupItem.visible=!0,this.btnShare.enable())`,
  and `PartyCakeShareItem.dataChanged @961499` picks the page art
  `1==this.data?"share_cake_1_png":cur_state==complete?"share_cake_2_png":"text_noCake_share_tips_png"`.
  So slot 2's reward is claimable (via `partycake_reward_share(2)`) only after
  `cur_state == complete`, but it also needs `share_get[1] != 1`.
* `share_reward` = `[14, 204001]`, one claim per slot, 0-based `share_get`.
* `light_reward` = `204001 × 2`.
* the task catalogue: name, `total`, `cream`, `sugar` — all in the table; the ads-only
  tasks (3, 4) are skipped when `BaseChannel.getInstance().supportAds()` is false.
* the quiz: 3 options, the correct-answer flag is expressed as `reward.length > 1`
  (a 2-item reward means "correct"), one emote art for asking
  (`neighbor_emote_{guest}_0`) and two for the result (`_1` = correct, `_2` = wrong).
* the "pending materials" dance: `pre_cream`/`pre_sugar` are only committed by
  `partycake_get_mate`, and their presence raises the red dot
  (`checkRedot @163644`: `(this.data.pre_cream>0||this.data.pre_sugar>0)&&(e=1)`).

**Unrecoverable (server-only):**

* the daily/period accumulation rule for `task_list[].count` and when it resets.
  The client only renders `count/total`; nothing in the client or the tables says
  whether progress is cumulative for the whole event or reset per day, nor how many
  days the event was designed to run.
* which tasks pay out and when — there is **no** `partycake_get_task_reward`; the only
  route to materials is the `pre_cream`/`pre_sugar` push + `partycake_get_mate`, so the
  engine decides when a task's `total` is reached and how much 奶油/翻糖 is pending.
  The table's per-task `cream`/`sugar` are the natural choice (and are what the task row
  displays via `groupGoods1/2`: `sugar → item 200007`, `cream → item 200006`).
* the `answer`/`reward` generation: the 3 quiz options are item ids the engine invents,
  the `guest` is a random 0…2, and `wrong` is a retry counter. Nothing in the tables
  lists the correct option — the client only knows `reward.length`.
* material sources outside the task list (聚会 / 旅行 / purchase). The table does not
  put 200006/200007 in any shop.
* how many times a part may be attempted, and any cooldown between layers.
* the `part.time` unlock schedule's *intent* (see below) beyond the three literal
  timestamps.
* the share reward's trigger timing (see the `req_reward_share` note in §3.1.2) and any
  per-day share cap (none is visible client-side: `PartyCakeShareView` will let the
  player share both slots in a row).

### 3.7 Landmines

1. **`part` out of range ⇒ crash.** `updateCake @968562` does
   `var l=t[this.data.part].time` and `t[this.data.part].name` for
   `cur_state ∈ {0,1,2,3}`; `part = 0` (the current stub) is `undefined.time` ⇒
   TypeError. Keep `part ∈ 1..5` in playable states.
2. **`part` > 5 is only safe with `cur_state ∈ {4,5,6}`** — that combination is exactly
   what `checkMakePart()` produces after the candle layer, so the engine must NOT return
   `state: 0` together with `part: 6`.
3. **Never answer `partycake_load` with an empty body.** `{"code":0}` wipes
   `end_time`/`part`/`cur_state` to `undefined` → the button hides and, if the user was
   in the view, the next `updateCake()` throws on `part`.
4. **`partycake_make`'s `layer` must be a valid key of the *current* part.** The model
   dereferences `partycakeData.get("cake")[part].layers[layer].cream` inside the
   callback; a bogus layer throws. Also the layer must be one the player has not made
   (`isMakeLayer` guard is client-side only for the icons; the reply is not validated),
   and the client subtracts the cost again locally — so reply only after the engine has
   actually deducted.
5. **`partycake_answer`'s `index` is 1-based** (the view sets `cur_selete = t` for
   `t = 1..3`) and is sent verbatim as `["index"]`.
6. **`answer` must contain exactly 3 ids that exist in `Item.json`** — the QA renderer
   dereferences `.img` unguarded (§0.1.6). The same applies to `reward[].item_id`
   (`@957864`).
7. **`task_list` must be row objects with `id`/`count`/`is_done` and the `id` must exist
   in `PartyCakeData.task_list`** — the client does
   `h = partycakeData.get("task_list")[a.id]` and then `cfg.name`/`cfg.total` in
   `PartyCakeTaskItem.dataChanged @970468`; an unknown id is a crash in a list renderer
   (i.e. the exact 呱呱吃坏肚子了 class of bug).
8. **`partycake_load_qa` without `guest`** → `this.data.guest` undefined →
   `neighbor_emote_undefined_0_png` (blank art, no crash) and `lbQue` renders
   `以下哪个食物undefined看起来最喜欢？`. Cosmetic but visible; always send `guest` 0…2.
9. **`partycake_load_task` writes `task_list[id-1]`** — it relies on `task_list` already
   existing as an array (guaranteed by any `partycake_load`, since
   `Utils.convertArray` runs on it). A push before the first load would throw, and the
   id is assumed 1-based and dense.
10. **`share_get` is 0-based in the client and 1-based on the wire**
    (`share_get[e-1]` vs `req_reward_share(i+1)`); off-by-one marks the wrong slot as
    claimed and permanently locks a reward.
11. **The two ads-dependent tasks (3, 4)** — if the engine counts them toward `total`
    progress while the client hides their rows, the player sees an unexplained "3/3
    done" that cannot be filled. Either honour `supportAds()` (false in our offline
    build) and exclude them, or serve `is_done: 1` for them.
12. The `openGiftView @966735` path uses
    `this.data.layers[this.data.layers.length-1]` as the layer key for the *gift*
    lookup — i.e. it assumes `layers` is non-empty right after a successful make. If
    `partycake_reward_make` returns a state change while `layers` is empty (e.g. after a
    reload mid-`make_reward`), `layers[-1]` is `undefined` →
    `r=...layers[undefined]` → `undefined.item_id` → crash. Keep `layers` non-empty
    whenever `cur_state ∈ {1}` is served.

---

## 4. Cross-family checklist for the engine

Before the three buttons can appear and every click can complete:

1. `client_load_role.settings.guideStep == "Complete"` (§0.1.3).
2. `springcard_load`, `greetcard_load`, `partycake_load` are in `BOOT_PUSH` (they already
   are — `index.js@25050-25200`) **and** answer with full payloads, never `{}`.
3. `end_time` > `core.Time.getServerTime()` for all three; nothing else opens them.
4. Every needResponse reply carries `code: 0` on success.
5. `springcard_send.box_id > 0`, `springcard_buy.tags_id > 0`,
   `springcard_share_tags.share_code` a non-empty string.
6. `greetcard_get_reward.list` / `greetcard_get_task_item.list` / `springcard_load.items`
   are arrays, never `undefined`.
7. Every `type:100` payload id ∈ `greetCard.tags`, every `type:101` id ∈
   `springCard.tags` (§0.1.6) — this is the crash that must never come back.
8. `partycake_load.part ∈ 1..5` for playable states; `task_list` rows are objects whose
   `id` exists in the table.
9. `partycake_load_qa.answer` = exactly 3 valid item ids.
10. Do not reply to the `needResponse:false` commands (`greetcard_read_new`,
    `greetcard_send_gift`, `greetcard_feedback_gift`) — a reply without a session is
    dispatched as a push and logged as an unknown protocol.

### 4.1 Current stubs and what changes

`index.js @230580`:

```js
greetcard_load: () => ({ end_time: 0, start_time: 0, card_info: {}, task_item: [] }),
springcard_load: () => ({ end_time: 0, start_time: 0, card_info: {}, task_harvest: 0, buy_num: 0,
  can_buy_num: 0, share_num: 0, share_get: 0, box_id: 0, share_code: '', items: [], task_item: [], reward_list: [] }),
partycake_load: () => ({ end_time: 0, start_time: 0, cream: 0, sugar: 0, pre_cream: 0, pre_sugar: 0,
  cur_state: 0, part: 0, layers: [], task_list: [], share_get: [] }),
```

* `start_time` is inert (§0.1.4) — drop it or keep it, it changes nothing.
* `card_info: {}` is **already a latent crash**: it is only harmless because
  `end_time: 0` keeps the button hidden and no view opens. Replace with
  `{bg:0,bless:0,tags:[0,0,0]}`.
* `part: 0` is likewise a latent crash for the same reason.
* `springcard_load` is missing `global_num` (needed by `updateCount`) and `share_code`
  should be `''` (already); `greetcard_load` is missing `send_list`, `get_list`,
  `items`, `task_login`, `task_share`, `can_reward`, `global_num`, `new_index`,
  `stock_num` — all reachable by `GreetCardView.update`.
* `partycake_load` is missing nothing structurally but needs a real `task_list` of six
  row objects.

---

## 5. What could NOT be determined

1. **All original server-side rules** listed per family in §1.6 / §2.6 / §3.6 — reward
   tables beyond the client display, daily caps and reset boundaries (`buy_num`,
   `can_buy_num`, `task_harvest`, `share_num/share_get`, `stock_num`, task progress),
   `global_num` accumulation and its reward tiers, `share_code` generation/expiry,
   the SpringCard small-vs-big box decision, and the PartyCake material economy outside
   the six tasks. Any value chosen for these is **self-designed** and must be labelled
   as such — none of it can be presented as restored.
2. **The PartyCake state→step mapping** in §3.1.1 (which part returns `qa` vs `light`) is
   a reconstruction from the enum + `checkMakePart` call sites. The orphaned
   `light_reward`/`complete` states, the single-layer parts 3 and 5 and the presence of
   `cake_make_6_1_on.png` all fit, but the original assignment is not recoverable from
   the client or the tables.
3. **`PartyCakeData.cake[].time`** (1671379200 / 1671984000 / 1672588800 = 2022-12-19 /
   12-26 / 2023-01-02 CST) is the only date gate in these three features, it lives in
   the **client's encrypted `config.eab`** (`PartyCakeData_json`), and a payload cannot
   change it. Any play date ≥ 2023-01-02 satisfies it, so the feature is open in
   practice, but a build that must be *provably* date-independent needs `config.eab`
   repacked (or `main.min.js` patched) with `time: 1` for parts 2–5. I did not attempt
   the repack — `config.eab`'s index is not plain JSON (magic `…0D 0A 1B 0A`) and no
   existing tool in `work/tools/` was run against it here.
4. **`springcard_get_task_item`** is declared in `protocol.js` and in the client's
   `ProtocolList` but never sent; nothing reveals its intended payload. It can be left
   unimplemented.
5. **`Item.json` icons**: no `goods_*` icon (`goods_201_png` for the SpringCard shop
   bag, `goods_200/202/203/300/301/91/92/19` for the cake/gift items) has an entry in
   `default.res.json`, so reward icons render blank. This is a general resource-extraction
   gap, not specific to these families, and I did not trace where the icon atlas lives.
6. The **`can_buy_num` / `buy_num`** semantics are only inferred from the shop loop
   (`can_buy_num` icons total, of which `can_buy_num - buy_num` are enabled).
7. Whether the greetcard "task" counters (`task_login` / `task_share`) and the
   springcard `task_harvest` had a daily reset is unknown; the client treats them as
   plain booleans/ints refreshed by whatever the server sends.
