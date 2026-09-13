/* 回家之后：读引擎/客户端的行囊(4 格)与桌子(8 格)，并打开客户端真正的 BagTable 界面。
   BagTable 的格子是在 onComplete -> once(ENTER_FRAME) 里才建的，所以要**轮询**等 bt.bag/bt.table 出来，
   再逐格读：
     - 该格的**语义类型**（Bag.renderItem 的 items[i].type：0=便当 1=护身符 2=道具）
     - 该格**实际画出来的贴图**（image.source）
   modelItemId 与 slotMeaning 对不上 = 错位。 */
(function () {
  var eng = window.__engine;
  var pm = core.PageManage.getInstance();
  var L = core.ViewLayerType.SceneLayer, HR = core.RemoveViewType.HideBefore;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var DB = Tabikaeru.DataManager.instance().ItemDB;
  var SLOTNAMES = ['LunchBox(便当)', 'Amulet(护身符)', 'Tool_1(道具)', 'Tool_2(道具)'];
  var out = {};

  out.engineBag = eng.state.items.bag.slice();
  out.engineDesk = eng.state.items.desk.slice();
  out.clientBag = (M.getBagDataList() || []).slice();
  out.clientDesk = (M.getDeskDataList() || []).slice();
  out.status_engine = eng.state.frog.status;
  out.isHome_client = Tabikaeru.Game.instance().isHome;
  out.bagSlotsModel = {};
  (M.getBagDataList() || []).forEach(function (id, i) {
    if (id !== -1) {
      var row = DB.get(id);
      out.bagSlotsModel['slot' + i + '=' + SLOTNAMES[i]] =
        (row ? (row.name + ' type=' + row.type + ' spend=' + row.spend) : 'NO-ROW')
        + ' | wouldDraw=' + (row ? String(Tabikaeru.path.formatPathImage(row.img)) : '-');
    }
  });

  pm.addViewControl(MainInController, L, HR);
  var t0 = Date.now();
  var phase = 'waitView';
  var view = null;
  return new Promise(function (resolve) {
    var iv = setInterval(function () {
      var ctl = pm.getControl(MainInController, L);
      view = ctl ? ctl.getView() : null;
      if (phase === 'waitView' && view && view.stage && Tabikaeru.Game.instance().isHome) {
        out.waitedViewMs = Date.now() - t0;
        out.houseStateBeforeBagOpen = {
          frogCap_visible: view.frogCap ? view.frogCap.visible : 'no-node',
          player_alive: !!view.player,
          curAnimName: view.curAnimName,
        };
        try { view.onTapBag(); out.onTapBagCalled = true; } catch (e) { out.onTapBagError = String(e && e.message); }
        phase = 'waitBag';
      }
      if (phase === 'waitBag') {
        var bt = view.bag;
        if (bt && bt.bag && bt.bag.items && bt.bag.items.length) {
          clearInterval(iv);
          out.bagTableCreated = true;
          out.bagPageCreated = true;
          out.bagSlots = bt.bag.items.map(function (it, i) {
            var src = it.image ? it.image.source : null;
            return {
              slot: i,
              slotType: it.type,
              slotMeaning: SLOTNAMES[i],
              drawnSource: (typeof src === 'string') ? src : Object.prototype.toString.call(src),
              modelItemId: (M.getBagDataList() || [])[i],
            };
          });
          out.bagSlotMisplaced = out.bagSlots.filter(function (s) {
            return s.modelItemId !== -1 && s.slotType !== (DB.get(s.modelItemId) || {}).type;
          }).map(function (s) { return 'slot' + s.slot + ': ' + SLOTNAMES[s.slot] + ' 里画的是 item ' + s.modelItemId; });
          out.deskSlotTypes = (bt.table && bt.table.items ? bt.table.items : []).map(function (it) { return it.type; });
          resolve(JSON.stringify(out, null, 1));
        }
        if (Date.now() - t0 > 20000) {
          clearInterval(iv);
          out.bagTableCreated = !!bt;
          out.bagPageCreated = !!(bt && bt.bag);
          resolve(JSON.stringify(out, null, 1));
        }
      }
      if (Date.now() - t0 > 25000) { clearInterval(iv); resolve(JSON.stringify(out, null, 1)); }
    }, 250);
  });
})()
