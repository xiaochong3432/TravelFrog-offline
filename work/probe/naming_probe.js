(async function () {
  /* B1 复现：把开局起名流程走一遍，数一数"起名界面"出现了几次，
     并记录每一步的 guideStep、期间收到的推送。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  var out = { seen: [], pushes: [] };

  /* 记录引擎往客户端推了什么（这能看出流程中是否有 client_load_role 打断） */
  try {
    var eng = window.__engine;
    var origTick = eng.tick;
    eng.tick = function () {
      var ps = origTick.apply(this, arguments) || [];
      ps.forEach(function (p) { out.pushes.push(String(p.cmd)); });
      return ps;
    };
  } catch (e) { out.hookErr = String(e); }

  function walk(fn) {
    (function w2(n, d) {
      if (!n || d > 24) return;
      try { fn(n, d); } catch (e) { }
      (n.$children || []).forEach(function (c) { w2(c, d + 1); });
    })(egret.MainContext.instance.stage, 0);
  }
  function find(pred) { var hit = null; walk(function (n) { if (!hit && pred(n)) hit = n; }); return hit; }
  function step() { try { return core.ModelManage.getInstance().getModel(UserModel).getClientSettings().guideStep; } catch (e) { return '?'; } }
  function skinOf(n) { var m = /getSkinsPath\("([^"]+)"\)/.exec(String(n.constructor)); return m ? m[1] : ''; }

  out.stepAtBoot = step();
  out.welcomeFound = !!find(function (n) { return n.btn_yes && n.btn_enter && n.canvas; });

  /* 1) 关掉欢迎页（调用它自己的回调，等于玩家点了"同意"） */
  var welcome = find(function (n) { return n.btn_yes && n.btn_enter && n.callback; });
  if (welcome) { out.welcomeSkin = skinOf(welcome); try { welcome.callback(); } catch (e) { out.welcomeErr = String(e); } }
  await sleep(1500);
  out.stepAfterWelcome = step();

  /* 2) 看起名界面 */
  var named = find(function (n) { return n.t_name && n.btn_yes && n.c_name; });
  out.namedFound = !!named;
  out.namedSkin = named ? skinOf(named) : '';
  if (named) {
    out.seen.push({ at: 'first', step: step() });
    out.namedSteps = Object.keys(named).filter(function (k) { return /Step/.test(k); });
    out.currentStep = named.currentStep;
    /* 输名字 + 点确认（走它自己的 handler） */
    try { named.t_name.text = '呱呱'; } catch (e) { }
    try { named.totalTouchEvents({ currentTarget: named.btn_yes }); } catch (e) { out.tapErr = String(e); }
    await sleep(2000);
    out.stepAfterName = step();
    out.currentStepAfter = named.currentStep;
    /* 完成卡：点 canvas（客户端的完成动作） */
    try { named.totalTouchEvents({ currentTarget: named.canvas }); } catch (e) { out.canvasErr = String(e); }
    await sleep(2000);
    out.stepAfterComplete = step();
  }

  /* 3) 再过两秒看有没有"第二次"起名界面 */
  await sleep(2500);
  var named2 = find(function (n) { return n.t_name && n.btn_yes && n.c_name; });
  out.namedFoundAgain = !!named2;
  out.namedSameInstance = named2 === named;
  out.finalStep = step();
  out.pushCounts = out.pushes.reduce(function (a, c) { a[c] = (a[c] || 0) + 1; return a; }, {});
  out.engineName = (function () { try { return window.__engine.state.name; } catch (e) { return '?'; } })();
  out.clientName = (function () { try { return core.ModelManage.getInstance().getModel(RoleModel).getName(); } catch (e) { return '?'; } })();
  out.guideStepAfterAll = step();
  return out;
})()
