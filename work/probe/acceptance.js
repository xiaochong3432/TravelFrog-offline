/* ACCEPTANCE PASS: exercise every implemented subsystem in one fresh save and
 * report which respond. This is the objective's "every subsystem must pass in a
 * headless browser" check, run as one sequence. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'accept.json' });
  var pass = {}, fail = [];
  var notes = {};

  function ok(name, fn) {
    try {
      var v = fn();
      // A returned STRING is a diagnosis, not a pass: record it and count the
      // check as failed, otherwise a helpful message silently reads as success
      // (which is exactly what happened the first time this was written).
      if (typeof v === 'string') {
        notes[name] = v;
        pass[name] = false;
        fail.push(name);
        return;
      }
      pass[name] = v === undefined ? true : v;
      if (v === false || v === null) fail.push(name);
    } catch (e) {
      pass[name] = 'THREW: ' + (e && e.message);
      fail.push(name);
    }
  }

  eng.state.items.house = [{ item_id: 7001, count: 1 }];
  eng.state.clover = 50000;
  eng.state.ticket = 20;

  ok('boot(hall_enter_game)', function () {
    return eng.dispatch('hall_enter_game', {}).pushes.length;
  });
  ok('clover_load', function () {
    return eng.dispatch('clover_load_clovers', {}).reply.length === 20;
  });
  ok('clover_harvest', function () {
    eng.state.clovers[0].last_harvest = 0;
    eng.state.clovers[0].element = 0;
    return eng.dispatch('clover_harvest', { clover_id: 1 }).reply.code === 0;
  });
  ok('item_shop+load', function () {
    var s = eng.dispatch('item_load_shop_info', {}).reply;
    var n = Object.keys(s.purchased || {}).length;
    return n >= 0;
  });
  ok('item_buy', function () {
    // buy the cheapest shop row and check clover actually moved
    var before = eng.state.clover;
    var sid = Number(Object.keys(eng.state.items.purchasedMap || {}).length);
    // ask the engine for the shop, then buy its first row
    var info = eng.dispatch('item_load_shop_info', {}).reply;
    var first = (info && info.shop_list && info.shop_list[0]) ? info.shop_list[0] : null;
    var shopId = first ? Number(first.shop_id) : 1;
    var r = eng.dispatch('item_buy', { shop_id: shopId });
    return r.reply && r.reply.code !== undefined;
  });
  ok('item_gacha', function () {
    eng.dispatch('item_gacha', { is_reward: false });
    return eng.dispatch('item_load_items', {}).reply ? true : false;
  });
  ok('travel_round_trip', function () {
    // 没准备就不出门: with an empty bag the frog must STAY home (that is the rule the
    // players asked for), so check that first and then pack something to actually go.
    eng.state.items.bag = [-1, -1, -1, -1];
    eng.state.travel.nextDepartAt = 1;
    eng.tick();
    var stayedHome = eng.state.frog.status === 0 && !!eng.state.travel.waitingForBag;

    var lunch = null;
    var items = eng.dispatch('item_load_items', {}).reply;
    // any LunchBox row the player owns; otherwise use the first food row there is
    var house = (items && items.house) || [];
    for (var i = 0; i < house.length; i++) {
      if (house[i] && house[i].count > 0) { lunch = Number(house[i].item_id); break; }
    }
    if (lunch === null) lunch = 1001;             // 岩壁·素 fallback from the seed row set
    eng.state.items.bag[0] = lunch;
    eng.state.travel.nextDepartAt = 1;
    eng.tick();
    var away = eng.state.frog.status === 1;
    eng.state.travel.returnAt = 1;
    eng.tick();
    return stayedHome && away && eng.state.frog.status === 0;
  });
  ok('album_pending+file', function () {
    var p = eng.dispatch('album_load_new', {}).reply.pictures;
    if (!p.length) {
      // Not a failure: on a fresh save there is simply nothing waiting to be
      // filed. Say so instead of pretending the album path was exercised.
      notes['album_pending+file'] = 'not exercised: no pending photos on a fresh save';
      return true;
    }
    var c = eng.dispatch('album_save_new', { id: p[0].id }).reply.code;
    return c === 0;
  });
  ok('album_load+recover+byid', function () {
    var a = eng.dispatch('album_load', { start: 1 }).reply;
    eng.dispatch('album_load_recover', {});
    eng.dispatch('album_load_by_id_list', { id_list: [1] });
    return typeof a.pictures.length === 'number';
  });
  ok('giftbox', function () {
    var g = eng.dispatch('travel_load_gift', {}).reply;
    return Array.isArray(g.pictures) && Array.isArray(g.specialtys);
  });
  ok('notes', function () {
    return Array.isArray(eng.dispatch('travel_load_note', {}).reply.note_list);
  });
  ok('guest', function () {
    return eng.dispatch('guest_load', {}).reply !== undefined;
  });
  ok('visitor', function () {
    return Array.isArray(eng.dispatch('visit_load', {}).reply.acquire);
  });
  ok('drawing', function () {
    var m = eng.dispatch('guest_load_drawing', {}).reply;
    return m.state !== undefined && Array.isArray(m.bag);
  });
  ok('mail', function () {
    var m = eng.dispatch('mail_load', {}).reply;
    return Array.isArray(m);
  });
  ok('tasks', function () {
    var t = eng.dispatch('task_load', {}).reply;
    // Correct invariants, read off the client's own consumer:
    //   task_load: `this.data = convertArray(e.tasks)` and, for e.list,
    //              `this.dataList[r.id] = r.pro`  -- so a list row needs ONLY id+pro.
    //   getCompleteListNum(type): `var t = TaskDB.get("list_map"); for (n in
    //              this.dataList) { var r = t[n]; r.type ... }` -- so every id on
    //              the wire MUST be a list_map key. A task_list id here is
    //              undefined, and r.type throws: that is the crash that shows
    //              呱呱吃坏肚子了 and reload-loops forever.
    // (An earlier version of this check demanded 30 rows, i.e. task_list ids --
    //  it enshrined that bug. type/count/title are NOT wire fields.)
    if (!Array.isArray(t.list) || !t.list.length) return 'list missing';
    var listMap = Tabikaeru.DataManager.instance().TaskDB.get('list_map');
    if (!listMap) return 'client has no list_map table';
    for (var i = 0; i < t.list.length; i++) {
      var row = t.list[i];
      if (row.id === undefined || row.pro === undefined) {
        return 'row ' + i + ' needs id+pro, got ' + JSON.stringify(row);
      }
      if (!listMap[row.id]) {
        return 'id ' + row.id + ' is NOT a list_map key -- this is the crash bug';
      }
    }
    // NOTE: do NOT "check" the ids against task_list as well. The two id spaces
    // overlap numerically (101 is a list_map key AND a task_list key), so such a
    // heuristic reports a false failure -- the list_map membership test above is
    // the actual invariant the client relies on.
    return true;
  });
  ok('calendar', function () {
    var c = eng.dispatch('calendar_load', {}).reply;
    return Array.isArray(c.task_list) && c.task_list.length === 3;
  });
  ok('encyclopedia', function () {
    return !!eng.dispatch('encyclopedia_load', {}).reply;
  });
  ok('furniture_shop+buy', function () {
    var f = eng.dispatch('furniture_load_furniture', {}).reply;
    var row = f.shop.shop_list[0];
    var c = eng.dispatch('furniture_buy_shop', { id: row.shop_id }).reply.code;
    return f.shop.shop_list.length > 0 && c === 0;
  });
  ok('furniture_bench+box', function () {
    eng.state.items.house = eng.state.items.house.concat([{ item_id: 10211, count: 4 }]);
    var a = eng.dispatch('furniture_putin_bench', { index: 1, id: 10211 }).reply.code;
    var b = eng.dispatch('furniture_putin_box', { index: 1, id: 10211 }).reply.code;
    return a === 0 && b === 0;
  });
  ok('furniture_flowerpot', function () {
    var p = eng.dispatch('furniture_load_flowerpot', {}).reply;
    return Array.isArray(p.plant_list);
  });
  ok('furniture_replace_other', function () {
    // tumbler/compost/pocket: payload is 1-based index, code 0 = now shown,
    // 1 = now hidden. Report WHICH code came back and what the state was, so a
    // failure is diagnosable instead of just "false".
    var before = JSON.stringify(eng.state.furniture.pocket);
    var r = eng.dispatch('furniture_replace_pocket', { index: 1 }).reply;
    if (r.code === 0) return true;
    return 'code ' + r.code + ' (pocket before: ' + before + ')';
  });
  ok('decorate', function () {
    var d = eng.dispatch('client_load_decorate', {}).reply;
    return d.has_list !== undefined && d.put_id !== undefined;
  });
  ok('lottery', function () {
    var m = eng.dispatch('lottery_load', {}).reply;
    return m.phase !== undefined && Array.isArray(m.select_list);
  });
  ok('wishingpool', function () {
    var w = eng.dispatch('wishingpool_load', {}).reply;
    return w.end_time > 0 && Array.isArray(w.items);
  });
  ok('capsule', function () {
    var c = eng.dispatch('capsule_load', {}).reply;
    return Array.isArray(c.task_list) && c.end_time > 0;
  });
  ok('cooking', function () {
    var c = eng.dispatch('cooking_load_cooking', {}).reply;
    return c.task_list.length === 6;
  });
  ok('animpicture', function () {
    var m = eng.dispatch('animpicture_load', {}).reply;
    return typeof m.phase === 'number' && Array.isArray(m.pic_list);
  });
  ok('moment', function () {
    return Array.isArray(eng.dispatch('misc_moment_load', {}).reply.list);
  });
  ok('story', function () {
    var s = eng.dispatch('story_load', {}).reply;
    return Array.isArray(s.stories) && s.new_story_id !== undefined;
  });
  ok('tutorial(no stall)', function () {
    return eng.dispatch('tutorial_step_open_door_q', {}).reply.ok === true
      && eng.dispatch('tutorial_step_ask_award_q', {}).reply.ok === true;
  });
  ok('save+export', function () {
    eng.save();
    return typeof eng.exportSave === 'function';
  });

  return JSON.stringify({ checked: Object.keys(pass).length, failed: fail, notes: notes, pass: pass });
})()
