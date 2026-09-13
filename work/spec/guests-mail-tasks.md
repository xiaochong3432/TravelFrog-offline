# 访客 / 邮件 / 任务与成就 / 日历 / 故事 / 抽奖 / 图鉴 —— 字段级实现规格

> 目标读者：`work/run/engine/index.js` 的实现者。
> 本文只描述**客户端要什么（回包/推送必须长什么样）**与**服务端该维护什么状态**，不改引擎代码。
>
> ## 证据约定
> - `[D:<fn>]` = `work/tools/dump_handlers.py` 导出的 `prototype.<fn>` 函数体（见本文引用片段）。
> - `[C:<Class>]` = `work/tools/cls.py` / `dump_class.py` 导出的类体（owner 类名）。
> - `[X:<偏移>]` = `main.min.js` 字符偏移处的原始代码（`work/tools/jsx.py`）。
> - `[DB:<文件>]` = 客户端本地配置表（已从 `work/run/web/resource/China/eab/config.eab` 解密导出，见 §0.4）。
> - **标注「推测」的条目没有客户端证据支撑**，是实现自由度最大的地方。
>
> 本文所有引用片段均可在 `work/spec/*.txt` 里找到原始 dump。

---

## 0. 全局前提（先读，否则会踩坑）

### 0.1 协议名转换
沿用现有引擎：只有第一个下划线变点（`guest_load` → `guest.load`）。`toWire()` 已实现，本规格所有命令名写「下划线规范名」。

### 0.2 两类命令：推送 vs 请求
- **推送**（`addProtocolCallback(...)` 注册，客户端从不主动 send）：`guest_load`、`guest_load_drawing`、`mail_load`、`task_load`、`task_load_list`、`calendar_load`、`calendar_load_note`、`calendar_task_update`、`story_load`、`lottery_load`、`encyclopedia_load`。
  证据：各 Model 的 `initModel()`：
  - `TravelModel.initModel` [C:TravelModel]：`addProtocolCallback("client_load_events","guest_load","album_load","mail_load_mails","mail_ejoy_active_code","album_load_new",...,"notify_new_mail","mail_load")`
  - `GuideTaskModel.initModel` [C:GuideTaskModel]：`addProtocolCallback("task_load","task_load_list")`
  - `CalendarModel.initModel` [C:CalendarModel]：`addProtocolCallback("calendar_load","calendar_load_note","calendar_task_update")`
  - `StoryModel.initModel` [C:StoryModel]：`addProtocolCallback("story_load")`
  - `LotteryModel.initModel` [C:LotteryModel]：`addProtocolCallback("lottery_load")`
  - `EncyModel.initModel` [C:EncyModel]：`addProtocolCallback("encyclopedia_load")`
  - `DrawingModel.initModel` [C:DrawingModel]：`addProtocolCallback("guest_load_drawing","guest_accept_invit","guest_putin_bag","guest_takeout_bag")`
- **陷阱**：`mail_load_mails` 既是请求又有推送回调，其 handler 是 `function(e,t)`，`t` 是**请求参数**（`t.start`/`t.count`）[D:mail_load_mails]。若服务端把它当推送发，`t` 为 undefined → `t.start` 抛异常。**禁止推送 `mail_load_mails`**。
- `needResponse` 一览（`work/tools/proto_list.py` 输出，`work/spec/out_proto.txt`）：
  ```
  guest_load        True   guest_load_drawing True  guest_confirm      False
  guest_accept_invit True  guest_serve        False  guest_putin_bag    True
  guest_takeout_bag True   guest_lock_bag     True   guest_finish       False
  guest_set_expire_time False
  mail_load True  mail_load_mails True  mail_open False  mail_read False  mail_ejoy_active_code True
  task_load True  task_load_list True   task_get_reward True  task_get_list_reward True  task_client_pro False
  calendar_load True calendar_load_note True calendar_task_update True
  calendar_get_luck_reward True  calendar_get_st_reward True
  calendar_get_beginer_reward True  calendar_get_code_reward True (params ['day'])
  story_load True  story_read_new_story False  story_send_gift False  story_feedback_gift False
  lottery_load True lottery_open True lottery_select True lottery_confirm_reward True
  encyclopedia_load True  encyclopedia_set_show_sub False (params ['long_id'])
  item_gacha True  item_update True  item_update_ticket True  clover_update True
  ```
  `needResponse=False` 的命令客户端不等待回包（`h(data, ctx)` 返回 `undefined` 即可，dispatch 会自动跳过）。

### 0.3 ★最关键的前提：客户端的「发奖」函数全是空函数
```
UserModel.addClover   = function(e){}          [X:213760 附近]
UserModel.addTicket   = function(e){}          [X:213774]
ItemModel.addHouseItem= function(e,t,i){void 0===i&&(i=!0)}   // 空实现
UserModel.consumeClover/consumeTicket/consumeHouseItem 都只是「够不够」的判断，返回 bool，不扣
```
证据：`addClover=function(e){}`、`addTicket=function(e){}`、`consumeTicket=function(e){return this.ticket>=e?!0:!1}`、
`addHouseItem=function(e,t,i){void 0===i&&(i=!0)}`、`consumeHouseItem=function(e,t){var i=this.itemDataAll.GetValue(e);return i>=t?!0:!1}`
（原始片段见 `work/spec/ctx_ticket2.txt` 与本次搜索输出；用 `python work\tools\jsx.py out.txt "addTicket=function" 100 300 5` 可复现）。

**结论（必须遵守）**：任何奖励——邮件礼包、任务奖励、日历奖励、故事赠礼、访客招待回报、抽奖券——客户端都**不会自己加进数值**。服务端必须
1. 在存档里真的加上；
2. 主动推送权威状态：
   - 三叶草 → `clover_update {clover}`（handler: `setClover(e.clover)`）[D:clover_update]
   - 抽奖券 → `item_update_ticket {ticket}`（handler: `setTicket(e.ticket)`）[D:item_update_ticket]
   - 家里物品 → `item_update {item:{item_id,count}}`（count 是**绝对值**；`0` 表示扣光）[D:item_update]
   - 或整包 → `item_load_items {...}`

### 0.4 配置表都在本地，没有问题
`work/run/web/resource/China/default.res.json` 把 `gameplay_json / taskData_json / calendarData_json / encyclopedia_json / lotteryData_json / drawingPageData_json / drawingCollectData_json / drawingCommonData_json / story_json / Achieve_json / Character_json / MailEvent_json / GoalNumber_json / visitors_json / step_json / decoration_json` 全部映射到 `config_eab`，即 `work/run/web/resource/China/eab/config.eab`（magic `89 45 41 42 0d 0a 1b 0a`，XXTEA 加密）。
解密命令（已有工具）：
```
python work\tools\eab_dec.py get work\run\web\resource\China\eab\config.eab gameplay_json work\spec\data\gameplay_json.json
```
已导出的副本在 `work/spec/data/`（本次任务产出，可直接读）。

---

## 1. 访客（guest / 邻居）

### 1.1 事实依据（先把机制讲清楚）

**(a) 数据类**
```
prototype.guest_load=function(e,t){ this.guestData=new GuestData(e) }        [D:guest_load]  (TravelModel)
var GuestData=function(){ function e(e){
  if(this.id=-1,this.confirmed=!1,this.served=!1,this.expire_time=0,this.pos=0,e)
    for(var t=0,i=Object.keys(e); t<i.length; t++){ var n=i[t];
      null!=this[n] ? this[n]=e[n] : (BaseChannel...jf_commit(...,"GuestData 数据合并错误，{0} 属性不存在"), core.Log.warning(...)) }
} }                                                                            [X:190002]
```
- **可推送字段只有 5 个**：`id`、`confirmed`、`served`、`expire_time`、`pos`。
  合并逻辑是 `null != this[n] ? 赋值 : 警告`，未声明字段（值为 `undefined`）**不会赋值**，只会打一条 warning + 上报。所以多推字段 = 无效 + 日志噪音 + 分析上报。
- `pos` 在本客户端**从未被读取**（除声明外 0 处引用）。但服务端常量 `FRIEND_RNDPOS_MAX: 3`（[X:419998]）与 `Character.json` 的 `rndPos` 数组长度（3）完全一致 →
  **强推断**：`pos` = `rndPos` 的下标（0..2），原版客户端用它随机摆放访客。国服这个 build 不用它，但**建议照发一个 0..2 的随机值**（保持与原版一致，且如果将来换 JP 客户端就有用）。

**(b) 访客是谁 = `id` 决定形象**
```
[DrawingModel] this.data={state:DrawingState.accept,guest:-1,bag:[],pages:[],colls:[],show_coll:0,pen_motion:"write"}
[C:MainOutController].checkFriend:
  switch(GameConfig.language){ case"China": i=["wugui","maotouying3","songshu"]; break;
                               case"Japan": i=["katatsumuri_niwa","mitsubati_niwa","isigame_niwa","kaeru_niwa"] }
  var n=i[t.id]; ...
  case"maotouying3": o="idle" ... ; case"wugui": o="idle" ...; case"songshu": o="newAnimation"
  this.guestAnimName=r, this.friendView_Dragonbones=new core.DragonbonesView(r,...)   [X:867637]
```
国服只有 3 个访客，`id` 即数组下标 0/1/2。

**(c) 访客角色表（权威数据）** `[DB:config/MainData/Character.json]` → 解密副本 `work/spec/data/Character_json.json`
| id | name | 形象(aniName) | cloverPow | flagValue | taste 长度 |
|----|------|----------------|-----------|-----------|-----------|
| 0 | 困困 | AniAnimation/MainOut/katatsumuri_niwa（蜗牛） | 50 | 0 | 55 |
| 1 | 胖胖 | AniAnimation/MainOut/mitsubati_niwa（蜜蜂） | 60 | 3 | 55 |
| 2 | 跳跳 | AniAnimation/MainOut/isigame_niwa（乌龟） | 80 | 6 | 55 |

同文件顶部还有 `rowItemId`（55 个特产 item_id），与 `Specialty.json` 按 id 顺序**完全一致**（本次已数值校验：`Character.rowItemId == [s.itemId for s in sorted(Specialty,key=id)]`，且 `Specialty.id` 连续 0..54）。

**(d) 口味（招待用什么、给什么反馈）**
```
Tabikaeru.Game.getFriendTaste=function(guestId,itemId){
  var n=DataManager.instance().CharaDB,  r=DataManager.instance().SpecialtyDB,
      o=n.src.data.find(e=>e.id===t),   a=-1, s=r.list();
  for(c=0;c<s.length;c++) if(s[c].itemId===i){a=c;break}
  return {friend:o, feeling:o.taste[a]}
}                                                                             [X:441568]
```
→ `feeling = Character[id].taste[特产id]`，特产 id 就是 `Specialty.id`（0..54）。
`feeling` 取值在表里只有 `10 / 20 / 40 / 60 / 80`。
反馈文案（**客户端本地拼，不需要服务端下发**）：
```
[C:MainOutController].friendFeedBack:
  e = feeling>=80 ? "两眼放光 高兴地扑了上来"
    : feeling>=60 ? "吃得津津有味 嘴巴吧唧个不停"
    : feeling>=20 ? "一声不吭 顽强填饱了肚子"
    :               "看了一眼 没有什么胃口"
  标题 = "{物品名}{访客名} 招待提示"     // 访客名用客户端硬编码的 ["困困","胖胖","跳跳"][friend.id]
```
注：`cloverPow` / `flagValue` / `aniName` / `rndPos` 在 `main.min.js` 里 **0 次引用**（已全文件搜索），属于「服务端数据」。

