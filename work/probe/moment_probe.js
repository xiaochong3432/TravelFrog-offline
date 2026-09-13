/* Browser verification of the 回忆彩蛋 (moment) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'moment.json' });
  var o = {};

  var l0 = eng.dispatch('misc_moment_load', {}).reply;
  o.hasListKey = Array.isArray(l0.list);
  o.before = l0.list.length;

  // a real moment id (momentData rows include 1, 10, 101...)
  var id = 1;
  o.unlockCode = eng.dispatch('misc_moment_unlock', { id: id }).reply.code;
  var l1 = eng.dispatch('misc_moment_load', {}).reply;
  o.after = l1.list;
  o.dupCode = eng.dispatch('misc_moment_unlock', { id: id }).reply.code;
  o.afterDup = eng.dispatch('misc_moment_load', {}).reply.list.length;
  o.badCode = eng.dispatch('misc_moment_unlock', { id: 999999 }).reply.code;
  o.afterBad = eng.dispatch('misc_moment_load', {}).reply.list.length;

  // a second, different one
  o.secondCode = eng.dispatch('misc_moment_unlock', { id: 101 }).reply.code;
  o.total = eng.dispatch('misc_moment_load', {}).reply.list.length;

  eng.save();
  o.saved = eng.state.moments.length;
  return JSON.stringify(o);
})()
