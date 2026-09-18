# 旅行 / 纪念品 / 明信片相册 / 旅行笔记 —— 字段级实现规格

> 目标读者：要改 `work/run/engine/index.js` 的实现者。
> 本文只写规格，不含引擎改动。
> **每条结论都标注依据**（客户端函数名 + 在 `main.min.js` 里的字符偏移）。
> 没有客户端依据的推断一律标 **[推测]**。

---

## 0. 证据来源

| 代号 | 含义 |
|---|---|
| 客户端 | `work/base/assets/game/js/main.min.js`（v1001，1,315,423 B） |
| `@偏移` | 该标识符在**解码后的 UTF-8 字符串**中的字符下标（`dump_class.py` / `occur.py` 同坐标系；注意 `dump_range.py` 用的是**原始字节**偏移，两者不等价，本次新增了 `work/spec/_dumps/dr.py` 用解码偏移导出） |
| 数据表 | `work/spec/_dumps/tables/*.json` —— 本次**新解出**的客户端数据表，直接来自 `resource/China/eab/config.eab`（60 张表，含 `Note/Picture/PictureTag/Collection/Specialty/Item/resources/Word/GoalNumber/zh-CN`）。提取方法与密钥见 **§11** |
| dump 目录 | `work/spec/_dumps/`（本次导出的所有代码片段都在这里，可直接引用来复核） |

本文里出现的所有"客户端函数"都是从 `main.min.js` 用括号配平导出的原始代码，不是转述。
**引用优先级：函数/类名 > `@偏移`**。偏移只用于快速定位；如果偏移与函数名不符，以函数名为准
（`main.min.js` 是压缩过的单行文件，类的边界偶尔落在 IIFE 内部，`var X=function` 的名字未必是类名）。

---

## 1. 协议层约定（本次逐行复核过，与 README 一致）

### 1.1 客户端发送（`SocketManage.prototype.send` @336284）

```js
t.prototype.send = function (t, i) {              // t=cmd, i=callback(action)
  for (var n = [], r = 2; r < arguments.length; r++) n[r - 2] = arguments[r];
  ...
  var o = ProtocolList.protocolList[t], a = o[0], s = o[1];   // a=参数名数组, s=needResponse
  if (a.length != n.length) return void e.Log.error("发送的协议：... 参数与定义参数不匹配...");
  var c = t, l = c.indexOf("_");                   // 只有第一个下划线变点
  if (l >= 0) { var h = c.split(""); h.splice(l, 1, "."), c = h.join("") }
  var u = {};
  if (s && (this.sessionID++, u.session = this.sessionID), u.timestamp = Math.floor(e.Time.getServerTime()), u.cmd = c, a.length > 0) {
    u.data = {};
    for (var p = 0; p < a.length; p++) u.data[a[p]] = n[p]     // 参数按【名字】打包
  }
  var d = JSON.stringify(u);
  ... u.callbackFun = i, this.activateProtocol[u.session] = u ...
}
```

要点：

1. **参数严格按个数校验**：`travel_read_note` 定义 1 个参数（`id`），所以客户端一定发**一个**值；实际那个值是**数组**（见 §7.2）。引擎不能假设 `data.id` 是标量。
2. `needResponse=false` 的协议**不带 session**，引擎不该回包（回了也不会被消费，但会打日志）。
3. 参数按名塞进 `data`，所以回包字段名必须与客户端读取的字段名完全一致。

### 1.2 回包 / 推送的区分（`SocketManage.prototype.AnalysisProtocol` @337837）

```js
var r = JSON.parse(n);
if (e.String.isNullOrEmpty(r.cmd))                        // 有 cmd → 推送
  if (null != r.session) {                                // 无 cmd 有 session → 回包
    var o = this.activateProtocol[r.session];
    if (o) { delete this.activateProtocol[r.session];
      var a = o.cmd.replace(".", "_"), s = o.callbackFun;
      this.HasEventListener(a) || null != s
        ? (this.HasEventListener(a) && this.DispatchEvent(new e.Event(a, r.data, o.data)),
           s && s.apply(r.data, o.data))
        : e.Log.warning("协议：" + a + " 未定义回调函数...");
    } else e.Log.warning("协议编号：" + r.session + " 不存在");
  } else e.Log.warning("返回协议失败，协议名未定义");
else { var a = r.cmd.replace(".", "_");                    // 推送
       this.HasEventListener(a) ? this.DispatchEvent(new e.Event(a, r.data))
                                : e.Log.warning("协议：" + a + " 未定义回调函数...") }
```

要点：

* `r.cmd` 用 `String.replace(".", "_")` 还原 —— 只换**第一个**点，所以线上名是 `travel.load_gift` → `travel_load_gift`。**引擎的 `toWire()` 已经是对的。**
* **回调签名是 `(r.data, o.data)`** —— 第一个参数是回包体，第二个是**请求参数对象**。证据：`core.Action2.prototype.apply = function(e,t){ return this.call(e,t) }`（@344855）。所以 `travel_gift_to_bag` 的 `function(i,n)` 里 `n` 是 `{item_id:...}`，不是回包。
* **推送体就是 `r.data` 本身**，不做任何包装；有 `cmd` 的那一层才带 `{cmd,data}`。

### 1.3 数组型回包

`client_load_events` 的处理器写死 `Array.isArray(e)`：

```js
t.prototype.client_load_events = function (e, t) {
  this.travelEventList = Array.isArray(e) ? e : [], ...
```
依据：`TravelModel.client_load_events` @200770（dump 见 `_dumps/TravelModel.txt:250`）。

→ **`client.load_events` 的回包体必须是一个裸 JSON 数组**，线上形态 `{"session":N,"data":[...]}`。
同理 `mail_load` 用 `Utils.convertArray(e)`（两种都容忍），但 `client_load_events` 不容忍。当前引擎（`index.js` 的 `client_load_events`）请核对是不是发数组。

---

## 2. 客户端关键枚举与数据结构（这些是写规格的地基）

### 2.1 `Tabikaeru.DataType.ItemType`（**道具分类的唯一权威**）

依据：`@408500` 附近的 IIFE（`_dumps/itemtype3.txt`）：

```js
e[e.NONE=-1]="NONE", e[e.LunchBox=0]="LunchBox", e[e.Amulet=1]="Amulet",
e[e.Tools=2]="Tools", e[e.Specialty=3]="Specialty", e[e.Gift=5]="Gift",
e[e.HandCraftTool=7]="HandCraftTool", e[e.HandCraftStuff=8]="HandCraftStuff",
e[e.Other=9]="Other", e[e.FURNITURE_RESOURCE=10]=..., e[e.FURNITURE_ITEM=11]=...,
e[e.FURNITURE_TOOL=12]=..., e[e.FURNITURE_PAPER=13]=..., e[e.RESOURCE=14]=...,
e[e.Courtyard=15]=..., e[e.COMPOSE=16]=...
```

`Tabikaeru.DataType.ItemAmuletType.FLOWER = 1`（@409028 附近，`_dumps/itemtype.txt:6`）。

### 2.2 `TimerEvent.Type`（`notify.new_event` 的 `evt_type` 全表）

依据：`@415900` 附近（`_dumps/timertype3.txt`）：

```js
e[e.NONE=0]="NONE", e[e.GoTravel=1]="GoTravel", e[e.BackHome=2]="BackHome",
e[e.Picture=3]="Picture", e[e.Drift=4]="Drift", e[e.Return=5]="Return",
e[e.Guest=6]="Guest", e[e.Gift=7]="Gift", e[e.Story=8]="Story",
e[e.StoryGift=9]="StoryGift", e[e.StoryFeedback=10]="StoryFeedback",
e[e.Visitor=11]="Visitor", e[e.Recharge=12]="Recharge", e[e.Decoration=13]="Decoration",
e[e.AntiAddition=14]="AntiAddition", e[e.NewNote=15]="NewNote",
e[e.VisitFriend=16]="VisitFriend", e[e.DropReward=17]="DropReward",
e[e.Consume=18]="Consume", e[e.DriftBottle=19]="DriftBottle",
e[e.MuseumMiss=20]="MuseumMiss", e[e.FurnitureFinish=21]="FurnitureFinish",
e[e.FurniturePut=22]="FurniturePut", e[e.PartyGo=23]="PartyGo",
e[e.PartyResult=24]="PartyResult", e[e.CardGift=25]="CardGift",
e[e.CardFeedback=26]="CardFeedback", e[e.CardNew=27]="CardNew",
e[e.FurnitureVersion=1022], e[e.AunnalReview=1023]
```

与本子系统相关的只有：`1 GoTravel`、`2 BackHome`、`3 Picture`、`15 NewNote`、`16 VisitFriend`。

### 2.3 `Mail.EvtId`

依据：`@412850` 附近（`_dumps/mailedit2.txt`）：

```js
e[e.NONE=0], e[e.System=1], e[e.Gift=3], e[e.Leaflet=5], e[e.StoryGift=6],
e[e.Taobao=7], e[e.Drift=8], e[e.Captcha=9], e[e.ShareURL=10],
e[e.NewPicture=11], e[e.Explor=12], e[e.SpecPicture=13], e[e.CardGift=14], e[e.Notice=15]
```

`NewPicture=11` / `SpecPicture=13` 的邮件 **`mail.pictures` 数组**是"新明信片"的另一个入口（见 §4.4）。

### 2.4 传输对象（构造函数即默认值 = 字段清单）

依据：`@190400` 附近（`_dumps/album_a.txt:45-80`）：

```js
var TravelEventInfo = function () { function e() {
  this.id = 0; this.evt_type = 0; this.evt_id = 0;
  this.evt_value = []; this.evt_string = []; this.evt_pic = [];
} ... }

var PictureInfo = function () { function e() {
  this.pic_id = 0;      // → Picture 表 id（100..3205）
  this.id = 0;          // 相册/礼品盒里的【唯一实例 id】
  this.layers = [];     // 【服务端下发的合成图层】
  this.for_ads = false; // 广告照片
  this.visit = false;   // 朋友来访时拍的
  this.hash = "";       // 客户端自己算：id + "_" + index
} ... }

var ResourceInfo = function () { function e() {
  this.ticket = 0; this.clover_point = 0; this.reward_gacha = 0;
  this.ads_id = null; this.share_id = null;
} ... }

var ItemInfo = function () { function e() { this.item_id = 0; this.count = 0 } ... }

var Redmsg = function () { function e() {
  this.type = 0; this.position = 0; this.display = 0; this.number = 0
} ... }
```

### 2.5 错误码表（**客户端本地表**，服务端只需回 `{code}`）

依据：`MessageModel.getErrorInfo` @148263 读 `RES.getRes("errcode_json")`；
表已解出：`work/spec/_dumps/tables/errcode.json`（59 条，其中 71–76 / 100–102 是本子系统的）：

| code | desc（客户端显示的原文） |
|---|---|
| 0 | 成功 |
| **71** | 照片插入失败 |
| **72** | 照片删除失败 |
| **73** | 照片到达上限 ← **相册满** |
| **74** | 删除错误的照片id |
| **75** | 保存错误的新照片id |
| **76** | 删除错误的新照片id |
| **100** | 礼品盒的照片已满 |
| **101** | 相册的照片已满 |
| **102** | 礼品盒的特产已满 |

> ⚠️ 73 与 101 都是"相册满"，但触发路径不同：
> * `album_save_new` 走 73（`Result.ReceivePostcard` 的保存按钮，`_dumps/rp2.txt`）
> * `travel_gift_to_album` 走 101（礼品盒 → 相册，`GiftBoxModel.gift_to_album` @116933）
> **两个都要实现**，客户端 UI 文案/分支不一样。

