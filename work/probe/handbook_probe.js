/* 图鉴: does a collected item render as collected instead of "?" (simplified) */
const out = {};
try {
  const E = window.__engine;
  const DM = Tabikaeru.DataManager.instance();
  const IM = core.ModelManage.getInstance().getModel(ItemModel);

  const firstCol = Number(DM.CollectDB.index(0).id);
  const firstSpec = Number(DM.SpecialtyDB.index(0).itemId);
  out.granted = { collection: firstCol, specialty: firstSpec };
  if (E.state.handbook.collections.indexOf(firstCol) === -1) {
    E.state.handbook.collections.push(firstCol);
  }
  if (E.state.handbook.specialtys.indexOf(firstSpec) === -1) {
    E.state.handbook.specialtys.push(firstSpec);
  }

  core.SocketManage.getInstance().send('item_load_handbook', new core.Action2(function (r) {
    out.reply = r ? { collections: (r.collections || []).length,
      specialtys: (r.specialtys || []).length } : null;
  }));

  out.collectionsAfter = (IM.getCollectionsList() || []).length;
  out.specialtysAfter = (IM.getSpecialtysList() || []).length;

  const cl = IM.collectionList;
  out.collectionListTotal = cl.length;
  out.collectionListOwned = cl.filter((x) => x.count > 0).length;
  out.ownedCollectionNames = cl.filter((x) => x.count > 0).slice(0, 3)
    .map((x) => x.cfg.name);
  const sl = IM.specialtyList;
  out.specialtyListTotal = sl.length;
  out.specialtyListOwned = sl.filter((x) => x !== -1).length;
  out.ownedSpecialtyNames = sl.filter((x) => x !== -1).slice(0, 3)
    .map((x) => x.name);

  core.PageManage.getInstance().addViewControl(CollectionViewControl,
    core.ViewLayerType.WindowLayer);
  out.viewOpened = true;
} catch (e) {
  out.error = String(e && e.stack || e);
}
return JSON.stringify(out);
