/* Browser verification of the 料理 (cooking) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'cook.json' });
  var o = {};

  var l0 = eng.dispatch('cooking_load_cooking', {}).reply;
  o.fields = Object.keys(l0).sort().join(',');
  o.month = l0.month;
  o.taskCount = l0.task_list.length;
  o.taskShape = l0.task_list[0] ? Object.keys(l0.task_list[0]).sort().join(',') : null;
  o.select = l0.select;

  // the dealt tasks must all be achievable (no ad/share rows)
  var types = [];
  for (var i = 0; i < l0.task_list.length; i++) types.push(l0.task_list[i].id);
  o.dealtIds = types.join(',');

  // a task cannot be claimed before its target
  o.claimTooEarly = eng.dispatch('cooking_complete_task', { id: l0.task_list[0].id }).reply.code;
  o.monthProAfterRefusal = eng.dispatch('cooking_load_cooking', {}).reply.month_pro;

  // real gameplay advances it: cross a week boundary -> task 1 (每周登录) completes
  eng.state.cooking.lastWeek = eng.state.cooking.week - 1;
  eng.dispatch('cooking_load_cooking', {});
  var t1 = null;
  for (var j = 0; j < eng.state.cooking.taskList.length; j++) {
    if (Number(eng.state.cooking.taskList[j].id) === 1) t1 = eng.state.cooking.taskList[j];
  }
  o.task1Pro = t1 ? t1.pro : null;
  o.claimAfterProgress = eng.dispatch('cooking_complete_task', { id: 1 }).reply.code;
  o.monthPro = eng.state.cooking.monthPro;

  // harvests advance the 80-clover task
  var t4 = null;
  for (var k = 0; k < eng.state.cooking.taskList.length; k++) {
    if (Number(eng.state.cooking.taskList[k].id) === 4) t4 = eng.state.cooking.taskList[k];
  }
  for (var h = 0; h < 3; h++) {
    eng.state.clovers[0].last_harvest = 0;
    eng.state.clovers[0].element = 0;
    eng.dispatch('clover_harvest', { clover_id: 1 });
  }
  o.task4Pro = t4 ? t4.pro : null;

  // start_cooking: refused while open, then pays the dish
  o.startRefused = eng.dispatch('cooking_start_cooking', {}).reply.code;
  var month = eng.state.cooking.month;
  var sel = eng.state.cooking.select;
  for (var m = 0; m < eng.state.cooking.taskList.length; m++) {
    eng.state.cooking.taskList[m].complete = true;
  }
  o.startCode = eng.dispatch('cooking_start_cooking', {}).reply.code;
  o.complete = eng.state.cooking.complete;

  // theme switch re-deals
  o.selectCode = eng.dispatch('cooking_select', { index: 2 }).reply.code;
  var l2 = eng.dispatch('cooking_load_cooking', {}).reply;
  o.selectAfter = l2.select;
  o.tasksAfterSelect = l2.task_list.length;
  o.monthProAfterSelect = l2.month_pro;

  // ad / share are refused, not faked
  o.adCode = eng.dispatch('cooking_look_ad', {}).reply.code;
  o.shareCode = eng.dispatch('cooking_share', {}).reply.code;

  eng.save();
  o.savedSelect = eng.state.cooking.select;
  return JSON.stringify(o);
})()
