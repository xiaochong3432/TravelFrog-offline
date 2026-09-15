(async function () {
  /* 主界面顶部那一排按钮（groupTop）到底是哪几个？顺便把"左数第二个/右数第二个"点出来看它开了什么。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  try { var n0 = document.getElementById('__notice_ok'); if (n0) n0.click(); } catch (e) { }
  await sleep(1500);

  var view = null;
  (function walk(node, d) {
    if (view || !node || d > 18) return;
    if (node.groupTop || node.miniGroup) { view = node; return; }
    var kids = node.$children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], d + 1);
  })(egret.MainContext.instance.stage, 0);
  var out = { viewFound: !!view };
  if (!view || !view.groupTop) return out;

  function describe(node, label, depth) {
    var g = null;
    try { g = node.localToGlobal(0, 0); } catch (e) { }
    var src = '';
    try { src = node.source || ''; } catch (e) { }
    var kids = (node.$children || []).map(function (c) { return describe(c, label, (depth || 0) + 1); });
    return {
      label: label, cls: (function () {
        try {
          var src = String(node.constructor);
          var m = /getSkinsPath\("([^"]+)"\)/.exec(src);
          return m ? m[1] : src.slice(0, 40);
        } catch (e) { return ''; }
      })(),
      name: node.name || '', src: src, text: (node.text || '') + '',
      vis: node.visible, touch: node.touchEnabled,
      x: g ? Math.round(g.x) : null, y: g ? Math.round(g.y) : null,
      w: Math.round(node.width || 0), h: Math.round(node.height || 0),
      kids: kids,
    };
  }
  var top = view.groupTop;
  out.groupTop = { vis: top.visible, x: (top.localToGlobal(0, 0) || {}).x, kids: (top.$children || []).length };
  out.children = (top.$children || []).map(function (c, i) { return describe(c, 'child' + i, 0); });

  /* 找到所有可见的、可点的叶子，按 x 排序 → 这就是玩家说的"左数/右数" */
  var buttons = [];
  (function collect(node) {
    if (!node) return;
    var t = false;
    try { t = !!node.touchEnabled && node.visible; } catch (e) { }
    var hasImg = false;
    try { hasImg = !!node.source; } catch (e) { }
    var g = null; try { g = node.localToGlobal(0, 0); } catch (e) { }
    if (t && hasImg && g && g.y < 400) {
      buttons.push({ src: node.source, x: Math.round(g.x), y: Math.round(g.y),
        w: Math.round(node.width), h: Math.round(node.height) });
    }
    (node.$children || []).forEach(collect);
  })(view);
  buttons.sort(function (a, b) { return a.x - b.x; });
  out.buttons = buttons;

  /* 点"左数第二个" */
  function tapAt(b) { return window.__egretTap(b.x + Math.round(b.w / 2), b.y + Math.round(b.h / 2)); }
  out.viewsBefore = (window.__egretViews() || []).slice(0, 6);
  if (buttons.length >= 2) {
    out.tapLeft2 = buttons[1];
    tapAt(buttons[1]);
    await sleep(2500);
    out.viewsAfterLeft2 = (window.__egretViews() || []).slice(0, 6);
    out.modalAfterLeft2 = (function () {
      var txt = [];
      (function walk2(n, d) {
        if (!n || d > 22) return;
        try { if (n.text) txt.push(String(n.text).slice(0, 40)); } catch (e) { }
        (n.$children || []).forEach(function (c) { walk2(c, d + 1); });
      })(egret.MainContext.instance.stage, 0);
      return txt.slice(0, 25);
    })();
  }
  return out;
})()
