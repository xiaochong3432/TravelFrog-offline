(function () {
  /* Did the edit reach the client's MODELS, i.e. is a restart still needed?
     These are the very objects the pages render from. */
  var out = { types: {} };
  ['EncyModel', 'ItemModel', 'FurnitureModel', 'TravelModel', 'EncyViewControl', 'LumberroomViewControl']
    .forEach(function (n) { out.types[n] = typeof window[n]; });

  function model(name) {
    try { return core.ModelManage.getInstance().getModel(window[name]); }
    catch (e) { return null; }
  }
  var ency = model('EncyModel');
  var item = model('ItemModel');
  var fur = model('FurnitureModel');
  var travel = model('TravelModel');

  if (ency && ency.data) {
    out.encyUnlock = ency.data.unlock_list.length;
    out.encyShowSub = Object.keys(ency.data.show_sub).length;
    out.encyDesc = Object.keys(ency.data.unlock_desc).length;
    out.encyIsOpen = ency.isOpen();
  }
  if (item) {
    out.handbookCollections = (item.collectionsList || []).length;
    out.handbookSpecialtys = (item.specialtysList || []).length;
  }
  if (fur && fur.serverData) out.furnitureOwned = (fur.serverData.has_fur || []).length;
  if (travel) out.albumCount = travel.getPictureCount ? travel.getPictureCount() : null;

  /* Replay EncyView.getItemsByTab with the client's OWN table */
  try {
    var table = Tabikaeru.DataManager.instance().encyData.get('list');
    var show = ency.data.show_sub;
    var byTab = {};
    for (var k in show) {
      var row = table[String(show[k])];
      if (row) byTab[row.tab] = (byTab[row.tab] || 0) + 1;
    }
    out.itemsByTab = byTab;
    out.tableName = table[String(show[Object.keys(show)[0]])] ?
      table[String(show[Object.keys(show)[0]])].name : null;
  } catch (e) { out.tabErr = String(e && e.message); }
  return JSON.stringify(out);
})()
