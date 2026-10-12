#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.5：动态照片「吃坏肚子」修复（必须作为补丁链的一步，否则引擎一重建就丢）。

客户端渲染一张明信片时会**无条件遍历 `pic.layers`**：
    AnimPictureShowPage.updatePic() -> pictureList[t].setData(pic)   // 只对 pic.id > 0 的槽位
      -> PictureItemRender.data -> PictureRender.render(pic)
      -> Tabikaeru.loadPicture(pic) / getPictureTexture(pic)
           function i(e){ if(e){ for (var i="",n=0,r=e.layers; n<r.length; n++){…} } }
           function r(e,i){ for (var n="",r=0,o=e.layers; r<o.length; r++){…} }
`e.layers === undefined` 时读 `.length` 直接抛 TypeError -> Reload.JSError = 吃坏肚子。

而 `animpicture_load` 之前发的是裸行（`exp_pic` / `pic_list[].pictures` 用 `.slice()`）。
玩家路径："开存储槽位 -> 放照片 -> 重启 -> 再打开这张动态照片" 必崩；
只开槽位（槽位是 {id:0}，客户端不会 setData）或重启前把照片取下来都不崩 —— 与反馈一致。

修法：
  ① `withLayers()` 加固成**永远返回 `layers` 数组**（表里没有这张就给 []，官方 7 张空图层
     模板本来就是空白，渲染成空白正好，绝不再抛错）；
  ② `animPayload()` 的 `exp_pic` 与 `pictures` 一律过 `withLayers()`。
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parents[2]
ENGINE = ROOT / "work/build/v4_engine/index.js"

eng = ENGINE.read_bytes().decode("utf-8")
if "AN ALWAYS returns a `layers` ARRAY" in eng:
    print("引擎里已经有动态页 layers 修复，跳过")
    sys.exit(0)

edits = [
    ("withLayers 永远给数组",
     """/** Attach the composed `layers` for a postcard's pic_id. */
function withLayers(p) {
  if (!p) return p;
  const rec = pictureLayers[String(p.pic_id)];
  if (!rec) return p;
  const out = Object.assign({}, p, { layers: rec.layers });
  return out;
}""",
     """/** Attach the composed `layers` for a postcard's pic_id.
 *
 *  ALWAYS returns a `layers` ARRAY, even when the table has no record for that pic_id:
 *  the client composes every card by iterating `pic.layers`
 *  (`Tabikaeru.loadPicture` / `getPictureTexture` both do `for (… r = e.layers; … r.length …)`),
 *  so an undefined `layers` is a hard TypeError -> Reload.JSError ("吃坏肚子").
 *  7 official templates genuinely have empty layer lists; an empty array renders blank,
 *  which is exactly what those are supposed to look like. */
function withLayers(p) {
  if (!p) return p;
  const rec = pictureLayers[String(p.pic_id)];
  const layers = (rec && Array.isArray(rec.layers)) ? rec.layers : [];
  const out = Object.assign({}, p, { layers });
  if (rec && rec.travelers) out.travelers = rec.travelers;
  return out;
}"""),
    ("animPayload 每张照片都过 withLayers",
     """      exp_pic: (A.expPic || []).slice(),""",
     """      exp_pic: (A.expPic || []).map(withLayers),"""),
    ("animPayload 槽位照片同样",
     """        pictures: (p.pictures || []).slice(),""",
     """        pictures: (p.pictures || []).map(withLayers),"""),
]

for name, old, new in edits:
    n = eng.count(old)
    if n != 1:
        sys.exit("引擎锚点【%s】出现 %d 次" % (name, n))
    eng = eng.replace(old, new, 1)
    print("引擎已改：", name)

ENGINE.write_text(eng, encoding="utf-8", newline="")
print("写出 %s（%d 行）" % (ENGINE.relative_to(ROOT), len(eng.split("\n"))))
