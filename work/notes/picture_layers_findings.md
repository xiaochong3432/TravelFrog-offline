# 相册明信片图层摆位核查（"小青蛙有时飞在天上"）

核查时间：2026-09-12　工作目录 `H:\AI\frog`
**未修改任何发行物**：`dist/**`、`work/run/engine/index.js`、`work/tools/build_picture_layers.py`、
`work/run/engine/data/picture-layers.json`、`work/run/web/js/main.min.js.clean` 全部原样。
新增物只在 `work/probe/`、`work/shots/`、`work/notes/`。

> 注意：核查期间 `work/run/engine/index.js` 的 mtime/大小被**另一个进程**
> （`node work\tools\engine_test.js`，同一台机器上的并发任务）改动过（336748 → 349566 字节）。
> 下面的行号是改动后的最新行号；引用时请以文中给出的代码原文为准。

---

## 0. 结论速览

| 项 | 结论 |
|---|---|
| 反馈是否属实 | **属实**（可复现，有真页面数值证据） |
| 现象 | 明信片上"小青蛙"这一层（pose 层）的 y 比正确位置**高约 175 − 精灵高度 px**（典型 105~125 px），x 比正确位置**偏右半个精灵宽度**；同时**所有景物层都被钉在 (0,0)**，导致地面/屋顶/海面等横带跑到画面顶部 |
| 根因 | `work/tools/build_picture_layers.py` 的**摆位重建规则错了**：①景物一律 `(view.x, view.y)`＝(0,0)；②pose 用 `(250+frogPos, 175+frogPos)` 当**左上角**，而官方锚点是**底边中点**、参考线是**画布底边(350)** |
| 官方对照 | 用游戏自带的**照片动图 spine**（`animpictureData.json` → `resource/China/animation/gif_photo/gif_{1,2,3}`）恢复出来的官方摆位，与我们的输出逐层对不上 |
| 是否需要改引擎 | 不需要（`index.js` 只是转发 `picture-layers.json`）；改动集中在生成脚本 |

---

## 1. 客户端契约（先钉死坐标系，其余结论都建立在它上面）

`work/run/web/js/main.min.js.clean`，照片渲染模块（`__reflect(AnmData...)` 之后紧跟的
`var Tabikaeru; !function(e){...}` 块，偏移 ≈401233）：

```js
function t(t){var i=e.DataManager.instance().ResourcesDB[t.toString()];
  return i||(core.Log.warning("照片资源配置表 resources_json 中未找到 ID："+t+" 的图片路径"),
  i=e.DataManager.instance().ResourcesDB[1]),i}                       // resId -> 资源路径
function a(e){var t=e.lastIndexOf("/"),i=e.length,n=e.slice(t+1,i);return n+"_png"}  // 取 basename + "_png"
function r(e,i){ void 0===i&&(i=1);
  for(var n="",r=0,o=e.layers;r<o.length;r++){var l=o[r];
     n+=l.layer[0].toString()+l.layer[1].toString()+l.layer[2].toString()}   // 缓存 key 只用 layer[0..2]
  var h,u=c[n];
  if(u)h=u.texture,u.count++;
  else{ Utils.FpsManager.instance().boost(); var p=s; p.removeChildren();
    for(var d=0,g=e.layers;d<g.length;d++){ var f=g[d], v=new egret.Bitmap,
        _=RES.getRes(a(t(f.layer[0])));
      if(null==_)return null;                       // 任一贴图缺失 => 整张照片渲染失败(返回 null)
      v.texture=_; v.x=f.layer[1]; v.y=f.layer[2];  // ★ 左上角坐标，无 anchor/scale/rotation
      p.addChild(v) }
    h=new egret.RenderTexture,
    h.drawToTexture(p,new egret.Rectangle(0,0,500,350),i),   // ★ 视口固定 500x350
    1==i&&(u=c[n]={name:n,texture:h,count:1}), ... }
  return h }
e.getPicturePath=t, e.loadPicture=i; e.renderPicture=n, e.getPictureTexture=r;
```

由此确定的字段约定（**证据级**）：

