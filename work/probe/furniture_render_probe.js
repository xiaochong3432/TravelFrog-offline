/* 摆放后让客户端把家具纹理组建起来，并报告场景/资源组状态。 */
(function () {
  var eng = window.__engine;
  if (!eng) return JSON.stringify({ error: 'no engine' });
  var Model = core.ModelManage.getInstance().getModel(FurnitureModel);
  var out = {};

  eng.dispatch('client_gm', { cmd: 'all_furniture' });
  /* 摆满 4 个新家具（不同 type），并换一个 xw101 风格 */
  [2001, 2002, 2025, 2027].forEach(function (id) {
    eng.dispatch('furniture_replace_fur', { id: id });
  });
  eng.dispatch('furniture_replace_fur', { id: 10104 });
  var load = eng.dispatch('furniture_load_furniture', {});
  if (load.reply) Model.furniture_load_furniture(load.reply);

  out.putFur = (Model.getHomeFurnitures() || []).map(function (f) { return f.id + ':' + f.type; });
  out.hasFurCount = (Model.getOwnedFurnitures() || []).length;

  /* 客户端自己的加载函数：placed 家具的 res+"_png" 是否都能拿到 */
  var DB = Tabikaeru.DataManager.instance().FurnitureDB;
  out.missingTextures = [];
  (Model.getHomeFurnitures() || []).forEach(function (f) {
    var row = DB.get(f.id);
    if (!row) { out.missingTextures.push('no-row:' + f.id); return; }
    (row.res || []).forEach(function (stem) {
      if (!RES.hasRes(stem + '_png')) out.missingTextures.push(stem);
    });
  });

  /* 场景是否已经建好（家具是不是已经在场景里） */
  out.hasMainOut = !!(core.PageManage.getInstance().getControl && (function () {
    try { return core.PageManage.getInstance().getControl(MainOutController); } catch (e) { return null; }
  })());
  try {
    var mv = core.PageManage.getInstance().getControl(MainOutController);
    out.mainOutVisible = mv ? mv.visible : 'no-view';
  } catch (e) { out.mainOutVisible = 'threw'; }

  /* 顶部视图是谁（标题页还是场景） */
  try {
    var pm = core.PageManage.getInstance();
    out.layers = Object.keys(pm).filter(function (k) { return /layer/i.test(k); }).length;
  } catch (e) { out.layers = 'threw'; }
  return JSON.stringify(out, null, 1);
})()