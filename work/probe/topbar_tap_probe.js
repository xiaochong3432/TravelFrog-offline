(async function () {
  /* 点右上角那一排按钮（从左到右第 1/2/3 个），报出每个点开的是什么界面。
     注意：不要动引导（改引导状态会把 UI 一起禁掉，之前的截图就是这么变空的）。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  var out = { steps: [] };
  try { var n0 = document.getElementById('__notice_ok'); if (n0) n0.click(); } catch (e) { }
  await sleep(1500);

  function walk(fn) {
    (function w2(n, d) {
      if (!n || d > 24) return;
      try { fn(n, d); } catch (e) { }
      (n.$children || []).forEach(function (c) { w2(c, d + 1); });
    })(egret.MainContext.instance.stage, 0);
  }
  function effVisible(n) { var c = n; while (c) { if (c.visible === false) return false; c = c.parent; } return true; }
  function texts() {
    var t = [];
    walk(function (n) { try { if (n.text) t.push(String(n.text).slice(0, 24)); } catch (e) { } });
    return t.slice(0, 20);
  }
  function topViews() {
    return (window.__egretViews() || []).filter(function (v) { return !/MainOut\/MainOut/.test(v.skin); }).slice(0, 3);
  }

  /* 右上角那一排：找所有"父链可见 + 顶部 + 有 touchEnabled"的节点，按 x 排序 */
  var cands = [];
  walk(function (n) {
    var g = null; try { g = n.localToGlobal(0, 0); } catch (e) { }
    if (!g || !effVisible(n)) return;
    if (g.y < -20 || g.y > 70) return;
    var w2 = Math.round(n.width || 0), h2 = Math.round(n.height || 0);
    if (w2 < 40 || w2 > 200 || h2 < 40 || h2 > 130) return;
    if (!n.touchEnabled) return;
    var img = '';
    (function find(m, d) { if (img || d > 3 || !m) return; try { if (m.source) { img = String(m.source); return; } } catch (e) { } (m.$children || []).forEach(function (c) { find(c, d + 1); }); })(n, 0);
    cands.push({ x: Math.round(g.x), y: Math.round(g.y), w: w2, h: h2, img: img, name: String(n.name || '') });
  });
  /* 去掉重叠冗余（同一按钮的父子节点） */
  var buttons = [];
  cands.sort(function (a, b) { return (a.y - b.y) || (a.x - b.x); });
  cands.forEach(function (c) {
    if (buttons.some(function (b) { return Math.abs(b.x - c.x) < 8 && Math.abs(b.y - c.y) < 8; })) return;
    buttons.push(c);
  });
  out.topButtons = buttons;
  out.textsAtStart = texts();

  for (var i = 0; i < buttons.length && i < 4; i++) {
    var b = buttons[i];
    var before = topViews().length;
    window.__egretTap(b.x + Math.round(b.w / 2), b.y + Math.round(b.h / 2));
    await sleep(2200);
    var after = topViews();
    out.steps.push({ idx: i, at: [b.x, b.y], img: b.img, opened: after.slice(0, 2), texts: texts().slice(0, 12) });
    /* 关掉刚开的东西 */
    try {
      var pm = core.PageManage.getInstance();
      var layer = pm.getLayer ? pm.getLayer(core.ViewLayerType.WindowLayer) : null;
      if (layer) for (var j = layer.numChildren - 1; j >= 0; j--) { try { layer.removeChild(layer.getChildAt(j)); } catch (e) { } }
    } catch (e) { }
    await sleep(800);
  }
  return out;
})()