**(e) 停留多久 = 客户端自己算，然后回写给服务端**
```
[C:MainOutController].checkFriend(e):        // e = gameplay_json["邻居"]
  var t=travelModel.getGuestData();
  if(t && t.id>=0){
    if(0==t.expire_time){
      t.expire_time = core.Time.getServerTime() + 60*MathExtend.Range(e.DurationFloor, e.DurationUpper);
      SocketManage.send("guest_set_expire_time", null, t.expire_time);
    }
    ...绘制访客龙骨动画
  }                                                                                    [X:867637]
```
`[DB:config/GameplayData/gameplay.json]`（解密副本 `work/spec/data/gameplay_json.json`）：
```json
{ "串门": {"DurationFloor":30,"DurationUpper":30,"Gameplay":"串门","OverdueContinue":0,"Sort":1},
  "邻居": {"DurationFloor":30,"DurationUpper":30,"Gameplay":"邻居","OverdueContinue":1,"Sort":2} }
```
→ `Range(30,30)` = 30 → 访客停留 **30 分钟（1800 秒）**。

**(f) 访客怎么「出现」——只有一条路：服务端推 `guest_load`**
```
[C:GameplayModel].getGameplayList():
  var i=travelModel.getGuestData();
  if(i && i.id>=0){
    var n="邻居"; if(e=getGameplayInfo(n)){
      if(i.expire_time>0 && i.expire_time>now) return [e];            // ★早退：只返回邻居
      (0!=e.OverdueContinue || 0==i.expire_time || i.expire_time>now) && t.push(e)
    } else Log.warning("玩法配置表中未定义玩法：邻居") }
  var r=visitorModel.getVisitorData(); ... // 串门
  return t.sort((a,b)=>a.Sort-b.Sort)                                [X:114533]
```
```
[C:MainOutController].checkGameplay():
  clearFriend(); clearVisitor(); updateVisitorGift();
  var e=getGameplayList(), t=e[0];
  if(t){ if(e.length>1) for(n=1..) if(e[n].OverdueContinue!=0) switch(e[n].Gameplay){
           case"邻居": var r=getGuestData();
             r && r.expire_time<=now && (r.id=-1, send("guest_finish")) }   // ★唯一的客户端移除
         switch(t.Gameplay){ case"邻居": this.checkFriend(t); break; case"串门": this.updateVisitor(t) } }
                                                                                 [X:864647]
```
```
// 黄条「朋友来访」在事件系统里弹
[C:Result.eventSystem]:
  var C=GameplayModel.getGameplayList(), M=C?C[0]:null;
  if(M){ var E=[TimerEvent.Type.Guest, TimerEvent.Type.Visitor];
         switch(M.Gameplay){ case"邻居": E.splice(E.indexOf(Guest),1); break; case"串门": E.splice(E.indexOf(Visitor),1) }
         ...从 travelEventList 里剔掉 E }
  var S=travelModel.getGuestData();
  if(S && S.id>=0 && !S.confirmed && M && "邻居"==M.Gameplay){
    Music.play("SE_Popup"); var k=_("朋友来访"), P=new Notification;
    P.notify(c,(NotificationType)2 /*Yellow_Friend*/,k,function(){
      travelModel.sendGuestConfirmed();                    // → send("guest_confirm", null, guestData.id)
      ...首次来访引导（仅本地 clientSettings）})
  }                                                                              [X:884305]
```

**(g) 点访客 → 送吃的**
```
[C:MainOutController].friendClick:
  guestData.id>=0==0 && jf_commit(warning,"friendClick():guest_data_empty")
  if(guestData.served) return ModalAlert("已经给小伙伴赠送过礼物了。")
  playerBag = new PlayerBag(true,false, ItemType.Specialty /*=3*/, PlayerBag_ParentType.Neighbor, true)
  选中物品 → ModalConfirm("确认喂食小伙伴吗？") → travelModel.sendGuestServed(itemId); friendFeedBack(itemId)

[C:TravelModel].sendGuestServed(e):        // e = item_id
  guestData && !guestData.served && ItemModel.consumeHouseItem(e,1) /*只是判断*/ &&
  (guestData.served=true, send("guest_serve", null, guestData.id, e))            [X:193129]
```
→ **招待只能用「特产」（Item.type==3）**；客户端自己把 `served` 置 true。

**(h) 抽屉系统（guest_load_drawing）** `[C:DrawingModel]` 全文见 `work/spec/ctx_drawingmodel.txt`
```
initModel: addProtocolCallback("guest_load_drawing","guest_accept_invit","guest_putin_bag","guest_takeout_bag")
default data: {state:accept, guest:-1, bag:[], pages:[], colls:[], show_coll:0, pen_motion:"write"}
guest_load_drawing(e): this.data=e; data.pages=convertArray(e.pages); data.colls=convertArray(e.colls); dispatch(UPDATE)
request_accept_invit(): send("guest_accept_invit",Action2, true )   // 0==code → data.state=accept
request_reject_invit(): send("guest_accept_invit",Action2, false)   // 0==code → data.state=wait
changeItem(i,itemId,cb):  // i 是 0 基下标，发送时 +1
   if(data.bag[i]!=itemId && data.bag[i]!=-1) send("guest_takeout_bag",Action1, i+1)  // 0==code → data.bag[i]=itemId
   if(itemId!=-1)                            send("guest_putin_bag", Action1, i+1, itemId) // 0==code → data.bag[i]=itemId
lockBag/unlockBag(): data.state==accept(或lock) ? send("guest_lock_bag",Action1) : 直接回调
                     // 回包 i && 0==i.code → state=lock(或 accept)
isOpen(): ItemModel.getHouseItemCount(Tabikaeru.ItemID.DRAWING_BOOK /*=7001*/) > 0
```
枚举：
```
DrawingState: wait=0, invite=1, accept=2, lock=3, visit=4                        [X:579635]
Tabikaeru.ItemID: DRAWING_BOOK=7001, WATAR=7002, FERTILIZER=7003,
                  CLOVER=2e5, TICKET=200001, COMPASS=200002                       [X:417064]
```
`data.show_coll` 的使用（屋内摆件）：
```
[C:MainInView].updateDrawingCollect(): var e=DrawingModel.data.show_coll;
  if(e>=0){ var n=DrawingCollect.get(e); ... r.source = n.scene; r.data=e }
[C:MainInView].updateCollects(): if(show_coll==0) setClientSettings("noticeDrawing",-1)
  else if(noticeDrawing!=show_coll) ... 弹 Green_Picture「屋内似乎多了些东西」[X:805314]
[C:MainInView].updateParty(): 3==frogStatus ? i_party.icon=["party_wugui_png","party_maotouying_png","party_songshu_png"][DrawingModel.data.guest]
[C:MainInView].updateFlogStatus(): case"hikki_ie": s=DrawingModel.data.pen_motion||"write"  // 青蛙写笔记的动作
```

### 1.2 实现规格

#### 状态（建议 `state.guest`）
```js
guest: {
  id: -1,            // -1 = 没有访客；0/1/2 = 困困/胖胖/跳跳
  confirmed: false,  // 玩家已点掉「朋友来访」
  served: false,     // 已招待
  expireTime: 0,     // 客户端回写的到期 unix 秒；0 = 还没定
  pos: 0,            // = Character.rndPos 下标（0..FRIEND_RNDPOS_MAX-1）
  arriveAt: 0,
  nextTryAt: 0,      // 下次掷「是否来访」的时间（FRIEND_VISIT_RNDSEC=1800 一步）
  lastLeaveAt: 0,    // 上次离开时间（用于 FRIEND_VISIT_COOL=21600 冷却）
  drawing: {         // 绘画/绘本邀请（guest_load_drawing）
    state: 0, guest: -1, bag: [], pages: [], colls: [], showColl: 0, penMotion: 'write'
  }
}
```

#### 访客出现/离开的规则（节奏参数见 §1.3，那里有 `Tabikaeru.Define` 的原始常量作依据）
- **谁触发？** 客户端没有任何「请求访客」的协议；出现只能靠 `guest_load` 推送。何时推：
  1. 开局（`hall_enter_game` 的 `BOOT_PUSH`）已包含 `guest_load`（现状，`{}` = id:-1 = 无访客）；
  2. `tick()` 里按 §1.3 的规则掷骰（每 1800 s 一次、10% 概率、6 h 冷却）→ 推
     `guest_load {id:rand 0..2, confirmed:false, served:false, expire_time:0 或 now+1800, pos:rand 0..2}`；
  3. 「是否要求 `frog.status===0`（蛙在家）」**没有任何证据**（`Tabikaeru.Define` 里也没有对应常量）→ 属实现自由度，建议不限制。
- **停留**：两种等价做法，**推荐 B**：
  - **A（让客户端定时）**：`expire_time:0` → 客户端 30 分钟后自己算并 `guest_set_expire_time`；服务端记下这个值。注意：此时 `getGameplayList` 不会早退，若同时存在「串门」访客，`e[0]` 会是串门 → 访客不绘制（见 §1.1(f) 的 `t=e[0]`）。当前引擎 `visit_load` 返回 `{}`，`prototype.visit_load` 只在 `e.visitor` 为真时才建 `visitorData`（[D:visit_load]），所以串门不会出现 → **A 也安全**。⚠️ 若将来给 `visit_load` 填了 `visitor`，必须用 B。
  - **B（服务端定死）**：直接推 `expire_time = now + 1800` → `getGameplayList` 立刻 `return [邻居]`，串门被压制，访客必然绘制。**更稳，推荐 B。**
- **离开**：服务端到点后**主动推** `guest_load {id:-1, confirmed:false, served:false, expire_time:0, pos:0}`（清空），并记 `lastLeaveAt` 供冷却用。
  客户端的 `guest_finish` 只在「同时存在 2 个玩法且访客已过期」时才会发（见 (f)），单靠它不可靠 → 收到 `guest_finish` 时服务端也应当作「请清掉访客」处理（幂等）。

#### 命令逐条

| 命令 | 方向 | 参数 | 回包 | 服务端动作 |
|---|---|---|---|---|
| `guest_load` | 推送 | — | 无（`needResponse=true` 但客户端不 send） | payload 见下 |
| `guest_confirm` | 收 | `{id}` | 无 | `guest.id==id` → `confirmed=true`；**之后所有 `guest_load` 都要带 `confirmed:true`**，否则黄条会重复弹 |
| `guest_set_expire_time` | 收 | `{time}` | 无 | `guest.expireTime=time`；`time<=now` 时立刻清空访客 |
| `guest_serve` | 收 | `{id, item_id}` | 无 | 校验 `id` 与当前访客一致、未 served、`item_id` 是特产且家里有 ≥1 → 扣 1 个、`served=true`、按 §1.3 发奖；推 `item_update`/`clover_update`（**不要重推 `guest_load`**，客户端已把 served 置 true；但离线重进时要能恢复 → 存档里保留到访客离开） |
| `guest_finish` | 收 | 无 | 无 | 清空访客（`id=-1`） |
| `guest_load_drawing` | 推送 | — | — | 见 §1.2 payload |
| `guest_accept_invit` | 收/回 | `{is_accept}` | `{code:0}` | `is_accept=true` → state=accept；`false` → state=wait。**必须回 `{code:0}`**（`0==t.code` 才改本地 state） |
| `guest_lock_bag` | 收 | 无 | `{code:0}` | 在 accept↔lock 之间切换。回包必须是**对象且 code==0**（`i && 0==i.code`；返回 `undefined` 什么都不发生） |
| `guest_putin_bag` | 收 | `{pos, id}` | `{code:0}` | `pos` 为 **1 基**（客户端发 `i+1`）。把 `id` 放进访客包 `pos-1`，家里扣 1 个 |
| `guest_takeout_bag` | 收 | `{pos}` | `{code:0}` | `pos` 1 基。取出并还给家里（客户端会 `addHouseItem`，但那是空函数 → **服务端必须推 `item_update`**） |