### 2.6 数据表结构（本次新解出，`work/spec/_dumps/tables/`）

| 表 | 条数 | 结构 |
|---|---|---|
| `Picture.json` | 349 | `{id, name, type:'Normal'\|'Tools'\|'Goal'\|'Unique', backImage:[名字], frontImage:[名字], effect:'', frogPos:{x,y}, frogPos_s:{x,y}, frogPose, frogPose_s, travelerPos:[{x,y}×3], travelerPose:[str×3], view:{x,y}, priority:bool, randomSet:bool, place?:GoalNumberId, share?:1\|2\|3}` |
| `PictureTag.json` | 198 | `{id, Tag, picNames:[名字], tagType:'Normal'}` |
| `Note.json` | 191 | `type1`×137(id 1000..1136, `factorType:'Drop'`) / `type2`×27(id 2000..2026) / `Own_Note`×27(id 20000..20260, 有 `attach`)；公共字段 `{id, img:{index,src}, info, quality:1\|2, factorData, factorType}` |
| `Word.json` | 197 | `{id, img:{index,src}, type:1\|2}`（type 1 宽 40、type 2 宽 20） |
| `Collection.json` | 62 | `{id, img, info, info2, name, place, type:1(35)\|2(7)\|3(20)}`，`type==3` = 博物馆藏品 |
| `Specialty.json` | 64 | `{id, itemId, place}`（`itemId` 3000..3063） |
| `Item.json` | 410 | `{id, type:ItemType, sub_type, name, info, img, price, own_num, spend}` |
| `resources.json` | 1268 | `resId(字符串键) → 图片路径`，如 `"1": "Picture/Normal/sky05"` |
| `GoalNumber.json` | 38 | `{id, name, tag}` —— 33 个城市 + 5 个博物馆（id 100..104，tag 前缀 `g_bwg_`） |

`Item.json` 的类型分布（`work/spec/_dumps/imgsize.txt`）：

```
type 0  LunchBox  91 个   id 0..
type 1  Amulet    55 个   id 1000..1021, 1100..
type 2  Tools     12 个   id 2000..2011
type 3  Specialty 64 个   id 3000..3063
type 5  Gift      12 个   id 5001..5602
type 14 RESOURCE  83 个   id 200000(三叶草)/200001(兑奖券)/200002(罗盘)...
其它: 7/8/9/10/11/12/13/15/16（手工/家具/庭院/合成）
```

**`Item` 里没有 2066。** README §「核心循环已跑通：旅行」用它当例子是错的 —— `ItemDB.get(2066)` 返回 `undefined`，客户端会把它当"掉落"处理（`d && d.type==Specialty ? push : else push`），弹出一个空图标。引擎生成 `evt_value[5..]` 时**必须用真实存在的 item id**。

### 2.7 资源名规则 `Tabikaeru.path.formatPathImage`

依据：`@1260810` 附近（`_dumps/pathns.txt`）：

```js
function i(e) {
  return "string" == typeof e
    ? (-1 == e.indexOf("_png") && -1 == e.indexOf("_jpg") ? (e ? e + "_png" : "") : e || "")
    : (e ? e.index + "_png" : "")
}
```

→ `{index:"pic_1000", src:"Scene/Note/Pic"}` 只用到 `index`，资源名 = `pic_1000_png`；**`src` 字段被忽略**。

---

## 3. 【核心】明信片 = `PictureInfo` + 服务端合成的 `layers`

这是整个子系统**最关键、也最容易踩的**一点。

### 3.1 客户端只渲染，不合成

依据：`Tabikaeru.getPictureTexture` / `loadPicture` / `renderPicture`（`@401000` 附近，`_dumps/pixtex.txt`）：

```js
function t(t) {                       // getPicturePath(resId)
  var i = e.DataManager.instance().ResourcesDB[t.toString()];
  return i || (core.Log.warning("照片资源配置表 resources_json 中未找到 ID：" + t + " 的图片路径"),
               i = e.DataManager.instance().ResourcesDB[1]), i
}
function i(e) {                       // loadPicture(pictureInfo)
  if (e) {
    for (var i = "", n = 0, r = e.layers; n < r.length; n++) {
      var o = r[n]; i += o.layer[0].toString() + o.layer[1].toString() + o.layer[2].toString()
    }
    var s = c[i] ? c[i].texture : null;
    return s ? new Promise(function (e, t) { e() })
             : Promise.all(e.layers.map(function (e) { return RES.getResAsync(a(t(e.layer[0]))) }))
  }
  return core.Log.error("加载相片失败，相片数据不能为空"), new Promise(function () {})
}
function r(e, i) {                    // getPictureTexture(pictureInfo, scale=1)
  void 0 === i && (i = 1);
  for (var n = "", r = 0, o = e.layers; r < o.length; r++) {
    var l = o[r]; n += l.layer[0].toString() + l.layer[1].toString() + l.layer[2].toString()
  }
  var h, u = c[n];
  if (u) h = u.texture, u.count++;
  else {
    var p = s; p.removeChildren();
    for (var d = 0, g = e.layers; d < g.length; d++) {
      var f = g[d], v = new egret.Bitmap, _ = RES.getRes(a(t(f.layer[0])));
      if (null == _) return null;
      v.texture = _, v.x = f.layer[1], v.y = f.layer[2], p.addChild(v)
    }
    h = new egret.RenderTexture, h.drawToTexture(p, new egret.Rectangle(0, 0, 500, 350), i), ...
  }
  return h
}
```

结论（**确定**）：

* `layers` 是**数组**，元素形如 `{layer: [resId, x, y]}`；`resId` 是 `resources_json` 的**键**（数字形态）。
* 三元素被拼成缓存 key（`resId+x+y` 连字符串），所以**同一个 `resId` 配不同坐标是不同图层**，`resources.json` 里出现重复路径是正常的。
* 渲染画布固定 **500×350**。
* 每个图层按 `(x, y)` 摆放，`RES.getRes(path)+"_png"` 取图。

**交叉验证**（同一约定的另一处独立证据）：`TimerEvent.Type.FurnitureFinish` 分支（`case TimerEvent.Type.FurnitureFinish:` @887500 起，`_dumps/ev_switch_b.txt:54`）：

```js
for (var e = { id: Q, layers: [] }, t = 1, i = g.evt_value.length; i > t; t += g.evt_value[0])
  e.layers.push({ layer: g.evt_value.slice(t, t + g.evt_value[0]) });
```
服务端在 `evt_value` 里用 `[stride, resId, x, y, resId, x, y, ...]` 传图层 —— **stride=3 正好对应 `[resId,x,y]`**，说明 `layers` 的构造权 100% 在服务端。

### 3.2 缺 `layers` 会怎样（各调用点）

| 位置 | 依据 | 缺 `layers` 的后果 |
|---|---|---|
| 相册格子 `AlbumPicture.init` | `AlbumPicture` @485000（`init` @485198） | `image.data = e`；`PictureRender.render→getPictureTexture` 拿到 `null` 再走 `loadPicture(pic)` → `e.layers` 长度 0 → `Promise.all([])` 立即 resolve → 纹理仍然没有 → **格子空着** |
| 相册列表 `AlbumView.createPage` | `AlbumView` @468172（`createPage` @477439），`_dumps/AlbumView.txt:178` | `o.init(pictureList[r] && pictureList[r].layers ? pictureList[r] : null, ...)` → **没有 layers 就传 null，格子直接空** |
| 相册页刷新 `AlbumView.requestPagePictures` | `AlbumView` @468172（`requestPagePictures` @475612），`_dumps/AlbumView.txt:129` | 调 `checkPictureByIds(t)` → 发 `album_load_by_id_list` 补图层 |
| 礼品盒相册 `PictureItemRender` | `PictureItemRender` @1210474 | `this.image.source="picture_loader_png"; this.image.data=this.data` → 同样需要 layers |
| 明信片大图 `PostcardListItem.update` | `PostcardListItem` @1228680 | `null == this.data.pic.layers` → 调 `checkPictureByIds([pic])` 再补一次 |
| 设为封面 `RoleModel.setPictureID` | @173497 | `this.pictureInfo = e.layers` —— **封面背景也是拿 layers 直接铺**，所以选封面同样需要 layers |

`picture_loader_png` 是一个注册过的自定义 Egret loader（`Tabikaeru.PictureRenderHelper`，`_dumps/loadpicture.txt:12`），它对 `data` 调 `getPictureTexture`。

### 3.3 引擎怎么造 `layers` —— 可用的与不可用的

**可用（客户端数据里有的）：**

* `Picture.json` 的 `backImage` / `frontImage`：**图层名字数组**（如 `["sky05","cloud01","bird","mou_back03","tree02","tree01","roof01"]`）。
* `resources.json`：`名字` → `路径` 的映射表（`资源路径的最后一段 == 名字`）。实测 420 个不同名字里绝大多数能反查到唯一 resId，例如
  `chuisihaitang_back → 1011`、`wet_back → 53`、`sky04 → 14`。
  少数**查不到**：`rnd_sea`、`rnd_mou_back`、`rnd_pose_roof1`、`rnd_pose_beach1` —— 这些是 `rnd_` 前缀的**随机组令牌**，由服务端在运行时挑一个具体图。
* `Picture.json` 的 `frogPos` / `frogPos_s` / `travelerPos[i]`：青蛙/来客的坐标。
* `view: {x:0,y:0}`：实测 349 张全部是 `{0,0}`。

**不可用（客户端根本没有）：**

* **背景/前景图层的坐标**。`Picture.json` 只给名字，不给坐标。
* `resources.json` 里重复路径（`sky05` 同时是 resId 1 和 3）说明 resId 本身不是"资源 id"而是**服务端合成器用的图层槽位 id**，槽位语义只存在于已关服的服务端里。

**实测旁证**：`resources.json` 指向的图片里 **353 张是 500×350**（正好是画布尺寸），其余是 80×80、45×33 之类的小图（青蛙/来客立绘）。也就是说**背景图层极可能就是按 (0,0) 整幅贴上去的**，只有青蛙/来客用 `frogPos`/`travelerPos` 摆位。

→ **[推测，但证据较强]** 最小可用合成方案：

```
layers = []
for name in picture.backImage:            # 顺序 = 绘制顺序（数组顺序即 z 序）
    resId = nameToResId(name)             # resources.json 反查；rnd_* 先随机挑一个真实名字
    layers.push({ layer: [resId, 0, 0] })
# 青蛙：从 resources.json 里找 frogPose 对应的立绘 resId
layers.push({ layer: [poseResId, picture.frogPos.x, picture.frogPos.y] })
for name in picture.frontImage:
    layers.push({ layer: [nameToResId(name), 0, 0] })
```

`nameToResId` 需要用**真正的资源名字**（`Picture.json` 里的名字）去和 `resources.json` 的**路径末段**做等值匹配；`rnd_xxx` 需要一张手工映射表或"随机挑同前缀的一张"。
**[推测]** `frogPose` / `travelerPose` 的值（`pose_beijing1` 之类）在 `resources.json` 里**也查不到**（不是图片名而是姿态组名），需要实测确认青蛙立绘该怎么取。

**验证方法（推荐先做）**：写一个 Node 脚本，用上面的算法给全部 349 张 `Picture` 造 `layers`，再把结果塞进 `album_load_all` 让客户端渲染，逐张截图对比"图是不是一张正常风景照"（而不是纯白/错位）。**这一条必须在引擎里真跑一遍，不能只看代码。** 如果 (0,0) 不行，退路是：
1. 用 `PictureTag.json` 把同 tag 的图分组，只保留能正确渲染的组；
2. 或者只用 `backImage[0]`（`MuseumPictureView.dataChanged` @917246 就是这么干的：`PictureDB.get(id).backImage[0]` 去掉第一个下划线前缀 → `xxx_png`，博物馆明信片走这条单图路径）。

