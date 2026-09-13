(async function () {
  /* 老存档修复的真页面验收：塞一份"旧版本写出的"手工品行
     （完成的祈愿物没有 stamp_time/stamp、印章停在表里不存在的 state 4），
     经客户端自己的 socket 拉一次 pray_load_grays，然后读**客户端模型**
     （HandCraftModel.prayCraftList / stampCraftList —— 详情卡与两页就从它渲染）。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w8 = 0; w8 < 60 && !window.__engine; w8++) await sleep(500);
  var eng = window.__engine;
  var out = {};
  if (!eng) return { error: 'no engine (loopback never installed)' };
  var old = {
    seq: 9, pending: [],
    wishes: [
      { id: 1, state: 4, body: 101, paper: 1001, content: 0, make_time: 1700000000, u_id: 1 },
      { id: 2, state: 2, body: '', paper: '', content: 0,
        make_time: Math.floor(Date.now() / 1000) + 100000, u_id: 2 },
    ],
    stamps: [{ id: 1, state: 4, time: 1700000000, u_id: 3 }],
  };
  eng.state.craft = JSON.parse(JSON.stringify(old));
  out.seeded = { wish_state: 4, wish_stamp_time: undefined, stamp_state: 4 };

  var sm = core.SocketManage.getInstance();
  var reply = null;
  sm.send('pray_load_grays', new core.Action2(function (r) { reply = r; }));
  await sleep(300);
  out.replyFinished = (reply && reply.wishs || []).filter(function (w) { return Number(w.state) === 4; })[0];
  out.replyStampState = (reply && reply.stamps || []).map(function (s) { return s.state; })[0];

  /* 客户端模型：改名/取模方式与探针同事一致（裸标识符 HandCraftModel 在页面里可用） */
  try {
    var m = core.ModelManage.getInstance().getModel(HandCraftModel);
    out.modelWish = (m.prayCraftList || []).filter(function (w) { return Number(w.state) === 4; })[0];
    out.modelStampStates = (m.stampCraftList || []).map(function (s) { return s.state; });
  } catch (e) { out.modelError = String(e); }

  var w = out.replyFinished || out.modelWish || {};
  out.dateWouldRender = Number(w.stamp_time) > 0
    ? core.DateFormat.format(1000 * Number(w.stamp_time), core.DateFormater['YYYY.MM.DD']) : 'NaN';
  out.sealReady = Number(w.stamp) > 0 && w.stamp_state !== undefined;
  out.fixed = Number(w.stamp_time) > 0 && Number(w.stamp) > 0 && out.replyStampState === 3;
  return out;
})()