`guest_load` payload（**只有这 5 个键**）：
```js
{ id: 2, confirmed: false, served: false, expire_time: 0, pos: 1 }
// pos 建议给 0..2 的随机值（= rndPos 下标，见 1.3 的 FRIEND_RNDPOS_MAX）
// 无访客： { id: -1, confirmed: false, served: false, expire_time: 0, pos: 0 }
```

`guest_load_drawing` payload（客户端整包替换 `data`，多推的键会被保留但无用）：
```js
{
  state: 2,                 // DrawingState: wait 0 / invite 1 / accept 2 / lock 3 / visit 4
  guest: 2,                 // 邀请者 = 访客 id（0..2）；-1 = 无
  bag: [3014, -1, -1, -1],  // 访客包里的物品 id（-1 = 空），长度与 UI 一致
  pages: [1, 2, 3],         // 已解锁画页 id（drawingPageData 的 key）
  colls: [1, 5],            // 已收集画作 id（drawingCollectData 的 key）
  show_coll: 0,             // 当前屋内展示的画作 id；（0 或 -1 表示不展示，见 updateDrawingCollect）
  pen_motion: 'write'       // 青蛙写笔记的 spine 动作名
}
```
- `pen_motion` 默认 `"write"`，`[C:MainInView].updateFlogStatus` 用 `data.pen_motion||"write"`。
- `isOpen()` 要求家里有 `7001`（DRAWING_BOOK 友情绘本）→ 想让玩家看到邀请，先给他一个 `7001`。

### 1.3 ★访客的节奏与回报：客户端里藏着一张「原版服务端常量表」

`main.min.js` 的 `Tabikaeru.Define` 字面量里有整套访客（原版 FRIEND = 邻居/访客）规则常量。
用 `python work\tools\friendconst.py` 逐字核对：**这些键名在整个 1.3 MB 的 JS 里各只出现 1 次**（就是定义处），
即客户端从不使用它们 —— 它们是**随客户端一起下发的服务端调参表**，正是我们要的权威规则。

```js
// [X:419870]  Tabikaeru.Define（节选，与访客相关）
FRIEND_VISIT_RNDPER: 10,              // 有访客的概率（百分点）
FRIEND_VISIT_RNDSEC: 1800,            // 访问时长（秒）= 30 分钟；也可读作随机检查周期
FRIEND_VISIT_COOL: 21600,             // 两次来访的冷却（秒）= 6 小时
FRIEND_VISIT_ACTCOUNT_MIN: 6,
FRIEND_VISIT_ACTCOUNT_MAX: 8,         // 一次来访中访客的动作次数 6~8
FRIEND_RNDPOS_MAX: 3,                 // = Character.rndPos.length → GuestData.pos 的取值数
FRIEND_ITEM_DEBUFF: [0.6, 0.75, 0.9], // 招待收益的 3 档折扣系数
FRIEND_GIFTPER_NORMAL: { Clover:80, FourClover:18, Ticket:2, MAX:100 },   // 普通回礼权重
FRIEND_GIFTPER_RARE:   { Clover:20, FourClover:50, Ticket:30, MAX:100 },  // 稀有回礼权重
FRIEND_GIFTFIX:        { Clover:0,  FourClover:1,  Ticket:1 },            // 稀有回礼保底
FRIEND_GIFTBOUNUS_CLOVER: 20,         // 额外三叶草
FRIEND_GIFTBOUNUS_TICKET: 1,          // 额外抽奖券
FRIEND_GIFTBOUNUS_TICKET_MAX: 3,      // 额外抽奖券上限
FourLeafCloverID: 1000,               // 四叶草 = 物品 id 1000
MAIL_MAX: 100, ACHIEVE_MAX: 100, HaveItemMax: 99, TicketMax: 999, DAYTIME_COUNT: 7
```
`FRIEND_GIFTPER_*` 里的 `i.Clover`/`i.FourClover`/`i.Ticket` 的 `i` 就是枚举
`Tabikaeru.Gift = { NONE:-1, Clover:0, FourClover:1, Ticket:2, MAX:3 }` [X:417944]（`MAX:3` = 权重总和 100 的校验位）。
另外 `FourLeafCloverID: 1000` **确实被客户端用到**（`clover_harvest` 回调里：`0==element → addClover(1)`；`1==element → addHouseItem(FourLeafCloverID,1)`；`2==element → addHouseItem(sprite,1)`）[X:171843] —— 因为 `addHouseItem` 是空函数，**四叶草也必须由服务端推 `item_update`**（顺带修一下现有 `clover_harvest`）。

#### 由此推出的访客节奏（**证据 + 推断**）
| 参数 | 值 | 依据 |
|---|---|---|
| 来访概率 | 每次检查 10% | `FRIEND_VISIT_RNDPER:10`（证据） |
| 检查周期 | 1800 s（30 min） | `FRIEND_VISIT_RNDSEC:1800`（证据，同一常量兼作访问时长）；与 `gameplay.json` 的 `DurationFloor/Upper=30` 完全吻合（旁证） |
| 访客停留 | 30 min | `gameplay.json` + `FRIEND_VISIT_RNDSEC`（证据） |
| 来访冷却 | 6 h | `FRIEND_VISIT_COOL:21600`（证据） |
| 是否有「蛙必须在家」条件 | **无证据** | 客户端不判定；原版常量里也没有对应项 → 建议不限制（**推测**） |

→ 建议的 `tick()` 规则（**推测的调度，节奏参数有据**）：
```
若 guest.id < 0 且 now >= guest.nextTryAt 且 now >= lastGuestLeftAt + 21600:
    以 10% 概率 → 推 guest_load(id=随机 0..2, expire_time = now+1800 或 0, pos=随机 0..2)
    nextTryAt = now + 1800
```

#### 招待（`guest_serve`）的回礼模型（**证据 + 推断**）
1. 掷骰决定「普通 / 稀有」：
   - **推断**：`feeling >= 80`（`Character.taste[specialtyId] == 80`，客户端文案「两眼放光」）→ 走 `FRIEND_GIFTPER_RARE`；否则 `FRIEND_GIFTPER_NORMAL`。
   - 另一条**同样合理**的解释：访客 id / 是否稀有由服务端另掷（`FRIEND_GIFTPER_*` 的 18% / 50% 四叶草率暗示「稀有」是一个独立事件）。
2. 按权重抽类别：`Clover` / `FourClover` / `Ticket`。
   - 类别 = `Clover` → 给三叶草（数量无直接常量 → 建议用 `FRIEND_GIFTBOUNUS_CLOVER:20` 或 1~3，**推测**）。
   - 类别 = `FourClover` → 给物品 `1000` ×`FRIEND_GIFTFIX.FourClover`（≥1），走 `item_update {item:{item_id:1000,count}}`。
   - 类别 = `Ticket` → 抽奖券 ×`FRIEND_GIFTFIX.Ticket`（≥1），走 `item_update_ticket {ticket}`。
3. 额外奖励：`clover += 20`（`FRIEND_GIFTBOUNUS_CLOVER`），`ticket += 1`（`FRIEND_GIFTBOUNUS_TICKET`，累计不超过 `FRIEND_GIFTBOUNUS_TICKET_MAX=3`）。**两者是「bonus」，推测触发条件 = feeling 达到最高档（80）**。
4. `FRIEND_ITEM_DEBUFF: [0.6, 0.75, 0.9]` 的用法**无证据**（客户端 0 引用）。最两种可能：
   (a) 三档口味（20/40/60）对应的收益折扣；(b) 连续招待同一种食物的衰减。建议先用 (a)：`feel=10 → ×0.6`、`feel=20/40 → ×0.75`、`feel=60 → ×0.9`、`feel=80 → ×1 + bonus`。
5. 无论怎么算，**发奖后必须推** `clover_update {clover}` / `item_update_ticket {ticket}` / `item_update {...}`（§0.3）。
6. 服务端**不要**下发反馈文案：`feeling` 分档文案、访客名（`["困困","胖胖","跳跳"]`）完全由客户端本地计算 [X:870770]。
7. 招待消耗：客户端只送**特产**（`Item.type==3`），且 `consumeHouseItem` 是空判断 → 服务端自己扣 1 个并推 `item_update`。

---

## 2. 邮件（mail）

### 2.1 事实依据

