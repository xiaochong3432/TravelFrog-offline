/* Browser verification of the 许愿池 (wishingpool) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'wish.json' });
  var o = {};

  // 1. the pool is OPEN (isOpen() is now < end_time; 0 would mean never)
  var l0 = eng.dispatch('wishingpool_load', {}).reply;
  var now = Math.floor(Date.now() / 1000);
  o.endTimeFuture = l0.end_time > now;
  o.coin = l0.coin;
  o.prizes = l0.items.length;
  o.itemShape = l0.items[0] ? Object.keys(l0.items[0]).sort().join(',') : null;

  // 2. a wish draws, spends a coin, decrements the drawn stock
  var c0 = l0.coin;
  var houseBefore = eng.state.items.house.length;
  var w = eng.dispatch('wishingpool_wish', {});
  o.wishId = w.reply.id;
  o.stateChanges = w.stateChanges || null;
  o.pushedItem = w.pushes.filter(function (p) { return p.cmd === 'item.update'; }).length;
  var l1 = eng.dispatch('wishingpool_load', {}).reply;
  o.coinAfter = l1.coin;
  o.coinSpent = c0 - l1.coin;
  var b = null, a = null;
  for (var i = 0; i < l0.items.length; i++) { if (l0.items[i].id === w.reply.id) b = l0.items[i]; }
  for (var j = 0; j < l1.items.length; j++) { if (l1.items[j].id === w.reply.id) a = l1.items[j]; }
  o.limitBefore = b && b.limit;
  o.limitAfter = a && a.limit;

  // 3. no coins -> id 0 (the only signal the client acts on)
  eng.state.wishingPool.coin = 0;
  o.noCoinId = eng.dispatch('wishingpool_wish', {}).reply.id;

  // 4. no stock -> id 0 and no coin spent
  for (var k = 0; k < eng.state.wishingPool.items.length; k++) {
    eng.state.wishingPool.items[k].limit = 0;
  }
  eng.state.wishingPool.coin = 7;
  o.noStockId = eng.dispatch('wishingpool_wish', {}).reply.id;
  o.coinUnspent = eng.state.wishingPool.coin;

  // 5. stock never goes negative
  for (var m = 0; m < eng.state.wishingPool.items.length; m++) {
    eng.state.wishingPool.items[m].limit = 2;
  }
  eng.state.wishingPool.coin = 50;
  for (var q = 0; q < 50; q++) eng.dispatch('wishingpool_wish', {});
  var neg = 0;
  for (var r = 0; r < eng.state.wishingPool.items.length; r++) {
    if (eng.state.wishingPool.items[r].limit < 0) neg++;
  }
  o.negativeLimits = neg;

  eng.save();
  o.savedCoin = eng.state.wishingPool.coin;
  return JSON.stringify(o);
})()
