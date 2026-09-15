/* annual_request_probe.js -- drive the review through the CLIENT'S OWN path
 * (`AnnualReviewModel.request()`, main.min.js.clean @byte 83536) instead of a bare
 * SocketManage.send, which bypasses the model's callback and leaves cacheData stale.
 *
 * Answers, end to end:
 *   1. with finished 手工品 in the save, what do stamp_num / wish_num become?
 *   2. what does the review actually SAY about 印章 / 祈愿物 (the player-visible line)?
 *   3. does the review contain ANY image bound to a stamp/pray/wood/paper craft asset,
 *      any per-item row (eui.List), any tab bar, or any per-handicraft date?
 *
 * IIFE expression, no trailing semicolon.
 */
(async () => {
  const out = {};
  const E = window.__engine;
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
  const AM = core.ModelManage.getInstance().getModel(AnnualReviewModel);

  /* --- seed finished 手工品: 2 印章 + 2 祈愿物 --- */
  const now = Math.floor(Date.now() / 1000);
  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: 1700000000, u_id: 1 },
             { id: 2, state: 4, body: 102, paper: 1002, content: 2, make_time: 1700000100, u_id: 2 }],
    stamps: [{ id: 109, state: 4, time: 1700000000, u_id: 3 },
             { id: 207, state: 4, time: 1700000100, u_id: 4 }],
    pending: [], seq: 4,
  };

  /* --- 1. the client's own request, so cacheData is really refreshed --- */
  out.cacheBefore = JSON.parse(JSON.stringify(AM.cacheData));
  try { AM.request(); } catch (e) { out.requestErr = String(e); }
  await WAIT(2500);
  out.cacheAfter = JSON.parse(JSON.stringify(AM.cacheData));

  /* --- 2. open the review and read every string it renders, page by page --- */
  try { core.PageManage.getInstance().addViewControl(AnnualReviewViewControl, core.ViewLayerType.WindowLayer); }
  catch (e) { out.openErr = String(e); }
  await WAIT(3000);

  const textsOf = () => {
    const t = [];
    walk((n) => {
      try {
        if (n instanceof egret.TextField && n.text) t.push(String(n.text));
        /* the review's chat items may be custom labels */
        if (!(n instanceof egret.TextField) && typeof n.text === 'string' && n.text) t.push(String(n.text));
      } catch (e) { }
    });
    return [...new Set(t)];
  };
  const imagesOf = () => {
    const a = [];
    walk((n) => { if (n instanceof eui.Image) a.push(String(n.source)); });
    return [...new Set(a)];
  };
  const chatsOf = () => {
    const c = [];
    walk((n) => { if (Array.isArray(n.chats) && n.chats.length) (n.chats || []).forEach((x) => c.push(x)); });
    return c;
  };

  out.pages = [];
  for (let page = 0; page < 4; page++) {
    const texts = textsOf(), imgs = imagesOf(), chats = chatsOf();
    out.pages.push({
      page,
      texts,
      chatLines: chats.map((c) => c.text),
      /* art bound to a craft asset? (exclude the generic *_paper_* frame names) */
      craftArt: imgs.filter((x) => /stamp|pray|wood[0-9]|paper[0-9]|craft_pic/i.test(x)),
      nImages: imgs.length,
    });
    let next = null;
    walk((n) => { if (!next && typeof n.next === 'function') next = n; });
    if (!next) break;
    try { next.next(true); } catch (e) { out.nextErr = String(e && e.message); break; }
    await WAIT(2200);
  }
  /* leave the page that mentions the crafts on screen for the screenshot */
  out.pageWithCraftText = out.pages.findIndex((p) =>
    p.chatLines.concat(p.texts).some((s) => /印章|祈愿物/.test(String(s))));

  /* --- 3. structural check: rows / tabs / dates anywhere in the review --- */
  let listRows = 0, toggles = 0, dateLike = [], annualNodes = 0;
  walk((n) => {
    try {
      if (n instanceof eui.List) listRows += (n.$children || []).length;
      if (n instanceof eui.ToggleButton) toggles++;
      if (typeof String(n.constructor) === 'string' && /AnnualReview/.test(String(n.constructor))) annualNodes++;
      if (n instanceof egret.TextField && /\d{4}[-./]\d{1,2}/.test(String(n.text))) dateLike.push(String(n.text));
    } catch (e) { }
  });
  out.reviewListRows = listRows;
  out.reviewToggleButtons = toggles;
  out.reviewDateLikeTexts = dateLike;
  out.reviewNodes = annualNodes;
  return JSON.stringify(out, null, 1);
})()
