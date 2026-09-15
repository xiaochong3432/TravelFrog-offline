/* Browser verification of the 扭蛋活动 (capsule) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'capsule.json' });
  var o = {};

  // 1. the event is OPEN and the payload has the full model
  var l0 = eng.dispatch('capsule_load', {}).reply;
  o.endTimeFuture = l0.end_time > Math.floor(Date.now() / 1000);
  o.fields = Object.keys(l0).sort().join(',');
  o.coin = l0.coin;
  o.hasStartedFlag = eng.state.capsule.started === 1;

  // 2. spending the last coin must NOT re-grant the allowance
  eng.state.capsule.coin = 0;
  o.reloadCoinStillZero = eng.dispatch('capsule_load', {}).reply.coin;

  // 3. twist draws a real reward and pays it out
  eng.state.capsule.coin = 20;
  var c0 = eng.state.capsule.coin;
  var tw = eng.dispatch('capsule_twist', {});
  o.rewardId = tw.reply.reward_id;
  o.pushedCoin = tw.pushes.filter(function (p) { return p.cmd === 'capsule.load_coin'; }).length;
  var l1 = eng.dispatch('capsule_load', {}).reply;
  o.coinSpent = c0 - l1.coin;
  o.rewardListLen = l1.reward_list.length;

  // 4. no coins -> reward_id 0
  eng.state.capsule.coin = 0;
  o.noCoinId = eng.dispatch('capsule_twist', {}).reply.reward_id;

  // 5. patch deals into an empty list, then deals nothing
  eng.state.capsule.coin = 20;
  eng.state.capsule.taskList = [];
  eng.state.capsule.patchNum = 8;
  var p1 = eng.dispatch('capsule_patch', {}).reply.task_list;
  o.patch1 = p1.length;
  o.patch1HasCompleteFlag = p1.length ? (p1[0].complete === false) : null;
  eng.state.capsule.patchNum = 8;
  o.patch2 = eng.dispatch('capsule_patch', {}).reply.task_list.length;

  // 6. real gameplay completes the matching task
  var findTask = function (id) {
    for (var i = 0; i < eng.state.capsule.taskList.length; i++) {
      if (Number(eng.state.capsule.taskList[i].id) === id) return eng.state.capsule.taskList[i];
    }
    return null;
  };
  var t1 = findTask(1), t5 = findTask(5), t8 = findTask(8);
  o.dealtTasks = [!!t1, !!t5, !!t8];
  eng.state.clovers[0].last_harvest = 0;
  eng.state.clovers[0].element = 0;
  eng.dispatch('clover_harvest', { clover_id: 1 });
  o.task1AfterHarvest = t1 ? t1.complete : null;

  // 7. a REFUSED action must not tick a task off
  eng.state.pictures = [];
  eng.state.albumPending = [];
  var bad = eng.dispatch('album_save_new', { id: 999 });
  o.refusedCode = bad.reply.code;
  o.task8AfterRefusal = t8 ? t8.complete : null;

  // 8. a SUCCESSFUL one does
  eng.state.albumPending = [{ id: 6001, pic_id: 100, read: 0, new: 1 }];
  eng.dispatch('album_save_new', { id: 6001 });
  o.task8AfterSuccess = t8 ? t8.complete : null;

  // 9. fast_task charges the table cost
  eng.state.capsule.coin = 100;
  var cost = 30;
  o.fastCode = eng.dispatch('capsule_fast_task', { index: 1 }).reply.code;
  o.coinAfterFast = eng.state.capsule.coin;

  // 10. get_coin collects pre_coin
  eng.state.capsule.preCoin = 4;
  o.getCoinCode = eng.dispatch('capsule_get_coin', {}).reply.code;
  o.coinAfterGet = eng.state.capsule.coin;
  o.preAfterGet = eng.state.capsule.preCoin;

  eng.save();
  o.savedCoin = eng.state.capsule.coin;
  return JSON.stringify(o);
})()
