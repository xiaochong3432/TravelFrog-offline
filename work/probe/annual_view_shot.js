/* annual_view_shot.js -- open the REAL 年度总结 (annual review), advance to the page that
 * carries the 「…一共雕刻了{0}个印章，完成了{0}个祈愿物。」 line, and report every image
 * reference + every text on every page.
 *
 * WHY: the report "「手工品」栏的「祈愿物」/「印章」" could in principle be this view
 * (that is where the words 印章 / 祈愿物 appear as strings at all). This probe settles it:
 * if the review renders NO image bound to a stamp/pray resource and NO per-handicraft date,
 * then the player cannot have been looking at it.
 *
 * IIFE expression, no trailing semicolon.
 */
(async () => {
  const out = {};
  try { const n = document.getElementById('__notice'); if (n) n.style.display = 'none'; } catch (e) { }
  const WAIT = (ms) => new Promise((r) => setTimeout(r, ms));

  const walk = (fn) => {
    (function w(n, d) {
      if (!n || d > 18) return;
      try { fn(n); } catch (e) { }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(egret.MainContext.instance.stage, 0);
  };
  const findSkin = (key) => { let hit = null; walk((n) => { if (!hit && String(n.constructor).indexOf(key) >= 0) hit = n; }); return hit; };
  const scan = () => {
    const texts = [], images = [];
    walk((n) => {
      if (n instanceof egret.TextField && n.text) texts.push(n.text);
      if (n instanceof eui.Image) images.push(String(n.source));
    });
    return { texts: [...new Set(texts)], images: [...new Set(images)] };
  };

  /* ask for the payload the way the client does, then open the review */
  try {
    await new Promise((res) => {
      let done = false;
      core.SocketManage.getInstance().send('annual_load', new core.Action2(function (r) { done = true; return res(r); }));
      setTimeout(() => { if (!done) res(null); }, 3000);
    });
    out.payload = core.ModelManage.getInstance().getModel(AnnualReviewModel).cacheData;
  } catch (e) { out.payloadErr = String(e); }

  try {
    core.PageManage.getInstance().addViewControl(AnnualReviewViewControl, core.ViewLayerType.WindowLayer);
    out.opened = true;
  } catch (e) { out.opened = 'THREW ' + (e && e.message); }
  await WAIT(3000);

  const found = findSkin('AnnualReview');
  out.review_found = !!found;
  out.pages = [];
  /* walk the review's own pages and record what each one shows */
  for (let page = 0; page < 4; page++) {
    const s = scan();
    out.pages.push({
      page,
      nTexts: s.texts.length,
      /* text that mentions the two features at all */
      mentionStampWish: s.texts.filter((t) => /印章|祈愿物/.test(t)),
      /* any image whose source names a stamp / pray / wood / paper asset? */
      craftArt: s.images.filter((x) => /stamp|pray|wood|paper|craft/i.test(x)),
      allImages: s.images,
    });
    /* the review advances through its own pages with next() */
    let next = null;
    walk((n) => { if (!next && typeof n.next === 'function' && String(n.constructor).indexOf('AnnualReview') >= 0) next = n; });
    if (!next) break;
    try { next.next(true); } catch (e) { out.nextErr = String(e && e.message); break; }
    await WAIT(2200);
  }
  /* the page carrying the 印章/祈愿物 line, for the screenshot */
  const hit = out.pages.findIndex((p) => p.mentionStampWish.length > 0);
  out.pageWithStampWishText = hit;
  return JSON.stringify(out, null, 1);
})()
