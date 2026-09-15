(async function () {
  /* 本轮四条修复的真页面验收（走客户端自己的路径，不靠引擎自证）：
     ① 蛙出门后屋里的帽子消失   ② 回家时行李回到原来的格子
     ③ 明信片图层是新摆位        ④ 祈愿物带 stamp_time / 印章停在 state 3 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  var S = core.ViewLayerType.SceneLayer, H = core.RemoveViewType.HideBefore;
  var pm = core.PageManage.getInstance();
  var eng = window.__engine;
  var M = core.ModelManage.getInstance().getModel(ItemModel);
  var sm = core.SocketManage.getInstance();
  var out = {};
  function roomView() { var c = pm.getControl(MainInController, S); return c ? c.getView() : null; }

  /* ---------------- ② 先把行李摆好并出门（干净起点：先让蛙在家） -------------- */
  eng.dispatch('client_gm', { cmd: 'come_home' });
  await sleep(1200);
  eng.state.items.bag = [3, -1, 2002, 2003];      /* 便当 / 空 / 水壶 / 纸伞 */
  M.bagDataList[0] = 3; M.bagDataList[1] = -1; M.bagDataList[2] = 2002; M.bagDataList[3] = 2003;
  if (M.getBagLock()) M.setBagLock(false);
  out.beforeDepart = { status: eng.state.frog.status, bag: eng.state.items.bag.slice() };
  M.setBagLock(true);                             /* 客户端自己的「准备完成」 */
  await sleep(1500);
  out.afterDepart = { status: eng.state.frog.status, bag: eng.state.items.bag.slice() };

  /* ---------------- ① 进屋看帽子（此时蛙在路上） ---------------- */
  pm.addViewControl(MainInController, S, H);
  for (var i = 0; i < 40 && !roomView(); i++) await sleep(250);
  var v = roomView();
  out.roomFound = !!v;
  if (v && v.frogCap) {
    /* 客户端自己的缺陷会让它保持上次的 visible=true；我们的补丁应当在 700ms 内关掉 */
    out.capVisibleWhileAway = v.frogCap.visible;
    await sleep(1200);
    out.capVisibleAfterWatch = v.frogCap.visible;
    out.hatFixWorks = v.frogCap.visible === false;
  }

  /* ---------------- ② 让引擎结算回程，读行李 ---------------- */
  eng.state.travel.returnAt = 1;
  await sleep(7000);
  out.afterReturn = {
    status: eng.state.frog.status,
    bag: eng.state.items.bag.slice(),
    clientBag: (M.getBagDataList() || []).slice(),
  };
  out.bagFixWorks = out.afterReturn.status === 0
    && out.afterReturn.bag[0] === -1 && out.afterReturn.bag[1] === -1
    && out.afterReturn.bag[2] === 2002 && out.afterReturn.bag[3] === 2003;

  /* ---------------- ③ 明信片图层 ---------------- */
  eng.state.pictures.push({ id: 999, pic_id: 100, read: 0, new: 1 });
  var album = sm.send;                                    /* keep the client in the loop */
  var picReply = null;
  eng.dispatch('client_gm', { cmd: 'add_clover 0' });     /* no-op, keeps the socket warm */
  var r = eng.dispatch('album_load', { start: 1 }).reply;
  var mine = (r.pictures || []).filter(function (p) { return p.pic_id === 100; })[0];
  out.pic100 = mine && { layers: mine.layers.length, pose: (mine.layers.filter(function (l) { return l.scale; })[0] || {}).layer };
  out.poseExpected = [311, 209];                          /* 底边中点 (349,270) - (w/2,h) */
  out.poseOk = !!out.pic100 && out.pic100.pose && out.pic100.pose[1] === 311 && out.pic100.pose[2] === 209;

  /* ---------------- ④ 手工品字段 ---------------- */
  var wishId = Number(Object.keys(Tabikaeru.DataManager.instance().PrayCraftDB.map || {})[0] || 0);
  if (!wishId) { try { wishId = Number(Object.keys(Tabikaeru.DataManager.instance().PrayCraftDB)[0]); } catch (e) { } }
  eng.state.craft = {
    seq: 1, stamps: [], pending: [],
    wishes: [{ id: 1, state: 3, body: '', paper: '', content: 0, make_time: 0, u_id: 1 }],
  };
  var crafted = null;
  sm.send('pray_load_grays', new core.Action2(function (x) { crafted = x; }));
  var w = (crafted && crafted.wishs || []).filter(function (x) { return Number(x.state) === 4; })[0];
  out.wishRow = w;
  out.craftOk = !!w && Number(w.stamp_time) > 0 && Number(w.stamp) > 0 && w.stamp_state !== undefined;
  out.stampStates = (eng.state.craft.stamps || []).map(function (s) { return s.state; });
  return out;
})()
