/* 把 frogCap 关掉再截一张：与 baghat_j 的截图逐像素比较，就能确认"家里的帽子"就是这个节点。 */
(function () {
  var L = core.ViewLayerType.SceneLayer;
  var pm = core.PageManage.getInstance();
  var ctl = pm.getControl(MainInController, L);
  var v = ctl ? ctl.getView() : null;
  if (v && v.frogCap) v.frogCap.visible = false;
  return JSON.stringify({
    frogCap_visible: v && v.frogCap ? v.frogCap.visible : 'no-view',
    player_alive: v ? !!v.player : null,
  }, null, 1);
})()