* layer 条目形状 = `{"layer":[resId, x, y]}`，另有一个可选 `scale`。
  **`scale` 在相册渲染路径里根本没被读**（缓存 key 只拼 `layer[0..2]`，绘制用 `layer[1]/layer[2]`）。
  它只在"不倒翁/玻璃球"那条路径里被读（`TumblerLoader.createTexture` 里的 `e.layers[o].layer[3]`/`layer[4]`，
  偏移 ≈902399，那是另一个 `layer[]` 结构）。→ 我们在 `picture-layers.json` 里发的 `"scale":1` 是**无效字段**。
* `x`,`y` = 该贴图**左上角**在 **500×350 画布**里的坐标（`drawToTexture` 的 clipBounds 恒为 `(0,0,500,350)`）。
  没有 anchor、没有 z 序字段；**数组顺序 = 绘制顺序**。
* `ALBUM_SIZE_X=500 / ALBUM_SIZE_Y=350`（`work/run/engine/data/define.json`，见 `work/album-facts.txt`）。
* `resId` 必须是 `resources.json` 的真实键，否则静默回退到 `ResourcesDB[1]`。

真页面复核（见 §5）拿到了同样的 rect：客户端自己调的是
`drawToTexture(container, Rectangle(0,0,500,350), 2)`。

---

## 2. 我们的生成脚本到底做了什么

`work/tools/build_picture_layers.py`：

* `L290-295`：**所有** `backImage` 条目
  ```python
  vx = (row.get('view') or {}).get('x', 0) or 0
  vy = (row.get('view') or {}).get('y', 0) or 0
  for n in (row.get('backImage') or []):
      if not emit(n, vx, vy, ptype):        # emit() = layers.append({'layer':[rid, x, y]})
  ```
  而 `Picture.json` 里 **`view` 在全部 351 行都是 `{"x":0,"y":0}`**（实测：min=p25=med=p75=max=0）。
  ⇒ 每一层的景物都被写到 **(0,0)**。
* `L273-275 / L311-314`：pose 摆位
  ```python
  POSE_OX = int(os.environ.get('POSE_OX', '250'))
  POSE_OY = int(os.environ.get('POSE_OY', '175'))
  ...
  layers.append({'layer': [int(rid), int(pos.get('x',0)+POSE_OX), int(pos.get('y',0)+POSE_OY)], 'scale': POSE_SCALE})
  ```
  即 **左上角 = (250+frogPos.x, 175+frogPos.y)**，175 被当作"画布竖向中心"。

`work/tools/build_picture_layers.py` L261-272 的注释自述了推导过程：
> "y spans only -75..-94 ... With the centre at 175 the frog lands at y 81..95, ON the scene's own
> geometry (tree/roof/ground), which is what a visual check of rendered output confirms."

**这句话正是错误的闭环**：景物同时也被压到了顶部，所以"青蛙落在景物上"这个目视结论只是在错误构图上自洽。

---

## 3. 官方对照数据从哪来（关键证据来源）

`work/run/engine/data/tables/animpictureData.json`（游戏自带表，"把明信片做成动图"功能）：

```json
{"base_info":{"album_id":9002,"album_num":4,"page_id":9001},
 "list":{"1":{"phase_list":[{"layer":1,...},{"layer":2,"spine":"gif_1_bg1"},...],"pic_list":[100]},
         "2":{...,"pic_list":[104]},
         "3":{...,"pic_list":[2000]}},
 "pic_map":{"100":1,"104":2,"2000":3}}
```

这张表把 **Picture 行 → 一套 spine 动图**。而 spine 里的 slot 名字**和 Picture 表的画名完全一致**，
所以它就是官方对**同一批素材、同一个 500×350 相框**的摆位。以图 104 为例：

* `Picture.json` 图 104 `back_n_beach3`：`backImage=["sky04","rnd_sea","rnd_mou_back","flower01","earth"]`，`frontImage=["flower02"]`
* `gif_2_bg1` 的 slot：`sky04` / `sea01` / `mou_back01` / `flower01` / `earth`
* `gif_2_fg1` 的 slot：`flower02` / `flower03` / `flower04` / `flower05`

