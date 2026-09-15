/* Seed a save with a spread of postcards, using the in-page engine itself so the
   save always has the exact shape the engine expects (no hand-written JSON that
   could drift from defaultState). Then report what the engine will hand the
   client for album_load. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'seed.json' });
  // one postcard from each artwork type, plus a few specials
  var ids = [100, 101, 102, 105, 1000, 1020, 2000, 2001, 2005, 2100, 3000, 3005];
  eng.state.pictures = ids.map(function (p, i) {
    return { id: i + 1, pic_id: p, read: 0, new: 1 };
  });
  eng.save();
  var r = eng.dispatch('album_load', { start: 1 });
  var pics = r.reply.pictures;
  return JSON.stringify({
    seeded: ids.length,
    returned: pics.length,
    withLayers: pics.filter(function (p) { return p.layers && p.layers.length; }).length,
    sample: pics.slice(0, 3).map(function (p) {
      return { pic_id: p.pic_id, n: (p.layers || []).length };
    }),
    travelers: pics.filter(function (p) { return p.travelers; }).length
  });
})()