### 3.4 明信片怎么"获得"

有**两条**入口，服务端都要做：

**入口 A —— 旅行回家（推荐主力）**
服务端推 `album_load_new`（见 §4.4）。客户端把它存进 `newPictureInfoList`；当旅行事件队列排空后，`Result.eventSystem` 的 else 分支会弹横幅「{蛙名} 送来了照片。」，点开就是明信片弹窗。

依据：`Result.eventSystem`（`var Result` @883276）末尾的 `else` 分支（`_dumps/ev_switch_d.txt:65`）：

```js
} else {                                   // 没有待处理旅行事件时
  var Gt = T.getFirstNewPictureInfo();
  if (Gt) {
    Music.play("SE_Popup");
    var k = _("{0} 送来了照片。", y),
        F = function () { Music.play("SE_Popup"); var e = new i(Gt);
                          e.addEventListener(egret.Event.REMOVED_FROM_STAGE, p, null), c.addChild(e) },
        P = new r;
    P.notify(c, n.Green_Picture, k, F)
  } else T.handleAdsPicture() && BaseChannel...promptNewAds("frog_back", ...)
    : T.handleSharePicture() ? ... : ...
}
```

**入口 B —— 邮件（原版的主路径）**
`Mail.EvtId.NewPicture(11)` / `SpecPicture(13)` 的邮件，打开时：

依据：`@793690` 附近（`_dumps/mailaccept.txt:4`）：

```js
else if (this.mailInfo.type == Mail.EvtId.NewPicture || this.mailInfo.type == Mail.EvtId.SpecPicture)
  core.ModelManage.getInstance().getModel(TravelModel).pushNewPictureIDs(this.mailInfo.pictures),
  this.acceptCallback && this.acceptCallback.apply(this, this.mailInfo), this.mailView.hideBanner();
```

`pushNewPictureIDs` 的**唯一**调用点就在这里（全文 grep：`@192569` 定义、`@793801` 调用）。

`newPictureIDs` 的作用（`TravelModel.album_load_new` @204090）：

```js
for (var c = [], l = 0, h = t /* e.pictures */; l < h.length; l++) {
  var u = h[l];
  this.newPictureIDs.length > 0 && 0 == u.for_ads && c.push(u)
}
this.newPictureIDs.length = 0;
this.saveNewPictureNow(c);
```

→ **只有当 `newPictureIDs` 非空时**，`album_load_new` 里的非广告照片才会**立刻**弹出 `ReceivePostcard` 保存框；否则只是进 `newPictureInfoList`，等横幅点击。

**[推测]** 原版设计意图：`NewPicture` 邮件里带 `pictures`（服务端已经决定给哪几张），玩家点"领取"后服务端再推一次 `album_load_new`（同一批图），客户端才会直接弹保存框。
**离线实现的简化建议**：回家时**不发邮件**，直接推 `album_load_new`，让横幅路径生效（少一个环节、视觉上一样）。

### 3.5 明信片的"纪念品"部分（不要和明信片搞混）

回家奖励里那个"大图"**不是明信片**，是 `Collection` 表（62 条）的**纪念品**：

依据：`Result.ModalSpeciality`（`var Result` @883276，`_dumps/rp2.txt:86`）：

```js
var a = function (e) { function t(t, i, n) {         // t=collectId, i=specialtyItemId[], n=onClose
    ...
    var e = Tabikaeru.DataManager.instance();
    if (-1 !== t) {
      var n = e.CollectDB.get(t);
      n && (r.ippin.source = Tabikaeru.path.formatPathImage(n.img),
            3 == n.type ? r.currentState = "museum" : r.currentState = "normal")
    }
    for (var o = 0; o < i.length; o++) { var a = i[o], n = (i[o+1], e.ItemDB.get(a));
      n && (r["meibutu" + (o + 1)].source = Tabikaeru.path.formatPathImage(n.img)) }
  ...
} (eui.Component); __reflect(a.prototype, "ModalSpeciality");
```

* `evt_value[4]` → **`Collection` 表 id**（`CollectDB.get`），`type==3` 时弹窗切到 `museum` 皮肤；`-1` = 没有。
* `evt_value[5..]` 里 `ItemType.Specialty(3)` 的 → 弹窗下方的"名物"小图（`meibutu1..N`）。
* **`ModalSpeciality` 里没有明信片**。回家事件不会显示明信片。

---

## 4. 相册（`album_*`，9 条）

一条重要的总览：**8 条命令里只有 7 条是客户端主动发的，`album_load_new` 客户端从不发送。**

依据：全文只有 3 处出现字符串字面量 `"album_load_new"` —— `@192050`（`addProtocolCallback` 注册表）、`@204090`（处理器定义）、`@377294`（客户端自己的协议表）。
没有任何 `send("album_load_new", ...)`。

→ **`album_load_new` 是纯推送。** 引擎应该把它放进推送路径（`ctx.push('album_load_new', ...)`）。

### 4.1 `album_load`（分页拉取 · 客户端主动）

* 协议：`needResponse: true`，params `["start","count"]`。
* 发送点只有一处（`TravelModel.checkPictureInfoPage` @194617；send 调用点 @195003）：

```js
t.prototype.checkPictureInfoPage = function (e, t) {      // e=start(1-based), t=end
  if (e > t) return core.Log.warning("检测相册页面失败，start 不能小于 end"), !1;
  var i = !0;
  if (this.pictureCount >= e)
    if (this.pictureInfoList.length >= t) {
      for (var n = e - 1; t > n; n++)
        if (null == this.pictureInfoList[n] || null == this.pictureInfoList[n].layers) { i = !1; break }
    } else i = !1;
  else i = !1;
  return i || core.SocketManage.getInstance().send("album_load", null, e, t - e + 1), i
}
```

* 回包处理（`TravelModel.album_load` @201410）：

```js
t.prototype.album_load = function (e, t) {
  for (var i = Array.isArray(e.pictures) ? e.pictures : [], n = 0; n < i.length; n++)
    i[n] && (this.pictureInfoList[e.start + n - 1] = i[n]);
  this.pictureCount = e.total;
  this.dispatchEvent(new core.Event(TravelEventType.updateAlbum))
}
```

**回包规格（必填三字段）：**

```jsonc
{
  "pictures": [ PictureInfo, ... ],   // 允许有空位（falsy 会被跳过）
  "total": 42,                        // 相册总数 → pictureCount，分页算页数用
  "start": 1                          // 本次返回的起始下标【1-based】，客户端按 start+n-1 落位
}
```

* `start` 必须回显请求里的 `start`（服务端可以修正，但客户端用回包里这个值，不是请求值）。
* `pictures` 里的元素**建议直接带 `layers`**（这样后续 `checkPictureByIds` 不会再多问一轮），`layers` 可以留一个"轻量版"（只 `id/pic_id`）让客户端再补。
* 推送时会落到 `BOOT_PUSH`（引擎已经有 `album_load`）。**注意**：既然客户端从不主动发它，那 `BOOT_PUSH` 里这一条的语义是"开机给首页" —— `start=1` 且带 `layers` 才合理，否则相册一打开就是空的。
  建议：开机推 `album_load {pictures:[前 N 张带 layers], total:全部, start:1}`，或干脆推 `album_load_all`（见下）。

### 4.2 `album_load_all`（全量 id 列表 · 客户端主动）

* 协议：`needResponse: true`，params `[]`。
* 发送点（`TravelModel.requestAlbum` @193380）：

```js
t.prototype.requestAlbum = function (e) { core.SocketManage.getInstance().send("album_load_all", e) }
```
`requestAlbum` 的调用点只有 `AlbumController.totalCustomEvents` 的 `TravelEventType.addPicture` 分支（@466661 附近的 `case TravelEventType.addPicture: this.getModel(TravelModel).requestAlbum()`）：
「有照片从礼品盒搬进相册时，若相册界面开着就重拉全量」。

* 回包处理（`TravelModel.album_load_all` @201654）：

```js
t.prototype.album_load_all = function (e, t) {
  if (e && e.id_list) {
    for (var i = Array.isArray(e.id_list) ? e.id_list : [], n = 0, r = i.length; r > n; n++)
      i[n].hash = i[n].id + "_" + n;                  // 客户端自己算 hash
    for (var o = {}, a = 0, s = this.pictureInfoList; a < s.length; a++) { var n = s[a]; o[n.id] = n }
    this.pictureInfoList = i;
    for (var n = 0, r = this.pictureInfoList.length; r > n; n++)
      o[this.pictureInfoList[n].id] && (this.pictureInfoList[n] = o[this.pictureInfoList[n].id]);  // 已缓存带 layers 的对象覆盖回来
    this.pictureCount = i.length;                      // 【注意】用 id_list.length，不是 total
    this.dispatchEvent(new core.Event(TravelEventType.updateAlbum))
  }
}
```

**回包规格：**

```jsonc
{ "id_list": [ { "id": 9001, "pic_id": 2000, "for_ads": false, "visit": false }, ... ] }
```

* 只认 `id_list`；**`total` 被忽略**（`pictureCount = id_list.length`）。
* 每项 `id` 必须唯一且非 0（`o[n.id]=n` 会互相覆盖）。
* `layers` 可以不给 —— 客户端会用 `album_load_by_id_list` 按页补；但**必须给 `id`**，否则 `hash` 和 `checkPictureByIds` 都对不上。
* 顺序 = 相册顺序（`AlbumView.updateAlbum` 之后会按 `pic_id` 排序或 reverse，客户端自己处理）。

### 4.3 `album_load_by_id_list`（按 id 批量补 layers · 客户端主动）

* 协议：`needResponse: true`，params `["id_list"]`。
* 发送点（`TravelModel.checkPictureByIds` @194223；send 调用点 @194483）：

```js
t.prototype.checkPictureByIds = function (e, t) {     // e = PictureInfo 数组
  for (var i = !1, n = [], r = 0, o = e; r < o.length; r++) { var a = o[r]; n.push(a.id) }
  for (var s = 0, c = this.pictureInfoList; s < c.length; s++) {
    var a = c[s];
    if (n.indexOf(a.id) >= 0 && null == a.layers) { i = !0; break }
  }
  i ? core.SocketManage.getInstance().send("album_load_by_id_list", new core.Action2(function (e, i) {
        t && t.apply()
      }), n) : t && t.apply()
}
```

⚠️ **`data.id_list` 是 id 的数组**（`n` 是 `picture.id` 列表，不是对象列表）。这和 `album_load_all` 的 `id_list`（对象数组）**同名不同义**，别搞混。

* 回包处理（`TravelModel.album_load_by_id_list` @202137）：

```js
t.prototype.album_load_by_id_list = function (e, t) {
  if (e && e.pic_list) {
    for (var i = e.pic_list, n = {}, r = 0, o = i; r < o.length; r++) {
      var a = o[r];
      null == n[a.id] ? n[a.id] = [a] : n[a.id].push(a)
    }
    for (var s = 0, c = this.pictureInfoList; s < c.length; s++) {
      var a = c[s];
      n[a.id] && n[a.id].length > 0 && (a.layers = n[a.id].shift().layers)
    }
    this.dispatchEvent(new core.Event(TravelEventType.updateAlbumContent))
  }
}
```

**回包规格：**

```jsonc
{ "pic_list": [ { "id": 9001, "layers": [ {"layer":[1,0,0]}, ... ] }, ... ] }
```

