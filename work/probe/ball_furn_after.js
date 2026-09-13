(function () {
  /* After 获得全部家具: does the client's OWN model hold the new list, i.e. is a restart
     still needed? FurnitureModel.serverData is only written by furniture_load_furniture,
     which used to arrive only at login. */
  var out = {};
  try {
    var fur = core.ModelManage.getInstance().getModel(window.FurnitureModel);
    out.hasFur = (fur.serverData.has_fur || []).length;
    out.shopList = (fur.serverData.shop.shop_list || []).length;
    out.bench = (fur.serverData.bench || []).length;
  } catch (e) { out.furErr = String(e && e.message); }
  try {
    var item = core.ModelManage.getInstance().getModel(window.ItemModel);
    out.handbook = (item.collectionsList || []).length + '/' + (item.specialtysList || []).length;
  } catch (e) { out.itemErr = String(e && e.message); }
  try {
    var ency = core.ModelManage.getInstance().getModel(window.EncyModel);
    out.ency = ency.data.unlock_list.length + '/' + Object.keys(ency.data.show_sub).length;
  } catch (e) { out.encyErr = String(e && e.message); }
  var panel = document.getElementById('__save_panel');
  out.note = panel.querySelectorAll(':scope > div')[1].textContent;
  return JSON.stringify(out);
})()
