/* Which button in the garden opens an EMPTY (black) view?

Mechanical sweep: for every skinned button in the MainOut scene, tap it, then measure
how many nodes the newly opened view contributed and whether an exception fired. A view
that adds ~nothing is a black screen. Destructive/irrelevant buttons are skipped by name
(exit / logout / share / pay), and clover points are left alone (they harvest). */
const out = {};
const stage = egret.MainContext.instance.stage;

const views = [];
(function w(n, d) {
  if (!n || d > 14) return;
  let src = '';
  try { src = String(n.constructor && n.constructor.toString()); } catch (e) { /* */ }
  const m = /getSkinsPath\("([^"]+)"\)/.exec(src);
  if (m) views.push({ node: n, skin: m[1] });
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) w(k[i], d + 1);
})(stage, 0);
const mainOut = views.find((v) => v.skin === 'MainOut/MainOut.exml');
if (!mainOut) return JSON.stringify({ error: 'no MainOut' });
const V = mainOut.node;

const countNodes = () => {
  let n = 0;
  (function w2(x, d) {
    if (!x || d > 14) return;
    n++;
    const k = x.$children || [];
    for (let i = 0; i < k.length; i++) w2(k[i], d + 1);
  })(stage, 0);
  return n;
};

const SKIP = /exit|logout|close|back|share|pay|recharge|clover|pocket|money|redot|notification/i;
const results = [];
const buttons = [];
for (const key of Object.keys(V)) {
  if (SKIP.test(key)) continue;
  const o = V[key];
  if (!o || typeof o !== 'object') continue;
  if (String(o.__class__ || '') !== 'Button' && String(o.__class__ || '') !== 'eui.Button') continue;
  if (!o.visible) continue;
  buttons.push({ key, node: o });
}

for (const b of buttons) {
  const before = countNodes();
  let threw = null;
  try {
    b.node.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
  } catch (e) {
    threw = String(e && e.message || e);
  }
  const added = countNodes() - before;
  /* close whatever opened so the next tap starts clean: find the last added control */
  let closed = '';
  try {
    const vs = (window.__views || []).filter((v) => v.op === 'add');
    const last = vs[vs.length - 1];
    if (last && added > 0) {
      /* PageManage.removeControl needs the class; the recorder only keeps its source,
         so instead close via the stage's top controller when it exposes close(). */
      for (const v of views) {
        if (v.node && typeof v.node.close === 'function' && v.node.parent
            && v.node !== V && v.node.parent !== V) { /* leave it; reported below */ }
      }
    }
  } catch (e) { closed = String(e && e.message || e); }
  results.push({ btn: b.key, addedNodes: added, threw, closed });
}

out.buttons = buttons.map((b) => b.key);
out.results = results;
out.blankViews = results.filter((r) => r.threw || r.addedNodes <= 1);
return JSON.stringify(out);