* 只认 `pic_list`；每一项只用到 `id` 和 `layers`。
* 同一 `id` 可以出现**多次**（客户端按顺序 `shift()` 消耗，只有第一个生效）—— 这是为"同一张照片渲染多条"预留的，离线实现给一条即可。
* 推送 `TravelEventType.updateAlbumContent` → `AlbumController` → `AlbumView.onPicturesUpdate()` → 只更新当前页。

### 4.4 `album_load_new`（**服务端推送** · 新明信片）

回包/推送体（`TravelModel.album_load_new` @204090 全文）：

```js
t.prototype.album_load_new = function (e) {
  this.newAdsPictureInfoList = [], this.newPictureInfoList = [];
  for (var t = Array.isArray(e.pictures) ? e.pictures : [], i = 0; i < t.length; i++) {
    var n = t[i];
    n.for_ads ? this.newAdsPictureInfoList.push(n) : this.newPictureInfoList.push(n)
  }
  if (this.hasAds = e.has_ads, this.isShare = e.is_share, this.hasAds) {
    var r = this.getModel(AdsModel).getAdsPlace("frog_back");
    r && this.getModel(AdsModel).isValidAds(r) || (this.hasAds = !1, this.isShare = !0)
  }
  for (var o = Array.isArray(e.visted_pic) ? e.visted_pic : [], a = 0, s = o; a < s.length; a++) {
    var i = s[a]; i.visit = !0, this.newPictureInfoList.push(i)
  }
  this.dispatchEvent(new core.Event(TravelEventType.updateNewAlbum)), this.eventUpdateNewAlbum.apply();
  for (var c = [], l = 0, h = t; l < h.length; l++) {
    var u = h[l]; this.newPictureIDs.length > 0 && 0 == u.for_ads && c.push(u)
  }
  this.newPictureIDs.length = 0, this.saveNewPictureNow(c), ...
}
```

**推送体规格：**

```jsonc
{
  "pictures":  [ PictureInfo, ... ],  // 新拍到的照片（需带 layers 才能显示）
  "visted_pic":[ PictureInfo, ... ],  // 朋友来访时拍的（会被强制 visit=true）
  "has_ads":   false,                 // 【离线恒 false】否则会走广告分支
  "is_share":  false                  // 【离线恒 false】
}
```

要点：

* 三个数组都缺一不可？—— 不，代码用 `Array.isArray` 兜底，缺了不报错。但 `has_ads/is_share` 若为 `true`，客户端会去问 `AdsModel.getAdsPlace("frog_back")`，离线环境拿不到有效广告位 → 自动 `hasAds=false, isShare=true` → 然后会弹"帮忙微信分享"的确认框（见 `Result.eventSystem` 的 else 分支）。**所以离线必须 `has_ads:false, is_share:false`**。
* `for_ads:true` 的照片进 `newAdsPictureInfoList`，`deleteAllAdsPicture` 会 `album_delete_new` 掉它们 —— **离线不要用 for_ads**。
* 推送 `updateNewAlbum` 事件 → `MainOutController` 不监听它（它只监听 `updateEvents/updateMial/updateRedpoint` 等），但 `eventUpdateNewAlbum` 这个 `core.Action` 被 `VisitFriend` 流程用作"照片弹窗关掉后继续"的信号（`Result.eventSystem` 的 `VisitFriend` 分支 @891000）。
* `getFirstNewPictureInfo` 会按 `id` 去重（`TravelModel.getFirstNewPictureInfo` @196382），所以重复推同一张不会叠加。

### 4.5 `album_save_new`（把新明信片存进相册 · 客户端主动）

* 协议：`needResponse: true`，params `["id"]`（`id` = 新照片的 `PictureInfo.id`）。
* 发送点（`TravelModel.saveNewPictureInfo` @197385；send 调用点 @197552）：

```js
t.prototype.saveNewPictureInfo = function (e, t) {
  for (var i, n = this, r = this.newPictureInfoList, o = 0; o < r.length; o++)
    if (i = r[o], i.id == e)
      return void core.SocketManage.getInstance().send("album_save_new", new core.Action2(function (e, o) {
        var a = n.getModel(MessageModel).getErrorInfo(e.code);
        if (a && 0 == a.code) {
          for (var s = !1, c = r.length - 1; c >= 0; c--) r[c].id == i.id && (r.splice(c, 1), s = !0);
          s && (n.pictureCount++, n.pictureInfoList.push(i))            // 成功：加到相册末尾
        } else if (a && 75 == a.code)
          for (var c = r.length - 1; c >= 0; c--) r[c].id == i.id && r.splice(c, 1);
        t(a)
      }, this), e)
}
```

**回包规格：`{ "code": 0 }`**

| code | 客户端行为 | 引擎什么时候回 |
|---|---|---|
| 0 | 从 `newPictureInfoList` 移除、`pictureCount++`、`pictureInfoList.push(pic)`；`ReceivePostcard` 弹"保存成功。"并关闭 | 成功 |
| 73 | 弹"相册满了\n要删除一张照片继续保存吗？"→ 打开相册删除界面 | **相册已满** |
| 75 | 静默把该 id 从新照片列表移除；`ReceivePostcard` 也会自己关掉 | 保存错误的新照片 id（服务端没这张待存照片） |
| 其它 | `GuideHelpView.show(desc)` | 通用错误 |

依据（ReceivePostcard 侧）：`Result.ReceivePostcard`（`_dumps/rp2.txt`）：

```js
t.saveNewPictureInfo(e.pic.id, function (t) {
  if (t) if (0 == t.code) GuideHelpView...show(_("保存成功。"), ...)
  else if (73 == t.code) { var r = new ModalConfirm(_("相册满了\n要删除一张照片继续保存吗？"), function () {
        ... addViewControl(AlbumController, ..., { onDelete: ..., disableGiftBox: !0 }) }) ; e.addChild(r) }
  else 75 == t.code ? e.parent && (Music.play("SE_Enter"), e.parent.removeChild(e))
                    : GuideHelpView...show(t.desc, null, ...);
  else GuideHelpView...show(_("保存明信片失败！"), null, ...)
})
```

**服务端语义**：`album_save_new` 必须把那张"待保存"的照片从**新照片池**搬进**相册**。引擎要在存档里区分这两处（见 §9）。

### 4.6 `album_delete_new`（放弃保存 · 客户端主动）

* 协议：`needResponse: true`，params `["id"]`。
* 发送点两处：
  1. `TravelModel.deleteNewPictureInfo` @197892（玩家点 ReceivePostcard 的关闭 → 「确认放弃保存图片吗?」→ 发送）：
     ```js
     core.SocketManage.getInstance().send("album_delete_new", new core.Action2(function (e, i) {
       var r = n.getModel(MessageModel).getErrorInfo(e.code); t(r)
     }, this), e)
     ```
     ⚠️ 注意：**回调只把 errorInfo 传给外部，不做任何本地移除** —— 因为调用点 `onCloseTap` 自己会 `removeChild`。
  2. `TravelModel.deleteAllAdsPicture` @196929（批量删广告照片）：
     ```js
     for (var e, t = 0; t < this.newAdsPictureInfoList.length; t++)
       e = this.newAdsPictureInfoList[t], core.SocketManage.getInstance().send("album_delete_new", null, e.id);
     ```
* 回包：`{ "code": 0 }`（成功）。按用户确认的规则，把该 id 从待保存池移入回收站，保留原照片编号和内容；重复放弃不重复入站。不能直接销毁。相册已满而无法保存时，同样保留到回收站。

### 4.7 `album_delete`（从相册删除 · 客户端主动）

* 协议：`needResponse: true`，params `["id"]`。
* 发送点（`TravelModel.deletePictureInfo` @194996）：

```js
t.prototype.deletePictureInfo = function (e, t) {
  for (var i, n = this, r = this.pictureInfoList.length - 1; r >= 0; r--)
    if (i = this.pictureInfoList[r]) {
      if (i.id == e)
        return void core.SocketManage.getInstance().send("album_delete", new core.Action2(function (e, r) {
          var o = n.getModel(MessageModel).getErrorInfo(e.code);
          if (o && 0 == o.code) {
            var a = n.pictureInfoList.indexOf(i);
            a >= 0 ? n.pictureInfoList.splice(a, 1) : core.Log.warning("删除照片出错"),
            n.pictureCount--, n.dispatchEvent(new core.Event(TravelEventType.deletePicture))
          }
          t(o)
        }, this), e)
    } else this.pictureInfoList.splice(r, 1)      // 空位顺手清掉
}
```

* 回包：`{ "code": 0 }`。成功时客户端本地删掉并 `pictureCount--`。
* **服务端语义**：从相册移除 → 照片进**回收站**（见 4.8）。
  **[推测]** 这一点客户端无法证明（回收站是服务端概念），但 `album_load_recover` / `album_recover` 的存在只能这样解释。
* `AlbumView.deletePicture` @483246 成功后 `egret.setTimeout(this.reset, this, 66)` 重排界面。

### 4.8 回收站：`album_load_recover` + `album_recover`

* `album_load_recover`：`needResponse: true`，params `[]`。发送点两处：
  * `AlbumView.on_RecoverBtn` @473103（send 调用点 @473379）：打开"回收站"面板时
    ```js
    core.SocketManage.getInstance().send("album_load_recover", null)
    ```
  * `PictureRecover.onComplete` 的恢复回调 @493182：
    ```js
    e.getModel(TravelModel).recoverPictureInfo(e.lastSelectItem.pic.id, function (e) {
      return e && 0 != e.code ? void GuideHelpView.getInstance().show(e.desc)
                              : void core.SocketManage.getInstance().send("album_load_recover", null)
    })
    ```
* 回包处理（`TravelModel.album_load_recover` @205123）：
  ```js
  t.prototype.album_load_recover = function (e) {
    this.deletePictureInfoList = Array.isArray(e.pictures) ? e.pictures : [],
    this.dispatchEvent(new core.Event(TravelEventType.updateRecover))
  }
  ```
  → **回包规格 `{ "pictures": [PictureInfo, ...] }`**（`PictureRecover.updatePic` 只取前 **6** 个显示）。
* `album_recover`：`needResponse: true`，params `["id"]`。发送点（`TravelModel.recoverPictureInfo` @198231）：
  ```js
  core.SocketManage.getInstance().send("album_recover", new core.Action2(function (e, n) {
    var r = i.getModel(MessageModel).getErrorInfo(e.code);
    r && 0 == r.code && (i.pictureCount++, i.pictureInfoList.push(o),
                         i.dispatchEvent(new core.Event(TravelEventType.updateAlbum)));
    t(r)
  }, r), e)
  ```
  → 回包 `{ "code": 0 }`；客户端会把该对象（它已经在 `deletePictureInfoList` 里存过完整对象）重新 push 回相册。
* `PictureRecover.onComplete` 的 UI 事实（`PictureRecover` @492440）：6 个格子，`i.y = 180*floor(t/2)`，只有 `updateData(e[t])` 有数据的才 `visible=true`。
* **回收站容量**：客户端没有常量，**[推测]** 服务端定；离线建议与相册同容量或固定 6 个（正好一屏）。

### 4.9 相册界面的数据流（给实现者的心智模型）

依据：`AlbumController`（`_dumps/AlbumController.txt`）、`AlbumView`（`_dumps/AlbumView.txt`）。

```
打开相册 AlbumController.open
  → new AlbumView, view.reset(true, param)
      → updateAlbumSort → updateAlbum()
          pictureList = TravelModel.getPictureInfoList()      // 只读模型缓存！【不发协议】
          sort: sortTypeList.selectedIndex*10 + sortType2
                = 10 → 按 pic_id 升序 ; 11 → 按 pic_id 降序 ; 01 → reverse()
      → selectPage(0) → updateCurrentPage(0)
          → createPage([0, 1])      // 当前页 + 相邻页
          → requestPagePictures(0)  // 取当前页 6 个 → checkPictureByIds → album_load_by_id_list
```

