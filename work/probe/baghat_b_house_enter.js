/* 进屋，并**等一下**让 SceneLayer 过场（300+300ms tween）把视图装上去。
   注意 core.PageManage.getControl(Class) 不传层会直接报错返回 undefined —— 必须带层。 */
(function () {
  var L = core.ViewLayerType.SceneLayer;
  var HR = core.RemoveViewType.HideBefore;
  var out = {};
  core.PageManage.getInstance().addViewControl(MainInController, L, HR);
  var t0 = Date.now();
  return new Promise(function (resolve) {
    var iv = setInterval(function () {
      var ctl = core.PageManage.getInstance().getControl(MainInController, L);
      var v = ctl ? ctl.getView() : null;
      if (v || Date.now() - t0 > 15000) {
        clearInterval(iv);
        out.waitedMs = Date.now() - t0;
        out.viewFound = !!v;
        out.isHome_client = Tabikaeru.Game.instance().isHome;
        out.status_engine = window.__engine.state.frog.status;
        if (v) {
          out.frogCap_visible = v.frogCap ? v.frogCap.visible : 'no-frogCap-node';
          out.frogCap_source = v.frogCap ? String(v.frogCap.source) : null;
          out.player_alive = !!v.player;
          out.curAnimName = v.curAnimName;
          out.viewOnStage = !!v.stage;
        }
        resolve(JSON.stringify(out, null, 1));
      }
    }, 250);
  });
})()
