/* 读家里的蛙 + 帽子(frogCap)节点。帽子 = MainIn.exml 皮肤里的 eui.Image `frogCap`
   (source=bousi_ie_png，皮肤默认 visible=false)，由 MainInView.updateFlogStatus() 在 isHome 时置 true。 */
(function () {
  var out = {};
  var pm = core.PageManage.getInstance();
  var ctl = pm.getControl(MainInController);
  var v = ctl ? ctl.getView() : null;
  out.isHome_client = Tabikaeru.Game.instance().isHome;
  out.frogStatus = core.ModelManage.getInstance().getModel(RoleModel).getFrogStatus();
  out.status_engine = window.__engine.state.frog.status;
  out.mainInControlFound = !!ctl;
  out.viewFound = !!v;
  if (v) {
    out.frogCap_visible = v.frogCap ? v.frogCap.visible : 'no-frogCap-node';
    out.frogCap_source = v.frogCap ? String(v.frogCap.source) : null;
    out.player_alive = !!v.player;
    out.curAnimName = v.curAnimName;
    out.viewOnStage = !!(v.stage);
  }
  return JSON.stringify(out, null, 1);
})()