**结论（很重要）**：打开相册**不会**主动请求相册列表。它只渲染 `TravelModel.pictureInfoList` 里已有的东西。所以：

* `pictureInfoList` 的内容**只能**来自 `album_load` / `album_load_all` / `album_load_by_id_list`（以及 `album_save_new` / `album_recover` 的本地 append）。
* 因此 **服务端必须在开机（`BOOT_PUSH`）时给一次有内容的 `album_load` 或 `album_load_all`**，否则玩家打开相册永远是空的。
* 只有当"礼品盒→相册"发生（`TravelEventType.addPicture`）且相册开着时才重拉 `album_load_all`。

分页常量（`AlbumView` @468172，构造函数）：

```js
n.pageWidth = 768, n.currentPageIndex = 0, n.itemPerPage = 6, ...
```

* 相册每页 **6** 张（2 列 × 3 行，`o.x = n%2===0 ? 124 : 404`、`o.y = 200*floor(n/2)`）。
* 礼品盒相册页 `GiftBoxAlbumView.numsPageItem = 6`（`GiftBoxAlbumView` @650624）。
* 回收站 `PictureRecover` 也是 6。

### 4.10 相册容量

* 客户端**没有任何容量常量**。容量完全由服务端在 `album_save_new` / `travel_gift_to_album` 里判定。
* 唯一线索：客户端内置 GM 里有 `full_album` 命令，把相册填到 **180**：

  ```js
  else if ("full_album" == cmd)
    for (var list = Tabikaeru.DataManager.instance().PictureDB.list(),
             length_1 = 180 - this.getModel(TravelModel).getPictureInfoList().length, ...
  ```
  依据：`@662314`。

→ **[推测，依据较强]** 国服相册上限 = **180**。礼品盒照片上限未知（`errcode 100`），建议先取一个偏小的值（如 12 或 20），并做成可配置。

---

## 5. 礼品盒（`travel_load_gift` + 4 条搬运命令）

礼品盒 = 两个"待整理"池：**明信片**和**特产**。
依据：`GiftBoxView.onComplete`（`_dumps/GiftBoxView.txt`）：

```js
this.pageContainer.setPages([{ render: GiftBoxAlbumView, data: this.option },
                             { render: GiftBoxSpecialtyView, data: this.option }]),
-1 == this.c_typeGroup.selectedIndex && this.c_typeGroup.setSelected(0)
```
→ **tab 0 = 照片页，tab 1 = 特产页**（`ItemModel.moveItemToGiftBox` 里"礼品盒满了"跳转用的是 `{pageIndex: 1}`，即特产页；`GiftBoxAlbumView.on_albumBtn` 传 `disableAlbum`）。

### 5.1 `travel_load_gift`

* 协议：`needResponse: true`，params `[]`。
* 调用点：`GiftBoxModel.requestData()`（打开礼品盒时）+ 引擎 `BOOT_PUSH`。
  ```js
  t.prototype.requestData = function () { core.SocketManage.getInstance().send("travel_load_gift") }
  ```
  （注意：params 是空数组，所以 `send` 只传 1 个实参 → 合法。）
* 回包处理（`GiftBoxModel.travel_load_gift` @118657，全文）：

```js
t.prototype.travel_load_gift = function (e, t) {
  this.pictureList.source = Array.isArray(e.pictures) ? e.pictures : [];
  for (var i = Array.isArray(e.specialtys) ? e.specialtys : [], n = i.length - 1; n >= 0; n--) {
    var r = i[n].item_id, o = i[n].count;
    if (o > 1) {                                   // count>1 会被【展开成多行 count=1】
      i.splice(n, 1);
      for (var a = 0; o > a; a++) i.splice(n, 0, { item_id: r, count: 1 })
    }
  }
  this.specialityList.source = i, this.specialityList.refresh(), this.pictureList.refresh(),
  this.dispatchEvent(new core.Event(GiftBoxEventType.updateGiftBox))
}
```

**回包规格：**

```jsonc
{
  "pictures": [ PictureInfo, ... ],                 // 需带 layers（PictureItemRender 要渲染缩略图）
  "specialtys": [ { "item_id": 3014, "count": 1 } ] // count 可 >1，客户端会摊平成多行
}
```

* `specialtys[].item_id` 必须是 `Item.json` 里 `type==3` 的特产（`GiftBoxSpecialtyItem.dataChanged` 会 `ItemDB.get(item_id)`，取不到就 `return` → 空行）。
* `pictures` 的每项必须带**唯一 `id`**（`delete_album` / `gift_to_album` 都按 `id` 找）。
* 每次搬运成功后，客户端**自己**改本地列表，不重拉；所以服务端不需要在每次搬运后推送，但**在回家奖励后、开机时**必须推（引擎已在 `returnFrog` 里推了）。

### 5.2 `travel_gift_to_album`（礼品盒照片 → 相册）

* 协议：`needResponse: true`，params `["picture_id"]`。
* 参数里叫 `picture_id`，但**实际传的是 `PictureInfo.id`（相册唯一 id）**，不是 `pic_id`。
  依据 `GiftBoxAlbumView.on_popBtn`（`_dumps/GiftBoxAlbumView.txt:40`）：
  ```js
  this.getModel(GiftBoxModel).gift_to_album(e.map(function (e) { return e.id }), ...)
  ```
  以及 `PostcardListView` 回调 `t.getModel(GiftBoxModel).gift_to_album([e.pic.id], !1, null)`。
* 发送与回包处理（`GiftBoxModel.gift_to_album` @116933 全文）：

```js
t.prototype.gift_to_album = function (e, t, i) {     // e=id 数组, t=disableAlbum 标志, i=回调
  var n = this, r = function () {
    var r = function () {
      var o = e.pop();
      return null == o ? void (i && i()) : void core.SocketManage.getInstance().send(
        "travel_gift_to_album", new core.Action2(function (e, i) {
          var a = n.getModel(MessageModel).getErrorInfo(e.code);
          if (a && 0 != a.code) {
            if (a && 101 == a.code)
              if (t) GuideHelpView.getInstance().show(_("相册满了"), function () { Music.play("SE_Enter") }, ...);
              else if (null == core.DisplayManage.getInstance().getChildByName("ModalConfirm")) {
                Music.play("SE_Popup");
                var s = new ModalConfirm(_("相册满了，要删除一张照片继续保存吗?"), function () {
                  Music.play("SE_PageNext"),
                  core.PageManage.getInstance().addViewControl(AlbumController, core.ViewLayerType.WindowLayer,
                                                               core.RemoveViewType.Retain, { disableGiftBox: !0 })
                });
                s.name = "ModalConfirm", core.DisplayManage.getInstance().popup(s)
              }
          } else {
            for (var c = n.pictureList.length - 1; c >= 0; c--)
              if (n.pictureList.getItemAt(c).id == o) {
                n.pictureList.removeItemAt(c),
                n.dispatchEvent(new core.Event(GiftBoxEventType.updateGiftBox)),
                n.dispatchEvent(new core.Event(TravelEventType.addPicture));
                break
              }
            r()
          }
        }), o)
    };
    r()
  };
  core.Time.dayCheck("gift_to_album")
    ? core.DisplayManage.getInstance().getNoticeLayer().addChild(
        new ModalConfirm("确认放入相册?", function () { r() }, function () { i && i() }, !1, "gift_to_album"))
    : r()
}
```

* 回包：`{ "code": 0 }`；**相册满 → `{"code":101}`**。
* 成功时客户端发 `TravelEventType.addPicture` → 若相册界面开着，`AlbumController` 会发 `album_load_all` 重拉。
* 服务端语义：把该照片从礼品盒移到相册（`pic_id`/`layers` 原样保留）。

### 5.3 `travel_album_to_gift`（相册照片 → 礼品盒）

* 协议：`needResponse: true`，params `["picture_id"]`（同样是 `PictureInfo.id`）。
* 发送点（`TravelModel.putPicturesToGiftBox` @195534；send 调用点 @195763）：

```js
core.SocketManage.getInstance().send("travel_album_to_gift", new core.Action2(function (e, n) {
  var o = i.getModel(MessageModel).getErrorInfo(e.code);
  if (o && 0 == o.code) {
    var a = i.pictureInfoList.indexOf(r);
    a >= 0 ? (i.pictureInfoList.splice(a, 1), i.getModel(GiftBoxModel).onMovePicture(r))
           : core.Log.warning("移动照片出错"),
    i.pictureCount--, s--, i.dispatchEvent(new core.Event(TravelEventType.deletePicture))
  }
  t(o)
}), r.id)
```

* 回包：`{ "code": 0 }`；**礼品盒照片满 → `{"code":100}`**。
  依据 `AlbumView.putPictureToGiftBox` @483509：
  ```js
  else if (100 == e.code) {
    if (null != t.option && t.option.disableGiftBox) GuideHelpView...show(_("礼品盒满了"), ...)
    else if (null == t.getChildByName("ModalConfirm")) { ... ModalConfirm(_("礼品盒满了，要删除一张照片继续保存吗?"), ...) }
  }
  ```
* 成功时 `onMovePicture(r)` 把对象推进 `GiftBoxModel.pictureList` —— 所以服务端**不需要**再推 `travel_load_gift`。

### 5.4 `travel_gift_to_bag`（礼品盒特产 → 家里库存）

* 协议：`needResponse: true`，params `["item_id"]`。
* 发送点（`GiftBoxModel.gift_to_bag` @116236）：

```js
t.prototype.gift_to_bag = function (e) {                 // e = item_id 数组
  ...
  core.SocketManage.getInstance().send("travel_gift_to_bag", new core.Action2(function (i, n) {
    var r = t.getModel(MessageModel).getErrorInfo(i.code);
    if (!r || 0 == r.code)
      for (var o = t.specialityList.length - 1; o >= 0; o--)
        if (t.specialityList.getItemAt(o).item_id == e) {
          t.specialityList.removeItemAt(o), t.getModel(ItemModel).addHouseItem(e, 1, !0); break
        }
    t.dispatchEvent(new core.Event(GiftBoxEventType.updateGiftBox))
  }), e)
  ...
  core.Time.dayCheck("gift_to_bag") ? ... ModalConfirm("确认放入背包?", ...) : i()
}
```

* `code==0` 或 `errorInfo` 取不到（即 code 不在表里）都当成功。
* `ItemModel.addHouseItem` 是**空实现**（`ItemModel` @132961，`addHouseItem` @137164）：
  ```js
  t.prototype.addHouseItem = function (e, t, i) { void 0 === i && (i = !0) }
  ```
  → **服务端不必回库存，但客户端界面上的"家里物品"要等下一次 `item_load_items` 推送才更新**。**建议搬运成功后推一次 `item_load_items`**（这是"少一个推送界面就不动"的典型）。
  同理 5.5 也是。

### 5.5 `travel_bag_to_gift`（家里物品 → 礼品盒特产）

* 协议：`needResponse: true`，params `["item_id"]`。
* 发送点（`ItemModel.moveItemToGiftBox` @138980）：

