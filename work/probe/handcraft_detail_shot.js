/* handcraft_detail_shot.js -- leave the 印章 DETAIL open on a FINISHED stamp's first
 * card so a screenshot shows the blank artwork.
 *
 * The engine leaves a finished stamp at state 4 (work/run/engine/index.js:1599-1604),
 * StampCraftDB rows only declare state [1,2,3], StampCraftItemRender's
 * `n.state.indexOf(state)` is therefore -1, and StampCraftItemSkin's i_layer0/i_layer1
 * have no default source -- so that card draws the frame and nothing else.
 *
 * IIFE expression, no trailing semicolon.
 */
(async () => {
  const E = window.__engine;
  const WAIT = (ms) => new Promise((r) => setTimeout(r, ms));
  try { const n = document.getElementById('__notice'); if (n) n.style.display = 'none'; } catch (e) { }
  const walk = (fn) => {
    (function w(n, d) {
      if (!n || d > 18) return;
      try { fn(n); } catch (e) { }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(egret.MainContext.instance.stage, 0);
  };
  const findSkin = (key) => { let hit = null; walk((n) => { if (!hit && String(n.constructor).indexOf(key) >= 0) hit = n; }); return hit; };

  const now = Math.floor(Date.now() / 1000);
  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: 1700000000, u_id: 9001 },
             { id: 2, state: 1, body: '', paper: '', content: 2, make_time: now + 100000, u_id: 9002 }],
    stamps: [{ id: 109, state: 4, time: 1700000000, u_id: 9101 }],
    pending: [], seq: 9101,
  };
  await new Promise((res) => {
    let done = false;
    core.SocketManage.getInstance().send('pray_load_grays', new core.Action2(function (r) { done = true; return res(r); }));
    setTimeout(() => { if (!done) res(null); }, 3000);
  });

  const v = new HandCraftView();
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  await WAIT(1000);
  v.selectPage(1);                                  // tab 2 = 印章
  await WAIT(1200);
  const page1 = findSkin('HandCraft/StampCraftPageSkin.exml');
  const row = page1 && page1.list && page1.list.$children[0];
  page1.onItemTap({ item: row.data });              // opens StampCraftDetailView
  await WAIT(1800);

  const det = findSkin('HandCraft/StampCraftDetailViewSkin.exml');
  const cards = [];
  if (det && det.list) {
    (det.list.$children || []).forEach((c, ci) => {
      const g = c.g_stamp;
      cards.push({ card: ci, dataState: c.data && c.data.data && c.data.data.state,
        i_layer0: g ? String(g.i_layer0.source) : null,
        i_layer1: g ? String(g.i_layer1.source) : null,
        hasTexture: !!(g && g.i_layer0 && g.i_layer0.texture) });
    });
  }
  return JSON.stringify({ detOpen: !!det, cards, page1Rows: page1.list.$children.length });
})()
