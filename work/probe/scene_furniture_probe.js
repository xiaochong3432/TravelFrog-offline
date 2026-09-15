/* 摆上新家具并刷新庭院，然后截图。渲染不依赖引导是否走完（引导只是浮层）。 */
(function () {
  var eng = window.__engine;
  if (!eng) return JSON.stringify({ error: 'no engine' });
  var F = core.ModelManage.getInstance().getModel(FurnitureModel);
  var out = {};

  /* 1) 全部家具入手，然后摆上几件新增的（每件不同 type） */
  eng.dispatch('client_gm', { cmd: 'all_furniture' });
  var placedIds = [2001, 2002, 2005, 2010, 2025, 2027, 10104];
  placedIds.forEach(function (id) { eng.dispatch('furniture_replace_fur', { id: id }); });
  var lf = eng.dispatch('furniture_load_furniture', {});
  if (lf.reply) F.furniture_load_furniture(lf.reply);
  out.putFur = (F.getHomeFurnitures() || []).map(function (f) { return f.id + ':t' + f.type; });

  /* 2) 让庭院重建家具图层 */
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
  out.mainOut = !!mv;
  if (mv && typeof mv.updateFurniture === 'function') {
    try { mv.updateFurniture(); out.refreshed = true; } catch (e) { out.refreshed = String(e && e.message); }
  }
  /* 庭院家具层里现在有多少个显示对象（粗略的"画出来没有"指标） */
  if (mv) {
    var keys = Object.keys(mv).filter(function (k) { return /fur|clover|field|house/i.test(k); });
    out.mvKeys = keys.slice(0, 12);
    out.furContainer = (function () {
      for (var i = 0; i < keys.length; i++) {
        var v = mv[keys[i]];
        if (v && v.$children && /fur/i.test(keys[i])) return keys[i] + ':' + v.$children.length;
      }
      return 'n/a';
    })();
  }
  return JSON.stringify(out, null, 1);
})()