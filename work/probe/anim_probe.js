/* Browser verification of the 动态照片 (animpicture) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'anim.json' });
  var o = {};

  var l0 = eng.dispatch('animpicture_load', {}).reply;
  o.fields = Object.keys(l0).sort().join(',');
  o.picListLen = l0.pic_list.length;

  // the gate
  var u0 = eng.dispatch('animpicture_use_item', {});
  o.phaseType = typeof u0.reply.phase;
  o.phaseGeZero = u0.reply.phase >= 0;

  // select a pic_map postcard (100 is in pic_map)
  eng.state.pictures = [{ id: 5001, pic_id: 100, read: 0, new: 1 }];
  o.selectCode = eng.dispatch('animpicture_select_pic', { id: 5001 }).reply.code;
  o.albumAfterSelect = eng.state.pictures.length;
  var l1 = eng.dispatch('animpicture_load', {}).reply;
  o.pages = l1.pic_list.length;
  o.pageSlot = l1.pic_list.length ? l1.pic_list[0].id : null;
  o.phaseAfterSelect = l1.phase;

  // a postcard NOT in pic_map must be refused
  eng.state.pictures = [{ id: 5002, pic_id: 9999, read: 0, new: 1 }];
  o.notInMapCode = eng.dispatch('animpicture_select_pic', { id: 5002 }).reply.code;
  o.albumAfterRefusal = eng.state.pictures.length;

  // open_album walk
  o.openCode = eng.dispatch('animpicture_open_album', { index: 1 }).reply.code;
  o.putNum = eng.dispatch('animpicture_load', {}).reply.pic_list[0].put_num;

  // place a photo then take it back
  eng.state.pictures = [{ id: 5003, pic_id: 100, read: 0, new: 1 }];
  o.addCode = eng.dispatch('animpicture_album_add_pic', { index: 1, slot: 1, id: 5003 }).reply.code;
  o.albumAfterAdd = eng.state.pictures.length;
  o.removeCode = eng.dispatch('animpicture_album_remove_pic',
    { index: 1, slot: 1, flag: false }).reply.code;
  o.albumAfterRemove = eng.state.pictures.length;

  // walk the phases until the page finishes
  var sawZero = false, steps = 0;
  for (var i = 0; i < 20 && !sawZero; i++) {
    var r = eng.dispatch('animpicture_use_item', {});
    steps++;
    if (r.reply.phase === 0) sawZero = true;
  }
  o.sawZero = sawZero;
  o.steps = steps;
  o.itemNum = eng.dispatch('animpicture_load', {}).reply.item_num;

  // guide / get_item
  o.guideCode = eng.dispatch('animpicture_guide', {}).reply.code;
  o.guide = eng.dispatch('animpicture_load', {}).reply.guide;
  o.getItemCode = eng.dispatch('animpicture_get_item', {}).reply.code;
  o.itemNumAfterGet = eng.dispatch('animpicture_load', {}).reply.item_num;

  // remove a whole page (flag falsey returns the photos)
  eng.state.pictures = [];
  o.removePageCode = eng.dispatch('animpicture_remove_pic', { index: 1, flag: false }).reply.code;
  o.pagesAfterRemove = eng.dispatch('animpicture_load', {}).reply.pic_list.length;

  eng.save();
  o.savedPages = eng.state.animPicture.picList.length;
  return JSON.stringify(o);
})()
