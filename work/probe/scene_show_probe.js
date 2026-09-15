/* 走到收草这一步、把引导要的草收掉（它自己的 cloverFarm.onRequestHarves），
   再摆上新家具并刷新庭院，供截图。 */
(function () {
  var eng = window.__engine;
  var U = core.ModelManage.getInstance().getModel(UserModel);
  var out = { step: U.getClientSettings().guideStep };
  if (!eng) return JSON.stringify({ error: 'no engine' });

  function walk(node, depth, acc) {
    if (!node || depth > 14) return acc;
    acc.push(node);
    var kids = node.$children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc);
    return acc;
  }
  var all = walk(egret.MainContext.instance.stage, 0, []);
  var clsOf = function (n) { return String(n.__class__ || (n.constructor && n.constructor.name) || ''); };
  var mv = all.find(function (n) { return clsOf(n) === 'MainOutView'; });

  /* 1) 收草：引导的推进条件是"收到 element==1 的四叶草"或"台上收空" */
  var farm = mv && mv.cloverFarm;
  if (farm && Array.isArray(farm.viewList)) {
    var n = farm.viewList.length;
    for (var i = n - 1; i >= 0; i--) {
      try { farm.onRequestHarves(farm.viewList[i].info); } catch (e) { out.harvestErr = String(e && e.message); }
    }
    out.harvestedAsked = n;
    out.viewListLeft = farm.viewList.length;
  } else {
    out.farm = 'absent';
  }
  out.stepAfterHarvest = U.getClientSettings().guideStep;

  /* 2) 全部家具 + 摆上新增的 6 件，然后刷新庭院 */
  eng.dispatch('client_gm', { cmd: 'all_furniture' });
  [2001, 2002, 2005, 2010, 2025, 2027, 10104].forEach(function (id) {
    eng.dispatch('furniture_replace_fur', { id: id });
  });
  var F = core.ModelManage.getInstance().getModel(FurnitureModel);
  var lf = eng.dispatch('furniture_load_furniture', {});
  if (lf.reply) F.furniture_load_furniture(lf.reply);
  out.putFur = (F.getHomeFurnitures() || []).map(function (f) { return f.id + ':t' + f.type; });
  if (mv && typeof mv.updateFurniture === 'function') {
    try { mv.updateFurniture(); out.refreshed = true; } catch (e) { out.refreshed = String(e && e.message); }
  }
  out.viewsNow = (function () {
    var seen = {};
    all.forEach(function (x) { var c = clsOf(x); if (c && /View/.test(c)) seen[c] = 1; });
    return Object.keys(seen).slice(0, 12);
  })();
  return JSON.stringify(out, null, 1);
})()