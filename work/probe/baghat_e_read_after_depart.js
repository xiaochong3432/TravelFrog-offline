/* 出门之后，玩家还站在屋里的那一刻：帽子(frogCap)还在不在？
   MainInController 不订阅 RoleEventType.loadRole（只有 MainOutController 订阅：
   `case RoleEventType.loadRole: this.view && this.view.reset()`），
   而 MainInView.updateFlogStatus() 里 `if(isHome){ frogCap.visible=!0; ... }` 没有 else ——
   所以 status 0→1 时这个视图不会被重算，帽子保持上一次进屋时的 visible=true。 */
(function () {
  var L = core.ViewLayerType.SceneLayer;
  var out = {};
  var t0 = Date.now();
  return new Promise(function (resolve) {
    var iv = setInterval(function () {
      var ctl = core.PageManage.getInstance().getControl(MainInController, L);
      var v = ctl ? ctl.getView() : null;
      var home = Tabikaeru.Game.instance().isHome;
      if ((v && home === false) || Date.now() - t0 > 8000) {
        clearInterval(iv);
        out.waitedMs = Date.now() - t0;
        out.isHome_client = home;
        out.frogStatus = core.ModelManage.getInstance().getModel(RoleModel).getFrogStatus();
        out.status_engine = window.__engine.state.frog.status;
        out.viewFound = !!v;
        if (v) {
          out.frogCap_visible = v.frogCap ? v.frogCap.visible : 'no-node';
          out.player_alive = !!v.player;
          out.curAnimName = v.curAnimName;
          out.viewOnStage = !!v.stage;
        }
        resolve(JSON.stringify(out, null, 1));
      }
    }, 250);
  });
})()
