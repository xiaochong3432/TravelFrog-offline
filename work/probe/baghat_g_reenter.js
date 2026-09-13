/* 再进屋（= 点"回家"）。MainInController.open() 对已存在的 view 调 reset()
   -> updateFlogStatus()，按当前 isHome(false) 重算：帽子应当变成 false。
   这一步说明触发条件是"玩家此刻就站在这个视图上"。 */
(function () {
  var pm = core.PageManage.getInstance();
  var L = core.ViewLayerType.SceneLayer, HR = core.RemoveViewType.HideBefore;
  var out = {};
  var cTL = pm.getControl(MainOutController, L);
  out.frogCap_whileOutside_fromMainOut = 'n/a (MainOut 的蛙是另一个视图)';
  pm.addViewControl(MainInController, L, HR);
  var t0 = Date.now();
  return new Promise(function (resolve) {
    var iv = setInterval(function () {
      var ctl = pm.getControl(MainInController, L);
      var v = ctl ? ctl.getView() : null;
      if ((v && v.stage) || Date.now() - t0 > 12000) {
        clearInterval(iv);
        out.waitedMs = Date.now() - t0;
        out.isHome_client = Tabikaeru.Game.instance().isHome;
        out.viewOnStage = !!(v && v.stage);
        out.frogCap_visible = v && v.frogCap ? v.frogCap.visible : 'no-view';
        out.player_alive = v ? !!v.player : null;
        out.curAnimName = v ? v.curAnimName : null;
        resolve(JSON.stringify(out, null, 1));
      }
    }, 250);
  });
})()
