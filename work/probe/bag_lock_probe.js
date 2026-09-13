/* 行囊「准备完成」走真实客户端路径的验证。
 *
 * 之前 item_set_bag_completed 在我们引擎里没有 handler：客户端 BagView.lock() ->
 * ItemModel.setBagLock(true) -> send("item_set_bag_completed", null, true) 会被静默丢弃，
 * 青蛙只能等空闲定时器出门。这个探针确认修复：
 *   1) 引擎里有 handler 且能收到客户端的真实发送；
 *   2) 收到后立刻出发（frog.status = 1）并把 bag_completed 以权威值推回；
 *   3) 客户端的 ItemModel.item_load_items 把它读回 bagLock（这就是锁定按钮的状态）。
 *
 * 打包走引擎状态 + 客户端模型直写（等价于玩家在行囊界面放好便当），
 * 但"准备完成"这一步调用的是客户端自己的 API，不绕过它。
 */
(function () {
  var E = window.FrogEngine;
  var eng = window.__engine;
  if (!E || !eng) return JSON.stringify({ error: 'engine not ready', hasFrogEngine: !!E, hasEngine: !!eng });

  var Model = core.ModelManage.getInstance().getModel(ItemModel);
  var dm = Tabikaeru.DataManager.instance();

  /* 便当：ItemDB 里 type === 0（与引擎的 ITEM_TYPE_LUNCHBOX 一致） */
  var lunch = -1;
  try {
    var src = dm.ItemDB.src;
    var keys = Object.keys(src || {});
    for (var i = 0; i < keys.length; i++) {
      var row = src[keys[i]];
      if (row && Number(row.type) === 0) { lunch = Number(row.id); break; }
    }
  } catch (e) { /* ignore */ }
  if (lunch < 0) return JSON.stringify({ error: 'no lunch box in ItemDB' });

  /* 放好便当（引擎权威状态 + 客户端模型同步） */
  eng.state.items.bag[0] = lunch;
  Model.bagDataList[0] = lunch;
  if (Model.bagLock) Model.setBagLock(false);          // 确保从"未锁定"开始

  var before = {
    status: eng.state.frog.status,
    bagCompleted: eng.state.items.bagCompleted,
    clientBagLock: Model.getBagLock(),
    lunch: lunch,
  };

  /* 真实路径：客户端自己的 API 发 item_set_bag_completed */
  Model.setBagLock(true);

  /* 客户端把 bagLock 先乐观置真；我们关心的是"引擎有没有真的收到并出发" */
  var after = {
    status: eng.state.frog.status,
    bagCompleted: eng.state.items.bagCompleted,
    clientBagLock: Model.getBagLock(),
    returnAt: eng.state.travel.returnAt,
    tripCount: eng.state.travel.tripCount,
  };

  var verdict = (after.status === 1 && after.bagCompleted === 1 && after.returnAt > 0)
    ? 'PASS: 准备完成 reached the engine and sent the frog out'
    : 'FAIL: the lock did not start a trip';

  return JSON.stringify({ verdict: verdict, before: before, after: after });
})()
