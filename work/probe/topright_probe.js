(async function () {
  /* 数一数主界面右上角到底有哪几个按钮（玩家说"左数右数都是第二个"的那个）。
     做法：找到 MainOutView（有 miniGroup/lotteryGroup 这些字段的那个节点），
     把它的**可见**子节点里落在右上角的都列出来（名字 + 位置 + 皮肤图）。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  var out = {};
  try { var n0 = document.getElementById('__notice_ok'); if (n0) n0.click(); } catch (e) { }
  await sleep(1500);

  function view() {
    var found = null;
    (function walk(node, d) {
      if (found || !node || d > 18) return;
      if (node.miniGroup || node.lotteryGroup || node.adsGroup) { found = node; return; }
      var kids = node.$children || [];
      for (var i = 0; i < kids.length; i++) walk(kids[i], d + 1);
    })(egret.MainContext.instance.stage, 0);
    return found;
  }
  var v = view();
  out.viewFound = !!v;
  if (!v) return out;
  out.isHome = Tabikaeru.Game.instance().isHome;
  out.channel = (typeof GameConfig !== 'undefined' && GameConfig.channel);

  /* 逐个字段看它的位置：右上角 = 全局 x > 250 且 y < 220 */
  var rows = [];
  Object.keys(v).forEach(function (k) {
    var o = v[k];
    if (!o || typeof o !== 'object' || typeof o.visible !== 'boolean' || !o.localToGlobal) return;
    var g = null;
    try { g = o.localToGlobal(0, 0); } catch (e) { return; }
    if (!g) return;
    if (g.x < 240 || g.y > 260) return;
    var src = '';
    try { src = (o.source || '') + '|' + (o.text || ''); } catch (e) { }
    rows.push({ name: k, vis: o.visible, x: Math.round(g.x), y: Math.round(g.y),
      w: Math.round(o.width || 0), h: Math.round(o.height || 0), src: src.slice(0, 60) });
  });
  rows.sort(function (a, b) { return (a.y - b.y) || (b.x - a.x); });
  out.topRight = rows;

  /* 顺便看看这几个已知的"活动入口"组是否可见 */
  var groups = {};
  ['miniGroup', 'lotteryGroup', 'adsGroup', 'mailNotification', 'groupTop', 'moneyPanel', 'menu', 'shop_mc'].forEach(function (k) {
    var o = v[k];
    if (!o) { groups[k] = 'missing'; return; }
    var g = null; try { g = o.localToGlobal(0, 0); } catch (e) { }
    groups[k] = { vis: o.visible, x: g ? Math.round(g.x) : null, y: g ? Math.round(g.y) : null,
      kids: (o.$children || []).length };
  });
  out.groups = groups;
  out.canShowMini = (function () { try { return core.ModelManage.getInstance().getModel(RoleModel).canShowMini(); } catch (e) { return 'err:' + e; } })();
  return out;
})()
