/* Browser verification of the 回忆彩蛋 unlock rule (MomentType). */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'mt.json' });
  var o = {};

  // 1. frog motion -> type 1
  eng.state.moments = [];
  eng.state.frog.status = 0;
  var got1 = 0;
  for (var i = 0; i < 500 && got1 === 0; i++) {
    eng.state.frog.motionNextAt = 0;
    eng.tick();
    got1 = eng.state.moments.length;
  }
  o.type1Unlocked = got1;
  o.type1Sample = eng.state.moments.slice(0, 4);

  // 2. guest arrival -> type 3
  eng.state.moments = [];
  eng.state.guest = null;
  eng.state.guestCoolUntil = 0;
  eng.state.guestNextRollAt = 0;
  for (var j = 0; j < 700 && !eng.state.guest; j++) {
    eng.state.guestNextRollAt = 1;
    eng.tick();
  }
  o.guestArrived = !!eng.state.guest;
  o.afterGuest = eng.state.moments.slice();

  // 3. shop purchase -> type 4
  eng.state.moments = [];
  eng.state.clover = 100000;
  var f = eng.dispatch('furniture_load_furniture', {}).reply;
  var row = f.shop.shop_list[0];
  o.buyCode = eng.dispatch('furniture_buy_shop', { id: row.shop_id }).reply.code;
  o.afterBuy = eng.state.moments.slice();

  // 4. the explicit unlock command still works and stays idempotent
  eng.state.moments = [];
  o.manualCode = eng.dispatch('misc_moment_unlock', { id: 1 }).reply.code;
  o.afterManual = eng.dispatch('misc_moment_load', {}).reply.list.slice();
  o.manualDup = eng.dispatch('misc_moment_unlock', { id: 1 }).reply.code;
  o.afterDup = eng.dispatch('misc_moment_load', {}).reply.list.length;

  eng.save();
  o.saved = eng.state.moments.length;
  return JSON.stringify(o);
})()
