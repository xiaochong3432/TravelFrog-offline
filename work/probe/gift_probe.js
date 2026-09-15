/* Browser verification of the gift box (礼品盒) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'gift.json' });
  var out = {};

  // specialties come from the real table
  var SPEC = null;
  try { SPEC = eng.dispatch('travelload', {}); } catch (e) { }

  // 1. album must NOT leak into the gift box
  eng.state.pictures = [{ id: 1, pic_id: 100, read: 0, new: 1 }];
  var g0 = eng.dispatch('travel_load_gift', {}).reply;
  out.albumCount = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;
  out.giftBoxPictures = g0.pictures.length;
  out.giftBoxSpecialtys = g0.specialtys.length;

  // 2. album -> gift box -> album
  out.toGift = eng.dispatch('travel_album_to_gift', { picture_id: 1 }).reply.code;
  out.albumAfterMove = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;
  var g1 = eng.dispatch('travel_load_gift', {}).reply;
  out.giftPicsAfter = g1.pictures.length;
  out.giftPicHasLayers = !!(g1.pictures[0] && g1.pictures[0].layers
    && g1.pictures[0].layers.length);
  out.backToAlbum = eng.dispatch('travel_gift_to_album', { picture_id: 1 }).reply.code;
  out.albumRestored = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;

  // 3. specialty: buy a real one into the house, then stage/unstage
  var itemId = null;
  var items = eng.dispatch('item_load_items', {}).reply;
  for (var i = 0; i < items.house.length && !itemId; i++) { itemId = items.house[i].item_id; }
  if (itemId === null) {
    // put a known specialty in by hand (engine already validates against Item.json)
    itemId = 3014;
    eng.state.items.house = [{ item_id: itemId, count: 3 }];
  }
  out.stageCode = eng.dispatch('travel_bag_to_gift', { item_id: itemId }).reply.code;
  var g2 = eng.dispatch('travel_load_gift', {}).reply;
  out.stagedSpecialtys = g2.specialtys.length;
  out.unstageCode = eng.dispatch('travel_gift_to_bag', { item_id: itemId }).reply.code;
  out.giftBoxEmpty = eng.dispatch('travel_load_gift', {}).reply.specialtys.length;

  // 4. caps -> the client's own error branches
  eng.state.giftBox.specialtys = [{ item_id: itemId, count: 100 }];
  eng.state.items.house = [{ item_id: itemId, count: 2 }];
  out.fullBoxCode = eng.dispatch('travel_bag_to_gift', { item_id: itemId }).reply.code;
  eng.state.giftBox.specialtys = [];
  eng.state.pictures = [];
  for (var k = 0; k < 60; k++) {
    eng.state.pictures.push({ id: 1000 + k, pic_id: 100 + k, read: 0, new: 1 });
  }
  eng.state.giftBox.pictures = [{ id: 7777, pic_id: 200, read: 0, new: 1 }];
  out.fullAlbumCode = eng.dispatch('travel_gift_to_album', { picture_id: 7777 }).reply.code;

  // 5. notes + select_gift
  eng.state.notes = [{ id: 1, read: 0, timestamp: 5 }];
  eng.dispatch('travel_read_note', { id: [1] });
  out.noteRead = eng.dispatch('travel_load_note', {}).reply.note_list[0].read;
  eng.state.selectGift = { 0: { item_id: itemId, count: 2 } };
  var sg = eng.dispatch('item_select_gift', { index_list: [0] }).reply;
  out.selectGiftItems = sg.items.length;
  out.selectGiftReplay = eng.dispatch('item_select_gift', { index_list: [0] }).reply.items.length;

  eng.save();
  out.savedGiftPics = eng.state.giftBox.pictures.length;
  return JSON.stringify(out);
})()
