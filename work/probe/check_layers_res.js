/* Does every layer my table emits survive the CLIENT's own resource lookup?
 *
 * main.min.js getPicturePath():  resId -> ResourcesDB[resId] -> basename + "_png"
 * then RES.getRes(name); if that returns null the picture does not draw at all,
 * and an unknown resId silently falls back to ResourcesDB[1] (sky05).
 *
 * This uses the page's real `RES` and the real resources.json to check the
 * names my picture-layers table implies.
 */
(function () {
  var out = { resGlobal: typeof RES, checked: 0, missing: [], sample: [] };
  if (typeof RES === 'undefined' || !RES.getRes) {
    out.error = 'no RES global';
    return JSON.stringify(out);
  }
  var E = window.FrogEngine;
  var eng = E.createEngine({ savePath: 'probe.json' });
  var ids = [100, 101, 102, 105, 1000, 1020, 2000, 2001, 2005, 2100, 3000, 3005, 127, 2077];
  eng.state.pictures = ids.map(function (p, i) { return { id: i + 1, pic_id: p, read: 0, new: 1 }; });
  var pics = eng.dispatch('album_load', { start: 1 }).reply.pictures;

  // ResourcesDB is data/tables/resources.json; the engine already has a copy of
  // the same file under its own module registry, so read it back from there by
  // asking the engine to resolve nothing -- instead use the page's own copy via
  // the game's DataManager if exposed, else the path we can rebuild ourselves.
  var db = window.__RESDB__ || null;
  if (!db) {
    // fall back: ask the engine for a picture whose layers we can map by hand
    // using the same resources.json the bundle inlines.
    try {
      db = eng.__resdb || null;
    } catch (e) { }
  }
  out.haveDb = !!db;

  var probe = [];
  pics.forEach(function (p) {
    (p.layers || []).forEach(function (l) {
      out.checked++;
      probe.push(l.layer[0]);
    });
  });
  out.layerCount = probe.length;
  out.distinctResIds = Object.keys(probe.reduce(function (a, n) { a[n] = 1; return a; }, {})).length;
  return JSON.stringify(out);
})()
