/* Advance the annual review through its pages and collect EVERY rendered string,
   so "undefined" from a missing payload field cannot hide behind the first card. */
const stage = egret.MainContext.instance.stage;
function reviewView() {
  let v = null;
  (function walk(n, d) {
    if (d > 12 || !n || v) return;
    for (const c of (n.$children || [])) {
      let s = '';
      try { s = String(c.constructor); } catch (e) { }
      if (s.indexOf('AnnualReviewSkin.exml') >= 0) { v = c; return; }
      walk(c, d + 1);
      if (v) return;
    }
  })(stage, 0);
  return v;
}
function allText() {
  const out = [];
  (function walk(n, d) {
    if (d > 16 || !n) return;
    for (const c of (n.$children || [])) {
      if (c instanceof egret.TextField && c.text) out.push(c.text);
      walk(c, d + 1);
    }
  })(stage, 0);
  return out;
}

const am = core.ModelManage.getInstance().getModel(AnnualReviewModel);
await new Promise((r) => {
  core.SocketManage.getInstance().send('annual_load', new core.Action2(() => r()), );
  setTimeout(r, 2000);
});
core.PageManage.getInstance().addViewControl(AnnualReviewViewControl, core.ViewLayerType.WindowLayer);
await new Promise((r) => setTimeout(r, 2500));

const collected = [];
const v = reviewView();
for (let page = 0; page < 4; page++) {
  await new Promise((r) => setTimeout(r, 1800));
  collected.push({ page, texts: allText().filter((t) => t.length > 1 && t.length < 300) });
  try { v.next(true); } catch (e) { collected.push({ page, err: String(e && e.message) }); }
}

const flat = collected.flatMap((c) => c.texts || []);
return JSON.stringify({
  reviewData: am.cacheData,
  pages: collected.map((c) => ({ page: c.page, n: (c.texts || []).length, err: c.err || null })),
  undefinedTexts: flat.filter((t) => /undefined|NaN/.test(t)),
  sampleTexts: Array.from(new Set(flat)).filter((t) => t.length > 4 && !/^\d+$/.test(t)).slice(0, 30),
}, null, 1);
