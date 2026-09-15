/* 把回程时间置成过去，让引擎自己的 5s tick 走 returnFrog()（真实推送路径）。
   同时给桌子摆点东西，方便对照"桌面上的"和"行囊里的"。 */
(function () {
  var eng = window.__engine;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var out = {};
  eng.state.items.desk = [3, 4, -1, -1, 2000, -1, -1, -1];
  M.deskDataList = [3, 4, -1, -1, 2000, -1, -1, -1];
  out.beforeReturn = {
    status: eng.state.frog.status,
    engineBag: eng.state.items.bag.slice(),
    clientBag: (M.getBagDataList() || []).slice(),
    engineDesk: eng.state.items.desk.slice(),
  };
  eng.state.travel.returnAt = 0;
  return JSON.stringify(out, null, 1);
})()
