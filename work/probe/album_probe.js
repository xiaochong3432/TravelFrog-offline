/* Browser verification of the album management subsystem: pending -> album ->
   recycle bin -> recover, plus by-id loading and the save path. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'album.json' });
  var o = {};

  // 1. pending bucket is delivered by album_load_new and is NOT in the album
  eng.state.pictures = [];
  eng.state.albumDeleted = [];
  eng.state.albumPending = [{ id: 42, pic_id: 102, read: 0, new: 1 }];
  var n = eng.dispatch('album_load_new', {}).reply;
  o.newPics = n.pictures.length;
  o.newHasLayers = !!(n.pictures[0] && n.pictures[0].layers && n.pictures[0].layers.length);
  o.newForAds = n.pictures[0] && n.pictures[0].for_ads;
  o.hasAds = n.has_ads;
  o.albumBeforeFile = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;

  // 2. file it
  o.saveNewCode = eng.dispatch('album_save_new', { id: 42 }).reply.code;
  o.albumAfterFile = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;
  o.pendingAfterFile = eng.dispatch('album_load_new', {}).reply.pictures.length;

  // 3. delete -> recycle bin -> recover
  o.deleteCode = eng.dispatch('album_delete', { id: 42 }).reply.code;
  o.albumAfterDelete = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;
  var bin = eng.dispatch('album_load_recover', {}).reply.pictures;
  o.binLen = bin.length;
  o.binHasLayers = !!(bin[0] && bin[0].layers && bin[0].layers.length);
  o.recoverCode = eng.dispatch('album_recover', { id: 42 }).reply.code;
  o.albumAfterRecover = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;
  o.binAfterRecover = eng.dispatch('album_load_recover', {}).reply.pictures.length;

  // 4. album full -> save_new must answer 75 (the client drops the pending row)
  eng.state.pictures = [];
  for (var k = 0; k < 60; k++) {
    eng.state.pictures.push({ id: 1000 + k, pic_id: 100 + (k % 40), read: 0, new: 1 });
  }
  eng.state.albumPending = [{ id: 77, pic_id: 300, read: 0, new: 1 }];
  o.fullSaveCode = eng.dispatch('album_save_new', { id: 77 }).reply.code;
  o.pendingAfterFull = eng.dispatch('album_load_new', {}).reply.pictures.length;

  // 5. by-id load takes a plain number array
  var byid = eng.dispatch('album_load_by_id_list', { id_list: [1000, 1002] }).reply;
  o.byIdLen = byid.pictures.length;
  o.byIdIds = byid.pictures.map(function (p) { return p.id; });

  // 6. delete_new must not resurrect the row
  eng.state.albumPending = [{ id: 88, pic_id: 101, read: 0, new: 1 }];
  eng.dispatch('album_delete_new', { id: 88 });
  o.pendingAfterDeleteNew = eng.dispatch('album_load_new', {}).reply.pictures.length;

  // 7. the save-editor escape hatch, then persist
  eng.state.albumPending = [{ id: 99, pic_id: 105, read: 0, new: 1 }];
  eng.state.pictures = eng.state.pictures.slice(0, 3);
  var gm = eng.dispatch('client_gm', { cmd: 'file_pending' }).reply;
  o.gmOk = gm.succeed;
  o.gmInfo = gm.info;
  eng.save();
  o.savedAlbum = eng.state.pictures.length;
  o.savedBin = eng.state.albumDeleted.length;
  return JSON.stringify(o);
})()
