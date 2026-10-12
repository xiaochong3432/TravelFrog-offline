#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""V3.5 客户端补丁：修掉"反复快速点翻页键 -> 商品消失/空白页"。

根因（客户端 main.min.js 里逐字核对，类是 PageGroupScroller —— 分页滚动器，
商店的左右翻页箭头就挂在它的 prevCursor/nextCursor 上）：

    onPrev(){ this.selectedIndex -= 1 }                  // 无下限
    onNext(){ this.selectedIndex += 1 }                  // 无上限、无节流
    getPageScrollH(){
        var e = this.viewport,
            t = Math.min(this.viewport.contentWidth,
                         this.viewport.width * this._curPageIndex + this.offset);
        …
        return t;
    }
    updateCursors(){ nextCursor.visible = this.selectedIndex < this.numPages - 1 }

快速连点 -> `_curPageIndex` 一路超过 `numPages - 1` -> `getPageScrollH()` 取到
`contentWidth`（内容尾部之外）-> 视口停在内容右边之外 = **整页空白**；
同时 `updateCursors()` 因越界把 next 箭头藏起来，玩家连点回不去，只能退出商店重进
（视图重建、页码归零）—— 与反馈完全一致。

修法（三处夹取，都不改变正常翻页手感）：
  1. `onPrev/onNext` 把页码夹在 [0, numPages-1]；
  2. `getPageScrollH()` 把滚动位置夹在 [0, max(0, contentWidth - viewport.width)]，
     这样即使页码因为数据变化而超出范围，也永远滚不出内容；
  3. 同类的 `PageGroup`（另一套分页组件）与 `PageCursorsBar`（带 300ms 节流的滚动箭头）
     同样夹取，避免同一个坑在别的商店复现。

幂等：靠 V35-PAGING-FIX 标记判断是否已打过。
"""
import pathlib
import sys

sys.stdout.reconfigure(encoding="utf-8")
ROOT = pathlib.Path(__file__).resolve().parents[2]
CLIENT = ROOT / "work/build/v4_client/main.min.js"

t = CLIENT.read_text(encoding="utf-8", errors="surrogateescape")
if "/*V35-PAGING-FIX*/" in t:
    print("客户端已经打过翻页修复，跳过")
    sys.exit(0)

edits = [
    # ---- PageGroupScroller：页码夹取 ----
    ("PageGroupScroller.onNext",
     "t.prototype.onNext=function(){this.selectedIndex+=1}",
     "t.prototype.onNext=function(){/*V35-PAGING-FIX*/this.selectedIndex=Math.min(this.selectedIndex+1,Math.max(0,this.numPages-1))}"),
    ("PageGroupScroller.onPrev",
     "t.prototype.onPrev=function(){this.selectedIndex-=1}",
     "t.prototype.onPrev=function(){/*V35-PAGING-FIX*/this.selectedIndex=Math.max(0,this.selectedIndex-1)}"),
    # ---- PageGroupScroller：滚动位置夹取（永远滚不出内容）----
    ("PageGroupScroller.getPageScrollH",
     "return e instanceof eui.Group&&e.layout.horizontalGap&&(t+=e.layout.horizontalGap*this._curPageIndex),t}",
     "e instanceof eui.Group&&e.layout.horizontalGap&&(t+=e.layout.horizontalGap*this._curPageIndex);"
     "/*V35-PAGING-FIX*/var i=Math.max(0,this.viewport.contentWidth-this.viewport.width);"
     "return Math.max(0,Math.min(i,t))}"),
    # ---- PageGroup：另一套分页组件，同样夹取 ----
    ("PageGroup.onPrev",
     "t.prototype.onPrev=function(){this.curPageIndex-=1}",
     "t.prototype.onPrev=function(){/*V35-PAGING-FIX*/this.curPageIndex=Math.max(0,this.curPageIndex-1)}"),
    ("PageGroup.onNext",
     "t.prototype.onNext=function(){this.curPageIndex+=1}",
     "t.prototype.onNext=function(){/*V35-PAGING-FIX*/this.curPageIndex=Math.min(this.curPageIndex+1,Math.max(0,this.numPages-1))}"),
    # ---- PageCursorsBar：滚动箭头，步进后夹取（t = contentWidth, i = viewport.width 已在作用域内）----
    ("PageCursorsBar.onNext",
     "t>=e+2*i&&(this.viewport.scrollH+=this.viewport.parent.width)",
     "t>=e+2*i&&(this.viewport.scrollH=Math.max(0,Math.min(t-i,"
     "/*V35-PAGING-FIX*/this.viewport.scrollH+this.viewport.parent.width)))"),
    ("PageCursorsBar.onPrev",
     "(this.viewport.scrollH-=this.viewport.parent.width)",
     "(/*V35-PAGING-FIX*/this.viewport.scrollH=Math.max(0,this.viewport.scrollH-this.viewport.parent.width))"),
]

for name, old, new in edits:
    n = t.count(old)
    # PageGroup 在客户端里有两份同样的实现（两个脚本各自定义了一次），两处都要夹取
    allow = 2 if name.startswith("PageGroup.") else 1
    if n not in (1, allow):
        sys.exit("锚点【%s】出现 %d 次（应为 1%s）" % (name, n, (" 或 %d" % allow) if allow > 1 else ""))
    t = t.replace(old, new)
    print("已补：%s（%d 处）" % (name, n))

CLIENT.write_text(t, encoding="utf-8", errors="surrogateescape", newline="")
print("写出 %s（%d 字节）" % (CLIENT.relative_to(ROOT), len(t.encode("utf-8", "surrogateescape"))))
