/* Browser verification of the furniture subsystem.
 *
 * Drives the real protocol commands through the in-page engine and reports the
 * resulting authoritative state, so this is render-independent but exercises the
 * exact code the page runs. Also writes the state to localStorage through the
 * engine's own save() so a later probe can confirm it persisted.
 */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'furniture-probe.json' });
  var log = {};

  // --- shop window + list -------------------------------------------------
  var f0 = eng.dispatch('furniture_load_furniture', {}).reply;
  log.shopStart = f0.shop.start_time;
  log.shopLeave = f0.shop.leave_time;
  log.shopListLen = f0.shop.shop_list.length;
  log.shopRow0 = f0.shop.shop_list[0];
  log.benchLen = f0.bench.length;

  // --- buy the cheapest priced row ---------------------------------------
  eng.state.clover = 100000;
  var row = null;
  for (var i = 0; i < f0.shop.shop_list.length; i++) {
    var r = f0.shop.shop_list[i];
    var def = (window.FrogEngine && eng.__shop) ? null : null;
    row = r; break;
  }
  log.buyTarget = row;
  var before = eng.state.clover;
  var buy = eng.dispatch('furniture_buy_shop', { id: row.shop_id });
  log.buyCode = buy.reply.code;
  log.cloverDelta = eng.state.clover - before;
  log.pushedClover = buy.pushes.filter(function (p) { return p.cmd === 'clover.update'; }).length;
  log.pushedItem = buy.pushes.filter(function (p) { return p.cmd === 'item.update'; }).length;
  var f1 = eng.dispatch('furniture_load_furniture', {}).reply;
  log.shopLenAfter = f1.shop.shop_list.length;
  log.ownedAfter = eng.state.furniture.owned.length;

  // --- bench round trip --------------------------------------------------
  var itemId = row.item_id;
  var haveBefore = eng.state.items.house.filter(function (h) { return h.item_id === itemId; })
    .reduce(function (a, h) { return a + h.count; }, 0);
  log.toolHave = haveBefore;
  var put = eng.dispatch('furniture_putin_bench', { index: 1, id: itemId });
  log.putCode = put.reply.code;
  log.benchSlot0 = eng.dispatch('furniture_load_furniture', {}).reply.bench[0];
  var out = eng.dispatch('furniture_takeout_bench', { index: 1 });
  log.takeoutCode = out.reply.code;
  log.benchSlot0After = eng.dispatch('furniture_load_furniture', {}).reply.bench[0];

  // --- compost box -------------------------------------------------------
  var putBox = eng.dispatch('furniture_putin_box', { index: 2, id: itemId });
  log.boxPutCode = putBox.reply.code;
  log.boxList = eng.dispatch('furniture_load_compost', {}).reply.box_list;
  log.boxTakeCode = eng.dispatch('furniture_takeout_box', { index: 2 }).reply.code;

  // --- replace commands --------------------------------------------------
  log.tumblerShow = eng.dispatch('furniture_replace_tumbler', { index: 2 }).reply.code;
  log.tumblerHide = eng.dispatch('furniture_replace_tumbler', { index: 2 }).reply.code;
  log.compostShow = eng.dispatch('furniture_replace_compost', { index: 1 }).reply.code;
  log.pocketShow = eng.dispatch('furniture_replace_pocket', { index: 1 }).reply.code;

  // --- pocket ------------------------------------------------------------
  eng.state.furniture.pocket.clover = 99;
  var c0 = eng.state.clover;
  var pg = eng.dispatch('furniture_pocket_get', {});
  log.pocketGetCode = pg.reply.code;
  log.pocketCredited = eng.state.clover - c0;
  log.pocketAfter = eng.state.furniture.pocket.clover;

  // persist through the engine's own writer so a reload can verify it
  eng.save();
  log.savedClover = eng.state.clover;
  log.savedOwned = eng.state.furniture.owned.length;
  return JSON.stringify(log);
})()
