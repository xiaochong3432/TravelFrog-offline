(async function () {
  /* 关掉所有开场遮罩（权利声明、欢迎引导…），然后把**真实主界面**的按钮列出来，
     并报出每个按钮上的文字（比如"添加小程序"），供判断"右上角第二个"。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);

  function walkAll(fn) {
    (function w2(n, d) {
      if (!n || d > 22) return;
      try { fn(n, d); } catch (e) { }
      (n.$children || []).forEach(function (c) { w2(c, d + 1); });
    })(egret.MainContext.instance.stage, 0);
  }
  var out = { dismissed: [] };
  for (var pass = 0; pass < 6; pass++) {
    var hit = null;
    walkAll(function (n) {
      if (hit) return;
      var t = '';
      try { t = String(n.text || ''); } catch (e) { }
      if (!t) return;
      if (/同意|开始|进入|继续|确定|好的/.test(t) && n.touchEnabled) hit = n;
    });
    var btn = document.getElementById('__notice_ok');
    if (btn && pass === 0) { btn.click(); out.dismissed.push('notice'); }
    if (!hit) break;
    var g = null; try { g = hit.localToGlobal(0, 0); } catch (e) { }
    if (!g) break;
    out.dismissed.push(String(hit.text).slice(0, 20));
    window.__egretTap(Math.round(g.x + (hit.width || 100) / 2), Math.round(g.y + (hit.height || 40) / 2));
    await sleep(1200);
  }
  await sleep(1500);

  out.views = (window.__egretViews() || []).slice(0, 6);
  var view = null;
  walkAll(function (n) { if (!view && n.groupTop) view = n; });
  out.viewFound = !!view;
  if (!view) return out;

  var buttons = [];
  walkAll(function (n) {
    var t = false, hasImg = false, g = null;
    try { t = !!n.touchEnabled && n.visible; } catch (e) { }
    try { hasImg = !!n.source; } catch (e) { }
    try { g = n.localToGlobal(0, 0); } catch (e) { }
    if (t && g && g.y > -5 && g.y < 130) {
      buttons.push({ src: (n.source || '') + '', text: String(n.text || ''),
        x: Math.round(g.x), y: Math.round(g.y), w: Math.round(n.width || 0), h: Math.round(n.height || 0) });
    }
  });
  buttons.sort(function (a, b) { return a.x - b.x; });
  out.topButtons = buttons;

  /* 主界面上的所有文本（含"添加小程序"这类标签） */
  var texts = [];
  walkAll(function (n) { try { if (n.text) texts.push(String(n.text).slice(0, 30)); } catch (e) { } });
  out.texts = texts.slice(0, 40);
  return out;
})()
