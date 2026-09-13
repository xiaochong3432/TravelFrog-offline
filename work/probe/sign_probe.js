/* Which door-side element black-screens? Tap the candidates and see.

The garden scene's only note-like properties are `i_sign` (the visitor's sign, posted
at the door) and `btnPublicityMap` (parked at x=2104, the far right of the scrollable
garden). `state.notes` is empty in this build, so the note LIST has nothing -- the
question is what tapping these actually opens. */
const out = {};
const E = window.__engine;
const stage = egret.MainContext.instance.stage;
const now = Math.floor(Date.now() / 1000);

const views = [];
(function w(n, d) {
  if (!n || d > 14) return;
  let src = '';
  try { src = String(n.constructor && n.constructor.toString()); } catch (e) { /* */ }
  const m = /getSkinsPath\("([^"]+)"\)/.exec(src);
  if (m) views.push({ node: n, skin: m[1] });
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) w(k[i], d + 1);
})(stage, 0);
const mainOut = views.find((v) => v.skin === 'MainOut/MainOut.exml');
out.mainOutFound = !!mainOut;
if (!mainOut) return JSON.stringify(out);
const V = mainOut.node;

out.hasNoteRedot = !!V.i_noteRedot;
out.noteRedotVisible = V.i_noteRedot ? !!V.i_noteRedot.visible : null;
out.signVisibleBefore = !!V.i_sign.visible;
out.mapBtnVisible = !!V.btnPublicityMap.visible;
out.notesInSave = (E.state.notes || []).length;

/* force a 串门 visitor so the sign at the door becomes visible */
try {
  E.state.visitor = {
    province: '上海', city: '上海', name: '上海', title: 3, partner: 0, food: 2,
    first: true, expire_time: now + 3600, gift: { item_id: 100001, count: 2 }, carpet: 4,
  };
  E.dispatch('visit_load', {});
  for (const fn of ['updateVisitor', 'updateVisitorGift', 'checkGameplay']) {
    if (typeof V[fn] === 'function') V[fn]();
  }
  out.signVisibleAfter = !!V.i_sign.visible;
  out.visitorSignXY = [Math.round(V.i_sign.x), Math.round(V.i_sign.y)];
} catch (e) {
  out.visitorError = String(e && e.message || e);
}

/* tap the sign -- it is the only paper-like thing at the door */
out.tapSign = 'skipped';
if (V.i_sign && V.i_sign.visible) {
  try {
    V.i_sign.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
    out.tapSign = 'tapped';
  } catch (e) {
    out.tapSign = 'THREW ' + String(e && e.message || e);
  }
  out.openAfterSign = (window.__views || []).slice(-4);
}
return JSON.stringify(out);
