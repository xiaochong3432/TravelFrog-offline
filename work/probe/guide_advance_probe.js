/* 把新手引导往前推：找当前在台上的引导视图，用它自己的 tap handler 点，报告进度。 */
(function () {
  var U = core.ModelManage.getInstance().getModel(UserModel);
  var out = { step: U.getClientSettings().guideStep };

  function walk(node, depth, acc) {
    if (!node || depth > 12) return acc;
    acc.push(node);
    var kids = node.$children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc);
    return acc;
  }
  var all = walk(egret.MainContext.instance.stage, 0, []);
  var clsOf = function (n) { return String(n.__class__ || (n.constructor && n.constructor.name) || ''); };

  /* 台上都有谁（只报引导/场景相关的类） */
  var seen = {};
  all.forEach(function (n) { var c = clsOf(n); if (c && /Guide|Welcome|MainOut|Loading/.test(c)) seen[c] = 1; });
  out.views = Object.keys(seen);

  var mainOut = all.find(function (n) { return clsOf(n) === 'MainOutView'; });
  out.mainOut = !!mainOut;

  /* 引导视图：把它的可点元素都点一遍（它自己的回调推进 guideStep） */
  var tapped = 0, names = [];
  all.forEach(function (n) {
    var c = clsOf(n);
    if (!/Guide|Welcome/.test(c)) return;
    names.push(c);
    walk(n, 0, []).forEach(function (k) {
      if (k !== n && k.touchEnabled && k.dispatchEvent) {
        try { k.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP)); tapped++; } catch (e) { /* ignore */ }
      }
    });
  });
  out.tappedViews = names.slice(0, 6);
  out.taps = tapped;
  out.stepAfter = U.getClientSettings().guideStep;

  /* 名字那一页要点它自己的按钮 */
  var named = all.find(function (n) { return clsOf(n) === 'GuideNamedView'; });
  if (named) {
    try {
      if (named.t_name) named.t_name.text = named.t_name.text || '离线测试蛙';
      named.btn_yes.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
      out.namedDriven = true;
    } catch (e) { out.namedDriven = String(e && e.message); }
    out.stepAfterName = U.getClientSettings().guideStep;
  }
  return JSON.stringify(out);
})()