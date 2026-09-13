/* Browser verification of the two recovered caps. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'caps.json' });
  var o = {};

  // HaveItemMax: a single grant bigger than the cap must clamp, not overflow
  var itemId = 3001;
  eng.state.items.house = [{ item_id: itemId, count: 0 }];
  eng.state.selectGift = { 0: { item_id: itemId, count: 150 } };
  var r = eng.dispatch('item_select_gift', { index_list: [0] });
  var row = null;
  for (var i = 0; i < eng.state.items.house.length; i++) {
    if (eng.state.items.house[i].item_id === itemId) row = eng.state.items.house[i];
  }
  o.granted = r.reply.items.length ? r.reply.items[0].count : null;
  o.stored = row ? row.count : null;
  o.clampedTo99 = row ? row.count === 99 : false;
  // what the wire reports must agree with what is stored
  var items = eng.dispatch('item_load_items', {}).reply;
  var wire = null;
  for (var j = 0; j < items.house.length; j++) {
    if (items.house[j].item_id === itemId) wire = items.house[j].count;
  }
  o.wireCount = wire;

  // consuming is NOT clamped upward
  eng.state.selectGift = { 1: { item_id: itemId, count: -95 } };
  eng.dispatch('item_select_gift', { index_list: [1] });
  var row2 = null;
  for (var k = 0; k < eng.state.items.house.length; k++) {
    if (eng.state.items.house[k].item_id === itemId) row2 = eng.state.items.house[k];
  }
  o.afterConsume = row2 ? row2.count : 0;

  // MAIL_MAX on the read path
  eng.state.mails = [];
  for (var m = 0; m < 140; m++) {
    eng.state.mails.push({ id: m + 1, type: 3, title: 't', message: '', items: [], pictures: [] });
  }
  eng.state.mailTutorialSent = true;
  var mails = eng.dispatch('mail_load', {}).reply;
  o.mailsDelivered = mails.length;
  o.mailsStored = eng.state.mails.length;
  o.newestKept = mails[mails.length - 1].id;

  eng.save();
  o.savedMails = eng.state.mails.length;
  return JSON.stringify(o);
})()
