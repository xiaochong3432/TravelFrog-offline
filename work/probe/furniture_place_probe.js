/* 摆家具 + 渲染：在真客户端里验证新增的花园家具（xw10/xw101）。
 *
 * 客户端机制（读码得出）：
 *   getOwnedFurnitures() = serverData.has_fur（拥有）
 *   getHomeFurnitures()  = serverData.put_fur（已摆放）
 *   摆放后 loadFurnitureRes() 会按 FurnitureDB.get(id).res 逐个 `RES.hasRes(res + "_png")`
 *   并把命中的纹理塞进 "furniture_home" 资源组 —— 所以"图在不在、登记没登记"可以用
 *   RES.hasRes 直接问，不需要靠肉眼。
 *
 * 这个探针：一键获得全部家具 -> 摆放一件新家具（2001 墙壁·花园风格）-> 读回客户端状态
 * -> 逐个 RES.hasRes 检查新贴图。
 */
(function () {
  var eng = window.__engine;
  if (!eng) return JSON.stringify({ error: 'no engine' });

  var Model = core.ModelManage.getInstance().getModel(FurnitureModel);
  var out = {};

  /* 1) 一键获得全部家具（编辑器路径，等价于点悬浮球的按钮） */
  var gm = eng.dispatch('client_gm', { cmd: 'all_furniture' });
  out.gm = gm.reply && gm.reply.info;
  out.owned = (eng.state.furniture.owned || []).length;

  /* 把引擎状态推给客户端（loopback 会送 pushes，但这里直接调客户端自己的 handler 更明确） */
  var load = eng.dispatch('furniture_load_furniture', {});
  if (load.reply) Model.furniture_load_furniture(load.reply);
  out.clientHasFur = (Model.getOwnedFurnitures() || []).length;
  out.newOwned = [2001, 2025, 2027, 10104].filter(function (id) {
    return (Model.getOwnedFurnitures() || []).indexOf(id) >= 0;
  });

  /* 2) 摆放新增家具 2001（type 1，花园风格的墙） */
  var place = eng.dispatch('furniture_replace_fur', { id: 2001 });
  out.placeReply = place.reply;
  var load2 = eng.dispatch('furniture_load_furniture', {});
  if (load2.reply) Model.furniture_load_furniture(load2.reply);
  out.clientPutFur = (Model.getHomeFurnitures() || []).map(function (f) { return f.id + ':' + f.type; });
  out.clientHomeOfType1 = Model.getHomeFurniture(1);

  /* 3) 贴图是否真的能被客户端加载：这正是 loadFurnitureRes() 的判据 */
  var DB = Tabikaeru.DataManager.instance().FurnitureDB;
  var probes = ['xw10_1_1', 'xw10_1_2', 'xw10_1_3', 'xw10_25_1', 'xw101_4_1'];
  out.hasRes = {};
  out.rows = {};
  probes.forEach(function (stem) {
    var fid = stem.indexOf('xw101') === 0 ? 10104 : 2001;
    var row = DB.get(fid);
    out.rows[stem] = row ? (row.res || []).indexOf(stem) >= 0 : 'no-row';
    out.hasRes[stem] = RES.hasRes(stem + '_png');
  });

  /* 4) 图标（sheet 帧）：家具列表/商店里显示的那张 */
  out.iconHasRes = RES.hasRes('xw10_1_png');
  out.iconFrameOk = (function () {
    try {
      var sheet = RES.getRes('furniture_xw1_json');
      return sheet && sheet.getTexture && !!sheet.getTexture('xw10_1_png');
    } catch (e) { return 'threw: ' + e.message; }
  })();

  return JSON.stringify(out, null, 1);
})()