/* 工作台制作：在真客户端里走客户端自己的 API（FurnitureModel.setBenchItem/setBenchTool）。
 *
 * 原版没有制作命令、也没有配方表：服务端看着台面决定开工，完成时推
 * TimerEvent.FurnitureFinish(21)。这个探针验证我们实现的这条链：
 *   备料 -> 客户端把图纸放进物品位 -> 引擎自动开工并锁台 -> 锁定时放东西被拒
 *   -> 到点结算 -> 客户端 has_fur 里出现新家具、台面解锁。
 */
(function () {
  var eng = window.__engine;
  if (!eng) return JSON.stringify({ error: 'no engine' });
  var F = core.ModelManage.getInstance().getModel(FurnitureModel);
  var I = core.ModelManage.getInstance().getModel(ItemModel);
  var out = {};

  /* 1) 备料：图纸 10301（墙壁图册）+ 松木 x2 + 粗布 x1 */
  eng.dispatch('client_gm', { cmd: 'add_item 10301 1' });
  eng.dispatch('client_gm', { cmd: 'add_item 10001 2' });
  eng.dispatch('client_gm', { cmd: 'add_item 10005 1' });
  var li = eng.dispatch('item_load_items', {});
  if (li.reply) I.item_load_items(li.reply);
  out.houseBefore = I.getHouseItemCount(10301) + '/' + I.getHouseItemCount(10001) + '/' + I.getHouseItemCount(10005);

  /* 2) 把图纸放进 0 号物品位（客户端会发 furniture_putin_bench pos=6） */
  var before = eng.dispatch('client_gm', { cmd: 'bench_state' }).reply.info;
  F.setBenchItem(0, 10301);
  var lf = eng.dispatch('furniture_load_furniture', {});
  if (lf.reply) F.furniture_load_furniture(lf.reply);
  out.benchStateBefore = before;
  out.craft = eng.state.furniture.craft && eng.state.furniture.craft.furnitureId;
  out.clientLock = F.isLockBench();
  out.clientMateListLen = (F.getMateList() || []).length;
  out.benchWire = (F.getBenchItems() || []).slice();

  /* 3) 锁定期间客户端自己会挡（isLockBench -> "咱们不许动"）；服务端也要拒 */
  var refused = eng.dispatch('furniture_putin_bench', { pos: 2, id: 10005 });
  out.lockedPutinCode = refused.reply && refused.reply.code;

  /* 4) 到点结算（真机上就是等 15 分钟；这里用编辑器命令快进） */
  var fin = eng.dispatch('client_gm', { cmd: 'craft_finish' });
  out.finishMsg = fin.reply && fin.reply.info;
  var lf2 = eng.dispatch('furniture_load_furniture', {});
  if (lf2.reply) F.furniture_load_furniture(lf2.reply);
  out.clientOwns2001 = (F.getOwnedFurnitures() || []).indexOf(2001) >= 0;
  out.clientLockAfter = F.isLockBench();

  /* 5) 新家具能不能摆放 + 贴图在不在（摆放链的判据） */
  var place = eng.dispatch('furniture_replace_fur', { id: 2001 });
  out.placeCode = place.reply && place.reply.code;
  var DB = Tabikaeru.DataManager.instance().FurnitureDB;
  out.missingTextures = [];
  (DB.get(2001).res || []).forEach(function (stem) {
    if (!RES.hasRes(stem + '_png')) out.missingTextures.push(stem);
  });

  return JSON.stringify(out, null, 1);
})()