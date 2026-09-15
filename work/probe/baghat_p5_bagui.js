/* 步骤5：回家后读"行囊"（4 格）与"桌子"（8 格）的客户端模型，
   并打开客户端真正的 BagTable 界面，读出每一格：
     - 该格的**语义类型**（Bag.renderItem 里 items[i].type：0=便当 1=护身符 2=道具）
     - 该格**实际画出来的贴图**（image.source，来自 ItemDB.get(bagDataList[i]).img）
   两者的对应关系就是"错位"的直接证据。 */
(function () {
  var eng = window.__engine;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var DB = Tabikaeru.DataManager.instance().ItemDB;
  var out = {};

  out.engineBag = eng.state.items.bag.slice();
  out.engineDesk = eng.state.items.desk.slice();
  out.clientBag = (M.getBagDataList() || []).slice();
  out.clientDesk = (M.getDeskDataList() || []).slice();
  out.status = eng.state.frog.status;
  out.isHome_client = Tabikaeru.Game.instance().isHome;

  var names = {};
  out.clientBag.forEach(function (id) {
    if (id !== -1) {
      var row = DB.get(id);
      names[id] = row ? (row.name + ' type=' + row.type + ' spend=' + row.spend) : 'NO-ROW';
    }
  });
  out.bagItemMeta = names;
  out.imgPath = {};
  Object.keys(names).forEach(function (id) {
    var row = DB.get(Number(id));
    out.imgPath[id] = row ? String(Tabikaeru.path.formatPathImage(row.img)) : null;
  });

  /* 打开客户端的行囊/桌子界面（进屋 -> 点行囊） */
  var S = core.ViewLayerType.SceneLayer, H = core.RemoveViewType.HideBefore;
  core.PageManage.getInstance().addViewControl(MainInController, S, H);
  var ctl = core.PageManage.getInstance().getControl(MainInController, S);
  var view = ctl ? ctl.getView() : null;
  out.frogCap_visible_after_return = view && view.frogCap ? view.frogCap.visible : 'no-view';
  var ok = false;
  try { view.onTapBag(); ok = true; } catch (e) { out.onTapBagError = String(e && e.message); }
  out.onTapBagCalled = ok;

  var bt = view ? view.bag : null;
  out.bagTableCreated = !!bt;
  if (bt) {
    out.bagPageCreated = !!bt.bag;                 /* isHome 时才建 4 格行囊页 */
    var slots = [];
    if (bt.bag && bt.bag.items) {
      bt.bag.items.forEach(function (it, i) {
        var src = it.image ? it.image.source : null;
        slots.push({
          slot: i,
          slotType: it.type,                        /* 0=便当 1=护身符 2=道具 */
          drawnSource: (typeof src === 'string') ? src : Object.prototype.toString.call(src),
          modelItemId: (M.getBagDataList() || [])[i],
        });
      });
    }
    out.bagSlots = slots;
    var deskSlots = [];
    if (bt.table && bt.table.items) {
      bt.table.items.forEach(function (it, i) {
        deskSlots.push({ slot: i, slotType: it.type });
      });
    }
    out.deskSlotTypes = deskSlots;
  }
  return JSON.stringify(out, null, 1);
})()
