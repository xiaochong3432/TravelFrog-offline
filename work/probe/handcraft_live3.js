/* handcraft_live3.js -- isolate the 印章 art bug inside the real 手工品 window.
 *
 * Reading the client says the stamp art is chosen by
 *     StampCraftItemRender.dataChanged()
 *        i        = t.state || 0
 *        n        = StampCraftDB.get(t.id)          // stampData row
 *        r        = n.state.indexOf(i)              // stampData rows carry state [1,2,3]
 *        r >= 0 && (i_layer0.source = n.stamp_pic[r], i_layer1.source = n.pattern_pic[r])
 * so a row whose `state` is NOT in [1,2,3] sets NOTHING.
 *
 * The two skins differ in what "nothing" means, which is why the bug shows up in only
 * one place:
 *   page row skin (StampCraftPageSkin$Skin253$Skin254, default.thm.js:25071/25082)
 *       -> i_layer1 default "stamp_pic1_1_png", i_layer0 default "stamp1_1_png"
 *          => NOT blank, but WRONG STAMP (always #1) whenever r < 0
 *   detail card skin (StampCraftItemSkin, default.thm.js:24856-24873)
 *       -> i_layer0 / i_layer1 have NO default source
 *          => BLANK
 *
 * And StampCraftPageView.onItemTap builds the detail's card list as
 *     for (var i = t.state; i >= 1; i--) { copy.state = i; push(copy) }
 * so a FINISHED stamp (engine leaves state = 4) puts a state-4 card FIRST.
 *
 * Legs: three stamps -- finished (#109), in-flight (#4 state 3), fresh (#207 state 1).
 *
 * IIFE expression, no trailing semicolon.
 */
(async () => {
  const out = {};
  const E = window.__engine;
  const WAIT = (ms) => new Promise((r) => setTimeout(r, ms));
  try { const n = document.getElementById('__notice'); if (n) n.style.display = 'none'; } catch (e) { }

  const walk = (fn) => {
    (function w(n, d) {
      if (!n || d > 18) return;
      try { fn(n, d); } catch (e) { }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(egret.MainContext.instance.stage, 0);
  };
  const srcText = (n) => { try { return String(n.constructor); } catch (e) { return ''; } };
  const findSkin = (key) => { let hit = null; walk((n) => { if (!hit && srcText(n).indexOf(key) >= 0) hit = n; }); return hit; };
  /* named parts + image sources under a node, tagged with the owning class */
  const partsOf = (root) => {
    const a = [];
    (function w(n, d) {
      if (!n || d > 18) return;
      if (n instanceof eui.Image) {
        a.push({ src: String(n.source), tex: n.texture ? (n.texture.textureWidth + 'x' + n.texture.textureHeight) : 'none' });
      }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(root, 0);
    return a;
  };
  const ask = (cmd) => new Promise((res) => {
    let done = false;
    core.SocketManage.getInstance().send(cmd, new core.Action2(function (r) { done = true; return res(r); }));
    setTimeout(() => { if (!done) res('<no reply in 3s>'); }, 3000);
  });
  const DM = Tabikaeru.DataManager.instance();

  const T = 1700000000;
  const now = Math.floor(Date.now() / 1000);
  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: T, u_id: 9001 },
             { id: 2, state: 1, body: '', paper: '', content: 2, make_time: now + 100000, u_id: 9002 }],
    stamps: [
      { id: 109, state: 4, time: T, u_id: 9101 },               // engine's FINISHED shape
      { id: 4, state: 3, time: now + 100000, u_id: 9102 },      // a legal state
      { id: 207, state: 1, time: now + 100000, u_id: 9103 },    // a legal state
    ],
    pending: [], seq: 9103,
  };
  await ask('pray_load_grays');

  /* what stampData actually declares, straight from the CLIENT's own DB */
  out.tableShape = [109, 4, 207].map((id) => {
    const n = DM.StampCraftDB.get(id);
    return { id, state: n && n.state, nStates: n && n.state.length,
      stamp_pic: n && n.stamp_pic.map((x) => x.index),
      pattern_pic: n && n.pattern_pic.map((x) => x.index) };
  });

  let v = null;
  try { v = new HandCraftView(); core.DisplayManage.getInstance().getPopupLayer().addChild(v); } catch (e) { out.openErr = String(e); }
  await WAIT(1000);
  v.selectPage(1);                       // tab 2 = 印章
  await WAIT(1200);

  const page1 = findSkin('HandCraft/StampCraftPageSkin.exml');
  out.page1_rows = page1 && page1.list ? (page1.list.$children || []).length : null;
  out.page1_rows_detail = [];
  (page1 && page1.list ? page1.list.$children : []).forEach((r, i) => {
    const n = DM.StampCraftDB.get(r.data.id);
    const idx = n ? n.state.indexOf(r.data.state) : null;
    out.page1_rows_detail.push({
      i: i, id: r.data.id, state: r.data.state,
      expectedIndex: idx,
      expected_stamp_pic: n && idx >= 0 ? n.stamp_pic[idx].index : '<indexOf = -1 -> client sets nothing>',
      expected_pattern_pic: n && idx >= 0 ? n.pattern_pic[idx].index : '<indexOf = -1 -> client sets nothing>',
      rendered_stamp_art: partsOf(r).map((x) => x.src).filter((s) => /^stamp/i.test(s)),
    });
  });

  /* ---- open the DETAIL for the finished stamp (#109) and for #4 as control ---- */
  out.details = [];
  for (const wantId of [109, 4]) {
    const row = (page1 && page1.list ? page1.list.$children : []).find((r) => r.data.id === wantId);
    if (!row) { out.details.push({ id: wantId, err: 'row not found' }); continue; }
    try { page1.onItemTap({ item: row.data }); } catch (e) { out.details.push({ id: wantId, err: String(e) }); continue; }
    await WAIT(1300);
    const det = findSkin('HandCraft/StampCraftDetailViewSkin.exml');
    const cards = [];
    if (det && det.list) {
      (det.list.$children || []).forEach((c, ci) => {
        const g = c.g_stamp;
        cards.push({
          card: ci, cardState: c.currentState, dataState: c.data && c.data.data && c.data.data.state,
          i_layer0: g ? String(g.i_layer0.source) : '<no part>',
          i_layer1: g ? String(g.i_layer1.source) : '<no part>',
          i_layer0_hasTexture: !!(g && g.i_layer0 && g.i_layer0.texture),
          allImages: partsOf(c).map((x) => x.src),
        });
      });
    }
    out.details.push({ id: wantId, found: !!det, nCards: cards.length, cards });
    try { det && det.close && det.close(); } catch (e) { }
    await WAIT(600);
  }

  return JSON.stringify(out, null, 1);
})()
