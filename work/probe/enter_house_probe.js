/* 进屋看家具：家具是 MainInView（室内）按 FurnitureDB.res 渲染的，不是庭院。
   用客户端自己的进屋调用（MainOutView.houseBtn 的 handler 就是它）。 */
(function () {
  var eng = window.__engine;
  if (!eng) return JSON.stringify({ error: 'no engine' });
  var out = {};

  eng.dispatch('client_gm', { cmd: 'all_furniture' });
  [2001, 2002, 2005, 2010, 2025, 2027, 10104].forEach(function (id) {
    eng.dispatch('furniture_replace_fur', { id: id });
  });
  var F = core.ModelManage.getInstance().getModel(FurnitureModel);
  var lf = eng.dispatch('furniture_load_furniture', {});
  if (lf.reply) F.furniture_load_furniture(lf.reply);
  out.putFur = (F.getHomeFurnitures() || []).map(function (f) { return f.id + ':t' + f.type; });

  /* 客户端自己的进屋调用 */
  try {
    core.PageManage.getInstance().addViewControl(
      MainInController, core.ViewLayerType.SceneLayer, core.RemoveViewType.HideBefore);
    out.entered = true;
  } catch (e) { out.entered = String(e && e.message); }
  return JSON.stringify(out);
})()