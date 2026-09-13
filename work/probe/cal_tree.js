/* Print the display path of the calendar's imagePic and groupDay so the
   replacement layer can be inserted into the right parent/space. */
const stage = egret.MainContext.instance.stage;
let view = null;
(function walk(n, d) {
  if (d > 14 || !n || view) return;
  for (const c of (n.$children || [])) {
    let s = '';
    try { s = String(c.constructor); } catch (e) { }
    if (s.indexOf('CalendarSkin.exml') >= 0) { view = c; return; }
    walk(c, d + 1);
    if (view) return;
  }
})(stage, 0);
if (!view) return JSON.stringify({ error: 'no view' });

function describe(node) {
  const out = [];
  let n = node;
  let d = 0;
  while (n && d < 8) {
    let s = '';
    try { s = String(n.constructor); } catch (e) { }
    const m = /getSkinsPath\("([^"]+)"\)/.exec(s);
    const g = (() => { try { return n.localToGlobal(0, 0); } catch (e) { return null; } })();
    out.push({
      cls: m ? m[1] : ('<' + s.slice(0, 26) + '>'),
      xy: g ? Math.round(g.x) + ',' + Math.round(g.y) : '?',
      wh: Math.round(n.width) + 'x' + Math.round(n.height),
      kids: n.$children ? n.$children.length : 0,
    });
    n = n.parent;
    d++;
  }
  return out;
}

const parts = {};
for (const k of ['imagePic', 'groupDay', 'groupReward', 'imageToday', 'cover']) {
  parts[k] = view[k] ? describe(view[k]) : null;
}
/* the view's own children, in paint order */
const kids = [];
for (let i = 0; i < view.numChildren; i++) {
  const c = view.getChildAt(i);
  let s = '';
  try { s = String(c.constructor); } catch (e) { }
  kids.push({
    i, cls: s.slice(0, 34),
    name: c.name || '',
    vis: c.visible,
    wh: Math.round(c.width) + 'x' + Math.round(c.height),
  });
}
return JSON.stringify({ parts, viewChildren: kids }, null, 1);
