/* 找引导那一步要收的草：从 MainOutView 的属性里挖出草位管理器（有 viewList/onRequestHarves）。 */
(function () {
  var out = {};
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
  if (!mv) return JSON.stringify(out);

  /* 1) MainOutView 自己属性里，谁有 viewList / onRequestHarves */
  var hits = [];
  Object.keys(mv).forEach(function (k) {
    var v = mv[k];
    if (!v || typeof v !== 'object') return;
    var has = typeof v.onRequestHarves === 'function';
    var vl = Array.isArray(v.viewList) ? v.viewList.length : null;
    if (has || vl !== null) hits.push(k + '(cls=' + clsOf(v) + ',onReq=' + has + ',viewList=' + vl + ')');
  });
  out.ownProps = hits;

  /* 2) 显示树上谁有这些方法 */
  out.treeHolders = all.filter(function (n) { return typeof n.onRequestHarves === 'function'; })
    .map(function (n) { return clsOf(n); });

  /* 3) 台上的 CloverView 有几个、坐标多少 */
  var clovers = all.filter(function (n) { return clsOf(n) === 'CloverView'; });
  out.cloverViews = clovers.length;
  out.cloverPos = clovers.slice(0, 4).map(function (c) {
    var p = c.localToGlobal ? c.localToGlobal(0, 0) : { x: -1, y: -1 };
    return Math.round(p.x) + ',' + Math.round(p.y) + ' el' + (c.info ? c.info.element : '?');
  });

  /* 4) 谁盖在最上面（stage 的直接子层 + 每层子对象数） */
  out.top = (egret.MainContext.instance.stage.$children || []).map(function (c) {
    return clsOf(c) + ':' + ((c.$children || []).length);
  });
  return JSON.stringify(out, null, 1);
})()