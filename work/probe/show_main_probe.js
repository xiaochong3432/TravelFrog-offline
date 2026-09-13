(async function () {
  /* 目的：把开局引导按下"已完成"清掉，露出真正的主界面，然后
     (1) 列出右上角可见按钮及其皮肤图名；(2) 供截图给视觉核 OCR。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  var out = {};
  try { var n0 = document.getElementById('__notice_ok'); if (n0) n0.click(); } catch (e) { }
  await sleep(800);

  /* 1) 把引导步骤设成 Complete，并让 MainOut 自己重算一遍 */
  try {
    var um = core.ModelManage.getInstance().getModel(UserModel);
    out.guideBefore = um.getClientSettings().guideStep;
    um.clientSettings.guideStep = 'Complete';
  } catch (e) { out.guideErr = String(e); }
  function walk(fn) {
    (function w2(n, d) {
      if (!n || d > 22) return;
      try { fn(n, d); } catch (e) { }
      (n.$children || []).forEach(function (c) { w2(c, d + 1); });
    })(egret.MainContext.instance.stage, 0);
  }
  var ctl = null;
  try { ctl = core.PageManage.getInstance().getControl(MainOutController, core.ViewLayerType.SceneLayer); } catch (e) { }
  out.mainOutFound = !!ctl;
  if (ctl && ctl.getView && ctl.getView().checkGuide) {
    try { ctl.getView().checkGuide(); } catch (e) { out.checkGuideErr = String(e); }
  }
  await sleep(1200);

  /* 2) 把还挂着的引导视图摘掉（WelcomeView / GuideNamedView …） */
  var removed = [];
  var v2 = ctl && ctl.getView();
  if (v2) {
    (v2.$children || []).slice().forEach(function (c) {
      var src = '';
      try { src = String(c.constructor); } catch (e) { }
      var m = /getSkinsPath\("([^"]+)"\)/.exec(src);
      var skin = m ? m[1] : '';
      if (/Guide\//.test(skin)) { try { v2.removeChild(c); removed.push(skin); } catch (e) { } }
    });
  }
  out.removedGuideViews = removed;
  await sleep(600);

  /* 3) 列出屏幕上方可见按钮 */
  var buttons = [];
  walk(function (n) {
    var t = false, g = null;
    try { t = !!n.touchEnabled && n.visible; } catch (e) { }
    try { g = n.localToGlobal(0, 0); } catch (e) { }
    if (t && g && g.y > -10 && g.y < 140 && (n.source || n.text)) {
      buttons.push({ src: String(n.source || ''), text: String(n.text || ''),
        x: Math.round(g.x), y: Math.round(g.y), w: Math.round(n.width || 0), h: Math.round(n.height || 0) });
    }
  });
  buttons.sort(function (a, b) { return (a.y - b.y) || (a.x - b.x); });
  out.topButtons = buttons;
  out.guideAfter = (function () { try { return core.ModelManage.getInstance().getModel(UserModel).getClientSettings().guideStep; } catch (e) { return '?'; } })();
  return out;
})()
