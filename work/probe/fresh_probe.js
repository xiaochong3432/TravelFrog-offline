/* Verify the NEW-SAVE path in the browser: a brand-new engine, the guide
 * sequence the client itself performs, and that the boot push set is delivered. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'fresh.json' });
  var o = {};

  // start from nothing, like a first launch
  eng.state.pictures = [];
  eng.state.albumPending = [];
  eng.state.albumDeleted = [];
  eng.state.giftBox = { pictures: [], specialtys: [] };
  eng.state.items.house = [];
  eng.state.decoration = { hasList: [], putId: 0, status: 0 };
  eng.state.guide = { doorOpened: false, awardGiven: false, steps: [] };
  eng.state.tutorialAward = 0;

  // 1. a brand-new save boots: the boot push set comes back
  var boot = eng.dispatch('client_load_all_info', {});
  o.bootOk = !!boot.reply;
  o.bootPushes = boot.pushes.length;

  // 2. the guide sequence, exactly as main.min.js performs it
  eng.dispatch('tutorial_step_open_door', {});
  var q1 = eng.dispatch('tutorial_step_open_door_q', {});
  o.openDoorOk = q1.reply.ok;
  var c0 = eng.state.clover;
  var aw = eng.dispatch('tutorial_step_ask_award', {});
  var q2 = eng.dispatch('tutorial_step_ask_award_q', {});
  o.awardOk = q2.reply.ok;
  o.cloverGained = eng.state.clover - c0;
  o.pushedClover = aw.pushes.filter(function (p) { return p.cmd === 'clover.update'; }).length;
  o.pushedTicket = aw.pushes.filter(function (p) { return p.cmd === 'item.update_ticket'; }).length;
  o.guideSteps = eng.state.guide.steps.join(',');

  // 3. the award is once-only
  var c1 = eng.state.clover;
  eng.dispatch('tutorial_step_ask_award', {});
  o.secondClaimGain = eng.state.clover - c1;

  // 4. after the tutorial, the normal loop still answers
  var lf = eng.dispatch('furniture_load_furniture', {}).reply;
  o.shopOpen = lf.shop.start_time < Math.floor(Date.now() / 1000)
    && lf.shop.leave_time > Math.floor(Date.now() / 1000);
  o.shopRows = lf.shop.shop_list.length;
  o.albumLen = eng.dispatch('album_load', { start: 1 }).reply.pictures.length;
  o.wishEnd = eng.dispatch('wishingpool_load', {}).reply.end_time > 0;
  o.capsuleEnd = eng.dispatch('capsule_load', {}).reply.end_time > 0;
  o.cookTasks = eng.dispatch('cooking_load_cooking', {}).reply.task_list.length;
  o.encyclopedia = Object.prototype.toString.call(eng.dispatch('encyclopedia_load', {}).reply);
  o.tasks = eng.dispatch('task_load', {}).reply.task_list
    ? eng.dispatch('task_load', {}).reply.task_list.length : null;
  o.mails = eng.dispatch('mail_load', {}).reply.length;

  // 5. and the frog can actually go somewhere
  eng.state.travel.nextDepartAt = 1;
  eng.tick();
  o.frogWentOut = eng.state.frog.status === 1;
  eng.state.travel.returnAt = 1;
  eng.tick();
  o.frogCameHome = eng.state.frog.status === 0;

  eng.save();
  o.savedGuide = eng.state.guide.awardGiven;
  return JSON.stringify(o);
})()
