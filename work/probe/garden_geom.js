/* Scroll the garden so the house is centred and report the geometry, so a screenshot
   can be mapped back to content coordinates.

   Reports: stage size, scroller viewport offset, the house's on-screen position, and
   the on-screen rect of the garden's scene group. With those, a feature seen in the
   screenshot at fraction (fx, fy) maps to content coords
       x = sceneX + fx * sceneW      (then + scrollH for the unscrolled space). */
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
out.scaleMode = String(stage.scaleMode);

const house = mainOut.imgHouse;
if (house) {
  /* centre the house horizontally */
  const sc = mainOut.scroller;
  if (sc && sc.viewport && house) {
    try {
      const target = Math.max(0, house.x + house.width / 2 - stage.stageWidth / 2);
      sc.viewport.scrollH = target;
      out.scrolledTo = Math.round(target);
    } catch (e) { out.scrollError = String(e && e.message || e); }
  }
  const p = house.localToGlobal(0, 0);
  out.houseScreen = [Math.round(p.x), Math.round(p.y),
    Math.round(house.width), Math.round(house.height)];
}
const bg = mainOut.background;
if (bg) {
  const p = bg.localToGlobal(0, 0);
  out.backgroundScreen = [Math.round(p.x), Math.round(p.y),
    Math.round(bg.width), Math.round(bg.height)];
}
/* the visitor sign and its group, so its screen position is known too */
const sign = mainOut.i_sign;
if (sign) {
  const p = sign.localToGlobal(0, 0);
  out.signScreen = [Math.round(p.x), Math.round(p.y),
    Math.round(sign.width), Math.round(sign.height), !!sign.visible];
}
return JSON.stringify(out);
