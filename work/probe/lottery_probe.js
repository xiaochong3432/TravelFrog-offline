/* Browser verification of the 抽奖 / 邻里美食交流 (lottery) subsystem. */
(function () {
  var E = window.FrogEngine;
  if (!E) return JSON.stringify({ error: 'no FrogEngine' });
  var eng = E.createEngine({ savePath: 'lottery.json' });
  var o = {};

  // 1. roll until a phase starts
  eng.state.lotteryNextRollAt = 0;
  for (var i = 0; i < 600 && !eng.state.lottery.phase; i++) {
    eng.state.lotteryNextRollAt = 1;
    eng.tick();
  }
  o.phase = eng.state.lottery.phase;
  o.picks = eng.state.lottery.selectList.length;

  // 2. full field set with a truthy phase (a falsy phase makes the client
  //    ignore the entire payload, silently)
  var m = eng.dispatch('lottery_load', {}).reply;
  o.fields = Object.keys(m).sort().join(',');
  o.loadPhase = m.phase;

  // 3. open -> both keys must exist or the client shows nothing
  var c0 = eng.state.clover;
  var op = eng.dispatch('lottery_open', {});
  o.hasOpenItem = !!op.reply.open_item;
  o.hasExtraItem = !!op.reply.extra_item;
  o.openGain = eng.state.clover - c0;
  o.pushedClover = op.pushes.filter(function (p) { return p.cmd === 'clover.update'; }).length;
  o.stateAfterOpen = eng.state.lottery.state;

  // 4. perfect pick -> all flags 1, score inside 0..5
  var want = eng.state.lottery.selectList.slice();
  var sel = eng.dispatch('lottery_select', { list: want });
  o.selectCode = sel.reply.code;
  o.score = eng.state.lottery.score;
  o.flagsAllOne = eng.state.lottery.rightFlag.every(function (f) { return f === 1; });
  o.stateAfterSelect = eng.state.lottery.state;
  o.pushedLoad = sel.pushes.filter(function (p) { return p.cmd === 'lottery.load'; }).length;

  // 5. confirm pays and returns to Open
  var c1 = eng.state.clover;
  var cf = eng.dispatch('lottery_confirm_reward', {});
  o.confirmCode = cf.reply.code;
  o.confirmGain = eng.state.clover - c1;
  o.stateAfterConfirm = eng.state.lottery.state;
  o.answerCleared = eng.state.lottery.answer.length === 0;

  // 6. a blank pick must score 0 and pay 0 (relative, not asserting our numbers)
  eng.dispatch('lottery_open', {});
  eng.dispatch('lottery_select', { list: [] });
  o.blankScore = eng.state.lottery.score;
  var c2 = eng.state.clover;
  eng.dispatch('lottery_confirm_reward', {});
  o.blankGain = eng.state.clover - c2;

  eng.save();
  o.savedPhase = eng.state.lottery.phase;
  return JSON.stringify(o);
})()
