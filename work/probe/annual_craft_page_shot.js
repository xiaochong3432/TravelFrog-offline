/* annual_craft_page_shot.js -- leave the 年度总结 ON the page that carries the
 * 「…一共雕刻了N个印章，完成了N个祈愿物。」 sentence, so the screenshot shows how that
 * view presents 印章/祈愿物: one prose line, no icon, no row, no tab, no date.
 *
 * Uses AnnualReviewModel.request() (the client's own path) so cacheData is refreshed.
 *
 * IIFE expression, no trailing semicolon.
 */
(async () => {
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
  const chats = () => {
    let c = [];
    walk((n) => { if (Array.isArray(n.chats) && n.chats.length) c = n.chats; });
    return c;
  };

  const AM = core.ModelManage.getInstance().getModel(AnnualReviewModel);
  const now = Math.floor(Date.now() / 1000);
  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: 1700000000, u_id: 1 },
             { id: 2, state: 4, body: 102, paper: 1002, content: 2, make_time: 1700000100, u_id: 2 }],
    stamps: [{ id: 109, state: 4, time: 1700000000, u_id: 3 },
             { id: 207, state: 4, time: 1700000100, u_id: 4 }],
    pending: [], seq: 4,
  };
  AM.request();
  await WAIT(2500);

  core.PageManage.getInstance().addViewControl(AnnualReviewViewControl, core.ViewLayerType.WindowLayer);
  await WAIT(3000);

  /* page 0 = 开始页, page 1 = the chat page. Advance once and stop there. */
  const out = { stamp_num: AM.cacheData.stamp_num, wish_num: AM.cacheData.wish_num };
  let next = null;
  walk((n) => { if (!next && typeof n.next === 'function') next = n; });
  if (next) { try { next.next(true); } catch (e) { out.nextErr = String(e && e.message); } }
  await WAIT(2600);

  out.chatLines = chats().map((c) => c.text);
  out.craftLine = out.chatLines.find((t) => /印章|祈愿物/.test(String(t))) || null;
  const imgs = [];
  walk((n) => { if (n instanceof eui.Image) imgs.push(String(n.source)); });
  out.craftArtInView = [...new Set(imgs)].filter((x) => /stamp|pray|wood[0-9]|paper[0-9]/i.test(x));
  out.toggleButtons = 0;
  walk((n) => { if (n instanceof eui.ToggleButton) out.toggleButtons++; });
  return JSON.stringify(out, null, 1);
})()