**逐名对上**，`rnd_sea`/`rnd_mou_back` 正是被官方 roll 成了 `sea01`/`mou_back01`。
`gif_2_bg1.atlas` 里 `sea01` 的 `orig: 500, 164`，与相册素材 `sea01`（500×164）**完全一样**，
`mou_back01 orig 999x38` 与我们 `mou_back01`（500×38）**高度一致**，`flower01 orig 1626x158`
与我们 `flower01`（806×158）**高度一致** —— 只有横向被拉宽，**纵向摆位可以 1:1 搬过来**。

坐标系换算（每条都用"自明"用例校验过）：

* `screen_y = -y_spine`（图 104 的 `sky04` mesh 顶点恰好铺满 `x 0.01..500.01 / y 0.01..350.01`；
  图 100 的 `bg`（502×352）区域中心正好是 spine 坐标 `(249.99, -175.03)`＝画框正中；
  反向读数会把 `earth` 放到画面顶部、`sky` 放到画面底部，显然错）
* region 附件的 `x,y` 是**区域中心**（由上面 `bg` 的中心恰为 (250,175) 定出）
* mesh 附件的顶点是**骨骼局部坐标**，加骨骼世界坐标后同上翻转

---

## 4. 官方摆位 vs 我们的输出（`python work/probe/official_layout_probe.py`）

### 图 104 `back_n_beach3`（gif_2，逐名同素材 → 直接可比）

| 素材 | 官方 y（左上角） | 我们发的 y | 差 |
|---|---|---|---|
| `sky04`（mesh 500×350） | **0.01** | 0 | ✓ |
| `mou_back01`（38 高） | **76.25** | *（层被丢弃，见 §6.2）* | — |
| `sea01`（164 高） | **98.75** | 0（且我们 roll 成了 `sea02`） | −99 |
| `flower01`（158 高） | **106.36** | 0 | −106 |
| `earth`（地面，106 高） | **244.63**（底边 350.6） | **0**（0..88） | **−245** |
| 青蛙 `role_qw`（root=脚底中点） | 脚底 **(189.7, 276.3)** | 左上角 **(380, 95)** → 脚底 ≈141 | **−135** |

### 图 100 `back_n_roof1`（gif_1 是重绘版，但横带结构可比）

| 元素 | 官方 | 我们 |
|---|---|---|
| 满屏背景 `bg`（502×352） | 中心 (249.99, 175.03)＝画面正中 | `sky05`(0,0) ✓ |
| 远山带 `shan`（502×86） | y **218.88** | `mou_back03` y **0** |
| 屋顶带 `zg_1`（500×83） | y **268.50**（底边 351.1） | `roof01` y **0** |
| 青蛙角色 spine root | **(349.63, 274.29)** | 左上角 (349, 95) |

**注意 x=349 vs 349.63：几乎完全一致。** 官方 root 是"脚底中点"，所以
`(250 + frogPos.x, 350 + frogPos.y)` 就是青蛙的**脚底中点**：

| 图 | `frogPos` | 预测脚底 (250+x, 350+y) | spine root 实测 | Δ |
|---|---|---|---|---|
| 100 | (99, −80) | (349, 270) | (349.63, 274.29) | (0.6, **4.3**) |
| 104 | (130, −80) | (380, 270) | (189.66, 276.27) | (190.3*, **6.3**) |
| 2000 | (−86, −75) | (164, 275) | (162.67, 269.93) | (**1.3**, **5.1**) |

\* 图 104 的 x 不可比：`gif_2_role_qw` 是**走路动画**（有 `qw-foot` 骨骼、`gif_2_bg1` 骨架宽 2058
的横向卷轴），root 会随动画平移；图 100/2000 都是静止姿势，x 误差 ≤1.3 px。

**y 三项全部命中（误差 4.3/6.3/5.1 px，差异量级＝精灵自带透明边距），结论：
官方锚点 = 精灵"底边中点"，参考点 = (画布横向中心 250, 画布底边 350)。**

第 4 条独立佐证（不依赖 GIF）：**"整张画布"级别的 pose 精灵**。
`frogPos=(0,0)` 时官方公式给出的左上角恰好是 `(250−w/2, 350−h)`：

* 图 2098/2099/2100/2101…（`anhui1` 等 9 张 Goal）：pose 素材 **500×350**，官方锚点 → **(0, 0)**，
  正好铺满相框；我们的锚点 → **(250,175)**，只有右下 1/4 可见（可见率 0.25）。
