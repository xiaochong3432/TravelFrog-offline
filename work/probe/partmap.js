/* Map every clickable skin part of the open view(s).
   Set window.__VIEWKEY before running (e.g. 'Menu', 'MainOut', 'Shop').
   Lists own properties that are egret DisplayObjects with a real size, with
   global coordinates -- i.e. exactly the buttons a player can tap. */
const key = window.__VIEWKEY || 'MainOut';
const stage = egret.MainContext.instance.stage;
const views = [];

(function walk(node, depth) {
  if (depth > 12 || !node || views.length > 8) return;
  for (const c of (node.$children || [])) {
    let src = '';
    try { src = String(c.constructor); } catch (e) { }
    const m = /getSkinsPath\("([^"]+)"\)/.exec(src);
    if (m && m[1].indexOf(key) >= 0 && c.visible) views.push({ v: c, skin: m[1] });
    walk(c, depth + 1);
  }
})(stage, 0);

const out = views.map(({ v, skin }) => {
  const parts = [];
  for (const k in v) {
    if (k.charAt(0) === '$' || k.charAt(0) === '_') continue;
    let p;
    try { p = v[k]; } catch (e) { continue; }
    if (!p || typeof p !== 'object') continue;
    if (!(p instanceof egret.DisplayObject)) continue;
    if (!(p.width > 0 && p.height > 0)) continue;
    let g = null;
    try { g = p.localToGlobal(0, 0); } catch (e) { }
    parts.push({
      k, d: p.visible !== false,
      xy: g ? Math.round(g.x) + ',' + Math.round(g.y) : '?',
      wh: Math.round(p.width) + 'x' + Math.round(p.height),
      touch: p.touchEnabled,
      text: (typeof p.text === 'string' ? p.text : (typeof p.label === 'string' ? p.label : undefined)),
      src: (typeof p.source === 'string' ? p.source : undefined),
      cls: (p.constructor && p.constructor.name) || '',
    });
  }
  parts.sort((a, b) => a.k < b.k ? -1 : 1);
  return { skin, parts };
});

return JSON.stringify(out, null, 1);