```
[C:TravelModel]
  initModel: addProtocolCallback(...,"mail_load_mails","mail_ejoy_active_code",...,"notify_new_mail","mail_load")
  getMailInfoList() -> this.mailInfoList
  requestMail() -> send("mail_load")
  mail_load(e,t){ this.revice_mails(Utils.convertArray(e)) }          // ★ e 就是数组本身
  mail_load_mails(e,t){                                               // ★ t = 请求参数
     for(i=0;i<e.mails.length;i++) this.mailInfoList[i+e.start-1]=e.mails[i];
     var r=BaseChannel.getInstance().isClearAds();
     t.start+t.count<=e.total ? send("mail_load_mails",null, t.start+t.count, 5, r)
                              : (this.mailInfoList.length=e.mails.length, this.revice_mails(convertArray(this.mailInfoList))) }
  revice_mails(e){
     ...this.mailInfoList=e;
     for(i=len-1;i>=0;i--){ t=e[i];
        t.message && (t.message=String.chengeNewline(t.message,true));
        t.auto_open ? this.openMailInfo(t.id)
                    : (!this.checkMailItemType(t) && t.expire>0 && t.expire<=now && this.openMailInfo(t.id));
        t.type==Mail.EvtId.Drift   && t.read && this.openMailInfo(t.id);
        t.type==Mail.EvtId.Captcha && t.read && this.openMailInfo(t.id);
        t.type==Mail.EvtId.Explor  && 1!=t.opened && MuseumDayModel.setEmail(true);
        var n=t.resource.ads_id;                                     // ★ resource 必须存在
        if(n&&n.length>0){ var r=AdsModel.getAdsPlace(n); r&&AdsModel.isValidAds(r)||(t.resource.ads_id="",t.resource.share_id=n) } }
     this.mailInfoList.sort(Explor 排最后).reverse();
     dispatch(TravelEventType.updateMial) }
  openMailInfo(id){ for(...) if(t.id==id){ this.mailInfoList.splice(i,1);      // ★ 本地移除
        t.resource && (UserModel.addClover(t.resource.clover_point), UserModel.addTicket(t.resource.ticket));   // ★ 空函数
        t.items && for(o of t.items) ItemModel.addHouseItem(o.item_id,o.count);                               // ★ 空函数
        t.opened=true, send("mail_open",null,id), dispatch(updateMial) } }
  readMailInfo(id){ ... t.read=true, send("mail_read",null,id), dispatch(updateMial) }
  checkMailItemType(e){
     function t(e){ return (Array.isArray(e)?e.length:Object.keys(e).length)>0 }
     function i(e){ return null!=e && (e.clover_point>0||e.ticket>0||e.reward_gacha>0||e.ads_id.length>0||e.share_id.length>0) }
     return e.type==Mail.EvtId.Drift ? true : e.type==Mail.EvtId.Captcha ? true
          : t(e.items) || i(e.resource) || e.pictures.length>0 }               // ★ pictures 必须存在
  notify_new_mail(e){ var t=e.mail; t? (t.message&&=chengeNewline, this.mailInfoList.splice(0,0,t),
        t.auto_open?openMailInfo: ... , dispatch(updateMial), dispatch(receiveNewMail,t))
      : Log.warning("协议 notify.new_mail 返回的数据中没有 mail 属性") }        [C:TravelModel @191437]
```
```
var MailInfo=function(){ function e(){ this.id=0,this.type=0,this.sender=0,this.timestamp=0,
   this.title="",this.message="",this.expire=0,this.auto_open=!1,this.read=!1,this.opened=!1 } }   [X:191063]
Mail.EvtId = { NONE:0, System:1, Gift:3, Leaflet:5, StoryGift:6, Taobao:7, Drift:8, Captcha:9,
               ShareURL:10, NewPicture:11, Explor:12, SpecPicture:13, CardGift:14, Notice:15 }
               // 原始声明见 work/spec/ctx_mailenum2.txt（main.min.js 偏移 ~412900..413267）
```
```
[C:MailItemView].setInfo(mailView, mailInfo, acceptCallback):
  t_title.text = t.title
  switch(t.type){
    System|Notice → mail_system_png ;  Notice 另外 currentState="type3"
    Gift → switch(t.sender){0:mail_wugui_png;1:mail_maotouying_png;2:mail_songshu_png; default:i_mailSender.visible=false}
    StoryGift → mail_friendGiftIcon_png
    Taobao → mail_taobao_png ; Leaflet → (不换图)
    Drift → fillItems(), r=false, currentState="type2"
    Captcha → fillItems(), r=false, o=false
    ShareURL → fillItems(), r=false, o=false, currentState="type2"
    NewPicture|SpecPicture → fillItems(), r=false, o=false, currentState="type1"
    Explor → mail_explore_png, fillItems(), r=false, o=false, currentState="type2" }
  checkMailItemType(t) ? this.fillItems()
    : ( o && (r && !t.read && travelModel.readMailInfo(t.id), fillContext(),
              (t.type==Gift||t.type==Notice) && (btn_accept.visible=true)) )
  fillItems(): 读取 resource.clover_point/ticket/reward_gacha/ads_id/share_id、pictures.length、items[]
  hasAds(): mailInfo.resource.ads_id.length>0                                            [X:786113]
```
```
[C:MailItemView].acceptTouchEvents:
  type==StoryGift → ModalConfirm("是否感谢他的赠礼？", ()=>send("story_feedback_gift",null,mailInfo.id))
  type==CardGift  → ModalConfirm("是否感谢他的赠礼？", ()=>send("greetcard_feedback_gift",null,mailInfo.id))   [X:791307]
```
```
prototype.mail_ejoy_active_code=function(e){ }        // 什么都不做，回包被忽略        [D:mail_ejoy_active_code]
mail_ejoy_active_code 在 main.min.js 中只有 1 处（就是这个注册）→ 客户端从不发，由 ejoy SDK 桥发送。
```
兑换码走的是另一条命令（ProtocolList: `item_use_gift_code:[["gift_code"],!0]`）：
```
[C:CdkeyView].totalTouchEvent: 超过 14 字符 → "不能超过14个字符哦"
  若 CalendarModel.checkBeginnerCode(i) 命中 → 本地处理（走 calendar_get_code_reward）
  否则 send("item_use_gift_code", Action2, i)
     e.code==200 → "礼包码兑换成功"；否则 MessageModel.getErrorInfo(e.code).desc 或 "礼包码无效"   [X:544289]
```
`MailEvent_json`（教程/系统赠礼模板）`[DB:MailEvent_json.json]`：
```json
[{"CloverPoint":500,"id":0,"itemId":-1,"itemStock":0,"mailEvt":3,"message":"","senderCharaId":-1,"ticket":0,"title":"恭喜您完成教程！"},
 {"CloverPoint":0,"id":1,"itemId":1000,"itemStock":1,"mailEvt":3,"message":"","senderCharaId":-1,"ticket":0,"title":"请愉快继续游戏！"}]
```

### 2.2 实现规格

#### 存档（建议 `state.mails`）
```js
mails: [{ id, type, sender, timestamp, title, message, expire, auto_open,
          read, opened, resource:{clover_point,ticket,reward_gacha,ads_id,share_id},
          items:[{item_id,count}], pictures:[] }]
mailSeq: 1000   // id 自增
```
**邮件从哪来**（客户端没有任何创建逻辑 → 全部服务端生成）：
1. **系统赠礼**：教程结束/上线礼 —— 用 `MailEvent_json` 的模板（type=3 Gift，sender=-1 会隐藏头像）。
2. **邻居赠礼**：`type=3 Gift` + `sender=0/1/2`（对应困困/胖胖/跳跳头像）——建议在 `guest_serve` 之后回一封谢礼邮件（**推测**：原版邻居会回信）。
3. **旅行带回的信**：`type=11 NewPicture`（新明信片）/ `type=12 Explor`（博物馆）。
4. **故事赠礼**：`type=6 StoryGift` —— 内容放 `items`，玩家点「领取」后弹确认 → `story_feedback_gift`。
5. 节日/公告：`type=15 Notice`（按钮文案走 `fillContext`）、`type=1 System`。

#### 命令逐条

| 命令 | 方向 | 参数 | 回包/载荷 | 服务端动作 |
|---|---|---|---|---|
| `mail_load` | 推送 | — | **对象数组**（不是 `{mails:...}`） | 全量邮件列表。`needResponse=true` 但客户端不 send |
| `mail_load_mails` | 收（请求）| `{start, count, is_clear}` | `{mails:[...], total, start, count}` | 分页。**不要推送它**。`is_clear` = 客户端要求清广告位（`BaseChannel.isClearAds()`） |
| `mail_open` | 收 | `{id}` | 无（`needResponse=false`） | 标记已领取（`opened=true`）并从列表移除；把 `resource`/`items` 奖励真正加进存档并推 `clover_update`/`item_update_ticket`/`item_update`（**客户端不会自己加**） |
| `mail_read` | 收 | `{id}` | 无 | `read=true`（仅状态） |
| `mail_ejoy_active_code` | 收 | `{ticket}`（字符串） | `{}`（客户端忽略） | 返回 `{code:0}` 即可；不发奖（ejoy SDK 自行处理） |
| `notify_new_mail` | 推送 | — | `{mail:{...}}` | 新邮件；客户端插到列表头并弹「收到新邮件」提示。⚠️ **`protocol.js` 里缺 `notify_new_mail`，要先补协议表**，否则 `dispatch` 会走 UNKNOWN 分支、`needResponse` 判定也拿不到 |
| `item_use_gift_code` | 收 | `{gift_code}` | `{code:200}` 成功 | 兑换码。`code!=200` 时客户端用 `MessageModel.getErrorInfo(code).desc` 显示 → 建议只回 200 或 `{}`（走「礼包码无效」兜底） |

`mail_load` 单封邮件**必须**写成：
```js
{
  id: 1001,                 // 唯一，client 用它 mail_open/mail_read/收件箱 key
  type: 3,                  // Mail.EvtId
  sender: 0,                // Gift 时 0/1/2=困困/胖胖/跳跳；其它类型可 -1
  timestamp: 1789000000,
  title: '邻居的回礼',
  message: '谢谢你招待我！',   // 客户端会做换行转换，可含 \n
  expire: 0,                // 0 = 不过期；>0 且 <= now 且「无奖励内容」时客户端自动 open
  auto_open: false,         // true = 客户端立刻 open（服务端仍应收到 mail_open）
  read: false, opened: false,
  resource: { clover_point: 0, ticket: 0, reward_gacha: 0, ads_id: '', share_id: '' },  // ★ 必须有
  items: [],                // ★ 必须是数组
  pictures: []              // ★ 必须是数组（checkMailItemType 会读 .length）
}
```
> ⚠️ `resource`、`items`、`pictures` 三个键**缺任何一个都会抛异常**：
> `revice_mails` 无条件读 `t.resource.ads_id`；`checkMailItemType` 读 `e.pictures.length`。
> `resource.ads_id` / `resource.share_id` 必须是字符串或数组（读 `.length`）。

---

## 3. 任务（task）与成就（achieve）

### 3.1 事实依据

```
[C:GuideTaskModel]
  initModel: addProtocolCallback("task_load","task_load_list")
  task_load(e){ this.data=convertArray(e.tasks);
     for(r of convertArray(e.list)) this.dataList[r.id]=r.pro;
     this.updateRedot(); dispatch(GuideTaskEventType.UPDATE) }
  task_load_list(e){ for(r of convertArray(e.reward)) this.dataReward[r.id]=r.pro; this.updateRedot() }
  request_reward(id){ send("task_get_reward", Action1, id) → if(0==i.code){ 找 data 里 id 相同的 o:
       o.is_reward=true; var a=TaskDB.get("task_list")[id]; a && ItemModel.addHouseItem(a.reward_id,a.num);   // ★ 空函数
       updateRedot(); dispatch(UPDATE,true,o.id) } }
  req_list_reward(type, idx, cb){ var r=100*type + (idx+1); send("task_get_list_reward",Action1,r)
       → 0==code && (this.dataReward[type]=idx+1, cb(), updateRedot()) }
  req_client_pro(param){ send("task_client_pro", null, param) }
  getCompleteListNum(type): 遍历 dataList，凡 list_map[id].type==type 且 dataList[id]>=list_map[id].count → 计数
  getNextListReward(type): dataReward[type] || 0
  updateRedot():
     for(id in TaskDB.task_list){ r=task_list[id]; redotMap[r.type] ??= "GUIDE_TASK_"+r.type }   // 红点通道
     redotMap[100]="GUIDE_TASK_LIST"
     for(o of data){ l=task_list[o.id]; l && 0==o.is_reward && o.pro>=l.count && (t[l.type] = t[l.type]? t[l.type]+1 : 1) }
     for(type in TaskDB.list_type){ u=getCompleteListNum(Number(type));
        for(f of list_type[type].target) u>=f && p++;
        if(p > (dataReward[type]||0)) { t[100]=1; break } }
     for(r in redotMap) RedotManager.setRedotValue(redotMap[r], t[r]||0)                  [C:GuideTaskModel @126703]
```
`req_client_pro` 的**全部调用点**（`main.min.js` 里 3 处，除定义外）：
```
[C:GuideTaskView].childrenCreated: 若活动 travelmap 未开 → GuideTaskModel.req_client_pro("Map")
[C:TravelMapController].open:     GuideTaskModel.req_client_pro("Map")
[C:TravelNoteController].onShow:  GuideTaskModel.req_client_pro("NoteFriend")
```
→ 客户端只会报 3 类事件：`"Map"`（打开旅行地图/任务面板）和 `"NoteFriend"`（打开带旅友的笔记）。

`[DB:taskData_json.json]`（`work/spec/data/taskData_json.json`，45 KB）顶层 4 张表：
- `task_list`：**30 条任务**。字段 `{id, type, title, count, num, reward_id, pic}`。
  - `count` = 目标进度；`num` = 奖励数量；`reward_id` = 奖励物品 id（`200000`=三叶草、`1000`、`14`、`17`、`18`、`8000`、`9000`、`1012` …）。
  - 例：`{"1":{"count":1,"id":1,"num":10,"reward_id":200000,"title":"等蛙旅行回来","type":1}}`
  - id 分段：`1..9`(type1 旅行)、`101..105`(type2 旅行笔记)、`201..205`(type3 手工品)、`301..304`(type4 家具)、`401..403`(type5 友情绘本)、`901..904`(type9 杂七杂八)。
