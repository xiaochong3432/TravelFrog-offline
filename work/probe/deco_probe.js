/* Browser verification of the 庭院装饰 (decoration) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'deco.json' });
  var o = {};

  // 1. exact payload keys
  eng.state.decoration = { hasList: [{ id: 100, num: 2 }], putId: 101, status: 1 };
  var m = eng.dispatch('client_load_decorate', {}).reply;
  o.keys = Object.keys(m).sort().join(',');
  o.itemKeys = Object.keys(m.has_list[0]).sort().join(',');
  o.putId = m.put_id;
  o.status = m.status;

  // 2. display a flower
  eng.state.decoration = { hasList: [{ id: 100, num: 1 }], putId: 0, status: 0 };
  o.changeCode = eng.dispatch('client_change_decorate', { id: 100 }).reply.code;
  o.putAfter = eng.state.decoration.putId;
  o.statusAfter = eng.state.decoration.status;

  // 3. swapping consumes the OLD one only
  eng.state.decoration = { hasList: [{ id: 100, num: 1 }, { id: 101, num: 2 }], putId: 100, status: 1 };
  o.swapCode = eng.dispatch('client_change_decorate', { id: 101 }).reply.code;
  o.putAfterSwap = eng.state.decoration.putId;
  o.oldGone = !eng.state.decoration.hasList.some(function (x) { return x.id === 100; });
  var n101 = 0;
  for (var i = 0; i < eng.state.decoration.hasList.length; i++) {
    if (eng.state.decorhasOwnProperty === undefined) { }
    if (eng.state.decoration.hasList[i].id === 101) n101 = eng.state.decoration.hasList[i].num;
  }
  o.newNotDecremented = n101;

  // 4. not owned -> refused
  eng.state.decoration = { hasList: [], putId: 0, status: 0 };
  o.notOwned = eng.dispatch('client_change_decorate', { id: 100 }).reply.code;
  o.bogus = eng.dispatch('client_change_decorate', { id: 999999 }).reply.code;

  // 5. trips bring flowers home, and every id is real
  eng.state.decoration = { hasList: [], putId: 0, status: 0 };
  var lunch = null;
  for (var j = 0; j < eng.state.items.house.length && lunch === null; j++) {
    if (eng.state.items.house[j].item_id === 1) lunch = 1;
  }
  for (var k = 0; k < 60; k++) {
    eng.state.items.bag[0] = eng.state.items.bag[0] || 1;
    eng.state.travel.nextDepartAt = 1;
    eng.tick();
    eng.state.travel.returnAt = 1;
    eng.tick();
  }
  var total = 0;
  for (var q = 0; q < eng.state.decoration.hasList.length; q++) {
    total += eng.state.decoration.hasList[q].num;
  }
  o.flowersFromTrips = total;
  o.distinctFlowers = eng.state.decoration.hasList.length;

  eng.save();
  o.savedPut = eng.state.decoration.putId;
  return JSON.stringify(o);
})()
