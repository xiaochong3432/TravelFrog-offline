/* Which view does each invisible garden hit-area open? Record the SKIN PATH.

The previous sweep recorded `cls.name`, which is minified to "t" -- useless. The shell
already records every addViewControl with the class's function source in `window.__views`,
and a WindowView's source contains `getSkinsPath("...")`, so the skin identifies the view.
This taps only the nodes INSIDE the garden scroller (the scene hit-areas), which is where
the reported paper sits. */
const out = {};
const stage = egret.MainContext.instance.stage;

function skinFrom(src) {
  const m = /getSkinsPath\("([^"]+)"\)/.exec(String(src || ''));
  return m ? m[1] : '';
}

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

/* only the garden scene subtree */
let scroller = null;
(function find(n, d) {
  if (!n || d > 6 || scroller) return;
  if (String(n.__class__ || '') === 'eui.Scroller') { scroller = n; return; }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) find(k[i], d + 1);
})(mainOut, 0, 0);
out.scrollerFound = !!scroller;
if (!scroller) return JSON.stringify(out);

const cands = [];
(function walk(n, d, path) {
  if (!n || d > 14) return;
  const w = Number(n.width) || 0;
  const h = Number(n.height) || 0;
  const name = String(n.name || '');
  if (n.touchEnabled && w * h > 400 && w * h < 200000 && !/clover/i.test(name)) {
    cands.push({ node: n, path, name, cls: String(n.__class__ || ''),
      x: Math.round(n.x || 0), y: Math.round(n.y || 0), w: Math.round(w), h: Math.round(h) });
  }
  const kids = n.$children || [];
  for (let i = 0; i < kids.length; i++) {
    walk(kids[i], d + 1, path + '/' + (kids[i].name || String(kids[i].__class__ || i)));
  }
})(scroller, 0, 'scroller');

const results = [];
for (const c of cands) {
  const before = (window.__views || []).length;
  let threw = null;
  try {
    c.node.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
  } catch (e) {
    threw = String(e && e.message || e);
  }
  const addedList = (window.__views || []).slice(before).filter((v) => v.op === 'add');
  results.push({
    path: c.path, name: c.name, cls: c.cls, xy: [c.x, c.y], wh: [c.w, c.h],
    threw,
    opened: addedList.map((v) => skinFrom(v.fp) || String(v.fp).slice(0, 80)),
  });
}
out.candidates = cands.length;
out.results = results.filter((r) => r.opened.length || r.threw);
return JSON.stringify(out);
