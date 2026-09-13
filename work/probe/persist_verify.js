/* PERSISTENCE SWEEP step 3: read everything back after a reload. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'sweep.json' });
  var o = {};
  function check(name, got, want) {
    o[name] = (want === undefined) ? got : (got === want ? true : ('GOT ' + JSON.stringify(got) + ' WANT ' + JSON.stringify(want)));
  }

  check('clover', eng.state.clover, 4242);
  check('ticket', eng.state.ticket, 17);
  check('cloverSpanRerolled', eng.state.clovers[0].last_harvest > 0 ? true : 'span/last_harvest lost');

  var album = eng.dispatch('album_load', { start: 1 }).reply;
  check('albumFiled', album.pictures.length, 1);
  check('albumPending', eng.dispatch('album_load_new', {}).reply.pictures.length, 1);
  check('albumRecycleBin', eng.dispatch('album_load_recover', {}).reply.pictures.length, 1);

  var gift = eng.dispatch('travel_load_gift', {}).reply;
  check('giftPictures', gift.pictures.length, 1);
  check('giftSpecialty', gift.specialtys.length, 1);

  var bench = eng.dispatch('furniture_load_furniture', {}).reply.bench;
  check('benchSlot3', bench[2], 10211);
  var deco = eng.dispatch('client_load_decorate', {}).reply;
  check('decoPutId', deco.put_id, 100);

  var vis = eng.dispatch('visit_load', {}).reply;
  check('provinces', (vis.acquire || []).join(','), '上海,云南');
  check('visitorGift', vis.visitor && vis.visitor.gift && vis.visitor.gift.count, 4);
  check('visitorCarpet', vis.visitor && vis.visitor.carpet, 7);
  var dr = eng.dispatch('guest_load_drawing', {}).reply;
  check('drawingState', dr.state, 2);
  check('drawingColls', (dr.colls || []).join(','), '1,2');
  check('guestServed', eng.state.guest && eng.state.guest.confirmed, true);

  var wp = eng.dispatch('wishingpool_load', {}).reply;
  check('wishCoin', wp.coin, 9);
  var cap = eng.dispatch('capsule_load', {}).reply;
  // 33 is the seeded coin, PLUS the one-off opening allowance the engine grants the
  // first time the event is opened (FROG_CAPSULE_COIN, default 5). Asserting 33
  // here was wrong: it counted the seed but not the grant, so it failed with
  // "GOT 38 WANT 33" while the save round-tripped perfectly.
  var OPEN_COIN = Number(5);
  check('capsuleCoin', cap.coin, 33 + OPEN_COIN);
  check('capsuleTasksDealt', cap.task_list.length > 0 ? true : 'no tasks');

  var ck = eng.dispatch('cooking_load_cooking', {}).reply;
  check('cookingMonth', ck.month, 5);
  check('cookingPro', ck.month_pro, 2);
  check('cookingSelect', ck.select, 2);
  check('cookingTask', ck.task_list[0] && ck.task_list[0].complete, true);

  var lo = eng.dispatch('lottery_load', {}).reply;
  check('lotteryPhase', lo.phase, 7);
  check('lotteryAnswer', (lo.answer || []).join(','), '3001,3002');
  check('lotteryFlags', (lo.right_flag || []).join(','), '1,0');

  var ap = eng.dispatch('animpicture_load', {}).reply;
  check('animGuide', ap.guide, 3);
  check('animPages', ap.pic_list.length, 1);
  check('animPutNum', ap.pic_list[0] && ap.pic_list[0].put_num, 1);

  check('moments', (eng.dispatch('misc_moment_load', {}).reply.list || []).join(','), '1,101');
  var st = eng.dispatch('story_load', {}).reply;
  check('storyGift', st.stories[0] && st.stories[0].gift, 3001);
  check('storyFeedback', st.stories[0] && st.stories[0].feedback, 1);
  check('guideAwardGiven', eng.state.guide && eng.state.guide.awardGiven, true);

  var bad = Object.keys(o).filter(function (k) { return o[k] !== true; });
  return JSON.stringify({ checked: Object.keys(o).length, failed: bad, detail: o });
})()