* 图 205/3203/3204/3205：pose 素材 `mumianhua_pose_qw` **445×238**，`frogPos=(−28,1)`，官方
  → 左上角 **(−0.5, 113)**，精灵占 `x −0.5..444.5 / y 113..351`，**几乎完美贴合相框**；
  我们的锚点 → **(222,176)**，精灵落到 `x 222..667 / y 176..414`，**54% 被裁掉**。
  445/2=222.5 与 frogPos.x=−28 凑出左上角 −0.5——这不是巧合。

统计（`work/probe` 里的一次性统计脚本）：我们的锚点下 **200 个 pose 层里有 35 个**超出 500×350 相框；
官方锚点下只剩 18 个（且大多只溢出个位数像素）。

### 我们的青蛙 y 分布（n=200）

`min=13  p25=54  med=79  p75=126  max=286` —— **175/200 落在画面上半部，125/200 落在上 1/3**，
而官方脚底线在 270 附近。这就是"飞在天上"的量化含义。

---

## 5. 真页面 / 真实客户端复核（数值证据）

静态服务器：`work/run/web` 下 `python -m http.server 8186 --bind 127.0.0.1`（后台任务，已杀）。
驱动：`node work/tools/cdp_drive.js --url http://127.0.0.1:8186/index.html --port 9244
--profile work/shots/p-photo3 --fresh --wait 26000 --settle 2000
--step in:work/probe/layers_live_probe.js --step shot:work/shots/p-photo-album-layers.png`

探针 `work/probe/layers_live_probe.js` 钩住 `egret.RenderTexture.prototype.drawToTexture`
（正是客户端相册渲染唯一的那次调用），记录它拿到的容器的子对象（x/y/w/h）后再放行；
数据来自页面内引擎 `window.__engine.dispatch('album_load',{start:1})`（即服务端真实 payload），
渲染则调用客户端自己的 `Tabikaeru.loadPicture(pic)` + `Tabikaeru.getPictureTexture(pic,2)`。

实测输出（原样摘录，已截断到关键字段）：

```json
"layersFromEngine":{
 "100":[{"layer":[1,0,0]},{"layer":[2,0,0]},{"layer":[5,0,0]},{"layer":[6,0,0]},
        {"layer":[8,0,0]},{"layer":[7,0,0]},{"layer":[11,0,0]},{"layer":[190,349,95],"scale":1}],
 "104":[{"layer":[14,0,0]},{"layer":[16,0,0]},{"layer":[22,0,0]},{"layer":[390,0,0]},
        {"layer":[193,380,95],"scale":1},{"layer":[23,0,0]}],
 "205":[{"layer":[1064,0,0]},{"layer":[1068,0,0]},{"layer":[1072,222,176],"scale":1}],
 "2134":[{"layer":[1097,0,0]},{"layer":[1098,197,13],"scale":1}]},
"clientDraw":{
 "100":{"gotTexture":true,"rect":[0,0,500,350],"kids":[
     {"x":0,"y":0,"w":500,"h":363},{"x":0,"y":0,"w":521,"h":323},{"x":0,"y":0,"w":209,"h":118},
     {"x":0,"y":0,"w":500,"h":93},{"x":0,"y":0,"w":412,"h":224},{"x":0,"y":0,"w":421,"h":228},
     {"x":0,"y":0,"w":1254,"h":81},{"x":349,"y":95,"w":76,"h":61}]},
 "104":{"gotTexture":true,"rect":[0,0,500,350],"kids":[
     {"x":0,"y":0,"w":500,"h":341},{"x":0,"y":0,"w":500,"h":183},{"x":0,"y":0,"w":806,"h":158},
     {"x":0,"y":0,"w":500,"h":88},{"x":380,"y":95,"w":70,"h":46},{"x":0,"y":0,"w":500,"h":177}]},
 "205":{"gotTexture":true,"rect":[0,0,500,350],"kids":[
     {"x":0,"y":0,"w":500,"h":1000},{"x":0,"y":0,"w":500,"h":1000},{"x":222,"y":176,"w":445,"h":238}]},
 "2134":{"gotTexture":true,"rect":[0,0,500,350],"kids":[
     {"x":0,"y":0,"w":500,"h":350},{"x":197,"y":13,"w":18,"h":15}]}}}
```

