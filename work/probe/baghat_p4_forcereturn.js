/* 步骤4：把回程时间置为过去，让引擎自己的 5s tick 走 returnFrog（真正的 loopback 推送路径）。
   同时给桌子摆点东西，方便对照"桌面上的"与"行囊里的"。 */
(function () {
  var eng = window.__engine;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var out = {};

  /* 桌子上摆货（8 格 = [便当,便当,护身符,护身符,道具x4]） */
  eng.state.items.desk = [3, 4, -1, -1, 2000, -1, -1, -1];
  M.deskDataList = [3, 4, -1, -1, 2000, -1, -1, -1];

  out.beforeReturn = {
    status: eng.state.frog.status,
    engineBag: eng.state.items.bag.slice(),
    clientBag: (M.getBagDataList() || []).slice(),
    engineDesk: eng.state.items.desk.slice(),
  };
  eng.state.travel.returnAt = 0;      // 下一次 tick 就会回家
  out.returnAtForced = eng.state.travel.returnAt;
  out.tickIntervalMs = 5000;
  return JSON.stringify(out, null, 1);
})()
