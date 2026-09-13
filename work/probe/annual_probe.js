/* Open the 年度总结 (annual review) the way the game does, then report what data
   it was given. The view's copy is built from fields like travel_num / pic_num /
   stamp_num, so if the server sends no data the whole review renders "undefined". */
const am = core.ModelManage.getInstance().getModel(AnnualReviewModel);
out = {};

out.globals = ['AnnualReviewViewControl', 'AnnualReviewView', 'AnnualReviewModel']
  .map((k) => k + '=' + typeof window[k]);

/* ask the server for the review data the way the client does */
out.loadReply = await new Promise((resolve) => {
  core.SocketManage.getInstance().send('annual_load',
    new core.Action2(function (r) { resolve(r); }), );
  setTimeout(() => resolve('<no reply within 3s>'), 3000);
});
out.cacheData = JSON.parse(JSON.stringify(am.cacheData || null));

try {
  core.PageManage.getInstance().addViewControl(AnnualReviewViewControl, core.ViewLayerType.WindowLayer);
  out.opened = true;
} catch (e) {
  out.opened = 'THREW ' + (e && e.message);
}
await new Promise((r) => setTimeout(r, 2500));

/* what the review page actually rendered */
out.viewsFound = window.__egretViews().filter((v) => /Annual/.test(v.skin));
const found = window.__egretFind(['AnnualReviewStartPageSkin', 'AnnualReviewChatPageSkin', 'AnnualReviewFinishPageSkin']);
out.pages = found.map((h) => [h.cls, h.vis, h.x, h.y]);
/* read every TextField under the review view */
const texts = [];
(function walk(n, d) {
  if (d > 12 || !n) return;
  for (const c of (n.$children || [])) {
    if (c instanceof egret.TextField && c.text) texts.push(c.text);
    walk(c, d + 1);
  }
})(egret.MainContext.instance.stage, 0);
out.texts = texts.filter((t) => t && t.length < 200).slice(0, 40);
out.undefinedCount = texts.filter((t) => /undefined/.test(t)).length;
return JSON.stringify(out, null, 1);
