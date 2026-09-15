/* Read the furniture state back after a reload. Compare against __EXPECTED__,
   which the harness pastes from the seed step. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'p.json' });
  var f = eng.dispatch('furniture_load_furniture', {}).reply;
  var box = eng.dispatch('furniture_load_compost', {}).reply;
  var got = {
    clover: eng.state.clover,
    bench3: f.bench[2],
    box4: box.box_list[3],
    boxList: box.box_list,
    tumblerShow: eng.state.furniture.tumbler.showIndex,
    compostShow: box.show_index,
    pocket: eng.state.furniture.pocket.clover,
    owned: eng.state.furniture.owned.length,
    shopLen: f.shop.shop_list.length,
    expect: 'clover 49500, bench3 8002, box4 8002, tumblerShow 3, compostShow 2, pocket 250, shopLen 152'
  };
  return JSON.stringify(got);
})()
