/* 出门：先按玩家真实做法把行囊摆好（引擎权威状态 + 客户端模型同步），
   再用客户端自己的 API ItemModel.setBagLock(true) 发 item_set_bag_completed。
   走的是 __probe.js 的 loopback，所以引擎的 push 会真的推回客户端。 */
(function () {
  var eng = window.__engine;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var out = {};
  eng.state.items.bag = [3, -1, 2002, 2003];       /* 便当 / - / 水壶 / 朴素纸伞 */
  M.bagDataList[0] = 3; M.bagDataList[1] = -1; M.bagDataList[2] = 2002; M.bagDataList[3] = 2003;
  if (M.getBagLock()) M.setBagLock(false);
  out.beforeDepart = {
    engineBag: eng.state.items.bag.slice(),
    clientBag: (M.getBagDataList() || []).slice(),
    status: eng.state.frog.status,
  };
  M.setBagLock(true);                              /* 真实客户端路径 */
  out.afterDepart = {
    status: eng.state.frog.status,
    clientBag: (M.getBagDataList() || []).slice(),
    plan: eng.state.travel.plan ? {
      lunch: eng.state.travel.plan.lunch,
      carryBack: (eng.state.travel.plan.carryBack || []).slice(),
      tools: eng.state.travel.plan.tools,
    } : null,
  };
  out.isHome_client = Tabikaeru.Game.instance().isHome;
  return JSON.stringify(out, null, 1);
})()
