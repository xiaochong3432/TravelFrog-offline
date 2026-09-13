/* Tap one garden hit-area by coordinates, remember the class it opened so a later step
   can close it, and leave it on screen for the screenshot.

   window.__tapXY = [x, y] in garden content coordinates must be set by the driver first.
   The scene is inside a scroller, so the tap is dispatched on the node found there. */
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

let scroller = null;
(function find(n, d) {
  if (!n || d > 6 || scroller) return;
  if (String(n.__class__ || '') === 'eui.Scroller') { scroller = n; return; }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) find(k[i], d + 1);
})(mainOut, 0, 0);

const want = window.__tapXY || null;
if (!want) return JSON.stringify({ error: 'set window.__tapXY = [x,y] first' });
out.want = want;

/* patch addViewControl once, keeping the CLASS so it can be closed later */
const pg = core.PageManage.getInstance();
if (!pg.__clsPatched) {
  const orig = pg.addViewControl;
  pg.addViewControl = function (cls) {
    window.__openedCls = cls;
    window.__openedLayer = arguments[1];
    return orig.apply(this, arguments);
  };
  pg.__clsPatched = true;
}

const hits = [];
(function walk(n, d) {
  if (!n || d > 14) return;
  const w = Number(n.width) || 0;
  const h = Number(n.height) || 0;
  if (n.touchEnabled && w * h > 400 && w * h < 200000
      && Math.round(n.x) === want[0] && Math.round(n.y) === want[1]) {
    hits.push(n);
  }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) walk(k[i], d + 1);
})(scroller, 0);
out.hits = hits.length;
if (!hits.length) return JSON.stringify(out);

try {
  hits[0].dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
  out.tapped = true;
} catch (e) {
  out.tapped = 'THREW ' + String(e && e.message || e);
}
const v = (window.__views || []).filter((x) => x.op === 'add').slice(-1)[0];
out.openedSource = v ? String(v.fp).slice(0, 700) : null;
out.openedSkin = v ? (/getSkinsPath\("([^"]+)"\)/.exec(String(v.fp)) || [])[1] || '' : '';
return JSON.stringify(out);
