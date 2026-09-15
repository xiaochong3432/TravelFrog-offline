/* 点掉标题页的「开始」：找到文本是"开始"的节点，点它自己或它的父级按钮。 */
(function () {
  var out = { tried: [] };
  function walk(node, depth, acc, chain) {
    if (!node || depth > 16) return acc;
    var cls = String(node.__class__ || (node.constructor && node.constructor.name) || '');
    acc.push({ n: node, cls: cls, chain: chain + '>' + cls });
    var kids = node.$children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc, chain + '>' + cls);
    return acc;
  }
  var all = walk(egret.MainContext.instance.stage, 0, [], 'stage');

  /* 1) 谁在台上（顶层视图的类名分布） */
  var seen = {};
  all.forEach(function (x) { if (x.cls && /View|Control|Layer/.test(x.cls)) seen[x.cls] = (seen[x.cls] || 0) + 1; });
  out.views = Object.keys(seen).slice(0, 30);

  /* 2) 找文本是"开始"的节点 */
  var hits = all.filter(function (x) { return x.n && x.n.text === '开始'; });
  out.startNodes = hits.map(function (h) { return h.chain; });

  /* 3) 点它、以及它的父级（按钮通常是父级） */
  hits.forEach(function (h) {
    var targets = [h.n, h.n.parent].filter(Boolean);
    targets.forEach(function (t) {
      try {
        if (t.dispatchEvent) {
          t.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
          out.tried.push('tap:' + String(t.__class__ || (t.constructor && t.constructor.name) || '?'));
        }
      } catch (e) { out.tried.push('err:' + (e && e.message)); }
    });
  });
  return JSON.stringify(out, null, 1);
})()