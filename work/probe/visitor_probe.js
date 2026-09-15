/* Browser verification of the 串门访客 (VisitorData) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'visitor.json' });
  var o = {};

  // 1. no visitor -> the `visitor` key must be ABSENT (client: `e.visitor && ...`)
  eng.state.visitor = null;
  var r0 = eng.dispatch('visit_load', {}).reply;
  o.noVisitorKey = typeof r0.visitor;
  o.acquireIsArray = Array.isArray(r0.acquire);

  // 2. full field set present
  eng.state.acquireProvinces = [];
  eng.state.visitor = {
    province: '上海', city: '上海', name: '上海', title: 3, partner: 0, food: 2,
    first: true, expire_time: 9e9, gift: { item_id: 100001, count: 2 }, carpet: 5
  };
  var r1 = eng.dispatch('visit_load', {}).reply;
  o.fields = Object.keys(r1.visitor).sort().join(',');

  // 3. first visit -> province collected, no clover
  var c0 = eng.state.clover;
  eng.dispatch('visit_open', {});
  o.acquired = eng.state.acquireProvinces.join(',');
  o.cloverAfterFirst = eng.state.clover - c0;
  o.visitorCleared = eng.state.visitor === null;

  // 4. repeat visit with clover gift -> credited + pushed
  eng.state.visitor = {
    province: '上海', city: '上海', first: false, expire_time: 9e9,
    gift: { item_id: 100000, count: 7 }, carpet: 1
  };
  var c1 = eng.state.clover;
  var ov = eng.dispatch('visit_open', {});
  o.cloverGain = eng.state.clover - c1;
  o.pushedClover = ov.pushes.filter(function (p) { return p.cmd === 'clover.update'; }).length;

  // 5. repeat visit with ticket gift
  eng.state.visitor = {
    province: '上海', city: '上海', first: false, expire_time: 9e9,
    gift: { item_id: 100001, count: 3 }, carpet: 1
  };
  var t1 = eng.state.ticket;
  var ot = eng.dispatch('visit_open', {});
  o.ticketGain = eng.state.ticket - t1;
  o.pushedTicket = ot.pushes.filter(function (p) { return p.cmd === 'item.update_ticket'; }).length;

  // 6. carpet / expiry recording
  eng.state.visitor = {
    province: '云南', city: '云南', first: true, expire_time: 0,
    gift: { item_id: 100000, count: 1 }, carpet: 0
  };
  eng.dispatch('visit_set_carpet', { id: 6 });
  eng.dispatch('visit_set_expire_time', { time: 4242 });
  o.carpet = eng.state.visitor.carpet;
  o.expire = eng.state.visitor.expire_time;

  // 7. the roll spawns a visitor
  eng.state.visitor = null;
  eng.state.visitorNextRollAt = 0;
  eng.state.visitorCoolUntil = 0;
  for (var i = 0; i < 400 && !eng.state.visitor; i++) {
    eng.state.visitorNextRollAt = 1;
    eng.tick();
  }
  o.rolled = !!eng.state.visitor;
  o.rolledProvince = eng.state.visitor ? eng.state.visitor.province : null;

  eng.save();
  o.savedAcquire = eng.state.acquireProvinces.length;
  o.savedVisitor = !!eng.state.visitor;
  return JSON.stringify(o);
})()
