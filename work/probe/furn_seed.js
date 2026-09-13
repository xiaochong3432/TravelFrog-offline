/* Seed furniture state and persist it through the engine's own writer. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'p.json' });
  var list = eng.dispatch('furniture_load_furniture', {}).reply.shop.shop_list;
  var row = list[0];
  eng.state.clover = 50000;
  var buy = eng.dispatch('furniture_buy_shop', { id: row.shop_id });
  // stock up so BOTH the bench and the compost box can actually hold something
  // (otherwise the box assertion would be vacuously 0 == 0)
  eng.state.items.house = [{ item_id: row.item_id, count: 3 }];
  var p1 = eng.dispatch('furniture_putin_bench', { index: 3, id: row.item_id });
  var p2 = eng.dispatch('furniture_putin_box', { index: 4, id: row.item_id });
  eng.dispatch('furniture_replace_tumbler', { index: 3 });
  eng.dispatch('furniture_replace_compost', { index: 2 });
  eng.state.furniture.pocket.clover = 250;
  eng.save();
  window.__SEEDED__ = {
    shopId: row.shop_id, itemId: row.item_id, buyCode: buy.reply.code,
    putBench: p1.reply.code, putBox: p2.reply.code,
    clover: eng.state.clover,
    bench3: eng.state.furniture.bench[2],
    box4: eng.state.furniture.compost.boxes[3],
    boxList: eng.state.furniture.compost.boxes,
    tumblerShow: eng.state.furniture.tumbler.showIndex,
    compostShow: eng.state.furniture.compost.showIndex,
    pocket: eng.state.furniture.pocket.clover
  };
  return JSON.stringify(window.__SEEDED__);
})()