- `task_type`：6 组 `{type,name,desc,icon[],limit[],unlock[]}`；type=1 旅行 / 2 旅行笔记 / 3 手工品 / 4 家具 / 5 友情绘本 / 9 杂七杂八。
- `list_map`：**67 条清单条目** `{id, type, title, desc(富文本), count}`。id 形如 `101,102,103,201..205,301..306,401..406,...`，`type` 与 `task_type` 对应。客户端 `dataList[id]=pro`，服务端按 `pro>=count` 判定完成。
- `list_type`：**6 档「计划」奖励**：
  ```json
  {"1":{"name":"是日清单","target":[3],"reward":[1]},
   "2":{"name":"当周计划","target":[2,5],"reward":[202103,2]},
   "3":{"name":"半月计划","target":[3,6],"reward":[3,4]},
   "4":{"name":"月度计划","target":[2,4,6,8,12],"reward":[5,15,16,33,1104]},
   "5":{"name":"当季计划","target":[3,7,11],"reward":[8000,8000,1103]},
   "6":{"name":"年度计划","target":[4,9,14,21,30],"reward":[10103,10104,10106,10102,10105]}}
  ```
  `target[i]` = 需要完成的 `list_map` 条数；`reward[i]` = 第 i 档的奖励 item_id。`task_get_list_reward` 的 `id = 100*type + (档位序号，从1开始)`。

`[DB:GoalNumber_json.json]` —— **38 个 id**（33 个城市 + 5 家博物馆：`1..33` + `100..104`），字段 `{id,name,tag}`。
> ⚠️ 这**不是**任务表。它只在相册 WebView 里把明信片的 `place` 翻译成城市名：
> `[C:TravelMapController].onWebViewEvent('getPictureList')`: `m=(Number(PictureDB.get(pic_id).place)||0)>>0; w=GoalNumberDB.get(m); _.city=w.tag; _.city_name=w.name` [X:1126768]
> 所以「Goal 表 38 个 id」= 旅行目的地清单，与 `GuideTaskModel` 无关。

成就（称号）：
```
[C:RoleModel] client_load_role(e): var i=e.frog;
   this.name=i.name, this.useAchieveID=i.cur_achieve,
   this.achieveList=Array.isArray(i.achieves)?i.achieves:[],
   for(a of convertArray(i.achieves_time)) this.achieveTime[a.id]=a.time;
   this.frogStatus=i.status, this.frogMotion=i.motion, this.iconID=i.icon,
   this.pictureInfo=i.pic_show, this.todayStep=i.today_step, ...
   // RoleModel 的 client_load_role 处理，见 work/spec/ctx_batch4.txt
  getAchieveInfo(id) -> DataManager.instance().AchieveDB.get(id)
  isAchieveExpire(id) -> achieveTime[id] ? now>=achieveTime[id] : false
[C:MainInView].checkNewAchieve():
   if(isHome && guideStep==Complete){ i=RoleModel.getAchieveList();
      if(i.length>0){ r=UserModel.getClientSettings().achieveList.concat();
         if(i.length>r.length) for(o of i) if(-1==r.indexOf(o)){ r.push(o);
            UserModel.setClientSettings("achieveList",r,false); tipsNewAchieve(o,a>=s-1); break } } }
  tipsNewAchieve(id): r=RoleModel.getAchieveInfo(id);
     ModalAlert("恭喜获得称号：{0}\n{1}", r.name, r.description)                 [X:805314]
```
`[DB:Achieve_json.json]`：`[{id,name,info,description,is_special}]`，
例：`{"id":1,"name":"说走就走的旅行家","info":"旅行达到10次","description":"前几次的旅行总是那么新鲜！"}`、`{"id":0,"name":"一只蛙的旅行","info":"（默认）"}`。
→ **称号的判定规则写在 `info` 文案里，由服务端实现**（客户端不做任何判定）。

### 3.2 实现规格

#### 存档（建议）
```js
taskList: { pro: { '101': 1, '202': 37, ... },   // list_map id -> 进度
            reward: {} },                        // list_type 的 type -> 已领取档位数
tasks:    [{ id: 1, pro: 0, is_reward: 0 }],     // task_list 的 30 条（pro 由服务端累计）
achieves: [],          // 已获得称号 id 列表（frog.achieves）
achievesTime: [],      // [{id, time}]  time = 过期 unix；0 = 永久
curAchieve: 0,         // frog.cur_achieve，当前佩戴
```

#### `task_load` payload
```js
{
  tasks: [ { id: 1, pro: 0, is_reward: 0 }, ... ],   // 只需要 id / is_reward（pro 客户端不读，但建议一起给）
  list:  [ { id: 101, pro: 0 }, { id: 201, pro: 1 }, ... ]   // list_map 的进度
}
```
- `data = e.tasks` 是**数组**（`Utils.convertArray`）；`dataList[list[i].id] = list[i].pro`。
- 红点要消掉：把已领取的置 `is_reward:1`，并且 30 条里所有 `pro >= count && !is_reward` 的清零 → `GUIDE_TASK_*` 红点灭。`GUIDE_TASK_LIST` 红点在 `dataReward[type] >= 已达到的档位数` 时灭。

#### `task_load_list` payload
```js
{ reward: [ { id: 1, pro: 0 }, { id: 2, pro: 1 }, ... ] }   // dataReward[type]=pro（pro = 已领档数）
```

#### 命令逐条

| 命令 | 参数 | 回包 | 服务端动作 |
|---|---|---|---|
| `task_get_reward {id}` | `id` = task_list id | `{code:0}` | 校验 `pro>=count && !is_reward` → `is_reward=1`，按 `task_list[id]` 发 `reward_id × num`；推 `clover_update`/`item_update_ticket`/`item_update`；重推 `task_load`（让红点灭） |
| `task_get_list_reward {id}` | `id=100*type+(档位1..)` | `{code:0}` | `type=floor(id/100)`、`tier=id%100`；校验 `tier==已领档数+1` 且 `getCompleteListNum(type)>=list_type[type].target[tier-1]` → 发 `list_type[type].reward[tier-1]`；`dataReward[type]=tier`；推状态 + 重推 `task_load_list` |
| `task_client_pro {param}` | `"Map"` \| `"NoteFriend"` | 无（needResponse=false） | 把对应 `list_map` 条目的进度 +1（**映射关系客户端没给 → 自行定义，见下**） |

`task_client_pro` 的语义：客户端只报告「玩家打开了旅行地图」和「玩家打开了旅友笔记」。合理映射（**推测**）：
- `"Map"` → `list_map` 中与地图/目的地相关的条目，例如 `102`(有目标一定能到达)、`103`(去看更大的世界) —— 由标题文案决定，建议只对「未完成」的 +1 且每个 param 每天最多 +1 次（防刷）。
- `"NoteFriend"` → 旅友相关条目，例如 `204`/`205` 之外与笔记有关的项；同样建议去重。
> 由于 `param` 只有两个值而 `list_map` 有 67 条，**必然存在服务端侧的映射表**，原版数据不可考。建议做法：把两条 param 映射到 `list_map` 里 `count==1` 的对应条目，且每 param 每天只推进一次。

#### 成就（称号）
- 在 `rolePayload().frog` 里给全：
  ```js
  frog: { name, cur_achieve: 0, achieves: [], achieves_time: [], status, motion, icon, pic_show, today_step, decoration, taobao_data }
  ```
- 新增称号时**必须更新 `achieves` 数组**（客户端只在「服务端数组长度 > 本地已弹过的长度」时弹一次「恭喜获得称号」），可选同时给 `achieves_time:[{id,time}]`（限时称号，超时后客户端显示未佩戴状态）。
- 建议初期只给 `id:0`（默认称号）到 `achieves`，并把 `cur_achieve:0`；后续按 `Achieve.json` 的 `info` 文案逐个实现（旅行次数、特产种类数、三叶草数……）。
- `client_set_achieve`（换称号）在客户端是 fire-and-forget（`prototype.client_set_achieve` 不存在，dump 报 missing）→ 引擎已用 `client_set_achieve: () => undefined` 兜住，建议改为记录 `curAchieve`。

---

## 4. 日历（calendar）

### 4.1 事实依据

```
[C:CalendarModel]
  data 默认 = { new_flag:[], note_list:[], lucky_days:{}, st_days:{}, task_list:[] }
  initModel: addProtocolCallback("calendar_load","calendar_load_note","calendar_task_update")
  calendar_load(e){
     this.data.new_flag=convertArray(e.new_flag);
     this.data.task_list=convertArray(e.task_list);
     for(d of convertArray(e.lucky_days)) this.data.lucky_days[d.day]=d.item_id;   // ★ 数组转成 map
     for(d of convertArray(e.st_days))    this.data.st_days[d.day]=d.item_id;
     this.checkRedot() }
  calendar_load_note(e){ this.data.note_list=convertArray(e.list) }
  calendar_task_update(e){ e && e.task && (this.data.task_list[e.task.id-1]=e.task, this.checkRedot()) }
  req_beginer_reward(cb){ send("calendar_get_beginer_reward",Action2) → if(i.day>0){ new_flag[i.day-1]=1;
       显示 calendarData.beginner[i.day] 的 {item_id,num} } }         // ★ 不带参数
  req_code_reward(id,cb){ send("calendar_get_code_reward",Action2, id) → if(e.day>0){ new_flag[e.day-1]=1; 同上 } }
  req_st_reward(day,cb){ data.st_days[day] && send("calendar_get_st_reward",Action2) → if(0==n.code){
       显示 {item_id:data.st_days[day], count:1}; data.st_days[day]=null;
       data.task_list[0].complete=false; checkRedot() } }              // ★ 不带参数！
  req_luck_reward(day,cb){ data.lucky_days[day] && send("calendar_get_luck_reward",Action2) → if(0==n.code){
       显示 {item_id:data.lucky_days[day], count:1}; data.lucky_days[day]=null; checkRedot() } }  // ★ 不带参数！
  checkRedot(){ e=0; canGetBeginnerReward()&&(e=1); canGetStReward()&&(e=1); canGetLuckyReward()&&(e=1);
                RedotManager.setRedotValue(REDOT_CALENDAR,e) }
  canShowMainOutBtn(){ createDay<=7 ? true : (lucky_days[today] || 存在 st_days 的 key <= today) }
  canGetBeginnerReward(){ var e=RoleModel.getCreateDay(); return e>this.data.new_flag.length || this.data.new_flag[e-1]>0 ? false : true }
  canGetStReward(){ for(t of task_list) if(!t.complete) return false; return true }
  canGetLuckyReward(){ return null!=lucky_days[new Date(now*1000).getDate()] }
  getMonthFirstWeek()/getMonthMaxDay()   // 客户端自己算日历排版
  checkBeginnerCode(code){ for(i in calendarData.beginner) if(beginner[i].code==code)
      return new_flag[beginner[i].id-1]>0 ? (提示"该礼包已经领取过了") : createDay<=7 ? (提示"新呱同乐礼还在准备中") : (req_code_reward(beginner[i].id), true);
      return false }                                                                    [C:CalendarModel @84061]
```
```
[C:CalendarView].childrenCreated:
  s=今天(getDate()), c=getMonthFirstWeek()-1, l=getMonthMaxDay(); r=RoleModel.getCreateDay();
  for(每个格子 e){ o = imageList.length;          // o = 当月「第几天」(1..l)
     o>s && r++;                                   // 今天之后的格子 r 递增
     o>=s && beginner[r] ? (a=beginner[r].item_id, s==o && canGetBeginnerReward() && (h=true))
     : data.st_days[o]   ? (a=data.st_days[o], canGetStReward() && (h=true))
     : data.lucky_days[o]? (a=data.lucky_days[o], s==o && canGetLuckyReward() && (h=true), o>s && (a=-1))
     ; a==-1 → 图标用 calendar_icon_lucky_png（未来日期不剧透）；否则用 ItemDB.get(a).img
     ; 格子点击（仅当 天数<=今天）： s==o && canGetBeginnerReward() ? req_beginer_reward()
                                   : st_days[o] && canGetStReward() ? req_st_reward(o)
                                   : lucky_days[o] && ... → req_luck_reward(o) }
[C:CalendarDayView]:
  o = data.note_list[day-1];                      // 当天笔记 id
  if(n==day && beginner[createDay]) { o=beginner[createDay].note_id; codeText=beginner[createDay].code }
  c = calendarData.note[o]; ... c.pic / c.author / c.desc_list[{desc,align}]
  var g=data.st_days[day];
  if(!imageTips.visible && g){   // 有 st_days 且不是新呱同乐日 → 显示「日历任务」
     文案 = ["观看广告或完成分享（{0}/1）","累计获得三叶草（{0}/30）","商店抽奖兑换奖品（{0}/1）"]
     for(u=0;u<3;u++){ v=data.task_list[u]; d.text=format(文案[u],v.pro); d.textColor=v.complete?12046423:5528908 }
     l = ItemDB.get(g).img   // 用奖励物品图替换当天的画                     [X:527442]
```
`[DB:calendarData_json.json]`（378 KB）顶层 `{beginner, month, note}`：
- `beginner`：7 天新手礼 —— `{"1":{"code":"新呱同乐之报个到","id":1,"item_id":1201,"note_id":10001,"num":1}, ... "7":{... "item_id":1103,"note_id":10007,"num":1}}`
- `note`：536 条日历插画 `{pic, author, desc_list:[{desc,align}]}`。
- `month`：12 个月的月主题图 `{pic}`（`imagePic.source = month[月份].pic+"_png"`）。

