/* For the "N天" labels on the main scene, find WHICH property of the view holds
   them, plus the value of anything that looks like a countdown source. */
const stage = egret.MainContext.instance.stage;
let view = null;
(function walk(n, d) {
  if (d > 14 || !n || view) return;
  for (const c of (n.$children || [])) {
    let s = '';
    try { s = String(c.constructor); } catch (e) { }
    if (s.indexOf('MainOut.exml') >= 0) { view = c; return; }
    walk(c, d + 1);
    if (view) return;
  }
})(stage, 0);
if (!view) return JSON.stringify({ error: 'no MainOut view' });

function contains(root, node) {
  if (root === node) return true;
  for (const c of (root.$children || [])) if (contains(c, node)) return true;
  return false;
}

const out = { labels: [], owners: {} };
const targets = [];
(function collect(n, d) {
  if (d > 16 || !n) return;
  for (const c of (n.$children || [])) {
    if (c instanceof egret.TextField && c.text && /\d+\s*天/.test(c.text)) targets.push(c);
    collect(c, d + 1);
  }
})(view, 0);

for (const t of targets) out.labels.push(t.text);
for (const k in view) {
  if (k.charAt(0) === '$') continue;
  let p;
  try { p = view[k]; } catch (e) { continue; }
  if (!p || typeof p !== 'object' || !(p instanceof egret.DisplayObject)) continue;
  for (const t of targets) if (contains(p, t)) out.owners[k] = out.labels[targets.indexOf(t)];
}

/* candidate sources for a "days remaining" figure */
const src = {};
try {
  const cm = core.ModelManage.getInstance().getModel(CapsuleModel);
  src.capsule = { end_time: cm.data && cm.data.end_time, days: cm.data && cm.data.end_time ? Math.floor((cm.data.end_time - core.Time.getServerTime()) / 86400) : 0 };
} catch (e) { src.capsule = 'ERR ' + e.message; }
try {
  const wm = core.ModelManage.getInstance().getModel(WishingPoolModel);
  const d = wm.data || wm.poolData || {};
  src.wishing = { end_time: d.end_time, days: d.end_time ? Math.floor((d.end_time - core.Time.getServerTime()) / 86400) : 0 };
} catch (e) { src.wishing = 'ERR ' + e.message; }
try {
  const um = core.ModelManage.getInstance().getModel(UserModel);
  src.user = { createDay: core.ModelManage.getInstance().getModel(RoleModel).getCreateDay() };
  for (const k of ['getShowPay', 'getShowShareBtn']) src.user[k] = typeof um[k] === 'function' ? String(um[k]()) : 'n/a';
} catch (e) { src.user = 'ERR ' + e.message; }

return JSON.stringify({ labels: out.labels, owners: out.owners, src }, null, 1);
