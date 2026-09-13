/* Browser verification of the 友情绘本 (drawing) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'drawing.json' });
  var o = {};

  // 1. full model field set
  var m0 = eng.dispatch('guest_load_drawing', {}).reply;
  o.fields = Object.keys(m0).sort().join(',');
  o.bagLen = m0.bag.length;

  // 2. gated on owning item 7001
  eng.state.items.house = [];
  eng.state.drawing.state = 0;
  eng.state.drawingNextRollAt = 0;
  for (var i = 0; i < 600 && eng.state.drawing.state === 0; i++) {
    eng.state.drawingNextRollAt = 1;
    eng.tick();
  }
  o.stateWithoutBook = eng.state.drawing.state;

  // 3. with the book -> invitation arrives
  eng.state.items.house = [{ item_id: 7001, count: 1 }];
  eng.state.drawingNextRollAt = 0;
  for (var j = 0; j < 600 && eng.state.drawing.state === 0; j++) {
    eng.state.drawingNextRollAt = 1;
    eng.tick();
  }
  o.inviteState = eng.state.drawing.state;
  o.inviteGuest = eng.state.drawing.guest;

  // 4. accept, then pack. NOTE: keep a picture book in the house too -- the
  // roll is gated on owning item 7001, so consuming the only copy into the bag
  // silently stops the whole feature (I hit exactly that while probing).
  o.acceptCode = eng.dispatch('guest_accept_invit', { accept: true }).reply.code;
  o.stateAfterAccept = eng.state.drawing.state;
  var itemId = 3001;
  eng.state.items.house = [{ item_id: 7001, count: 1 }, { item_id: itemId, count: 3 }];
  var before = 0;
  var all = eng.dispatch('item_load_items', {}).reply.house;
  for (var q = 0; q < all.length; q++) { if (all[q].item_id === itemId) before = all[q].count; }
  o.houseBefore = before;
  o.putinCode = eng.dispatch('guest_putin_bag', { pos: 2, id: itemId }).reply.code;
  o.bagPos2 = eng.state.drawing.bag[1];
  var after = 0;
  var all2 = eng.dispatch('item_load_items', {}).reply.house;
  for (var q2 = 0; q2 < all2.length; q2++) { if (all2[q2].item_id === itemId) after = all2[q2].count; }
  o.houseAfter = after;

  // 5. lock -> trip -> returns with a real collectible
  o.lockCode = eng.dispatch('guest_lock_bag', {}).reply.code;
  o.stateLocked = eng.state.drawing.state;
  o.returnArmed = eng.state.drawingReturnAt > 0;
  var who = eng.state.drawing.guest;
  var collBefore = eng.state.drawing.colls.length;
  eng.state.drawingReturnAt = 1;
  eng.tick();
  o.collsGained = eng.state.drawing.colls.length - collBefore;
  o.stateAfterReturn = eng.state.drawing.state;
  o.bagCleared = eng.state.drawing.bag.every(function (v) { return v === -1; });
  o.guestWho = who;

  // 6. reject path through the SAME command
  eng.state.drawing.state = 1;
  o.rejectCode = eng.dispatch('guest_accept_invit', { accept: false }).reply.code;
  o.stateAfterReject = eng.state.drawing.state;

  eng.save();
  o.savedColls = eng.state.drawing.colls.length;
  return JSON.stringify(o);
})()
