/* 帽子像素归属：进屋（此时蛙在旅行）读 frogCap，并**显式置 true**，准备截图。
   下一次用 baghat_k 置 false 再截一张，两张图的差别就是 frogCap 画出来的东西。 */
(function () {
  var L = core.ViewLayerType.SceneLayer, HR = core.RemoveViewType.HideBefore;
  var pm = core.PageManage.getInstance();
  pm.addViewControl(MainInController, L, HR);
  var t0 = Date.now();
  return new Promise(function (resolve) {
    var iv = setInterval(function () {
      var ctl = pm.getControl(MainInController, L);
      var v = ctl ? ctl.getView() : null;
      if ((v && v.stage) || Date.now() - t0 > 12000) {
        clearInterval(iv);
        var stale = v && v.frogCap ? v.frogCap.visible : null;
        if (v && v.frogCap) v.frogCap.visible = true;
        resolve(JSON.stringify({
          isHome_client: Tabikaeru.Game.instance().isHome,
          frogCap_visible_asFound: stale,
          frogCap_set_to: v && v.frogCap ? v.frogCap.visible : 'no-node',
          frogCap_source: v && v.frogCap ? String(v.frogCap.source) : null,
          frogCap_x: v && v.frogCap ? v.frogCap.x : null,
          frogCap_y: v && v.frogCap ? v.frogCap.y : null,
          player_alive: v ? !!v.player : null,
          curAnimName: v ? v.curAnimName : null,
        }, null, 1));
      }
    }, 200);
  });
})()
