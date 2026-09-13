/* 步骤2：按玩家真实路径准备行李（行囊 4 格 = [便当, 护身符, 道具, 道具]）并出门。
   行囊 = 引擎 state.items.bag / 客户端 ItemModel.bagDataList（item_load_items.bag）
   便当 = id 3 (type0/spend1)  水壶 = 2002 (type2/spend0)  朴素纸伞 = 2003 (type2/spend0)
   出门走客户端自己的 API：ItemModel.setBagLock(true) -> item_set_bag_completed
   （这条路径会经过 __probe.js 的 loopback，引擎的 push 才会真的推回客户端） */
(function () {
  var eng = window.__engine;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var out = {};

  /* 直接写引擎权威状态 + 客户端模型（等价于玩家在行囊界面摆好） */
  eng.state.items.bag = [3, -1, 2002, 2003];
  M.bagDataList[0] = 3; M.bagDataList[1] = -1; M.bagDataList[2] = 2002; M.bagDataList[3] = 2003;
  if (M.getBagLock()) M.setBagLock(false);
  out.beforeDepart = {
    engineBag: eng.state.items.bag.slice(),
    clientBag: (M.getBagDataList() || []).slice(),
    status: eng.state.frog.status,
  };

  /* 客户端真实发送：准备完成 */
  M.setBagLock(true);

  out.afterDepart = {
    status: eng.state.frog.status,
    engineBag: eng.state.items.bag.slice(),
    clientBag: (M.getBagDataList() || []).slice(),
    clientBagLock: M.getBagLock(),
    plan: eng.state.travel.plan ? {
      lunch: eng.state.travel.plan.lunch,
      lunchFrom: eng.state.travel.plan.lunchFrom,
      amulet: eng.state.travel.plan.amulet,
      tools: eng.state.travel.plan.tools,
      carryBack: (eng.state.travel.plan.carryBack || []).slice(),
      stray: eng.state.travel.plan.stray,
    } : null,
    returnAt: eng.state.travel.returnAt,
  };

  /* 帽子：MainIn 视图还在（玩家正站在屋里/背包界面），reset() 没有被调用 */
  out.isHome_client = Tabikaeru.Game.instance().isHome;
  var ctl = core.PageManage.getInstance().getControl(MainInController, core.ViewLayerType.SceneLayer);
  var v = ctl ? ctl.getView() : null;
  if (v) {
    out.frogCap_visible = v.frogCap ? v.frogCap.visible : 'no-node';
    out.player_alive = !!v.player;
  } else out.view = 'MainInView cache 里没有（HideBefore 后被 cacheControlList 收走）';
  return JSON.stringify(out, null, 1);
})()
