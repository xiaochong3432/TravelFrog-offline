#!/usr/bin/env python3
"""Apply the offline-build patches to work/run/web (idempotent, from pristine source).

Always starts from js/main.min.js.clean (extracted straight from base.apk) so the
result is reproducible regardless of how many times this runs.

Patches, all deliberate parts of the offline port:
  1. enterGame gate      - GameConfig.activate is only ever set by a native-SDK
                           lifecycle resume, which does not happen in a browser.
  2. season key clamp    - only season11..season44 bundles ship; the "00" default
                           (before weather data arrives) requests files that do
                           not exist.
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os, sys, shutil

WEB = str(PROJECT_ROOT) + "/work/run/web"
MAIN = os.path.join(WEB, "js", "main.min.js")
CLEAN = MAIN + ".clean"

PATCHES = [
    (
        "merchant updates stock and closes a finished visit",
        'var n=core.Time.getServerTime();this.serverData.shop.start_time<n&&this.serverData.shop.leave_time>n&&',
        'var n=core.Time.getServerTime(),o=core.PageManage.getInstance().getControl(FurnitureShopController,core.ViewLayerType.WindowLayer);'
        'egret.clearTimeout(this.timerShopClose);'
        'if(o){if(!(this.serverData.shop.start_time<n&&this.serverData.shop.leave_time>n)){'
        'core.PageManage.getInstance().removeControl(FurnitureShopController,core.ViewLayerType.WindowLayer);'
        'core.DisplayManage.getInstance().popup(new ModalAlert(_("嘟嘟已经收拾回家了")));'
        '}else if(o.view)o.view.update();}'
        'this.serverData.shop.start_time<n&&this.serverData.shop.leave_time>n&&',
    ),
    (
        "compost data refreshes its own view",
        'this.compostData.compost_list=Utils.convertArray(e.compost_list),this.dispatchEvent(new core.Event(FurnitureEventType.UPDATE_TUMBER))',
        'this.compostData.compost_list=Utils.convertArray(e.compost_list),this.dispatchEvent(new core.Event(FurnitureEventType.UPDATE_COMPOST))',
    ),
    (
        "hidden compost clears its old image",
        't.prototype.update_compost=function(){var e=this.getModel(FurnitureModel).compostData;',
        't.prototype.update_compost=function(){this.compost.source="";var e=this.getModel(FurnitureModel).compostData;',
    ),
    (
        "bag packing checks slot type and inventory",
        't.prototype.setBagData=function(e,t,i){var n=this;if(void 0===t&&(t=-1),this.bagDataList.length>e)',
        't.prototype.setBagData=function(e,t,i){var n=this;void 0===t&&(t=-1);'
        'if(!Number.isInteger(e)||e<0||e>=4)return!1;'
        'if(t!==-1){var q=this.getItemInfo(t);if(!q||q.type!==[0,1,2,2][e]||(this.bagDataList[e]!==t&&this.getHouseItemCount(t)<1))return!1;}'
        'if(this.bagDataList.length>e)',
    ),
    (
        "desk packing checks slot type and inventory",
        't.prototype.setDeskData=function(e,t,i){var n=this;if(void 0===t&&(t=-1),this.deskDataList.length>e)',
        't.prototype.setDeskData=function(e,t,i){var n=this;void 0===t&&(t=-1);'
        'if(!Number.isInteger(e)||e<0||e>=8)return!1;'
        'if(t!==-1){var q=this.getItemInfo(t);if(!q||q.type!==[0,0,1,1,2,2,2,2][e]||(this.deskDataList[e]!==t&&this.getHouseItemCount(t)<1))return!1;}'
        'if(this.deskDataList.length>e)',
    ),
    (
        "bag does not draw rejected items",
        'Music.play("SE_Enter"),this.itemModel.setBagData(i,e,a);var s=',
        'Music.play("SE_Enter");if(!this.itemModel.setBagData(i,e,a))return;var s=',
    ),
    (
        "desk does not draw rejected items",
        'Music.play("SE_Enter"),this.itemModel.setDeskData(i,e,a),this.SetclearBtnState();var s=',
        'Music.play("SE_Enter");if(!this.itemModel.setDeskData(i,e,a))return;this.SetclearBtnState();var s=',
    ),
    (
        "drawing starts without an invitation",
        'this.data={state:DrawingState.accept,guest:-1,bag:[],pages:[],colls:[],show_coll:0,pen_motion:"write"}',
        'this.data={state:DrawingState.wait,guest:-1,bag:[],pages:[],colls:[],show_coll:0,pen_motion:"write"}',
    ),
    (
        "souvenir page requires a partner",
        'if(e.getModel(DrawingModel).data.state==DrawingState.accept||e.getModel(DrawingModel).data.state==DrawingState.lock){var l=new Souvenir;',
        'if(e.getModel(DrawingModel).data.guest>=0&&(e.getModel(DrawingModel).data.state==DrawingState.accept||e.getModel(DrawingModel).data.state==DrawingState.lock)){var l=new Souvenir;',
    ),
    # NOTE: the original build gated scene entry on
    #   this.loadComplete && isSyncComplete() && GameConfig.activate
    # We deliberately do NOT neutralise that gate: it is what guarantees the role
    # payload (and therefore guideStep) has been applied before MainOutView runs
    # checkGuide(). Punching it out caused a race where checkGuide() saw the
    # default guideStep "New" and opened the Welcome/开始 screen.
    # GameConfig.activate is supplied by the offline shell instead.
    (
        # The season resource groups that actually ship are season11..season44.
        # Any other key (notably the "00" default before weather data arrives)
        # makes the client request mainout_season00_* files that do not exist.
        "season key clamp",
        'getSeasonKey=function(){return this.data.season+""+this.data.hours_type}',
        'getSeasonKey=function(){var a=this.data.season,b=this.data.hours_type;'
        'return a>=1&&a<=4&&b>=1&&b<=4?a+""+b:"11"}',
    ),
]


def main():
    if not os.path.exists(CLEAN):
        print(f"missing pristine baseline: {CLEAN}")
        print("  extract it with:  python work/tools/zipx.py base.apk extract "
              "\"assets/game/js/main.min.js\" work/pristine")
        return 1
    text = open(CLEAN, "rb").read().decode("utf8")
    print(f"baseline: {CLEAN} ({len(text)} chars)")
    applied = 0
    for name, old, new in PATCHES:
        n = text.count(old)
        if n == 0:
            print(f"  [MISS] {name}: anchor not found (build drift?)")
            continue
        text = text.replace(old, new)
        applied += n
        print(f"  [ok]   {name}: {n} replacement(s)")
    open(MAIN, "wb").write(text.encode("utf8"))
    print(f"  wrote {MAIN}  ({applied} total replacements)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
