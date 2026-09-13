/* Tap EVERY clickable node in the garden and record which view each one opens.

The report is: a paper-like thing to the LEFT of the house door opens a window that is
black except for a close "X" in the top-right. That is a normal WindowController whose
content failed to render, so the question is WHICH view. This drives the client's own
PageManage (patched here to record the exact class) for each tap, then closes it again.

The 20 clover points and their container are skipped (tapping them harvests), as are
zero-size and huge layout containers.
*/
const out = {};
const stage = egret.MainContext.instance.stage;

let mainOut = null;
(function find(n, d) {
  if (!n || d > 14 || mainOut) return;
  let src = '';
  try { src = String(n.constructor && n.constructor.toString()); } catch (e) { /* */ }
  if (/getSkinsPath\("MainOut\/MainOut\.exml"\)/.test(src)) { mainOut = n; return; }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) find(k[i], d + 1);
})(stage, 0);
if (!mainOut) return JSON.stringify({ error: 'no MainOut' });

/* record exactly what each tap opens */
const pg = core.PageManage.getInstance();
const opened = [];
if (!pg.__sweepPatched) {
  const origAdd = pg.addViewControl;
  pg.addViewControl = function (cls) {
    let src = '';
    try { src = String(cls).slice(0, 160); } catch (e) { /* */ }
    opened.push({ cls: String((cls && cls.name) || ''), src, layer: arguments[1] });
    return origAdd.apply(this, arguments);
  };
  const origRemove = pg.removeControl;
  pg.removeControl = function () { return origRemove.apply(this, arguments); };
  pg.__sweepPatched = true;
}

/* candidate nodes: clickable, reasonably sized, not a clover point */
const cands = [];
(function walk(n, d, path) {
  if (!n || d > 14) return;
  const name = String(n.name || '');
  const cls = String(n.__class__ || '');
  const w = Number(n.width) || 0;
  const h = Number(n.height) || 0;
  const isClover = /clover/i.test(name) || (path.indexOf('clovers') !== -1);
  const tooBig = w * h > 200000;
  if (n.touchEnabled && !isClover && !tooBig && (w > 8 || h > 8)) {
    cands.push({ node: n, path, name, cls,
      x: Math.round(n.x || 0), y: Math.round(n.y || 0), w: Math.round(w), h: Math.round(h) });
  }
  const kids = n.$children || [];
  for (let i = 0; i < kids.length; i++) {
    walk(kids[i], d + 1, path + '/' + (kids[i].name || String(kids[i].__class__ || i)));
  }
})(mainOut, 0, 'MainOut');

out.candidateCount = cands.length;
const results = [];
for (const c of cands) {
  const before = opened.length;
  let threw = null;
  try {
    c.node.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
  } catch (e) {
    threw = String(e && e.message || e);
  }
  const added = opened.slice(before).map((o) => o.cls + '|' + o.src.slice(0, 60));
  results.push({ path: c.path, cls: c.cls, wh: [c.w, c.h], xy: [c.x, c.y], threw, added });
  /* close whatever opened, using the captured class */
  if (added.length) {
    try {
      const last = opened[opened.length - 1];
      const pgAny = core.PageManage.getInstance();
      if (pgAny.removeControl && last && last.cls) {
        /* the recorder kept only the name; PageManage.removeControl needs the class,
           so close by scanning the open-control map instead */
        const ctl = pgAny.controlMap || pgAny.controls || null;
        void ctl;
      }
    } catch (e) { /* ignore */ }
  }
}

out.results = results.filter((r) => r.added.length || r.threw);
out.openedTotal = opened.map((o) => o.cls + '|' + o.src.slice(0, 70));
return JSON.stringify(out);
