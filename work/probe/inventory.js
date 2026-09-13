/* Full inventory of the garden view's skin properties: name, class, visibility, touch.
   Needed because most actions hang off `this.menu` (Menu.exml) rather than the view. */
const out = { props: [], menu: [], classes: {} };
const stage = egret.MainContext.instance.stage;

function walk(n, d, visit) {
  if (!n || d > 15) return;
  visit(n);
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) walk(k[i], d + 1, visit);
}

let mainOut = null;
walk(stage, 0, (n) => {
  let src = '';
  try { src = String(n.constructor && n.constructor.toString()); } catch (e) { /* */ }
  if (!mainOut && /getSkinsPath\("MainOut\/MainOut\.exml"\)/.test(src)) mainOut = n;
});

if (!mainOut) return JSON.stringify({ error: 'no MainOut' });

for (const key of Object.keys(mainOut)) {
  const o = mainOut[key];
  if (!o || typeof o !== 'object') continue;
  const cls = String(o.__class__ || '');
  if (!cls) continue;
  if (/Button|Group|Image|Label|Menu|Redot|Dragonbones/.test(cls)) {
    out.props.push({
      key, cls,
      vis: o.visible === undefined ? null : !!o.visible,
      touch: !!o.touchEnabled,
      x: Math.round(o.x || 0), y: Math.round(o.y || 0),
    });
  }
}

const menu = mainOut.menu;
if (menu && typeof menu === 'object') {
  for (const key of Object.keys(menu)) {
    const o = menu[key];
    if (!o || typeof o !== 'object') continue;
    const cls = String(o.__class__ || '');
    if (!cls) continue;
    out.menu.push({ key, cls, vis: o.visible === undefined ? null : !!o.visible });
  }
}

/* which node classes actually exist in the tree (to know what to look for) */
walk(stage, 0, (n) => {
  const c = String(n.__class__ || '');
  if (c) out.classes[c] = (out.classes[c] || 0) + 1;
});
out.classes = Object.keys(out.classes).slice(0, 60);
return JSON.stringify(out);