这组数字本身就证明了：
1. 视口 rect 恒为 `(0,0,500,350)` → 坐标系确认；
2. **所有景物层 x=y=0**，包括 `roof01`（1254×81，实际只有左边 500px 可见、且贴在画面**顶部**）、
   `earth`（500×88，地面带贴着顶部）、`mumianhua_back`（500×1000，只露出最上面 350px ＝ 35%）；
3. 青蛙层被客户端摆在了 `(349,95)` / `(380,95)` / `(222,176)` / `(197,13)` —— 就是 JSON 里的值，
   客户端没有做任何修正；
4. 图 205 的 445×238 精灵按我们的坐标有 54% 落在 clip rect 之外。

`exceptions : 0 / page errors: 0`，截图 `work/shots/p-photo-album-layers.png`。

补充渲染对照（离线按客户端语义合成，`work/probe/render_layers_probe.py` /
`work/probe/compare_layout_probe.py`）：

* `work/probe/layers_render_lowy.png`（青蛙 y 最小的 16 张）——视觉复核逐格给出
  "floating in mid-air / in the sky with nothing under it"，与反馈一致；
* `work/probe/compare_104.png`：D 格（官方景物 y + 我们的青蛙层）就是玩家说的
  "青蛙飞在天上"；B 格（官方摆位）青蛙站在地面/花丛里；A 格（现状）下半张画面是空的天空、
  青蛙埋在花带里看不清。

---

## 6. 附带发现的另外两个缺陷（同类：摆位/解析重建不完整）

### 6.1 超过 500×350 的景物素材一律按 (0,0) 摆 → 大面积被裁

统计（非 pose 层 480 个）：**82 个（17%）的素材尺寸大于相框**。典型：

| 素材 | 尺寸 | 用在 | (0,0) 的后果 |
|---|---|---|---|
| `Picture/Normal/mumianhua_back` | 500×**1000** | 205,3203,3204,3205 | 只显示最上面 35%，很可能是天空 |
| `Picture/Normal/mumianhua_mid` | 500×**1000** | 205 | 同上 |
| `Picture/Normal/panda` / `leaf_05` | 500×**933** | 115 | 同上 |
| `Picture/Normal/ibis` | 500×**850** | 126 | 同上 |
| `Picture/Normal/rain` | **1000**×500 | 108 | 只显示左半 |
| `Picture/Normal/leaf_03/leaf_04` | 893×549 | 111..114 | 右边+下边被裁 |
| `roof01` | 1254×81 | 100,101 | 只显示左边 500，且贴在顶部 |

官方对 `earth`/`zg_1`/`shidun` 这三个**地面/前景横带**都是"底边贴画框底边"
（实测底边 y = 350.6 / 351.1 / 351.0）；我们的做法让它们跑到顶部。

### 6.2 `rnd_mou_back` 解析失败 → 整层丢失