```js
core.SocketManage.getInstance().send("travel_bag_to_gift", new core.Action2(function (o, a) {
  var s = n.getModel(MessageModel).getErrorInfo(o.code);
  if (s && 0 != s.code) {
    if (s && 102 == s.code && null == core.DisplayManage.getInstance().getChildByName("ModalConfirm")) {
      var c = new ModalConfirm(_("礼品盒满了，要更换保存的特产的吗？"), function () {
        Music.play("SE_PageNext"),
        core.PageManage.getInstance().addViewControl(GiftBoxController, core.ViewLayerType.WindowLayer,
                                                     core.RemoveViewType.RemoveBefore, { pageIndex: 1 }),
        i(s)
      });
      c.name = "ModalConfirm", core.DisplayManage.getInstance().popup(c)
    }
  } else if (r = n.itemDataAll.GetValue(e), r >= t) {
    r -= t; var l = n.getItemInfo(e);
    n.dispatchEvent(new core.Event(ItemEventType.updateHouseInfo, e)),
    n.getModel(GiftBoxModel).onMoveItem({ item_id: l.id, count: 1 })
  }
  i()
}), e)
```

* 回包：`{ "code": 0 }`；**礼品盒特产满 → `{"code":102}`**。
* ⚠️ 客户端成功分支只做 `updateHouseInfo`（**不真正扣本地库存**，`consumeHouseItem` @138472 也是空判定：`return i>=t ? !0 : !1`），所以**服务端必须自己扣，并推 `item_load_items`**。
* 名称歧义：这个协议叫 `travel_bag_to_gift`，但 `moveItemToGiftBox` 操作的是 `itemDataAll`（家里的物品），**不是 4 格行李 `bagDataList`**。不要被名字误导。

### 5.6 `travel_gift_delete_album`（从礼品盒删照片）

* 协议：`needResponse: true`，params `["id"]`。
* 发送点（`GiftBoxModel.delete_album` @115700；send 调用点 @115785）：

```js
t.prototype.delete_album = function (e, t) {          // e = PictureInfo.id
  var i = this;
  core.SocketManage.getInstance().send("travel_gift_delete_album", new core.Action2(function () {
    for (var n = 0, r = i.pictureList.length; r > n; n++)
      if (i.pictureList.getItemAt(n).id == e) { i.pictureList.removeItemAt(n); break }
    t()
  }), e)
}
```
* **回调不检查 `code`**，任何回包都会触发本地删除。回 `{"code":0}` 即可（甚至可以 `needResponse` 但回空对象）。

---

## 6. 一次完整旅行的数据流（端到端）

### 6.1 什么条件让蛙出门（客户端完全不管）

**客户端没有"去旅行"命令**（本次复核：协议表里没有任何 `travel_go` / `travel_start` 之类）。
`TimerEvent.Type.GoTravel` 只是一个**展示事件**：

依据：`Result.eventSystem`（`_dumps/mo_evt2.txt:19`）：

```js
case TimerEvent.Type.GoTravel:
  core.Log.print("qw name " + y), Music.play("SE_Popup");
  var V = g.evt_value[1] && g.evt_value[1] > 0 ? "{0} 精力充沛地出去旅行了" : "{0} 出去旅行了",
      G = _(V, y), U = new r;
  U.notify(c, n.Red_Travel, G, function () { p() });
  break;
```

→ **出门时间、出门与否、状态机，全部是服务端决定的。** 引擎的 `tick()` 定时器是唯一正确做法。

`evt_value[1] > 0` → "精力充沛"文案（其余 evt_value 无用）。
`evt_id` → 客户端用于 `client_confirm_event` 回执（见 6.4）。

**状态同步**：`frog.status` 必须同时靠 `client_load_role` 推送更新（`Tabikaeru.Game.isHome` = `status==0`）。引擎的 `departFrog`/`returnFrog` 都推了，正确。

### 6.2 出门时带什么（行李 bag / 桌子 desk 如何消耗）

客户端里**只有槽位内容，没有消耗逻辑**：

* 4 格行李的槽位类型（`Bag.renderItem` @431561，`_dumps/bagtypes.txt`）：
  ```
  slot0 = LunchBox(便当)   slot1 = Amulet(护身符)   slot2 = Tools(道具)   slot3 = Tools(道具)
  ```
* 8 格桌子的槽位类型（`Table.renderItem` @435619，`_dumps/desktypes.txt`）：
  ```
  slot0,1 = LunchBox   slot2,3 = Amulet   slot4..7 = Tools
  ```
  > 类名容易认错：4 格那个类叫 `Bag`（@429241），8 格那个类叫 `Table`（@434574），
  > 它们的父容器才是 `BagTable`（@425630，`__reflect(BagTable.prototype,"BagTable")`）。
* 数据来源：`item_load_items` 的 `bag`（4 个，`-1` = 空）与 `desk`（8 个，`-1` = 空）：
  依据 `ItemModel.item_load_items` @143332：
  ```js
  this.bagDataList = e.bag, this.deskDataList = e.desk,
  this.bagLock = e.bag_completed || !1, this.bagConflict = e.bag_conflict || !1,
  this.deskConflict = e.desk_conflict || !1;
  ```
* 客户端默认值：`bagDataList=[-1,-1,-1,-1]`、`deskDataList=[8×-1]`（`ItemModel` 构造函数 @132961）—— **尺寸别写错**。
* `bag_completed` = "行李打包完成"锁（`ItemModel.setBagLock` → `item_set_bag_completed`，`needResponse:false`）。
* 放/取协议（`ItemModel.setBagData` @133838 / `setDeskData` @134493）：
  ```
  item_putin_bag  {pos, item_id}   pos 从 1 开始
  item_takeout_bag{pos}
  item_putin_desk {pos, item_id}
  item_takeout_desk{pos}
  回包 { conflict: bool }   ← 客户端只读 conflict（写进 bagConflict/deskConflict）
  ```
  引擎已实现且用 `-1` 表示空位、`pos-1` 落位 —— 与客户端一致。

**消耗规则（引擎必须自己实现，客户端零依据）**：

* **[推测]** 出门时把 `bag` 4 格的物品 id **全部消耗掉**（清成 `-1`），并把相应用量从 `items.house` 里扣；`desk` 不动。
  理由：`desk` 的语义是"补货架"（见下面 zh-CN 文案），不是行李。
* **[推测]** 若 `bag` 全空，则从 `desk` 里**自动挑**（照 §8 的槽位类型规则），挑中的也消耗掉。
  依据（客户端唯一的文字说明，`tables/zh-CN.json` 键 `{0}首次打开背包`）：
  > "如果在**桌子**上放好了东西，即使{0}回来的时候你不在，{0}也会自己挑选东西出门旅行。快放些东西在桌面上吧"

* 消耗后**必须推 `item_load_items`**（否则界面上的行李还满着）—— 客户端不会自己清空。

### 6.3 外出期间的推送

出门后唯一需要推的是**状态**（引擎已做）：

```jsonc
{"cmd":"client.load_role","data":{... "status":1 ...}}     // 让青蛙从庭院消失
{"cmd":"notify.new_event","data":{"event":{"evt_type":1,"evt_value":[0,1],"evt_id":N}}}
```

若要显示"待机/聚会"等其他状态，同样靠 `client_load_role` 重推（README 已记）。

### 6.4 回家：`evt_type=2 (BackHome)` 的 `evt_value` 全解

依据：`Result.eventSystem` 的 `BackHome` 分支（`case TimerEvent.Type.BackHome:` @885790 起；`_dumps/mo_evt2.txt:35` 与 `_dumps/ev_switch_b.txt:1`）：

```js
case TimerEvent.Type.BackHome:
  core.Log.print("qw name " + y), Music.play("SE_Popup");
  var N = _("{0} 回来了。", y),
      F = function () {
        Music.play("SE_Popup");
        for (var e = g.evt_value[2],           // ← 三叶草
                 t = g.evt_value[3],           // ← 抽奖券
                 i = g.evt_value[4],           // ← Collection id（纪念品）
                 n = g.evt_value.slice(5),     // ← 物品 id 列表
                 r = [], s = [], l = 0, h = n; l < h.length; l++) {
          var u = h[l], d = Tabikaeru.DataManager.instance().ItemDB.get(u);
          d && d.type == Tabikaeru.DataType.ItemType.Specialty ? r.push(u)     // 特产
                                                              : s.push({ item_id: u, count: -1 })  // 掉落
        }
        var f = new o(e, t, function () {      // o = ModalReward(clover, ticket)
          v.AddCloverTween(e);
          var t = function () {
            s.length > 0 ? core.PageManage.getInstance().addViewControl(
                  TravelDropController, core.ViewLayerType.NoticeLayer, null,
                  { data: s, onClose: function () { p() } })
                         : p()
          };
          if (-1 === i && 0 === r.length) t();
          else { Music.play("SE_Popup"); var n = new a(i, r, t); c.addChild(n) }   // a = ModalSpeciality
        });
        c.addChild(f)
      },
      H = new r;
  H.notify(c, n.Blue_Result, N, F);
  break;
```

**`evt_value` 布局（确定的，比 README 更精确）：**

| 下标 | 含义 | 备注 |
|---|---|---|
| `[0]` | **未使用**（引擎填 0） | BackHome 分支从不读 `evt_value[0]`/`[1]` |
| `[1]` | **未使用**（引擎填 0） | 只有 GoTravel / PartyGo 用 `[1]` |
| `[2]` | **带回的三叶草数** | `UserModel.addClover` 走 tween，不推 `clover_update` 客户端数字也会动 |
| `[3]` | **带回的抽奖券数** | 同上 |
| `[4]` | **`Collection` 表 id**（纪念品/一品），`-1` = 没有 | **不是明信片 id！** `CollectDB.get(id)`，`type==3` → 博物馆皮肤 |
| `[5..]` | **物品 id 列表** | `ItemDB.get(id).type==3(Specialty)` → 进 `ModalSpeciality` 的"名物"位；**其余（含取不到的 id）→ 进 `TravelDropView` 掉落列表** |

**关键修正**：README/引擎注释写的"`[4]` = 明信片 id"**是错的**。`evt_value[4]` 是 `Collection`（62 条纪念品表）的 id。明信片走完全独立的 `album_load_new` 通道（§4.4 / §3.4）。

**回家之后要推的推送清单（缺一个界面就不更新）：**

| 顺序 | 推送 | 为什么必须 |
|---|---|---|
| 1 | `client_load_role` | `frog.status: 0` → 青蛙出现在庭院（README 已记） |
| 2 | `clover_update {clover}` | HUD 三叶草数字（`ItemModel.clover_update` @143481） |
| 3 | `item_update_ticket {ticket}` | HUD 抽奖券（`ItemModel.item_update_ticket` @143450 → `UserModel.setTicket`） |
| 4 | `notify.new_event {event:{evt_type:2, evt_value:[...], evt_id:N}}` | 弹「回来了」+ 奖励三连 |
| 5 | `travel_load_gift {pictures, specialtys}` | 礼品盒内容（特产进盒） |
| 6 | `album_load_new {pictures, visted_pic, has_ads:false, is_share:false}` | **新明信片**（有照片时才推） |
| 7 | `item_load_items {...}` | 若本次消耗了行李 / 加了掉落物品，界面才刷新 |
| 8 | `client_load_events [...]` | 若希望"回来"这类事件在下次进游戏时重放（见 6.5） |
| 9 | `travel_load_note {note_list}` | 有新笔记时（且通常**同时**要推 `notify.new_event` 的 `evt_type=15 NewNote`） |

**顺序很重要**：`notify.new_event` 最好在 `clover_update`/`travel_load_gift` 之后推，因为玩家点掉横幅的瞬间 UI 会立刻取模型里的值。

### 6.5 客户端对旅行事件的确认回执

依据 `TravelModel.readTraveEvents` @192661：

```js
t.prototype.readTraveEvents = function (e, t) {
  for (var i = 0; i < this.travelEventList.length; i++)
    if (this.travelEventList[i].id == e.id) {
      this.travelEventList.splice(i, 1),
      e.client || core.SocketManage.getInstance().send("client_confirm_event", t, e.id);
      break
    }
}
```

