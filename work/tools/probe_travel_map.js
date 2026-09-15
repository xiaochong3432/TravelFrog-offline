/* Real-page check for the destination system (work/run/engine/index.js).

   Runs INSIDE the loaded offline page (cdp_drive --step in:<this file>), so it
   proves three things the unit tests cannot:
     1. data/travel.json really is inlined in __offline-engine.js (a missing table
        degrades silently -- TV_OK would just be false);
     2. the live engine instance walks the map without throwing in the browser;
     3. the destination it reports is a real Area row and the postcards it pays are
        real Picture rows.

   The result is pushed into window.__probeLog, which `--step log` prints (an `in:`
   step's return value is not echoed by the driver).

   It mutates the CURRENT save (bag + forced trips), so it must run on a throwaway
   browser profile. */
window.__probeLog = window.__probeLog || [];
(function () {
  var e = window.__engine;
  if (!e) { window.__probeLog.push('TRAVEL PROBE: no window.__engine'); return; }
  var out = { ok: true, before: null, trips: [], after: null };

  try {
    out.before = {
      frog: e.state.frog.status,
      areas: Object.keys((e.state.travel.visited || {}).areas || {}),
    };

    /* 茄汁蛋包饭 (3, the longest lunch) + 蓝色铃铛 (1005 -> A_NORTH). */
    for (var i = 0; i < 6; i++) {
      e.state.items.bag = [3, 1005, -1, -1];
      e.state.travel.nextDepartAt = 1;
      e.state.travel.returnAt = 0;
      e.tick();
      e.state.albumPending = [];
      e.state.travel.returnAt = 1;
      e.tick();
      out.trips.push({
        visited: Object.keys((e.state.travel.visited || {}).areas || {}),
        pending: (e.state.albumPending || []).map(function (p) { return p.pic_id; }),
        specialtys: (e.state.handbook.specialtys || []).length,
        notes: (e.state.notes || []).length,
      });
    }

    out.after = {
      areas: Object.keys((e.state.travel.visited || {}).areas || {}),
      goals: ((e.state.travel.visited || {}).goals || []).slice(-4),
      notes: (e.state.notes || []).length,
    };
    if (!out.after.areas.length) out.ok = false;
  } catch (err) {
    out = { ok: false, error: String((err && err.message) || err) };
  }
  window.__probeLog.push('TRAVEL PROBE ' + JSON.stringify(out));
})();

