/* 回家后打开行囊界面，并把 PageScroller 滚到"行囊"那一页（4 格）再截图。
   同时报告每格的语义类型 / 实际贴图 / 模型里的 item id。 */
(function () {
  var pm = core.PageManage.getInstance();
  var L = core.ViewLayerType.SceneLayer, HR = core.RemoveViewType.HideBefore;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var DB = Tabikaeru.DataManager.instance().ItemDB;
  var SLOTNAMES = ['LunchBox(便当)', 'Amulet(护身符)', 'Tool_1(道具)', 'Tool_2(道具)'];
  var out = {};
  pm.addViewControl(MainInController, L, HR);
  var t0 = Date.now();
  var phase = 'view';
  var view = null;
  return new Promise(function (resolve) {
    var iv = setInterval(function () {
      var ctl = pm.getControl(MainInController, L);
      view = ctl ? ctl.getView() : null;
      if (phase === 'view' && view && view.stage && Tabikaeru.Game.instance().isHome) {
        view.onTapBag();
        phase = 'bag';
      }
      if (phase === 'bag' && view.bag && view.bag.bag && view.bag.bag.items && view.bag.bag.items.length) {
        var bt = view.bag;
        clearInterval(iv);
        out.bagX = bt.bag.x;
        out.pagesX = bt.table ? bt.table.x : null;
        try {
          bt.scroller.viewport.scrollH = bt.bag.x + 1;
          bt.scroller.viewport.validateDisplayList && bt.scroller.viewport.validateDisplayList();
          out.scrolledTo = bt.scroller.viewport.scrollH;
        } catch (e) { out.scrollError = String(e && e.message); }
        out.bagSlots = bt.bag.items.map(function (it, i) {
          var src = it.image ? it.image.source : null;
          return {
            slot: i,
            slotType: it.type,
            slotMeaning: SLOTNAMES[i],
            drawnSource: (typeof src === 'string') ? src : Object.prototype.toString.call(src),
            modelItemId: (M.getBagDataList() || [])[i],
            itemName: (M.getBagDataList() || [])[i] === -1 ? '-' : (DB.get((M.getBagDataList() || [])[i]) || {}).name,
          };
        });
        out.clientBag = (M.getBagDataList() || []).slice();
        out.clientDesk = (M.getDeskDataList() || []).slice();
        resolve(JSON.stringify(out, null, 1));
      }
      if (Date.now() - t0 > 20000) { clearInterval(iv); resolve(JSON.stringify(out, null, 1)); }
    }, 250);
  });
})()
