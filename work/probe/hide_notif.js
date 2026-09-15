/* Hide the scene's full-screen notification overlay (which covers the whole
   stage and may swallow taps) and report the touch flags of everything sitting
   above the scene at the tapped point. */
const stage = egret.MainContext.instance.stage;
const out = { hidden: [], above: [] };
const pt = { x: 560, y: 967 };

(function walk(n, d) {
  if (d > 12 || !n) return;
  for (const c of (n.$children || [])) {
    let s = '';
    try { s = String(c.constructor); } catch (e) { }
    const m = /getSkinsPath\("([^"]+)"\)/.exec(s);
    if (/MainOut\/Notification\.exml/.test(s)) {
      out.hidden.push('Notification vis=' + c.visible + ' touch=' + c.touchEnabled + ' touchChildren=' + c.touchChildren);
      c.visible = false;
    }
    /* does this node cover the tap point, and can it swallow the tap? */
    if (c.visible && c.touchEnabled) {
      try {
        const g = c.localToGlobal(0, 0);
        if (pt.x >= g.x && pt.x <= g.x + c.width && pt.y >= g.y && pt.y <= g.y + c.height) {
          out.above.push({
            d, skin: m ? m[1] : ('<' + s.slice(0, 30) + '>'),
            rect: [Math.round(g.x), Math.round(g.y), Math.round(c.width), Math.round(c.height)],
            touchChildren: c.touchChildren,
          });
        }
      } catch (e) { }
    }
    walk(c, d + 1);
  }
})(stage, 0);

out.tap = window.__egretTap(pt.x, pt.y);
return JSON.stringify(out, null, 1);
