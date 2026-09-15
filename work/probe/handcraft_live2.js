/* handcraft_live2.js -- reproduce the two player reports inside the REAL 手工品 window.
 *
 * window   = HandCraftView   (title art top_craft.png = "手工品")
 * tab 1    = PrayCraftPageView  (craft_type1_*.png = "祈愿物")
 * tab 2    = StampCraftPageView (craft_type2_*.png = "印章")
 *
 * CRITICAL DIFFERENCE from handcraft_live.js: the data is pushed through the
 * CLIENT'S OWN socket path (core.SocketManage.send), not __engine.dispatch. Only
 * the socket path reaches HandCraftModel, and the pages render from the model --
 * so v1 was reading boot-time rows, not the seeded ones.
 *
 * Legs:
 *   A. 祈愿物 detail date : seed a FINISHED wish, open its detail, read l_date
 *   B. 印章 row art        : seed a FINISHED stamp -- what does its row draw?
 *      control            : seed one in-progress stamp -- same code path, state 1
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
  /* every eui.Image below `root`, in traversal order */
  const imagesOf = (root) => {
    const a = [];
    (function w(n, d) {
      if (!n || d > 18) return;
      if (n instanceof eui.Image) a.push(String(n.source));
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(root, 0);
    return a;
  };
  const textsOf = (root) => {
    const a = [];
    (function w(n, d) {
      if (!n || d > 18) return;
      if (n instanceof egret.TextField && n.text) a.push(n.text);
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(root, 0);
    return a;
  };

  /* the client's own request path -- the ONLY one that feeds HandCraftModel */
  const ask = (cmd) => new Promise((res) => {
    let done = false;
    core.SocketManage.getInstance().send(cmd, new core.Action2(function (r) { done = true; return res(r); }));
    setTimeout(() => { if (!done) res('<no reply in 3s>'); }, 3000);
  });

  /* ---- seed: one FINISHED + one in-progress of each kind ---- */
  const T = 1700000000;                       // 2023-11-15 (+08:00) -- an unmistakable epoch
  let now = Math.floor(Date.now() / 1000);
  /* the engine picks its own stamps ids out of the table; reuse a finished row's id so we
     know exactly which stampData row the UI is asked to draw */
  E.state.craft = {
    wishes: [
      { id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: T, u_id: 9001 },
      { id: 2, state: 1, body: '', paper: '', content: 2, make_time: now + 100000, u_id: 9002 },
    ],
    stamps: [
      { id: 1, state: 3, time: T, u_id: 9003 },            // will advance to state 4
      { id: 4, state: 1, time: now + 100000, u_id: 9004 }, // stays state 1 forever
    ],
    pending: [], seq: 9004,
  };

  out.reply = await ask('pray_load_grays');
  out.modelWishes = JSON.parse(JSON.stringify(
    core.ModelManage.getInstance().getModel(HandCraftModel).getPrayCraftList()));
  out.modelStamps = JSON.parse(JSON.stringify(
    core.ModelManage.getInstance().getModel(HandCraftModel).getStampCraftList()));

  /* the date the client WOULD show if the field existed, for contrast */
  try {
    out.dateIf_make_time = core.DateFormat.format(1e3 * T, core.DateFormater['YYYY.MM.DD']);
  } catch (e) { out.dateIf_make_time = 'THREW ' + e.message; }
  out.wish0_fields = Object.keys(out.modelWishes[0] || {});

  /* ---- open the window ---- */
  let v = null;
  try { v = new HandCraftView(); core.DisplayManage.getInstance().getPopupLayer().addChild(v); out.opened = true; }
  catch (e) { out.opened = 'THREW ' + (e && e.message); }
  await WAIT(1200);

  /* ================= tab 1: 祈愿物 -- the DATE ================= */
  try { v.selectPage(0); } catch (e) { out.selectPage0 = 'THREW ' + e.message; }
  await WAIT(1200);
  const page0 = findSkin('HandCraft/PrayCraftPageSkin.exml');
  out.page0_rows = page0 && page0.list ? (page0.list.$children || []).length : null;
  out.page0_groups = page0 && page0.list
    ? (page0.list.$children || []).map((r) => JSON.stringify(r.data)) : null;

  /* open the DETAIL of the FINISHED wish -- that is the card carrying l_date */
  let finishedGroup = null;
  if (page0 && page0.list) {
    (page0.list.$children || []).forEach((r) => {
      const g = r.data || [];
      if (!finishedGroup && g.some((x) => x.state > 3)) finishedGroup = g;
    });
  }
  out.finishedGroup = finishedGroup ? JSON.stringify(finishedGroup) : null;
  try { if (finishedGroup) page0.onItemTap({ item: finishedGroup }); } catch (e) { out.detailThrew = String(e); }
  await WAIT(1200);
  const det = findSkin('HandCraft/PrayCraftDetailViewSkin.exml');
  out.detail_found = !!det;
  if (det) {
    out.detail_texts = textsOf(det);
    out.detail_images = imagesOf(det);
    (function w(n, d) {
      if (!n || d > 18) return;
      if (n.l_date && n.l_date.text !== undefined) { out.detail_l_date = n.l_date.text; out.detail_l_date_found = true; }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(det, 0);
  }
  try { det && det.close && det.close(); } catch (e) { }
  await WAIT(500);

  /* ================= tab 2: 印章 -- the ART ================= */
  try { v.selectPage(1); } catch (e) { out.selectPage1 = 'THREW ' + e.message; }
  await WAIT(1200);
  const page1 = findSkin('HandCraft/StampCraftPageSkin.exml');
  out.page1_found = !!page1;
  out.page1_rows = page1 && page1.list ? (page1.list.$children || []).length : null;
  out.page1_rowArt = [];
  if (page1 && page1.list) {
    (page1.list.$children || []).forEach((r, i) => {
      out.page1_rowArt.push({
        i: i, data: r.data,
        dbRowState: (function () {
          try {
            const n = Tabikaeru.DataManager.instance().StampCraftDB.get(r.data.id);
            return n ? JSON.stringify(n.state) : '<no StampCraftDB row>';
          } catch (e) { return 'THREW'; }
        })(),
        /* the two layers StampCraftItemRender writes: stamp_pic[r] and pattern_pic[r] */
        images: imagesOf(r).filter((s) => /^stamp/i.test(s)),
      });
    });
  }
  /* the same index arithmetic the client does, computed here for the report */
  out.page1_indexArithmetic = (page1 && page1.list ? (page1.list.$children || []) : []).map((r) => {
    const n = Tabikaeru.DataManager.instance().StampCraftDB.get(r.data.id);
    const idx = n ? n.state.indexOf(r.data.state) : null;
    return { id: r.data.id, state: r.data.state, stateIndexOf: idx,
      stamp_pic: n && idx >= 0 ? n.stamp_pic[idx].index : null,
      pattern_pic: n && idx >= 0 ? n.pattern_pic[idx].index : null };
  });

  /* tab art sanity: the two buttons must have real textures */
  out.tabs = [];
  if (v && v.c_typeGroup) {
    (v.c_typeGroup.$children || []).forEach((b, i) => {
      const img = (b.$children || [])[0];
      out.tabs.push({
        i: i, label: b.label,
        src: img ? String(img.source) : null,
        texW: img && img.texture ? img.texture.textureWidth : null,
        texH: img && img.texture ? img.texture.textureHeight : null,
      });
    });
  }

  /* leave the 印章 page on screen for the screenshot */
  return JSON.stringify(out, null, 1);
})()