* 玩家关掉一条事件弹窗后，客户端发 **`client_confirm_event {id: evt_id}`**（`needResponse:false`）。
* `e.client` 为真时不发（`client` 字段来自 `client_load_events` 里的历史事件，表示"客户端本地补的，不用回执"）。
* 引擎可用来记录"玩家已看过的最后一个事件"，避免重复推。**收到后不需要回包。**
* `Result.eventSystem` 是**串行**的：`s` 这个模块级布尔防止重入（`core.Log.warning("eventSystem() 函数正在执行，无需重复调用")`），每条事件处理完调 `p()` → `readTraveEvents` + 递归下一条。所以**一次推多条 `notify.new_event` 是对的**，客户端会排队逐个弹。

### 6.6 `notify_redmsg`（旅行红点）

* 推送体 `{ redmsg: { type, position, display, number } }`，`Redmsg` 类字段见 §2.4。
* `display == 1` → `TravelModel.redpointState = true` → 派发 `TravelEventType.updateRedpoint` → `MainOutController` → `view.updateRedpoint()`。
* 离线可以推 `{redmsg:{type:0,position:0,display:0,number:0}}` 清掉红点。

---

## 7. 旅行笔记（`travel_load_note` / `travel_read_note`）

### 7.1 `travel_load_note`

* 协议：`needResponse: true`，params `[]`。
* 调用点：`TravelNoteModel.loadNote(cb)` @207006（新笔记事件 `evt_type=15` 触发；也在 `BOOT_PUSH` 里）。
* 回包处理（`TravelNoteModel.travel_load_note` @208712 全文）：

```js
t.prototype.travel_load_note = function (e, t) {
  var i = [];
  if (Array.isArray(e.note_list))
    for (var n = Tabikaeru.DataManager.instance().TravelNoteDB, r = 0, o = e.note_list; r < o.length; r++) {
      var a = o[r], s = n.get(a.id);
      if (s) {                                    // ← Note 表里没有这个 id 就直接丢掉
        var c = new TravelNoteData;
        c.id = a.id, c.read = a.read, c.timestamp = a.timestamp, c.config = n.get(a.id), i.push(c)
      }
    }
  this.travelNodeList = i, this.updateRedot()
}
```

**回包规格：**

```jsonc
{ "note_list": [ { "id": 1000, "read": 0, "timestamp": 1789000000 }, ... ] }
```

* **每项只有 3 个字段**：`id`（Note 表 id）、`read`（0/1）、`timestamp`（**秒**）。
  依据 `TravelNoteItem.update`（`_dumps/TravelNoteItem.txt:18`）：
  ```js
  this.i_redot.visible = !e.read,
  this.t_date.text = core.DateFormat.format(1e3 * e.timestamp, core.DateFormater["YYYY.MM.DD"]);
  ```
  → `timestamp` 是**秒**（客户端乘 1000）。
* `config`（笔记名称/配图/正文）由**客户端本地表**提供，服务端不传。
* `note_list` 里**必须每个 id 都存在于 `Note.json`**（191 条：type1 id 1000..1136 共 137 条；type2 id 2000..2026 共 27 条；Own_Note id 20000..20260 共 27 条）。不存在会被静默丢弃。

### 7.2 `travel_read_note`

* 协议：`needResponse: **false**`，params `["id"]`。
* 发送点（`TravelNoteModel.sendReadNote` @207982；send 调用点 @208134）：

```js
t.prototype.sendReadNote = function (e) {
  for (var t = 0, i = e; t < i.length; t++) {
    var n = i[t], r = this.getNoteById(n);
    r && (r.read = !0)
  }
  core.SocketManage.getInstance().send("travel_read_note", null, e),
  this.dispatchEvent(new core.Event(ItemEventType.updateTravelNoteInfo, e)), this.updateRedot()
}
```
调用点：`TravelNoteView.onClose` → `sendReadNote(this.noteReadIDs)`（`_dumps/TravelNoteView.txt:8`），`noteReadIDs` 是**这一屏里被渲染过的 id 数组**。

**请求规格：`{ "id": [1000, 1001, ...] }`** —— 参数名是单数 `id`，值是**数组**。
**[推测]** 服务端逐个置 `read=1` 即可；不回包（`needResponse:false`）。**不要**因为参数是数组而尝试按单值处理。

### 7.3 笔记的展示与红点（影响服务端要不要推东西）

* 两张 tab：`TravelNoteView.onSelectGroupChange`（`TravelNoteView` @1140115）→ `currentType = selectedIndex==0 ? 1 : 2`。所以 **type 1 = 第一栏、type 2 = 第二栏**。
* 计数：`type1Btn.t_cur/t_max` = `getNoteNumsByType(1)` / `getNoteMaxByType(1)`；
  `getNoteMaxByType` 用**客户端 `Note.json` 全表**统计 `type==e` 的条数（`TravelNoteModel.getNoteMaxByType`），所以 **137/27 这两个上限是客户端自己算的，服务端不用管**。
* 红点：`TravelNoteModel.updateRedot` 统计 `read==0` 的条数 → `RedotManager.setRedotValue(RedotType.NEW_NOTE, n)`。
  → **服务端只要保证 `read` 字段正确，红点就对。**
* `Own_Note` 的挂载关系（**这是唯一需要服务端理解的"笔记组合"**）：
  * `Note.json` 里 27 条 `factorType:"Own_Note"` 的记录带 `attach` 字段，值指向一条 type-2 笔记的 id（例：`20000.attach = 2000`），`id` 从 20000 起、步长 10。
  * `TravelNoteItem.update`：渲染一条笔记时调 `getAttachNote(t.id)`，找到 `config.attach == 该 id` 的子笔记 → 切换 `currentState="hasAttach"`，同时显示它的图与正文。
    依据 `_dumps/TravelNoteItem.txt:22-23`。
  * `TravelNoteView.updateRedot`：子笔记的 `read` 归到**它 attach 的父笔记的 type** 上（`getNoteById(o.config.attach).config.type`）。
  * → 服务端可以在 `note_list` 里**同时**下发 `2000` 和 `20000`；`20000` 会作为 2000 的附属展示。
  * `TravelFriends` 表（`{...visitOpen}`）与 `GiftBoxModel.isOpen()`（`GiftBoxModel` @115249）有关，但与笔记红点无关。

### 7.4 `evt_type=15 (NewNote)` 的推送

依据 `Result.eventSystem`（`_dumps/ev_switch_d.txt:5`）：

```js
case TimerEvent.Type.NewNote:
  core.ModelManage.getInstance().getModel(TravelNoteModel).loadNote(function () {
    core.ModelManage.getInstance().getModel(TravelNoteModel).updateRedot()
  });
  break;
```

→ **`NewNote` 事件本身不弹任何 UI**，它只是让客户端**重新请求 `travel_load_note`**。
所以"得到新笔记"的正确做法是：

```jsonc
{"cmd":"notify.new_event","data":{"event":{"evt_type":15,"evt_id":N,"evt_value":[],"evt_string":[]}}}
```
（客户端收到后才来拉 `travel.load_note`；或者引擎直接推 `travel_load_note` + 事件两者其一。）

`evt_string` / `evt_pic` 是给 `Visitor`/`StoryGift`/`AntAddition`/`VisitFriend` 用的（如 `Visitor` 用 `evt_string[0]` 当来客名）。

---

## 8. 道具对旅行的影响（哪些是便当/护身符/道具，怎么影响目的地与带回物）

### 8.1 客户端明确能证明的（确定）

| 事实 | 依据 |
|---|---|
| `ItemType` 0/1/2/3 = 便当/护身符/道具/特产 | `@408500`（§2.1） |
| 行李 4 格 = [便当 ×1, 护身符 ×1, 道具 ×2] | `Bag.renderItem` @431561 |
| 桌子 8 格 = [便当 ×2, 护身符 ×2, 道具 ×4] | `Table.renderItem` @435619 |
| 背包页签 = 食物(LunchBox)/道具(Tools)/护身符(Amulet)/特产(Specialty) | `PlayerBag.switchTab`（`PlayerBag` @1213245） |
| 槽位类型限制的文案：「这里不能放便当/道具/护身符/特产哦」 | `tables/zh-CN.json` 键 |
| 物品提示分类文案：`ItemPutDesc` = LunchBox「物品栏-食物」/ Amulet「物品栏-护身符」/ Tools「物品栏-道具」/ Specialty「物品栏-特产」 | `@421130`（`_dumps/putdesc.txt`） |
| **道具决定去哪里**：「准备的**道具**会决定{0}去往何方。尝试准备不同的道具」 | `tables/zh-CN.json` 键 `{0}首次购买道具` |
| **桌子是自助补给**：「如果在**桌子**上放好了东西，即使{0}回来的时候你不在，{0}也会自己挑选东西出门旅行」 | `tables/zh-CN.json` 键 `{0}首次打开背包` |
| **护身符**：四叶草可作为旅行护身符（「四叶草可以用作旅行的护身符哟」） | `tables/zh-CN.json` 键 `首次获取四叶草`；`ItemAmuletType.FLOWER=1` |
| **照片与特产是"寄回来/带回来"的**：「{0}会寄来旅途中的**照片**，还会带回各地的**特产**」 | `tables/zh-CN.json` 键 `{0}领取奖励描述3` |
| 商店购买时背包/桌子占用的拦截文案：「该物品已放在背包」/「该物品已放在桌子上」/「该物品已随身携带」 | `@1216416` 附近 |

物品清单（`Item.json` 实测）：

* **便当 LunchBox**(type 0) 91 个，id 从 **0** 起：id0 奶油华夫饼(price 10)、id1 草莓可丽饼(30)、id2 沙拉皮塔饼(50)…
  `info` 文案暗示档次：id0「只能拿来垫垫肚子…闲逛时候的随身零食」、id1「刚好可以吃饱…短途观光」、id2「分量相当充足…出门远行的最佳选择」→ **便当的 price 就是"远行能力"**。
* **护身符 Amulet**(type 1) 55 个，id 1000..1021 / 1100..：id1000 四叶草、id1001 玉佩(3000)、id1002 绿色铃铛「**往东走**或许有好事发生」、1003 之类按颜色分方向。
  → **护身符的 info 里直接写了方位**（"往东/往南…"），这是"护身符影响方向"的客户端侧文字证据。
* **道具 Tools**(type 2) 12 个，id 2000..2011：竹筒/葫芦/水壶/…，info 全是**天气抗性**（"大热天也不怕中暑了"）→ 决定"能不能去某种地形/天气的地方"。

### 8.2 公开资料（日版原版社区共识 —— **间接依据，非客户端代码**）