### 4.2 实现规格

#### 存档（建议）
```js
calendar: {
  newFlag: [],            // 长度 ≥ 7；newFlag[createDay-1]==1 表示第 createDay 天的新呱同乐礼已领
  luckyDays: {},          // { "日": item_id }  幸运日
  stDays: {},             // { "日": item_id }  任务奖励日
  taskList: [ {id:1,pro:0,complete:false}, {id:2,...}, {id:3,...} ],   // 固定 3 条
  notes: []               // calendar_load_note 的 list（按 day-1 索引的 note id）
}
```
`createDay` = `floor((now - createTime)/86400) + 1`（客户端 `RoleModel.getCreateDay()`，与 `role.misc.create_time` 对应）。

#### payload

`calendar_load`（**必须是 4 个数组**）：
```js
{
  new_flag:   [0,0,0,0,0,0,0],                       // 索引 = createDay-1；1 = 已领
  task_list:  [ {id:1,pro:0,complete:false},
                {id:2,pro:0,complete:false},
                {id:3,pro:0,complete:false} ],       // ★ 必须正好 3 条，客户端按 0..2 直接取
  lucky_days: [ {day:5,item_id:1201}, {day:18,item_id:1000} ],   // [{day,item_id}]，day = 当月第几天
  st_days:    [ {day:1,item_id:8000},  {day:10,item_id:9000} ]   // 同上
}
```
`calendar_load_note`：`{ list: [10001, 10002, ...] }`（索引 = day-1，值为 `calendarData.note` 的 key；缺日用 0/''）。
`calendar_task_update`（推送单条）：`{ task: {id:2, pro:30, complete:true} }`（客户端写 `task_list[id-1]`，所以 `id` 必须 1..3）。

#### 命令逐条

| 命令 | 参数 | 回包 | 服务端动作 |
|---|---|---|---|
| `calendar_get_beginer_reward` | **无** | `{day: N}` | `N = createDay`（1..7）。若 `N<=7` 且 `newFlag[N-1]==0` → 发 `calendarData.beginner[N]` 的 `item_id × num`、置 `newFlag[N-1]=1`；已领则回 `{day:0}`（客户端只在 `day>0` 时处理） |
| `calendar_get_code_reward` | `{day: N}`（N = beginner id 1..7） | `{day: N}` | 与上面同一套校验/发奖，只是入口是兑换码。注意 `CalendarModel.checkBeginnerCode` 在 `createDay<=7` 时会本地拦截并提示「还在准备中」 |
| `calendar_get_st_reward` | **无** | `{code:0}` | 用**服务端当天日期**取 `stDays[today]`；若存在且 3 条 `task_list` 全 `complete` → 发 1 个、删掉 `stDays[today]`、把 `task_list[0].complete=false`（客户端也这么做）、推 `calendar_load` + `calendar_task_update` |
| `calendar_get_luck_reward` | **无** | `{code:0}` | 用服务端当天日期取 `luckyDays[today]` → 发 1 个、删掉该键、推 `calendar_load` |
| `calendar_task_update` | 推送 | — | 进度变化时推单条 |

> ★ **`calendar_get_st_reward` / `calendar_get_luck_reward` 客户端一个参数都不传**（源码核对见 `work/spec/out_sendargs.txt`：
> `"calendar_get_st_reward",new core.Action2(function(n){...})` 后面没有第三个参数）。
> 所以「哪一天」只能由服务端按自己的时钟判定。若服务端日期与客户端 `core.Time.getServerTime()` 不一致（我们就是服务端），不会出问题；但要注意**服务端必须按本地时区的那一天**来算 `getDate()`。
> 建议：为了兼容，服务端**也接受**可选的 `{day}`（若将来协议表补齐）。

#### 幸运日 / 任务日怎么定（**推测**）
客户端只消费数据，不定规则。建议：
- `lucky_days`：每月随机 3~5 天，`item_id` 取 `ItemDB` 里的小礼品（如 `200000` 三叶草按 item 表映射 / `1201` / `1000`）。
- `st_days`：每月随机 2~4 天，奖励用 `8000/9000` 一类的工具/家具类 id。
- 数据是「按 day-of-month」的，所以**每月 1 号（或上次生成月份 != 当前月）重新生成**，并全量推 `calendar_load`。
- 3 条日历任务的推进（**推测**）：
  - `task_list[0]`（看广告/分享 0→1）：用 `adsmgr` / share 相关命令触发，离线版可直接在打开日历时置 complete。
  - `task_list[1]`（累计三叶草 0→30）：`clover_harvest` 累计，可持久化「当日已获三叶草」。
  - `task_list[2]`（商店抽奖兑换奖品 0→1）：`item_gacha {is_reward:true}` 结算时置 complete。

---

## 5. 故事（story）

### 5.1 事实依据

```
var StoryData=function(){ function e(){ this.id=0, this.partner=0, this.name="", this.gift=-1, this.feedback=-1 } }   [X:188505]
[C:StoryModel]
  initModel: addProtocolCallback("story_load")
  story_load(e,t){ this.storyList=Array.isArray(e.stories)?e.stories:[], this.newStoryID=e.new_story_id||0 }
  readNewStory(){ 0!=this.newStoryID && (this.newStoryID=0, send("story_read_new_story")) }     // 无参数
  getStoryData(id): storyList 里 id 匹配的那条
  getStoryInfo(id): DataManager.instance().StoryDB.getStory(id)      // ← story.json 里的 {storyid,name,desc,icon,type}
  sendGift(id,itemId): 找 storyList 里 id 匹配的 i; return (-1==i.gift && ItemModel.consumeHouseItem(itemId,1))
        ? (i.gift=itemId, send("story_send_gift",null,id,itemId), true) : false            [C:StoryModel @188666]
[C:MainInView].checkStory():
  var e=storyModel.getStoryData(storyModel.getNewStoryID()), t=GreetCardModel.getNewCard();
  this.c_newStory.visible = (null!=e) || (null!=t);        // ★ 图标只在 stories 里存在 new_story_id 时才出现
  ... guideStory 引导 ...
[C:MainInView].c_newStory 点击 → new StoryAlertView().setInfo(getStoryData(getNewStoryID()), ...);
   storyModel.readNewStory(); GreetCardModel.req_read_new(); HandCraftModel.updateRedot(); checkStory()
[C:RelationshipView].renderItem():                              // 羁绊/关系图
  i = [].concat(storyModel.getStoryList());
  for(r=i.length-1;r>=0;r--) e=i[r], n[e.partner] ? (n[e.partner]++, i.splice(r,1)) : n[e.partner]=1;
  // ★ 每个 partner 只保留最后一条（同一旅友只显示最新故事）
[C:HandCraftModel].updateRedot(): var i=StoryModel.getStoryData(StoryModel.getNewStoryID());
  if(null==i){ ...手工红点... }                                  // 有新故事时压制手工红点
[C:MailItemView].acceptTouchEvents: type==StoryGift → send("story_feedback_gift",null,mailInfo.id)   // id = 邮件 id
```
`[DB:story_json.json]`：`{"const":{"friend_choice_percent":25}, "story":[{storyid,name,desc,icon,type}, ...]}`，
例：`{"desc":"在墙角发现的蜡笔\n和小伙伴画了好多好多的画","icon":"storyItem_1","name":"凹凸不平的蜡笔","storyid":1,"type":1}`。
`StoryDB.getStory(id)` 按 `storyid` 查 —— 所以 `stories[].id` **必须是 story.json 里存在的 storyid**。

### 5.2 实现规格

#### `story_load` payload
```js
{
  stories: [
    { id: 1,   // = story.json 的 storyid（决定名称/描述/图标）
      partner: 0,   // 旅友 = Character id（0/1/2）；关系图按它去重
      name: '凹凸不平的蜡笔',   // 可选，客户端字段存在但展示主要用 story.json
      gift: -1,     // 玩家已赠送的物品 id；-1 = 还没送
      feedback: -1  // 旅友回礼的物品 id；-1 = 还没回（★ 客户端只存不读，展示逻辑未证实 → 推测）
    }
  ],
  new_story_id: 1   // >0 → 主界面出现「新故事」图标；★ 必须能在 stories 里找到同 id 的条目，否则图标不显示
}
```
- 无新故事时 `new_story_id: 0`（`0!=this.newStoryID` 为 false → 不会发 `story_read_new_story`）。
- 服务端收到 `story_read_new_story` 后把 `newStoryID` 清 0，但**不需要**立刻重推 `story_load`（客户端自己也清了）；下次推送时给 0。

#### 命令逐条

| 命令 | 参数 | 回包 | 服务端动作 |
|---|---|---|---|
| `story_load` | 推送 | — | 全量 stories + new_story_id |
| `story_read_new_story` | 无 | 无（needResponse=false） | 把「未读新故事」标记清掉（持久化） |
| `story_send_gift {id, gift}` | `id`=story id, `gift`=item_id | 无 | 校验 `gift === -1` 且家里有该物品 → 扣 1 个、记 `gift=itemId`；推 `item_update`。**建议**：若 story.json 的 `const.friend_choice_percent=25`，可据此判定旅友是否满意（**推测**：这是「朋友挑选」成功率的百分点） |
| `story_feedback_gift {id}` | `id` = **邮件 id** | 无 | 玩家对 `type=6 StoryGift` 的邮件点「感谢他的赠礼」→ 服务端回礼：给 `feedback` 物品 + 推 `item_update`，并把邮件标记 `opened`；可顺带生成下一段故事（提高 `new_story_id`） |

