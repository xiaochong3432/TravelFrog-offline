/* Locate the "note stuck on the door" by enumerating the SCENE VIEW'S OWN PROPERTIES.

An EXML skin binds its children to properties on the view (`this.i_noteRedot = t`),
and those property names are the only reliable identifiers -- `node.name` is usually
empty. This lists every property of every live scene view whose name smells like a
note / door / sign / paper / map, then reports which PageManage views are open. */
const out = {};
const stage = egret.MainContext.instance.stage;

const views = [];
(function w(n, d) {
  if (!n || d > 14) return;
  let cls = String(n.__class__ || '');
  let src = '';
  try { src = String(n.constructor && n.constructor.toString()).slice(0, 200); } catch (e) { /* */ }
  const m = /getSkinsPath\("([^"]+)"\)/.exec(src);
  if (m) views.push({ node: n, skin: m[1] });
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) w(k[i], d + 1);
})(stage, 0);

out.skins = views.map((v) => v.skin);
const RE = /note|sign|paper|door|letter|map|clover|visitor|wall|photo|album/i;
out.parts = [];
for (const v of views) {
  const keys = Object.keys(v.node);
  for (const k of keys) {
    if (!RE.test(k)) continue;
    const o = v.node[k];
    if (!o || typeof o !== 'object') continue;
    out.parts.push({
      skin: v.skin, prop: k,
      cls: String(o.__class__ || ''),
      vis: o.visible === undefined ? null : !!o.visible,
      touch: !!o.touchEnabled,
      x: Math.round(o.x || 0), y: Math.round(o.y || 0),
      w: Math.round(o.width || 0), h: Math.round(o.height || 0),
    });
  }
}

/* which controllers are open right now (for correlating a tap with a view) */
try {
  out.openNow = (window.__views || []).slice(-6);
} catch (e) { out.openNow = 'n/a'; }

return JSON.stringify(out);
