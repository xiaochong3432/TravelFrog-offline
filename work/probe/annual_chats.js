/* annual_chats.js -- read the 年度总结's own generated copy (the `chats` array) so the
 * "印章 / 祈愿物" sentence can be compared with the 手工品 window's tabs.
 *
 * Point: in the review, 印章/祈愿物 are WORDS inside one chat line. There is no tab,
 * no per-item row, no icon and no date for either of them. This probe prints exactly
 * what the review says, and what node class says it.
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

  /* make the sentence non-trivial: give the save some finished 手工品 first */
  const E = window.__engine;
  const now = Math.floor(Date.now() / 1000);
  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: 1700000000, u_id: 1 },
             { id: 2, state: 4, body: 102, paper: 1002, content: 2, make_time: 1700000100, u_id: 2 }],
    stamps: [{ id: 109, state: 4, time: 1700000000, u_id: 3 },
             { id: 207, state: 4, time: 1700000100, u_id: 4 }],
    pending: [], seq: 4,
  };

  await new Promise((res) => {
    let done = false;
    core.SocketManage.getInstance().send('annual_load', new core.Action2(function (r) { done = true; return res(r); }));
    setTimeout(() => { if (!done) res(null); }, 3000);
  });
  out.payload = core.ModelManage.getInstance().getModel(AnnualReviewModel).cacheData;

  core.PageManage.getInstance().addViewControl(AnnualReviewViewControl, core.ViewLayerType.WindowLayer);
  await WAIT(3000);

  /* every node that carries a `chats` array -- those ARE the review's lines */
  out.chatPages = [];
  walk((n) => {
    if (Array.isArray(n.chats) && n.chats.length) {
      let cls = '';
      try { cls = String(n.constructor).slice(0, 60); } catch (e) { }
      out.chatPages.push({ cls, chats: n.chats.map((c) => ({ text: c.text, algin: c.algin })) });
    }
  });

  /* and every class the review put on screen, so "is there any per-item row / date
     label / tab bar in this view" can be answered from the node list itself */
  const classes = new Set();
  walk((n) => {
    let s = '';
    try { s = String(n.constructor); } catch (e) { return; }
    if (/AnnualReview/.test(s)) classes.add(s.slice(0, 80));
  });
  out.reviewClasses = [...classes];

  /* does the review contain any List/ItemRenderer (a per-item row) or TabBar? */
  let lists = 0, tabbars = 0, dateLabels = 0;
  walk((n) => {
    if (n instanceof eui.List) lists++;
    if (n instanceof eui.TabBar || n instanceof eui.ToggleButton) tabbars++;
    if (n instanceof egret.TextField && /yyyy|NaN|\.\d\d/.test(String(n.text))) dateLabels++;
  });
  out.euiListCount = lists;
  out.tabBarOrToggleCount = tabbars;
  out.dateLikeLabels = dateLabels;
  return JSON.stringify(out, null, 1);
})()
