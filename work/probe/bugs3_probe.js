/* Reproduce the reported crashes through the client's OWN entry points.

A) 喂特产给小伙伴: force a guest through the engine, let the push reach the client,
   then call TravelModel.sendGuestServed(itemId) -- the exact call the food button makes.
B) 解锁全部明信片: run the in-game GM command (client_gm), reload the album, open the
   album view and read what the model holds (layers or not).
C) 定位"门口的纸条": list every touchable node in the scene whose name or class smells
   like a note / door / letter, with coordinates, so it can be tapped deliberately. */
const out = {};
const E = window.__engine;
const now = Math.floor(Date.now() / 1000);
const M = core.ModelManage.getInstance();
const gm = (cmd) => {
  try { return JSON.stringify(E.dispatch('client_gm', { cmd }).reply).slice(0, 160); }
  catch (e) { return 'THREW ' + String(e.message || e); }
};

/* ---------------------------------------------------------------- A) 喂食 */
out.A = {};
try {
  E.state.guest = { id: 0, confirmed: true, served: false, expire_time: now + 3600, pos: 0 };
  E.dispatch('guest_load', {});                       // push the guest to the client
  const Travel = M.getModel(TravelModel);
  const g = Travel.getGuestData();
  out.A.clientGuestId = g && g.id;
  out.A.gmAddSpecialty = gm('add_specialty 3005 2');
  const spec = E.state.specia || E.state.specialtys.find((s) => s.count > 0);
  out.A.specialty = spec && spec.item_id;
  out.A.houseHasIt = E.state.items.house.some((h) => h.item_id === 3005 && h.count > 0);
  if (spec) {
    try {
      Travel.sendGuestServed(spec.item_id);
      out.A.served = 'called';
    } catch (e) {
      out.A.served = 'THREW ' + String(e && e.message || e);
    }
  }
} catch (e) {
  out.A.error = String(e && e.message || e);
}

/* ---------------------------------------------------- B) 解锁全部明信片 */
out.B = {};
try {
  out.B.gmUnlock = gm('unlock_pictures');
  const all = E.dispatch('album_load_all', {}).reply;
  out.B.total = all.total;
  out.B.withLayers = (all.pictures || []).filter((p) => p.layers).length;
  out.B.withoutLayers = (all.pictures || []).filter((p) => !p.layers).length;
  out.B.missingSample = (all.pictures || []).filter((p) => !p.layers)
    .slice(0, 10).map((p) => p.pic_id);
  /* open the album the way the button does */
  core.PageManage.getInstance().addViewControl(AlbumController,
    core.ViewLayerType.WindowLayer, core.RemoveViewType.HideBefore);
  out.B.albumOpened = true;
} catch (e) {
  out.B.error = String(e && e.message || e);
}

/* ------------------------------------------- C) 找"门口"的可点节点（只列举） */
try {
  const list = [];
  (function w(n, d) {
    if (!n || d > 15 || list.length > 120) return;
    const name = String(n.name || '');
    let cls = String(n.__class__ || '');
    if (!cls) {
      try { cls = String(n.constructor && n.constructor.name || ''); } catch (e) { /* */ }
    }
    if (/note|door|letter|paper|clover|wall/i.test(name) || /Note|Door|Letter/i.test(cls)) {
      list.push({ name, cls, touch: !!n.touchEnabled, x: Math.round(n.x),
        y: Math.round(n.y), visible: !!n.visible });
    }
    const k = n.$children || [];
    for (let i = 0; i < k.length; i++) w(k[i], d + 1);
  })(egret.MainContext.instance.stage, 0);
  out.C = list;
} catch (e) {
  out.C = { error: String(e && e.message || e) };
}

return JSON.stringify(out);