* 便当（おべんとう）的质量/数量决定**旅行时长与距离**；桌面上放好的便当会被自动带上。
* 护身符（おまもり）影响**方向与稀有度**（幸运符 → 稀有照片）。
* 道具（どうぐ）决定**目的地类型**（不同道具对应不同地点）。
* 返回时带回 特产 / 明信片 / 抽奖券 / 三叶草。
  来源：[旅行青蛙攻略汇总（9game）](https://www.9game.cn/news/2151671.html)、[旅行青蛙怎么玩（豆瓣）](https://www.douban.com/note/655534837/)、[旅行青蛙稀有照片怎么获得（techweb）](https://m.techweb.com.cn/article/2018-01-26/2635725.shtml)、[旅行青蛙物品中文翻译及基础玩法指南（海峡网）](http://m.hxnews.com/news/dmyx/djyx/yxgl/201801/28/1390300.shtml)

### 8.3 建议的实现规则（**全部是 [推测]**，但每一条都对应上面的一条证据）

```
出发时：
  lunch   = bag[0:2] 里第一个有效便当（没有就看 desk[0:2]）
  amulet  = bag[1] / desk[2:4]
  tools   = bag[2:4] + desk[4:8]
  消耗掉被选中的（从 items.house 扣），并清空对应槽位

目的地：从 tools 的 item_id 映射到 GoalNumber（33 个城市）
  tools 为空 → 只在"无道具"池（Normal/Unique 类照片）里挑
  tools 非空 → 优先在该工具绑定的地点里挑 Goal 照片（Picture.type=='Goal' 且 place==城市 id）

旅行时长：以 lunch.price 为主因子（10/30/50 → 短/中/长），
  映射到 FROG_TRAVEL_MIN/MAX 之间的一个值

带回物：
  clover : 1..3（基础），受 amulet 四叶草加成
  ticket : 概率 0.45
  Collection id（evt_value[4]）：按目的地/稀有度挑一个 Collection（type==3 的是博物馆，配合 GoalNumber id 100..104）
  Specialty（evt_value[5..]）：按目的地挑 Specialty 表里 place 匹配的 itemId（华南/华东/华北/西南/台湾/东北/华中…）
  明信片：按目的地挑 Picture.type=='Goal' && place==城市 id 的一张（或 Normal/Unique 随机），
          走 album_load_new 推送，不要放进 evt_value[4]
```

**映射表需要新建**（客户端没有）：
* `toolItemId → GoalNumber.id`：**[推测]** 用 `Item.info` 里的方位词（"往东走"）+ 手动表；道具只有 12 个，手工填最稳。
* `Specialty.place` 是**地区名**（"华南地区"/"华东地区"…），`GoalNumber.name` 是**城市名**，两者需要一张"城市 → 地区"的手工表（33 个城市，一次填完）。
* `Picture.place` 直接就是 `GoalNumber.id`（132 张有 `place`），**不需要映射**。

---

## 9. 建议的存档 schema（给引擎实现者）

```jsonc
{
  // ── 明信片 ───────────────────────────────────────────
  "pictures": [                       // 相册（已保存）
    {
      "id": 9001,                     // 【必须全局唯一、非 0】客户端按 id 定位/删除/搬运
      "pic_id": 2000,                 // Picture 表 id（100..3205），排序键
      "layers": [ {"layer":[1,0,0]}, {"layer":[402,99,-80]} ],
      "for_ads": false,               // 离线恒 false
      "visit": false
    }
  ],
  "newPictures": [ /* 同结构，等 album_save_new 搬进 pictures */ ],
  "recycledPictures": [ /* 同结构，album_delete 进来的 */ ],
  "pictureSeq": 9002,                 // id 自增游标
  "albumSort": "insert" | "pic_id",   // 可选：相册顺序策略（客户端默认按插入序，可改按 pic_id）

  // ── 礼品盒 ───────────────────────────────────────────
  "giftPictures": [ /* 同结构 */ ],
  "giftSpecialtys": [ {"item_id": 3014, "count": 1} ],

  // ── 特产 / 纪念品 ────────────────────────────────────
  "specialtys": [ {"item_id": 3000, "count": 1} ],   // 已进家里的（不算礼品盒）
  "collections": [ 12, 5 ],                          // 已获得的 Collection id（evt_value[4] 用）

  // ── 笔记 ─────────────────────────────────────────────
  "notes": [ {"id": 1000, "read": 0, "timestamp": 1789000000} ],

  // ── 行李 / 桌子（沿用现有 state.items） ───────────────
  "items": {
    "house": [ {"item_id": 0, "count": 3} ],
    "bag":  [-1,-1,-1,-1],                           // [便当, 护身符, 道具, 道具]
    "desk": [-1,-1,-1,-1,-1,-1,-1,-1],               // [便当,便当, 护身符,护身符, 道具×4]
    "bagCompleted": 0, "bagConflict": 0, "deskConflict": 0
  },

  // ── 当前这一趟旅行带了什么（供回家结算） ──────────────
  "travel": {
    "departAt": 0, "returnAt": 0, "nextDepartAt": 0, "tripCount": 0,
    "carried": { "lunch": 2, "amulet": 1000, "tools": [2001], "goal": 1 }
  }
}
```

要点：

* **`id` 与 `pic_id` 是两个不同的东西**，必须都存。`id` 唯一（客户端所有操作用它），`pic_id` 决定画面与排序。
* `layers` 在出门时就该算好并落盘（每次读盘不必重算）。
* `newPictures` 与 `pictures` 分开存 —— `album_save_new` / `album_delete_new` 的语义就是在这两个池之间搬。
* `album_load_all` 只需 `id_list`（`{id,pic_id,for_ads,visit}`），`layers` 可以省（客户端再按页补）。

---

## 10. 不确定 / 必须实测的清单

| # | 事项 | 现状 | 建议验证方式 |
|---|---|---|---|
| 1 | **`layers` 的坐标**：背景是否 (0,0)、青蛙立绘 resId 怎么取 | 客户端只渲染不合成（§3.3）；`resources.json` 353/1268 张是 500×350 | 用 §3.3 方案生成全 349 张，`album_load_all` 推进真客户端，逐张截图人眼/视觉模型判定 |
| 2 | `rnd_*` 令牌（`rnd_sea`/`rnd_mou_back`/`rnd_pose_*`）如何解析成具体 resId | `resources.json` 查不到 | 需要一张手工映射或"同前缀随机"；先跳过含 `rnd_` 的图验证其余 |
| 3 | 相册容量 | 客户端无常量；GM `full_album` 用 180 | 取 180（依据 @662314），做成可配 |
| 4 | 礼品盒照片/特产容量（errcode 100/102） | 客户端无常量 | 先取一个能用的小值并做成可配；用 `travel_gift_to_album` 回 101 以外**不要**回错码 |
| 5 | 回收站容量与保留策略 | `PictureRecover` 只显示 6 个 | 建议固定上限 6，超出丢最旧 |
| 6 | 明信片是走 `album_load_new` 还是 `NewPicture` 邮件 | 两条路都在客户端存在（§3.4） | 先只做 `album_load_new`（横幅路径），邮件后补 |
| 7 | `evt_value[4]` = Collection id（**不是明信片**） | 已由 `ModalSpeciality` 证明 | 若引擎现在按"明信片 id"填，回家弹窗会显示错误图/空图 |
| 8 | `travel_read_note` 的 `id` 是数组 | 客户端 `sendReadNote` 传数组 | 用 `data.id` 可能是数组的写法处理 |
| 9 | `client_load_events` 回包必须是**裸数组** | `Array.isArray(e)` | 核引擎现有实现 |
| 10 | 便当/护身符/道具 → 目的地/时长/带回物的**具体系数** | 无客户端依据，只有文案与公开资料 | 先按 §8.3 的 [推测] 实现，做成表驱动，后续调 |
| 11 | 是否有"不带便当就出门"的原版行为 | 客户端文案「请准备便当」/「快把便当准备好吧」，但没有强约束代码 | 建议：**允许空手出门**（否则离线玩家容易卡住），只是奖励差 |
| 12 | 行李消耗后是否要推 `item_load_items` | 客户端不会自己清 | **建议推**（否则行李格永远显示有货） |

---

## 11. 附：怎么把 `config.eab` 解出来（本次新打通，值得记一笔）

`resource/China/eab/config.eab` 是 **XXTEA 加密**的（魔数第 7 字节是 `0x1b` 而不是 `0x1a`，整体熵 7.9999），
官方服务端关服并不影响我们读它 —— **解密逻辑就在客户端里**：

依据：`eab.decode`（`@231700` 附近，`_dumps/se2.txt`）：

```js
var i = [137,69,65,66,13,10,26,10], n = [137,69,65,66,13,10,27,10], r = 4;
function t(e) {
  var t = new Uint8Array(e, 0, i.length),
      o = t[0]==i[0] && ... && (t[6]==i[6] || t[6]==n[6]) && t[7]==i[7];
  if (!o) return void console.warn("not eab");
  var a;
  if (t[6] == n[6]) {                                     // 加密分支
    var s = xxtea.decrypt(new Uint8Array(e, i.length), Utils.simpleEncrypt("r]|lnf\x80X\x81U\x82aq_r", 13));
    e = s.buffer, a = new DataView(e, 0, r)
  } else a = new DataView(e, i.length, r);
  var c = a.getUint32(0, !0),                              // 索引长度 u32 LE
      l = new Uint8Array(e, a.byteOffset + a.byteLength, c),
      h = Utf8ArrayToStr(l), u = JSON.parse(h),
      p = e.slice(l.byteOffset + l.byteLength);            // 各条目负载
  return { config: u, raw: p }
}
```

密钥生成（`Utils.simpleEncrypt`，函数名 `k`，`@301862`）：

```js
function k(e, t) {                       // t 默认 13
  void 0 === t && (t = 13);
  for (var i, n = 0, r = new Array, o = 0; o < e.length; o++)
    i = e.charCodeAt(o),
    o % 2 == 0 ? (n = i - t, r[o] = String.fromCharCode(n))
               : (n = i + t, r[o] = String.fromCharCode(n));
  return r.join("")
}
```

明文密钥字面量（15 个字符，码点）：
`[114,93,124,108,110,102,128,88,129,85,130,97,113,95,114]` → `r]|lnf<0x80>X<0x81>U<0x82>aq_r`

XXTEA 实现细节（`@227568` 附近的 `xxtea` IIFE，`_dumps/xxtea_core.txt`）—— **两个容易踩的点**：

1. **小端**打包（`r[o>>2] |= e[o] << ((3&o)<<3)`），不是常见的**大端**标准实现。
2. 密钥不足 16 字节会被**零填充到 16**（`function r(e){ if (e.length<16){ var t=new Uint8Array(16); t.set(e); e=t } return e }`）。
3. 解密后的最后一个 u32 是**原字节长度**（`t(v, true)`）。

本次已按此写出可运行的 Python 解密器：
`work/spec/_dumps/eabdec.py`（含 `simple_encrypt` / `xxtea_decrypt` / `decode`）
和 `work/spec/_dumps/extract_tables.py`（把 config.eab 的 60 张表全部导出到 `work/spec/_dumps/tables/`）。

实测输出：

```
config.eab: 1765824 bytes -> 1765812 plain bytes, 60 entries, data at 4978
   Note_json        off=220614   size=50607
   Picture_json     off=311367   size=247642
   Collection_json  off=33375    size=29206
   Item_json        off=65795    size=154411
   Specialty_json   off=564101   size=6140
   resources_json   off=1545501  size=49514
   ...
```

> **对引擎的意义**：`engine/data/gamedata.json` 现在只有 id 列表（`extract_gamedata.py` 从 `?dumpdb=1` 抠的），
> 拿不到 `layers` 所需的图层名/资源路径。而 `config.eab` 的解密钥匙**完全在客户端里**，
> 所以这 60 张表可以**离线完整拿到**，不需要真机 dump。建议把 `Picture/Note/Collection/Specialty/Item/resources/GoalNumber`
> 这 7 张表（共约 590 KB JSON）做成引擎的数据文件，替换现在残缺的 `gamedata.json`。

---

## 12. 本轮新增/修改的文件（均在 `work/spec/` 下，未触碰引擎）

* **`work/spec/travel-album.md`** —— 本文
* `work/spec/_dumps/` —— 全部代码片段与数据表
  * `tables/*.json` —— 从 config.eab 解出的 60 张客户端数据表
  * `dr.py`（按**解码偏移**导出）、`eabdec.py`（XXTEA 解密）、`extract_tables.py`、
    `dump_handlers` 输出 `travel.txt`、各类 `dump_class` 输出
  * `tables_summary.txt` / `imgsize.txt` / `errcode.txt` / `zhcn.txt` —— 表结构与文案汇总
