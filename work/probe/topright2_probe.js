(async function () {
  /* 主界面右上角到底哪几个按钮**真的可见**（把父链上的 visible 也算进去），
     它们分别叫什么、点了会开哪个界面（皮肤名）。用来定位玩家说的"右数第二个"。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  try { var n0 = document.getElementById('__notice_ok'); if (n0) n0.click(); } catch (e) { }
  try {
    var um = core.ModelManage.getInstance().getModel(UserModel);
    um.clientSettings.guideStep = 'Complete';
  } catch (e) { }
  var ctl = null;
  try { ctl = core.PageManage.getInstance().getControl(MainOutController, core.ViewLayerType.SceneLayer); } catch (e) { }
  if (ctl && ctl.getView && ctl.getView().checkGuide) { try { ctl.getView().checkGuide(); } catch (e) { } }
  await sleep(1200);
  var v = ctl && ctl.getView();
  var out = { mainOut: !!v };
  if (!v) return out;
  (v.$children || []).slice().forEach(function (c) {
    var m = /getSkinsPath\("([^"]+)"\)/.exec(String(c.constructor));
    if (m && /Guide\//.test(m[1])) { try { v.removeChild(c); } catch (e) { } }
  });

  function effVisible(n) {
    var cur = n;
    while (cur) {
      if (cur.visible === false) return false;
      cur = cur.parent;
    }
    return true;
  }
  function gpos(n) { try { var g = n.localToGlobal(0, 0); return g ? { x: Math.round(g.x), y: Math.round(g.y) } : null; } catch (e) { return null; } }

  var rows = [];
  Object.keys(v).forEach(function (k) {
    var o = v[k];
    if (!o || typeof o !== 'object' || typeof o.visible !== 'boolean' || !o.localToGlobal) return;
    var g = gpos(o);
    if (!g) return;
    if (g.y > 320 || g.y < -80) return;                 /* 上方一带（含滚动容器里超出 640 的） */
    var img = '';
    (function find(n, d) { if (img || d > 3 || !n) return; try { if (n.source) { img = String(n.source); return; } } catch (e) { } (n.$children || []).forEach(function (c) { find(c, d + 1); }); })(o, 0);
    rows.push({ prop: k, effVis: effVisible(o), ownVis: o.visible, x: g.x, y: g.y,
      w: Math.round(o.width || 0), h: Math.round(o.height || 0), img: img, touch: o.touchEnabled });
  });
  rows.sort(function (a, b) { return (a.y - b.y) || (a.x - b.x); });
  out.topRight = rows;

  /* 逐个把它们点开，记录打开的界面（皮肤名），然后关掉 */
  function topSkin() {
    var list = window.__egretViews ? window.__egretViews() : [];
    return list.slice(0, 4);
  }
  out.opened = {};
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i];
    if (!r.effVis || !r.touch) continue;
    out.viewsBefore = topSkin();
    window.__egretTap(r.x + Math.round(r.w / 2), r.y + Math.round(r.h / 2));
    await sleep(1600);
    var vs = topSkin();
    out.opened[r.prop] = vs.filter(function (x) { return !/MainOut\/MainOut/.test(x.skin); }).slice(0, 2);
    /* 关掉可能打开的窗口：Esc 不管用，直接移除最上层的非 MainOut 视图 */
    try {
      var pm = core.PageManage.getInstance();
      ['WindowLayer'].forEach(function (L) {
        var layer = pm.getLayer ? pm.getLayer(core.ViewLayerType[L]) : null;
        if (layer && layer.numChildren) {
          for (var j = layer.numChildren - 1; j >= 0; j--) {
            var ch = layer.getChildAt(j);
            var m = /getSkinsPath\("([^"]+)"\)/.exec(String(ch.constructor));
            if (m) { try { layer.removeChild(ch); } catch (e) { } }
          }
        }
      });
    } catch (e) { }
    await sleep(600);
  }
  return out;
})()
