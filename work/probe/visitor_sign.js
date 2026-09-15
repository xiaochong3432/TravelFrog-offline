/* The 串门 visitor's sign at the door (`i_sign`): does it appear, and what does tapping
   it open? Generated through the ENGINE's own visitor roll, not by hand, so the client
   gets exactly the payload it would get in play. */
const out = {};
const E = window.__engine;
const stage = egret.MainContext.instance.stage;

let mainOut = null;
(function w(n, d) {
  if (!n || d > 14 || mainOut) return;
  let src = '';
  try { src = String(n.constructor && n.constructor.toString()); } catch (e) { /* */ }
  if (/getSkinsPath\("MainOut\/MainOut\.exml"\)/.test(src)) { mainOut = n; return; }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) w(k[i], d + 1);
})(stage, 0);
if (!mainOut) return JSON.stringify({ error: 'no MainOut' });

/* Roll a visitor the way the game does. */
out.visitorBefore = !!E.state.visitor;
for (let i = 0; i < 400 && !E.state.visitor; i++) {
  E.state.visitorNextRollAt = 1;
  E.state.visitorCoolUntil = 0;
  E.tick();
}
out.visitorAfter = E.state.visitor ? {
  province: E.state.visitor.province,
  expireIn: E.state.visitor.expire_time - Math.floor(Date.now() / 1000),
} : null;

E.dispatch('visit_load', {});
for (const fn of ['updateVisitor', 'updateVisitorGift', 'checkGameplay', 'updateRedpoint']) {
  try { if (typeof mainOut[fn] === 'function') mainOut[fn](); } catch (e) {
    out['err_' + fn] = String(e && e.message || e);
  }
}
out.signVisible = mainOut.i_sign ? !!mainOut.i_sign.visible : null;
out.signSource = mainOut.i_sign ? String(mainOut.i_sign.source) : null;
out.visitorDragonbones = !!mainOut.visitorView_Dragonbones;
out.cVisitorVisible = mainOut.c_Visitor ? !!mainOut.c_Visitor.visible : null;
out.numChildrenVisitor = mainOut.c_Visitor ? (mainOut.c_Visitor.$children || []).length : null;

if (mainOut.i_sign && mainOut.i_sign.visible) {
  const before = (window.__views || []).length;
  try {
    mainOut.i_sign.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
    out.tapSign = 'tapped';
  } catch (e) {
    out.tapSign = 'THREW ' + String(e && e.message || e);
  }
  out.viewsDelta = (window.__views || []).length - before;
  out.lastViews = (window.__views || []).slice(-3);
} else {
  out.tapSign = 'skipped (sign not visible)';
}
return JSON.stringify(out);
