/* Find the red square: the client's GM entry trigger.

It sits at the left edge, roughly 38% down, in every screenshot -- so it is NOT part of the
scrolled garden. Walk the whole stage and report every node that is (a) a shape with a
reddish fill, or (b) a Button/Rect with a suspicious name; print class, colour, screen
position and size so the shell can hide the right one. */
const out = { reds: [], named: [] };
const stage = egret.MainContext.instance.stage;

(function walk(n, d, path) {
  if (!n || d > 16) return;
  let path2 = path + '/' + (n.name || String(n.__class__ || '?'));
  let fill = null;
  try {
    if (n.fillColor !== undefined && n.fillColor !== null) fill = n.fillColor;
  } catch (e) { /* ignore */ }
  const p = (function () { try { return n.localToGlobal(0, 0); } catch (e) { return null; } })();
  const w = Number(n.width) || 0;
  const h = Number(n.height) || 0;
  const cls = String(n.__class__ || '');

  if (fill !== null && typeof fill === 'number') {
    const r = (fill >> 16) & 255, g = (fill >> 8) & 255, b = fill & 255;
    if (r > 120 && g < 100 && b < 100) {
      out.reds.push({ path: path2, cls, fill: '#' + fill.toString(16),
        screen: p ? [Math.round(p.x), Math.round(p.y)] : null,
        wh: [Math.round(w), Math.round(h)], visible: !!n.visible,
        alpha: n.alpha === undefined ? null : n.alpha });
    }
  }
  if (/gm|debug|console/i.test(String(n.name || '')) || /GM/i.test(cls)) {
    out.named.push({ path: path2, cls, visible: !!n.visible,
      screen: p ? [Math.round(p.x), Math.round(p.y)] : null, wh: [Math.round(w), Math.round(h)] });
  }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) walk(k[i], d + 1, path2);
})(stage, 0, '');

out.stage = [stage.stageWidth, stage.stageHeight];
/* does the GM view class exist, so the new ball can open the real console? */
out.gmView = typeof eval('GMViewController') === 'function';
return JSON.stringify(out);
