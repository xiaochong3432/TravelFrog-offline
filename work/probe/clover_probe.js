/* Browser verification of the clover rule the CLIENT depends on. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'clover.json' });
  var o = {};
  var now = Math.floor(Date.now() / 1000);

  // what clover_load_clovers actually sends
  var list = eng.dispatch('clover_load_clovers', {}).reply;
  o.slots = list.length;
  o.fields = Object.keys(list[0]).sort().join(',');
  o.spanPositive = list[0].rebirth_span > 0;

  // reproduce the client's own draw condition on the real payload
  function drawn(s) {
    return !(s.last_harvest === -1 || (s.last_harvest > 0 && s.last_harvest + s.rebirth_span > now));
  }
  var c = list[0];
  o.readyDrawn = drawn({ last_harvest: 0, rebirth_span: c.rebirth_span });
  o.emptyDrawn = drawn({ last_harvest: -1, rebirth_span: c.rebirth_span });
  o.growingDrawn = drawn({ last_harvest: now - 10, rebirth_span: 3600 });
  o.elapsedDrawn = drawn({ last_harvest: now - 4000, rebirth_span: 3600 });

  // a real harvest must flip the slot to growing and re-roll the span
  c.last_harvest = 0; c.element = 0; c.sprite = 1;
  var before = c.rebirth_span;
  var r = eng.dispatch('clover_harvest', { clover_id: 1 });
  var after = eng.dispatch('clover_load_clovers', {}).reply[0];
  o.harvestCode = r.reply.code;
  o.afterHarvestGrows = drawn(after) === false;
  o.spanRerolledOverTrials = (function () {
    var changed = 0;
    for (var i = 0; i < 20; i++) {
      eng.state.clovers[0].last_harvest = 0;
      eng.state.clovers[0].element = 0;
      eng.state.clovers[0].sprite = 1;
      var b = eng.state.clovers[0].rebirth_span;
      eng.dispatch('clover_harvest', { clover_id: 1 });
      if (eng.state.clovers[0].rebirth_span !== b) changed++;
    }
    return changed;
  })();

  eng.save();
  o.savedSpan = eng.state.clovers[0].rebirth_span;
  return JSON.stringify(o);
})()