**解锁机制**：客户端完全没有解锁逻辑 → 故事解锁 = 服务端往 `stories` 里加入新条目并把 `new_story_id` 指向它。
**推测的触发点**（原版不可考，可自由设计）：旅行「到达目的地」带回 storyItem 类物品时、`guest_serve` 招待后、`story_feedback_gift` 后。

**邮件联动**（写给 `type=6 StoryGift` 的邮件）：
```js
{ id, type: 6, sender: -1, title: '旅友的赠礼', message: '...',
  expire: 0, auto_open: false, read: false, opened: false,
  resource: {clover_point:0,ticket:0,reward_gacha:0,ads_id:'',share_id:''},
  items: [{ item_id: <礼物>, count: 1 }],   // ★ 必须非空，否则 btn_accept 不显示、无法回礼
  pictures: [] }
```

---

## 6. 抽奖（lottery / 周末抽奖）

### 6.1 事实依据

```
[C:LotteryModel]
  data 默认 = { last_phase:0, phase:0, state:0, select_list:[], answer:[],
                extra_item:{item_id:0,count:0}, right_flag:[], egg_num:0, reward:[] }
  initModel: addProtocolCallback("lottery_load")
  lottery_load(e){ e.phase && ( this.data=e,
      this.data.select_list=convertArray(...), this.data.answer=convertArray(...),
      this.data.right_flag=convertArray(...), this.data.reward=convertArray(...) ) }   // ★ phase 为 0 时整包丢弃
  req_open(cb){ send("lottery_open",Action2) → i.open_item && i.extra_item &&
      ( 弹出 ItemRewardView([{item_id:i.open_item.item_id,count:i.open_item.count}]),
        data.state=LotteryState.Select, data.extra_item=i.extra_item, cb() ) }
  req_select(list,cb){ send("lottery_select",Action2,list) → 0==n.code && (data.answer=list, data.state=Complete, cb()) }
  req_confirm_reward(cb){ send("lottery_confirm_reward",Action2) → 0==i.code && (data.state=Open, data.answer=[], cb()) }
  isRewardState(){ return data.state==LotteryState.Reward }
  getLeftTime(){ if(0==phase||select_list.length<=0) return 0;
      var i=new Date(now*1000).getDay();   // 0=周日 … 6=周六
      return 0==i ? (今天0点+86400-now) : 6==i ? (今天0点+172800-now) : 0 }             [C:LotteryModel @145271]
Tabikaeru.LotteryState = { Open:0, Select:1, Complete:2, Reward:3 }                      [X:417944]
[C:MainOut...].lotteryGroup 点击:
    LotteryModel.isRewardState() ? addViewControl(LotterySettleViewControl) : addViewControl(LotteryViewControl)   [X:839391]
[C:LotteryView].childrenCreated:
    var i=(data.phase-1)%4+1; imageBg.source="anm_weekend_"+i+"_png";        // 4 套周末背景轮换
    imageOpen 点击 → LotteryModel.req_open(()=>updateState())
    groupExtra 点击 → popup(new LotteryExtraView)
    btnComplete 点击 → if(state==Select && !(selectList.length<5))
                          ModalConfirm("已经帮小伙伴做好决定了吗？", ()=>req_select(selectList,()=>updateState()))
    遍历 data.select_list（服务器给的物品 id 池）生成可点图标：
       点击时 if(state==Select){ 已选则移除；否则 selectList.length<5 时加入 }
    updateState(): imageOpen.visible = state==Open;  groupBottom.visible = state!=Open;
                   imageComplete.visible = state==Complete;  btnComplete.visible = state==Select;
        var i=(phase-1)%4+1, n=lotteryData.get("select_list")[i];       // 4 个邻居之一定背景/文案
        imageGuest.source=n.pic+"_png";
        lbAsk.text  = state==Select ? n.desc : n.desc2;
        lbTips.text = state==Select ? format("选出5款物品，帮{0}解决这个困扰", n.name) : "感谢你提供的帮助"  [X:773433]
[C:LotterySettleView].childrenCreated:
    var i=data, n=(data.last_phase-1)%4+1; imageBg.source="anm_weekend_"+n+"_png";
    o = count(right_flag[a]==1)
    c = format(lotteryData.get("settle_desc")[o], lotteryData.get("select_list")[n].name)
    5==data.egg_num && (c += lotteryData.get("extra_desc")[n][o])
    渲染 data.answer（right_flag==0 的置灰 Utils.getBlackFilter()）
    渲染 data.reward[{id,num,is_egg}]（is_egg==1 → 叠加 tips_egg_gift_png）
    btnOk → req_confirm_reward(()=>addViewControl(LotteryViewControl))                        [X:769500]
[DB:lotteryData_json.json]:
   select_list: {"1":{"desc":"愁眉苦脸的困困…","desc2":"做好决定的困困…","id":1,"name":"困困","pic":"neighbor_emote_0_0"},
                 "2":{...胖胖...},"3":{...跳跳...},"4":{...嘟嘟..."neighbor_emote_3_0"}}
   settle_desc: {"0":"{0}很感谢你的帮忙，但还是看得出有点可惜", ... "5":"{0}觉得你很不可思议，竟然全是对方喜欢的"}
   extra_desc:  {"1":{"0":"，对方不太接受这类美食", ... "5":"，双方还一起享受着这顿大餐"}, "2":..., "3":..., "4":{...植物...}}
```
抽奖券（ticket）的真实归属：
```
[C:抽奖视图].raffle(): return this.userModel.consumeTicket(Tabikaeru.Define.RAFFEL_NEEDTICKETS)   // ★ 只是判断
   ? (drawBtn.touchEnabled=false, send("item_gacha", null, false))
   : (ModalAlert("抽奖券不足"))
[C:ItemModel].item_gacha(e,t){ this.gachaColorBall = e.ticket; dispatch(updateGachaColorBall) }   // ★ 回包的 ticket = 彩球序号
[C:抽奖视图].reward_raffle(): getGachaColorBall()==-1 → send("item_gacha", null, true)   // 领取
Tabikaeru.Define.RAFFEL_NEEDTICKETS = 5                                                          [X:419653]
[C:UserModel].consumeTicket(e){ return this.ticket>=e ? true : false }   // 不扣
[C:UserModel].addTicket(e){}                                            // 空
```
→ **`lottery_*` 与抽奖券没有直接关系**。抽奖券（`res.ticket` / `item_update_ticket`）消费在 `item_gacha`（在家抽奖/扭蛋），每次 5 张，**必须由服务端扣并推 `item_update_ticket`**。

### 6.2 实现规格

#### 存档（建议）
```js
lottery: {
  phase: 0,            // 当前周次，>0 才会被客户端接受（0 = 活动未开启）
  lastPhase: 0,        // 上一周（结算界面用它选背景/邻居）
  state: 0,            // 0 Open / 1 Select / 2 Complete / 3 Reward
  selectList: [],      // 候选物品 id 池（服务器给，8~12 个）
  answer: [],          // 玩家上周提交的 5 个 id
  rightFlag: [],       // 与 answer 等长，1=对 0=错
  reward: [],          // [{id, num, is_egg}]  is_egg=1 → 显示彩蛋角标
  eggNum: 0,           // 猜对个数；==5 时额外显示 extra_desc
  extraItem: { item_id: 0, count: 0 },
  submittedAt: 0
}
```

#### `lottery_load` payload
```js
{
  last_phase: 0,
  phase: 12,                    // ★ 必须 > 0，否则客户端整包丢弃
  state: 1,                     // 0..3
  select_list: [1201,1000,3000,3001,3002,3003,3004,3005,3006,3007],   // 候选物品 id 池
  answer: [],                   // 上次提交（state<3 时通常为空）
  right_flag: [],
  reward: [],
  egg_num: 0,
  extra_item: { item_id: 0, count: 0 }
}
```

#### 命令逐条

| 命令 | 参数 | 回包 | 服务端动作 |
|---|---|---|---|
| `lottery_open` | 无 | **`{open_item:{item_id,count}, extra_item:{item_id,count}}`** —— 两个键都必须存在，否则客户端什么都不做 | `state` 必须为 Open → 发「开启礼包」奖励（`open_item`）+ 额外奖（`extra_item`，没有就 `item_id:0,count:0`）→ `state=Select` |
| `lottery_select {list}` | 5 个物品 id | `{code:0}` | 校验 `state==Select` 且 `list.length==5` 且都在 `select_list` 里 → `answer=list`、`state=Complete`、`submittedAt=now` |
| `lottery_confirm_reward` | 无 | `{code:0}` | `state==Reward` → 结算奖励真正入库（**推 `clover_update`/`item_update_ticket`/`item_update`**）、`state=Open`、`answer=[]` |
| `lottery_load` | 推送 | — | 每次进入游戏推一次即可（`BOOT_PUSH` 已含） |

#### 周期（**推测**：原版为每周末活动）
- `phase` 用「周序号」自增；`(phase-1)%4+1` 选邻居/背景。
- 客户端 `getLeftTime()` 只在**周日(0) / 周六(6)** 返回非 0 → 活动窗口是周末，结算时间点在**周日 24:00（即下周一 0 点）**。
- 结算流程（建议）：
  1. 周一 0 点：对上周 `answer` 判定 `rightFlag`、算 `reward`/`eggNum`、`lastPhase=phase`、`phase++`、`state=Reward` → 推 `lottery_load` + `client_load_role`(如需)；
  2. 玩家点开 → `lottery_confirm_reward` → `state=Open`；
  3. `lottery_open` 开新一周的礼包 → `state=Select`，并用**新的候选池**（建议从玩家已拥有的特产/纪念品里抽 8~12 个，**推测**）；
  4. `lottery_select` → `state=Complete`，等下一个周一。

**判定规则（推测）**：`lotteryData.select_list[idx].name` 是 4 个邻居；`extra_desc[4]` 的文案是「植物」相关，说明第 4 位（嘟嘟）偏好植物/家具类。建议：
- 用 `Character[id].taste[specialtyId]`（§1.1(d)，对 id 0/1/2 可用）作为正确性分数，取 `taste >= 60` 判为「对」；
- 第 4 位邻居不在 `Character.json` 里 → 需要自定义偏好表（**纯推测**，可用 `Item.type/sub_type`：植物/家具类算对）。
- `egg_num` 建议就填 `rightFlag` 里 1 的个数（客户端只在 `==5` 时追加 `extra_desc` 文案，含义自洽）。

---

## 7. 图鉴（encyclopedia）

### 7.1 事实依据