`work/probe/_bpl_readonly.py`（`build_picture_layers.py` 的只读副本，输出重定向到
`work/probe/_layers_probe_out.json`，**不碰 run/**）报告：

```
unresolved art names      : 35 occurrences
  distinct unresolved     : 18
    pose_* (needs pose family)   24
    back_g_* (city bg)           8
    rnd_* (random family)        2
      ...
      rnd_mou_back                   x2
```

原因：`build_picture_layers.py` 的 `family` 只登记"去掉最后一个 token"的别名
（`L119-121`：`parts[:-1]`），于是 `mou_back01` 登记在键 `mou` 下，而 `lookup_art('rnd_mou_back')`
去掉 `rnd_` 后要找的键是 `mouback` → 找不到 → 放弃。结果图 103/104 的**远山层整层消失**
（官方 `gif_2_bg1` 里 `mou_back01` 在 y=76.25）。

---

## 7. 修法建议（**补丁建议，未落盘**）

### 7.1 主修：pose 锚点（`work/tools/build_picture_layers.py`）

把 `L261-275` 那段常量与 `L290-350` 的三处摆位改成"底边中点"语义。

**新增**（建议插在 `lookup_art` 之后、`SCENERY` 之前）：

```python
# ---- 素材实际像素尺寸（pose 锚点需要） ------------------------------------
IMGDIR = os.path.join(ROOT, 'web', 'resource', 'China', 'images')
_size_cache = {}


def art_size(rid):
    """shipped PNG 的 (w, h)；找不到返回 None。"""
    if rid in _size_cache:
        return _size_cache[rid]
    p = RES.get(str(rid))
    fp = os.path.join(IMGDIR, p + '.png') if p else None
    sz = None
    if fp and os.path.exists(fp):
        with open(fp, 'rb') as fh:
            head = fh.read(24)
        if head[:8] == b'\x89PNG\r\n\x1a\n':
            sz = (int.from_bytes(head[16:20], 'big'),
                  int.from_bytes(head[20:24], 'big'))
    _size_cache[rid] = sz
    return sz


# POSE ANCHOR -- recovered from the game's own photograph-gif spines
# (animpictureData.pic_map {100:1,104:2,2000:3} -> resource/China/animation/gif_photo).
# The role skeleton's root bone is the sprite's BOTTOM-CENTRE and its screen
# position equals (250 + frogPos.x, 350 + frogPos.y):
#   pic 100  predicted (349, 270)   spine root (349.63, 274.29)
#   pic 2000 predicted (164, 275)   spine root (162.67, 269.93)
# (pic 104's gif is a walk cycle so its x is not comparable; y matched to 6.3px.)
POSE_ANCHOR_X = int(os.environ.get('POSE_ANCHOR_X', '250'))   # 画布横向中心
POSE_ANCHOR_Y = int(os.environ.get('POSE_ANCHOR_Y', '350'))   # 画布底边


def pose_xy(rid, pos):
    """pose 精灵的左上角：锚点(底边中点) - (w/2, h)。"""
    sz = art_size(rid)
    w, h = sz if sz else (0, 0)
    return (int(round(POSE_ANCHOR_X + (pos.get('x') or 0) - w / 2.0)),
            int(round(POSE_ANCHOR_Y + (pos.get('y') or 0) - h)))
```

**替换**三处（`L311-314`、`L324-327`、`L346-348`）的
`int(pos.get('x',0)+POSE_OX), int(pos.get('y',0)+POSE_OY)`
为 `*pose_xy(rid, pos)` / `*pose_xy(rid, p)`；`'scale'` 键可以顺手删掉（客户端不读，见 §1），
留下也无害。

预期效果：图 100 青蛙左上角 95 → **209**（脚底 270，正好落在官方屋顶带 268.5 上）；
图 104 95 → **224**（脚底 270，落在官方 `earth` 244.6..350.6 里）；
图 205 的 (222,176) → **(−0.5,113)**，445×238 精灵不再被裁；
9 张用 500×350 pose 素材的 Goal 明信片的 pose 层回到 (0,0)。

**已知残留（必须实测确认，不要盲信）**：`frogPos.y > 0` 的 16 行按"底边参考"会伸出画框下沿，
其中 5 行很严重（`1012-1015 Town*` y=111 → 顶端 389~395；`2012 beijing4` y=101 → 383；
`2084/2097 ningxia1/6` y≈31 → 363）。这 5~7 行的 `frogPos` 可能不是同一套参考，
或游戏本身就把它们裁掉。建议先只改 pose、只对这 16 行做例外表（走 `POSE_ANCHOR_Y` 环境变量
或一张显式 override 表），再逐张目视确认。

### 7.2 主修：景物 y（同一文件 `L290-295`）

我们把 `view` 当摆放参数，但 `view` 全表恒为 (0,0)，它**不是**摆放参数。
官方 y 需要另外的来源。已经从官方数据里**确证**的三条规则（3/3 场景一致）：

```python
# SCENERY y.  All scenery is currently emitted at (view.x, view.y) == (0,0), but
# `view` is {x:0,y:0} in ALL 351 rows -- it carries no placement.  Recovered from
# the gif spines (see notes §3): full-canvas backdrops really are (0,0), while the
# GROUND/FOREGROUND bands are BOTTOM-aligned to the frame:
#   gif_2 earth   bottom = 350.62 ;  gif_1 zg_1 (roof) bottom = 351.13 ;
#   gif_3 shidun  bottom = 351.00
BOTTOM_BAND = re.compile(
    r'^(earth|soil|ground|dimian|rail|road|roof|lu\d*|wood|flower\d*|sea\d*'
    r'|wheat|field|stone|shizi|pipa_fore|tulou|leaf_\d+)', re.I)


def scenery_xy(rid, name, vx, vy):
    """The two placement rules the official data actually shows."""
    sz = art_size(rid)
    if not sz:
        return int(vx), int(vy)
    w, h = sz
    n = name or ''
    if BOTTOM_BAND.match(n) or h > 350:      # 地面/前景横带，以及比画框高的竖向全景
        return int(vx), int(350 - h)         # 底边贴画框底边
    return int(vx), int(vy)                  # 满屏背景/天空等仍是 (0,0)
```

并把 `emit()` 改为 `self` 解析出的 `rid` 后再定坐标：

```python
    def emit(name, x, y, want_type=None):
        rid = lookup_art(name, want_type or ptype)
        if rid is None:
            return False
        cx, cy = scenery_xy(rid, name, x, y)
        layers.append({'layer': [int(rid), int(cx), int(cy)]})
        return True
```

**置信度说明**：这三条规则在能对照的 3 张图上成立，但**不是**全部 351 行的通解——
`shan`（远山带，502×86）在 gif_1 里 y=218.88，既不贴顶也不贴底，属于"中间带"，
目前没有可推广的判据。所以：
* 高置信：地面/前景横带底对齐（3/3）；满屏背景 (0,0)（3/3）；
* 低置信：其余横带。
建议先把 7.1（pose）落地（这一条证据最硬、收益最大），景物那条按上面的规则改了之后
**必须逐张目视复核**（`work/probe/render_layers_probe.py` 出 contact sheet）。

### 7.3 顺手修：`rnd_*` 家族解析（`L119-127`）

```python
    parts = base.split('_')
    # 注册"任意前缀 token 组合"的别名，否则 rnd_mou_back -> 'mouback' 这类
    # 多 token 名字永远匹配不到（family 只登记了 parts[:-1] == 'mou'）。
    for i in range(1, len(parts)):
        fam['_'.join(parts[:i]).lower().replace('_', '')].append(int(rid))
```
替代原来的 `parts[:-1]` 单行（保留 `parts` 本身与 alias 逻辑）。效果：`rnd_mou_back`
解析到 `mou_back0x`，图 103/104 的远山层不再消失。

### 7.4 `work/run/engine/index.js`

**不需要改。** `withLayers()`（`L117-124`）只是原样转发：
```js
function withLayers(p) {
  const rec = pictureLayers[String(p.pic_id)];
  if (!rec) return p;
  const out = Object.assign({}, p, { layers: rec.layers });
  if (rec.travelers) out.travelers = rec.travelers;
  return out;
}
```
`album_load`（现 `L5190`）、`album_load_all`（`L5198`）、`album_load_by_id_list`（`L5233`）
都只是调用它。改完生成脚本、重跑一次生成、重启服务即可。
（唯一要留意的：`travelers` 也走同一套错摆位——图 100 的 3 个旅伴在 JSON 里是
`[190,395,99]/[190,296,95]/[190,292,110]`，修 pose 时会一起被修正。）

---

## 8. 验证方法（修好后怎么证明）

### 8.1 离线数值（最快）

```
python work/probe/official_layout_probe.py      # 打印 gif spine 恢复的官方摆位 vs 我们发的
python work/probe/compare_layout_probe.py 104 work/probe/compare_104.png
```
判据：`compare_104.png` 的 **B 格**（官方摆位）青蛙站在地面/花丛上；
修好之后 **A 格（现状）应当和 B 格基本重合**，而 **D 格（官方景物 + 我们的青蛙）应当变成空**。

### 8.2 逐条硬指标（对图 100/104/2000，官方脚底实测值）

| 图 | 官方脚底 (x, y) | 修好后应满足 |
|---|---|---|
| 100 | (349.63, 274.29) | `frogPose` 精灵的底边中点 ≈ (349, 270)，误差 ≤ 8 px |
| 104 | (?, 276.27) | 青蛙脚底 y ≈ 270，且落在 `earth` 的 244.6..350.6 之间 |
| 2000 | (162.67, 269.93) | 底边中点 ≈ (164, 275) |

另外两条结构性断言：
* 图 2098/2099/2100 的 pose 素材（500×350）坐标必须是 **(0,0)**；
* 图 205 的 `mumianhua_pose_qw`(445×238) 左上角必须 ≈ **(−0.5, 113)**，即
  `x + w ≤ 500` 且 `y + h ≈ 350`。

### 8.3 真页面（必须有）

```
# 后台起静态服务器
cd work/run/web && python -m http.server 8186 --bind 127.0.0.1
# 驱动真页面；探针钩住客户端自己的 drawToTexture，读回每一层的 (x, y)
node work/tools/cdp_drive.js --url http://127.0.0.1:8186/index.html --port 9242 \
  --profile work/shots/p-photo --fresh --wait 26000 --settle 2000 \
  --step in:work/probe/layers_live_probe.js \
  --step shot:work/shots/after-fix.png
# 结束务必杀掉：只杀命令行含 p-photo 的 msedge，以及这个 http.server
```
修好后的验收断言（`clientDraw` 里逐条比对）：

* `rect` 恒为 `[0,0,500,350]`（不变，用来确认坐标系没动）；
* 图 104 的青蛙 `kids` 末项应为 `{x:345, y:224, w:70, h:46}`（＝底边中点 (380,270)）；
  图 100 应为 `{x:311, y:209, w:76, h:61}`；
* 图 205 应为 `{x:-0.5→0/-1, y:113, w:445, h:238}`（`x+w ≈ 445 ≤ 500`，不再溢出）；
* 景物层里凡是名字像地面/前景横带的，其 `y + h` 应 ≈ 350。

### 8.4 视觉复核

`work/probe/render_layers_probe.py out.png <picId...>` 出 contact sheet，
用视觉复核（或人眼）确认：青蛙脚下的像素不是纯天空/空 void，
地面带贴在画面底部而不是顶部。

---

## 9. 本次新增/使用到的文件

新增（全部只读或只写 work/probe、work/notes、work/shots）：

| 文件 | 用途 |
|---|---|
| `work/probe/official_layout_probe.py` | 从 gif spine 恢复官方摆位，逐层对比我们的输出 |
| `work/probe/layers_live_probe.js` | 真页面探针：钩 `drawToTexture`，读客户端实际摆位 |
| `work/probe/compare_layout_probe.py` | 2×2 对照图（现状 / 官方 / 混合），复现"飞在天上" |
| `work/probe/render_layers_probe.py` | 按客户端语义离屏合成 contact sheet |
| `work/probe/layers_stats.py` | 覆盖度/底部空洞统计 |
| `work/probe/frog_support_probe.py` | 青蛙脚下是否有实体支撑的统计 |
| `work/probe/pose_montage_probe.py` / `band_montage_probe.py` | pose / 横带素材目视核对 |
| `work/probe/hunt_layers.js` | 全仓扫描是否存在"官方真实 layers"（结论：没有） |
| `work/probe/_bpl_readonly.py` + `_layers_probe_out.json` | 生成脚本的只读副本，拿它自己的 unresolved 报告（不写 run/） |
| `work/probe/layers_render_*.png` / `compare_*.png` / `*_montage.png` | 证据图 |
| `work/shots/p-photo-album-layers.png` | 真页面截图 |

已确认清理：`http.server 8186` 已杀（`Get-NetTCPConnection -LocalPort 8186 -State Listen` 计数 = 0）；
`msedge` 里命令行含 `p-photo*` 的进程 0 个（用户自己的 msedge 未触碰）。

## 10. 已排除的可能

* **不是客户端问题**：客户端严格按 `layer[1]/layer[2]` 摆左上角，`drawToTexture` 视口固定 500×350，
  真页面实测与 JSON 完全一致（§5）。
* **不是引擎转发问题**：`withLayers` 原样透传（§7.4）。
* **不是 `scale` 字段造成的放大**：相册路径不读 `scale`（§1），我们发 `"scale":1` 也无副作用。
* **本地没有"官方真实 layers"可对照**：全仓扫描 `work/probe/hunt_layers.js` 只找到
  参考包 `Travel-Frog-Offline-Version` 的 `layers:[]` 和客户端类定义，没有官方服务端下发样例。
  本次的官方对照全部来自游戏自带的 gif spine 数据（§3）。
