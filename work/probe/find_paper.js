/* Where is the paper, and what does a REAL tap there open?

The report: the paper sits BETWEEN the workbench (content x~557) and the house door
(x~786), tapping it opens a black window with a working X, and the shell guard does NOT
fire -- so the view opens without throwing and simply paints nothing.

This reports the geometry needed to convert content coordinates to viewport pixels, and
scrolls the garden so that band is on screen. The driver then taps for real (Egret's own
hit test decides what is under the finger) and a follow-up probe reads `window.__views`
to name whatever opened. */
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

out.stage = [stage.stageWidth, stage.stageHeight];
out.window = [window.innerWidth, window.innerHeight];

/* the canvas that fills the window -- its CSS rect is what a viewport tap hits */
const canvas = document.querySelector('canvas') || document.querySelector('.egret-player canvas');
if (canvas) {
  const r = canvas.getBoundingClientRect();
  out.canvasRect = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
  out.dpr = window.devicePixelRatio;
}

/* scroll so the band between the bench and the door is centred */
const sc = mainOut.scroller;
if (sc && sc.viewport) {
  const target = Math.max(0, 660 - stage.stageWidth / 2);
  sc.viewport.scrollH = target;
  out.scrollH = Math.round(target);
}

/* the bench and the door, in garden content coordinates (the two known anchors) */
const bench = mainOut.imgFurnitureBench;
const house = mainOut.imgHouse;
out.bench = bench ? [Math.round(bench.x), Math.round(bench.y),
  Math.round(bench.width), Math.round(bench.height)] : null;
out.house = house ? [Math.round(house.x), Math.round(house.y),
  Math.round(house.width), Math.round(house.height)] : null;

/* every node in the scroller with touchEnabled, small or large, WITH its screen rect --
   including ones the earlier sweep dropped for being tiny */
const hits = [];
(function walk(n, d) {
  if (!n || d > 14) return;
  if (n.touchEnabled) {
    const p = n.localToGlobal(0, 0);
    const w = Number(n.width) || 0, h = Number(n.height) || 0;
    if (w > 0 && h > 0 && w < 400 && h < 400 && p.x > window.innerWidth - 900) {
      hits.push({ cls: String(n.__class__ || ''), name: String(n.name || ''),
        content: [Math.round(n.x), Math.round(n.y)], wh: [Math.round(w), Math.round(h)],
        screen: [Math.round(p.x), Math.round(p.y)] });
    }
  }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) walk(k[i], d + 1);
})(sc, 0);
out.touchables = hits.filter((h) => h.content[0] > 400 && h.content[0] < 900);
return JSON.stringify(out);
