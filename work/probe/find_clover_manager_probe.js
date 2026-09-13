/* 找到"庭院草位管理器"（有 viewList / onRequestHarves / onHarvest 的那个对象）在哪。 */
(function () {
  var out = { probes: {} };
  function walk(node, depth, acc) {
    if (!node || depth > 14) return acc;
    acc.push(node);
    var kids = node.$children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc);
    return acc;
  }
  var all = walk(egret.MainContext.instance.stage, 0, []);
  var clsOf = function (n) { return String(n.__class__ || (n.constructor && n.constructor.name) || ''); };
  out.nodeCount = all.length;

  var holders = all.filter(function (n) {
    return n && (typeof n.onRequestHarves === 'function' || (n.viewList && n.viewList.length !== undefined));
  });
  out.holders = holders.map(function (n) {
    return clsOf(n) + (typeof n.onRequestHarves === 'function' ? ' [has onRequestHarves]' : '')
      + (n.viewList ? ' viewList=' + n.viewList.length : '');
  });

  var mv = all.find(function (n) { return clsOf(n) === 'MainOutView'; });
  if (mv) {
    out.mainOutMethods = ['onRequestHarves', 'onHarvest', '_onRequestHarvest', 'updateFurniture', 'initCloverPoint']
      .map(function (k) { return k + '=' + (typeof mv[k]); });
    out.mainOutViewList = !!mv.viewList;
  }
  try {
    var ctl = core.PageManage.getInstance().getControl(MainOutController);
    out.controller = ctl ? (ctl.constructor && ctl.constructor.name) : 'null';
    if (ctl) {
      out.controllerMethods = ['onRequestHarves', 'onHarvest', 'updateFurniture', 'initCloverPoint']
        .map(function (k) { return k + '=' + (typeof ctl[k]); });
      out.controllerViewList = !!ctl.viewList;
      out.controllerIsView = !!ctl.$children;
    }
  } catch (e) { out.controller = 'threw: ' + (e && e.message); }
  return JSON.stringify(out, null, 1);
})()