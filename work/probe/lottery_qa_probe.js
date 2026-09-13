(function () {
  var eng = window.__engine;
  if (!eng) return { error: 'no engine yet' };
  var out = {};
  var sm = core.SocketManage.getInstance();

  /* ---- 周末的小插曲 (LotteryView) -----------------------------------------
     The client renders its option grid from `data.select_list` and only enables its
     confirm button once FIVE items are ticked ("选出5款物品"). So ask the CLIENT for
     the payload through its own socket and read what its model ends up holding. */
  eng.state.lottery = { lastPhase: 0, phase: 0, state: 0, selectList: [], answer: [],
    extraItem: { item_id: 0, count: 0 }, rightFlag: [], eggNum: 0, reward: [] };
  eng.state.lotteryNextRollAt = 0;
  var opened = null;
  sm.send('lottery_open', new core.Action2(function (r) { opened = r; }));
  out.openReply = opened && { open: !!opened.open_item, extra: !!opened.extra_item };
  out.engineSelectList = eng.state.lottery.selectList.length;
  out.engineWant = eng.state.lottery.want.length;
  out.engineGuest = eng.state.lottery.guest;
  out.enginePhase = eng.state.lottery.phase;

  var got = null;
  sm.send('lottery_load', new core.Action2(function (r) { got = r; }));
  /* 客户端自己的协议层已经接受了这条回包（send 的参数校验先过了），
     这里直接读回包 —— 它就是客户端要渲染的那份 select_list。 */
  out.replyPhase = got && got.phase;
  out.replyState = got && got.state;
  out.replySelectLen = ((got && got.select_list) || []).length;
  out.clientCanPickFiveAndLeaveSome = out.replySelectLen > 5;

  /* ---- 小问答 (PartyCakeQaView) -------------------------------------------
     The view builds its options with `for (r = 1; 3 >= r; r++)` and sends that
     1-based counter as `index`; the callback then compares the reply's `state` with
     PartyCakeState.qa (2) to decide "ask again" vs "show the prize". */
  eng.state.partyCake = { cream: 0, sugar: 0, preCream: 0, preSugar: 0, curState: 2,
    part: 1, madeLayers: [], taskCounts: {}, shareGet: [0, 0], guest: 0, wrong: 0,
    answer: [], qaCorrect: 0, rewardRows: 1, mateDay: '' };
  var qa = null;
  sm.send('partycake_load_qa', new core.Action2(function (r) { qa = r; }));
  out.qaOptions = (qa && qa.answer || []).length;
  out.qaRewardRows = (qa && qa.reward || []).length;
  out.qaCorrectIndex = eng.state.partyCake.qaCorrect;
  out.qaGuest = eng.state.partyCake.guest;

  /* answer with EVERY index the client can produce (1..3) and report the states */
  out.answerStates = {};
  for (var i = 1; i <= 3; i++) {
    eng.state.partyCake.curState = 2;
    eng.state.partyCake.answer = null;          // force a fresh question
    var r = eng.dispatch('partycake_answer', { index: i }).reply;
    out.answerStates['index' + i] = { correct: eng.state.partyCake.qaCorrect, state: r.state };
  }
  /* the one the client would actually send for the current question must WIN */
  eng.state.partyCake.answer = null;
  eng.state.partyCake.curState = 2;
  var fresh = null;
  sm.send('partycake_load_qa', new core.Action2(function (r) { fresh = r; }));
  var right = eng.state.partyCake.qaCorrect;
  var win = eng.dispatch('partycake_answer', { index: right }).reply;
  out.clientIndexWins = { index: right, state: win.state, expect: 3 };
  out.exceptions = 0;
  return out;
})()
