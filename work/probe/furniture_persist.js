/* After a page reload, does the furniture state come back? The save was written
   by the previous probe through the engine's own save() (localStorage). */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'furniture-probe.json' });
  var f = eng.dispatch('furniture_load_furniture', {}).reply;
  var box = eng.dispatch('furniture_load_compost', {}).reply;
  var pocket = eng.dispatch('furniture_load_pocket', {}).reply;
  return JSON.stringify({
    clover: eng.state.clover,
    shopLen: f.shop.shop_list.length,
    shopOpen: f.shop.start_time < Math.floor(Date.now() / 1000)
      && f.shop.leave_time > Math.floor(Date.now() / 1000),
    bench: f.bench,
    boxList: box.box_list,
    compostShow: box.show_index,
    pocketShow: pocket.show_index,
    benchmark: 'expected clover 99599, bench all -1, box all 0'
  });
})()
