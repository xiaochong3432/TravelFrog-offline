(async function () {
  /* 帽子补丁的真页面验收（玩家报"蛙蛙旅行的时候帽子还在家里"）。
     MainInView 的帽子节点是 `frogCap`（资源 bousi_ie_png）。客户端在 status 0->1 时
     不会重算屋里视图，所以帽子会留在原处；__probe.js 的补丁在引擎说"蛙不在家"时
     把它的 visible 关掉。这里走一遍：进屋 -> 让蛙出门 -> 看帽子。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  function room() {
    var found = null;
    (function walk(node, depth) {
      if (found || depth > 16 || !node) return;
      if (node.frogCap) { found = node; return; }
      var kids = node.$children || [];
      for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1);
    })(egret.MainContext.instance.stage, 0);
    return found;
  }
  var out = {};
  out.hasEngine = !!window.__engine;
  out.hatWatch = typeof window.__hatWatch;

  /* 进屋：主场景的 houseBtn 就是这条调用（MainOutView.houseBtn handler） */
  try {
    var v = room();
    out.roomBeforeEnter = !!v;
    if (!v) {
      var house = window.__egretPart('MainOut', 'houseBtn');
      if (house && house.length) { window.__egretTap(house[0].x + 20, house[0].y + 20); }
      await sleep(1500);
    }
  } catch (e) { out.enterError = String(e); }
  var view = room();
  out.roomFound = !!view;
  if (!view) return out;

  /* 先让蛙回家，量一下"在家"时的帽子 */
  window.__engine.dispatch('client_gm', { cmd: 'come_home' });
  await sleep(1200);
  out.homeStatus = window.__engine.state.frog.status;
  out.capVisibleWhileHome = !!view.frogCap.visible;

  /* 出门：客户端自己的路径是「准备完成」，而 GM 的 travel_now 直接出发 */
  window.__engine.dispatch('client_gm', { cmd: 'travel_now' });
  await sleep(1600);
  out.awayStatus = window.__engine.state.frog.status;
  out.capVisibleWhileAway = !!view.frogCap.visible;
  out.patched = out.capVisibleWhileAway === false;

  /* 再进屋一次（这是玩家实际会走的路径：出屋->进屋，屋里重新构建） */
  try {
    var back = window.__egretPart('MainOut', 'houseBtn');
    var inRoom = window.__egretPart('MainIn', 'houseBtn');
    if (inRoom && inRoom.length) window.__egretTap(inRoom[0].x + 20, inRoom[0].y + 20);
    await sleep(1200);
    if (back && back.length) window.__egretTap(back[0].x + 20, back[0].y + 20);
    await sleep(1500);
  } catch (e) { out.reenterError = String(e); }
  var v2 = room();
  out.roomFound2 = !!v2;
  if (v2) {
    out.capVisibleAfterReenter = !!v2.frogCap.visible;
    window.__hatWatch();
    out.capVisibleAfterWatch = !!v2.frogCap.visible;
  }
  out.stillAway = window.__engine.state.frog.status;
  return out;
})()
