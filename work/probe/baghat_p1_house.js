/* 步骤1：进屋（客户端自己的进屋调用），读家里的蛙 + 帽子(frogCap)状态。
   帽子节点是 MainIn.exml 皮肤里的 `frogCap`（source=bousi_ie_png，默认 visible=false），
   MainInView.updateFlogStatus() 只在 isHome 时把它置 true。 */
(function () {
  var out = {};
  var G = Tabikaeru.Game.instance();
  out.status_engine = window.__engine.state.frog.status;
  out.isHome_client = G.isHome;
  out.frogStatus_client = core.ModelManage.getInstance().getModel(RoleModel).getFrogStatus();

  try {
    core.PageManage.getInstance().addViewControl(
      MainInController, core.ViewLayerType.SceneLayer, core.RemoveViewType.HideBefore);
    out.enteredHouse = true;
  } catch (e) { out.enteredHouse = String(e && e.message); }

  out.hasMainInControl = !!core.PageManage.getInstance().getControl(MainInController, core.ViewLayerType.SceneLayer);
  var ctl = core.PageManage.getInstance().getControl(MainInController, core.ViewLayerType.SceneLayer);
  var v = ctl ? ctl.getView() : null;
  out.viewClass = v ? (v.__class__ && v.__class__.__name__) || (v.constructor && v.constructor.name) : null;
  if (v) {
    out.frogCap_visible = v.frogCap ? v.frogCap.visible : 'no-frogCap-node';
    out.frogCap_source = v.frogCap ? String(v.frogCap.source) : null;
    out.player_alive = !!v.player;
    out.curAnimName = v.curAnimName;
  }
  /* 皮肤里的默认值（新建视图时会不会带帽子） */
  out.skinDefaultKnown = 'MainIn.exml frogCap.visible=false (default.thm.js:28727)';
  return JSON.stringify(out, null, 1);
})()
