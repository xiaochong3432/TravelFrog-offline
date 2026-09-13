/* StartGatherClover 这一步要玩家真的收一次草：走客户端自己的 RoleModel.harvestClover。 */
(function () {
  var R = core.ModelManage.getInstance().getModel(RoleModel);
  var U = core.ModelManage.getInstance().getModel(UserModel);
  var out = { step: U.getClientSettings().guideStep };

  var list = R.getCloverGrowList() || [];
  out.slots = list.map(function (c) { return c ? (c.last_harvest + '/' + c.element) : '-'; });

  /* 找一个"能收"的草位：last_harvest <= 0 表示已成熟（客户端的判定） */
  var pick = -1;
  for (var i = 0; i < list.length; i++) {
    var c = list[i];
    if (c && (c.last_harvest <= 0)) { pick = i + 1; break; }
  }
  out.picked = pick;
  if (pick > 0) {
    try {
      R.harvestClover(pick, function () { });
      out.harvested = true;
    } catch (e) { out.harvested = String(e && e.message); }
  }
  out.clover = (core.ModelManage.getInstance().getModel(UserModel).getClover
    ? core.ModelManage.getInstance().getModel(UserModel).getClover() : undefined);
  out.stepAfter = U.getClientSettings().guideStep;
  return JSON.stringify(out);
})()