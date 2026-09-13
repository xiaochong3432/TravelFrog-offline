/* 步骤3：帽子是否"回家"——出去（MainOut）再进屋（MainIn）各一次。
   MainInController.open(): view 存在 -> view.reset() -> updateFlogStatus()，会按当前 isHome 重算。
   所以这一步能区分"永久错误"和"只是这个视图实例没被刷新"。 */
(function () {
  var out = {};
  var pm = core.PageManage.getInstance();
  var S = core.ViewLayerType.SceneLayer;
  var H = core.RemoveViewType.HideBefore;

  var ctlBefore = pm.getControl(MainInController, S);
  var vBefore = ctlBefore ? ctlBefore.getView() : null;
  out.beforeLeave = { frogCap_visible: vBefore && vBefore.frogCap ? vBefore.frogCap.visible : 'no-view' };

  pm.addViewControl(MainOutController, S, H);
  out.afterGoOutside = {
    mainInControlPresent: !!pm.getControl(MainInController, S),
    mainOutControlPresent: !!pm.getControl(MainOutController, S),
  };

  pm.addViewControl(MainInController, S, H);
  var ctl = pm.getControl(MainInController, S);
  var v = ctl ? ctl.getView() : null;
  out.afterReenter = {
    sameViewInstance: !!v && v === vBefore,
    isHome_client: Tabikaeru.Game.instance().isHome,
    frogCap_visible: v && v.frogCap ? v.frogCap.visible : 'no-view',
    player_alive: v ? !!v.player : null,
    curAnimName: v ? v.curAnimName : null,
  };
  return JSON.stringify(out, null, 1);
})()
