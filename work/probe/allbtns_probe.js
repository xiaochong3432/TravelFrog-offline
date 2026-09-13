(async function () {
  /* 全屏可见按钮清单（含每个按钮上的图片名），按位置排序 —— 用来定位"菜单按钮左边的那个"。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  try { var n0 = document.getElementById('__notice_ok'); if (n0) n0.click(); } catch (e) { }
  try { core.ModelManage.getInstance().getModel(UserModel).clientSettings.guideStep = 'Complete'; } catch (e) { }
  var ctl = null;
  try { ctl = core.PageManage.getInstance().getControl(MainOutController, core.ViewLayerType.SceneLayer); } catch (e) { }
  if (ctl && ctl.getView && ctl.getView().checkGuide) { try { ctl.getView().checkGuide(); } catch (e) { } }
  await sleep(1200);
  var v = ctl && ctl.getView();
  if (v) (v.$children || []).slice().forEach(function (c) {
    var m = /getSkinsPath\("([^"]+)"\)/.exec(String(c.constructor));
    if (m && /Guide\//.test(m[1])) { try { v.removeChild(c); } catch (e) { } }
  });
  await sleep(800);

  function effVisible(n) { var cur = n; while (cur) { if (cur.visible === false) return false; cur = cur.parent; } return true; }
  var rows = [];
  (function walk(n, d) {
    if (!n || d > 24) return;
    var src = '';
    try { src = String(n.source || ''); } catch (e) { }
    if (src && src !== 'undefined') {
      var g = null; try { g = n.localToGlobal(0, 0); } catch (e) { }
      if (g && effVisible(n)) {
        /* 只要最外层那张（父节点的图不算） */
        rows.push({ img: src, x: Math.round(g.x), y: Math.round(g.y),
          w: Math.round(n.width || 0), h: Math.round(n.height || 0),
          touch: !!n.touchEnabled, name: String(n.name || '') });
      }
    }
    (n.$children || []).forEach(function (c) { walk(c, d + 1); });
  })(egret.MainContext.instance.stage, 0);
  rows.sort(function (a, b) { return (a.y - b.y) || (a.x - b.x); });
  return { views: (window.__egretViews() || []).slice(0, 5), rows: rows.slice(0, 60) };
})()