```
[C:EncyModel]
  data 默认 = { unlock_list:[], unlock_desc:{}, show_sub:{} }
  initModel: addProtocolCallback("encyclopedia_load")
  encyclopedia_load(e){
     e = Utils.convertArrayAll(e);            // 把所有字段都转成数组（null/undefined → []）
     this.data.unlock_list = e.unlock_list;
     for(n of e.unlock_desc) this.data.unlock_desc[n.id] = convertArray(n.list);
     for(n of e.show_sub)    this.data.show_sub[n.id]    = n.sub_id;
     this.data.unlock_list.sort((a,b)=>a-b) }                                   // ★ 客户端会原地排序
  req_set_show_sub(long_id){
     var t = DataManager.instance().encyData.get("list")[long_id];
     this.data.show_sub[t.id] = long_id;
     send("encyclopedia_set_show_sub", null, long_id) }        // ★ 回包被忽略（callback=null）
  isOpen(){ return this.data.unlock_list.length>0 }
  isDescUnlock(id, idx){ var i=this.data.unlock_desc[id]; if(!i) return false;
     for(o of i) if(o==idx) return true; return false }                          [C:EncyModel @101198]
```
`[DB:encyclopedia_json.json]` 顶层 `{desc, list}`：
- `desc`：23 组 `{植物id: {"1":"金虎尾目-堇菜科-堇菜属","2":"多年生草本植物", ...}}` → 就是 `unlock_desc[id].list` 里那些**下标**对应的文案。
- `list`：**238 条**，key = `long_id`，字段 `{id, long_id, name, pic_id, pic_name, sub_id, sub_name, icon, pic_img, pos, scale, tab}`。
  例：`{"1010101":{"icon":"icon_chahua_zhongzhi_jiaojin_1","id":101,"long_id":1010101,"name":"角堇","pic_id":1,"pic_name":"主图","scale":0.8,"sub_id":1,"sub_name":"火龙果","tab":1}}`
  `long_id` 编码：`id*10000 + sub_id*100 + pic_id`（例 `1010101` → id 101, sub_id 01, pic_id 01）。
- 「图鉴」内容 = **花朵/植物**（`tab` 分类，`sub_name` 是果实/形态变体）。

### 7.2 实现规格

#### `encyclopedia_load` payload
```js
{
  unlock_list: [101, 102, 201],          // 已解锁的「植物 id」列表（数字，客户端会升序排序）
  unlock_desc: [                          // 每个植物已解锁的说明条目下标（对应 encyclopedia.desc[id] 的 key）
    { id: 101, list: [1, 2] },
    { id: 201, list: [1, 3, 4] }
  ],
  show_sub: [                             // 每个植物当前展示的变体（值是 long_id，不是 sub_id！）
    { id: 101, sub_id: 1010101 }
  ]
}
```
- `unlock_list` 为空 → `isOpen()` 为 false → 图鉴入口隐藏（`Lumberroom` 的 `encyBtn`）。
- `unlock_desc[n].list` 里放的是 **desc 的 key（字符串或数字都行，客户端用 `==` 比较）**。
- `show_sub[n].sub_id` 虽然字段名叫 `sub_id`，但客户端在 `req_set_show_sub` 里写回的是 **`long_id`**（`encyData.get("list")[long_id]` → `.id` 作 key，值 = long_id）。所以推送时也应给 `long_id`。

#### 命令

| 命令 | 参数 | 回包 | 服务端动作 |
|---|---|---|---|
| `encyclopedia_load` | 推送 | — | 全量图鉴状态（`BOOT_PUSH` 已含） |
| `encyclopedia_set_show_sub` | `{long_id}`（协议表参数名就是 `long_id`） | 忽略（客户端 callback=null） | 校验 `long_id` 属于已解锁植物 → 记 `showSub[id] = long_id`；`needResponse=false`，返回 `undefined` 即可 |

**解锁来源（推测）**：客户端无逻辑。建议由「种花/花瓶（flowerpot/compost）」与旅行带回的植物类物品驱动；离线版可先给 2~3 个植物做演示。

---

## 8. 状态存储建议汇总（写进 `save.json`）
```js
{
  guest:  { id, confirmed, served, expireTime, pos, arriveAt, nextTryAt, lastLeaveAt,
            drawing: { state, guest, bag, pages, colls, showColl, penMotion } },

  mails:  [ { id, type, sender, timestamp, title, message, expire, auto_open, read, opened,
              resource:{clover_point,ticket,reward_gacha,ads_id,share_id},
              items:[{item_id,count}], pictures:[] } ],
  mailSeq: 1000,

  tasks:  { list: [{id,pro,is_reward}],            // task_list 30 条
            proMap: { '101': 0, ... },             // list_map 进度
            reward: { '1': 0, ... } },             // list_type 已领档数
  achieves: [], achievesTime: [], curAchieve: 0,

  calendar: { newFlag: [], luckyDays: {}, stDays: {},
              taskList: [{id,pro,complete}×3], notes: [], month: 0 },

  stories:  [ {id, partner, name, gift, feedback} ],
  newStoryId: 0,

  lottery: { phase, lastPhase, state, selectList, answer, rightFlag, reward, eggNum, extraItem, submittedAt },

  encyclopedia: { unlockList: [], unlockDesc: {}, showSub: {} }
}
```

---

## 9. 不确定 / 需要你决策的点（按风险排序）

1. **`task_client_pro` 的 `param→list_map` 映射未知。** 客户端只发 `"Map"` / `"NoteFriend"`（`[C:GuideTaskView]`、`[C:TravelMapController]`、`[C:TravelNoteController]`），但 `list_map` 有 67 条。原版映射不可考 → 需要自定义（建议每 param 每天只推进一次）。**置信度：低（最高风险项）。**
2. **访客招待的「三叶草数量」与「普通/稀有」的触发条件没有直接常量。**
   已确定的：回礼**类别**权重 `FRIEND_GIFTPER_NORMAL/RARE`、保底 `FRIEND_GIFTFIX`、额外奖励 `FRIEND_GIFTBOUNUS_*`、折扣 `FRIEND_ITEM_DEBUFF`（§1.3）。
   未确定的：`Clover` 类别具体给多少三叶草、「稀有」是由 feeling 还是独立骰子决定。**置信度：中。**
3. **各系统奖励物品数值。** 客户端把 `addClover/addTicket/addHouseItem` 全写成空函数 → 「邮件给什么」「日历幸运日给什么」「故事回礼给什么」都只能设计。
   但 `task_list[i].reward_id/num`、`list_type[type].reward[tier]`、`calendarData.beginner[N]`、`lotteryData`、`PrizeClover/PrizeBalls` 是明确的。**置信度：中（表内明确，表外自由）。**
4. **`egg_num` 的确切含义。** 客户端只在 `5==egg_num` 时追加 `extra_desc` 文案（`[C:LotterySettleView]`），同时另用 `right_flag` 求和得到 `o`。最合理的解释是「猜对个数」= `sum(right_flag)`，但两者同时存在说明原版可能是「全中对」标记。**置信度：中。**
5. **`st_days` / `lucky_days` 的生成规则。** 客户端只消费，不定规则；`st` 的含义（推测 = 任务达成日 / small-task day）无证据。**置信度：低。**
6. **`story_data.feedback` 与 `partner`。** `partner` 用途明确（关系图按它去重，`[C:RelationshipView]`），`feedback` **只被赋值、从不被读**（`StoryData` 定义后 0 处读取）→ 可以随便给。故事解锁条件完全由服务端决定。**置信度：中（partner 高，feedback 低）。**
7. **访客的「是否需要蛙在家」。** 机制确定（服务端推 `guest_load`），节奏常量确定（§1.3），但「蛙是否必须在家」**没有任何证据**（`Tabikaeru.Define` 里也没有对应项）。**置信度：低（该条件可自由决定）。**
8. **`gameplay.json` 的 30 分钟是否线上原值。** 它与 `FRIEND_VISIT_RNDSEC:1800` 完全吻合，互相印证 → 可信度已大幅提高；但活动期是否被热更改过仍不可考。**置信度：高。**
9. **`notify_new_mail` 不在协议表里**（`protocol.js` MISSING），要用必须先补，否则会走 UNKNOWN 分支。
10. **`calendar_get_st_reward` / `calendar_get_luck_reward` 无参数**已用源码逐字核对（`work/spec/out_sendargs.txt`）→ 实现时按「服务端当天日期」判定，别指望拿到客户端的天数。（`calendar_get_code_reward` 例外，它带 `{day}`。）
11. **`encyclopedia_set_show_sub` 的 `needResponse` 在协议表里是 `false`**，而其它 `..._load` 都是 `true`；客户端 `callback=null` → 返回 `undefined` 是安全的。
12. **`Tabikaeru.Define` 常量里还有一批与其它子系统相关的可用数据**（`PrizeClover` 白玉10/青玉30/紫玉50/绿玉100/红玉350/黄玉1000、`PrizeBalls` 权重 40/25/22/9/3/1、`SHOP_TICKET_PER:15`、`MAIL_MAX:100`、`HaveItemMax:99` 等），本规格只用到与访客相关的部分，其余留给对应子系统的规格。

---

## 10. 关键证据文件索引（本任务产出）
| 文件 | 内容 |
|---|---|
| `work/spec/dump_guest.txt` | `guest_load` / `guest_load_drawing` / `guest_accept_invit` / `guest_putin_bag` / `guest_takeout_bag` 的 `prototype.*` 体 |
| `work/spec/dump_mail_task.txt` | `mail_load` / `mail_load_mails` / `task_load` / `task_load_list` 体 |
| `work/spec/dump_cal_story_lot.txt` | `calendar_*` / `story_load` / `lottery_load` / `encyclopedia_load` 体 |
| `work/spec/cls_mail_task.txt` | `TravelModel`（含邮件全部逻辑）、`GuideTaskModel` 全文 |
| `work/spec/cls_cal_story_lot.txt` | `CalendarModel` / `StoryModel` / `LotteryModel` / `EncyModel` 全文 |
| `work/spec/ctx_checkfriend.txt` | `checkFriend`（停留时长、形象、点访客流程、反馈文案） |
| `work/spec/ctx_checkgameplay.txt` | `checkGameplay`（过期清理）、`[C:CalendarModel]` 与日历视图 |
| `work/spec/ctx_guest_notify.txt` | 事件系统里的「朋友来访」黄条、`GameplayModel.getGameplayList` |
| `work/spec/ctx_sendsites.txt` | 各命令的 send 调用点与参数（`guest_confirm`/`guest_serve`/`mail_open`/`task_*`/`story_*`） |
| `work/spec/ctx_sendargs.txt` | 逐字核对的 `send(...)` 实参（用于确认 st/luck 不带 day） |
| `work/spec/ctx_enums2.txt` / `ctx_enum_more.txt` / `ctx_draw_lot_enum.txt` | `Mail.EvtId`、`TimerEvent.Type`、`DrawingState`、`LotteryState`、`Tabikaeru.ItemID`、`NotificationType` |
| `work/spec/ctx_lotteryview.txt` / `ctx_batch3.txt` | `LotteryView` / `LotterySettleView` 全文 |
| `work/spec/ctx_mailitem2.txt` / `ctx_mailcls.txt` | `MailItemView`（按类型渲染与领取）、`MailInfo` 字段 |
| `work/spec/ctx_drawingmodel.txt` | `DrawingModel` 全文 |
| `work/spec/ctx_calview.txt` | 日历格子与日详情（3 条任务文案、`st_days`/`lucky_days` 用法） |
| `work/spec/out_taskdata*.txt` | `taskData_json` 四张表的摘要 |
| `work/spec/out_friendconst.txt` | ★ 访客奖励/节奏常量（`FRIEND_*`）在全 JS 中的出现次数与原文，证明它们只存在于 `Tabikaeru.Define` |
| `work/spec/_gameconst.txt` | `Tabikaeru.Define` 全文（访客/抽奖/物品上限等全部常量）——**本次任务最重要的新证据来源**（由本次会话先前工作产出） |
| `work/spec/data/*.json` | 从 `config.eab` 解密的配置表副本 |
| `work/tools/jsx.py` `cls.py` `eab_dec.py` `proto_list.py` `sendargs.py` `friendconst.py` | 本次新增/使用的分析工具 |
