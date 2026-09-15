/* handcraft_live.js -- drive the REAL 手工 window (HandCraftView) and read back
 * what each of its two pages actually renders.
 *
 * WHY: the two complaints ("祈愿物 ... 日期出错" / "印章 ... 图片空白") are about a
 * view that only exists at runtime. Reading the minified client says what the
 * renderers REQUIRE; this probe says what the engine's payload makes them SHOW.
 *
 * Legs:
 *   1. seed state.craft with one FINISHED wish + one FINISHED stamp (known
 *      make_time/time) plus one in-progress of each
 *   2. pray_load_grays -> HandCraftModel (the only feeder of this window)
 *   3. open HandCraftView, page 0 (祈愿物=PrayCraftPageSkin), then page 1 (印章)
 *   4. open the 祈愿物 detail (PrayCraftDetailRender) and read its l_date text
 *
 * IIFE expression, no trailing semicolon (cdp_drive wraps it in `return (...)`).
 */
(async () => {
  const out = {};
  const E = window.__engine;
  const WAIT = (ms) => new Promise((r) => setTimeout(r, ms));

  const walk = (fn) => {
    (function w(n, d) {
      if (!n || d > 18) return;
      try { fn(n, d); } catch (e) { }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(egret.MainContext.instance.stage, 0);
  };
  const srcText = (n) => { try { return String(n.constructor); } catch (e) { return ''; } };
  const findSkin = (key) => {
    let hit = null;
    walk((n) => { if (!hit && srcText(n).indexOf(key) >= 0) hit = n; });
    return hit;
  };
  const collect = (root) => {
    const texts = [], images = [];
    (function w(n, d) {
      if (!n || d > 18) return;
      if (n instanceof egret.TextField && n.text) texts.push(n.text);
      if (n instanceof eui.Image) {
        images.push({ src: n.source === undefined ? '<undefined>' : String(n.source),
          w: Math.round(n.width), h: Math.round(n.height) });
      }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(root, 0);
    return { texts, images };
  };

  /* ---- 1. seed: a known epoch so a wrong date source is unmistakable ---- */
  const T = 1700000000;                       // 2023-11-14 UTC
  E.state.craft = {
    wishes: [
      { id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: T, u_id: 9001 },
      { id: 2, state: 2, body: '', paper: '', content: 2, make_time: T + 90, u_id: 9002 },
    ],
    stamps: [
      { id: 1, state: 3, time: T, u_id: 9003 },
      { id: 4, state: 1, time: T + 90, u_id: 9004 },
    ],
    pending: [], seq: 9004,
  };

  /* ---- 2. feed the model through the real command ---- */
  out.engineReply = E.dispatch('pray_load_grays', {}).reply;
  out.wishRow0 = out.engineReply.wishs[0];
  out.stampRow0 = out.engineReply.stamps[0];
  /* the renderer's date field, straight from the payload: */
  out.wishRow0_has_stamp_time = Object.prototype.hasOwnProperty.call(out.wishRow0, 'stamp_time');
  out.wishRow0_stamp_time = out.wishRow0.stamp_time;

  /* what DateFormat does with that value -- the exact expression the client runs */
  try {
    out.dateFormat_of_missing = core.DateFormat.format(1e3 * out.wishRow0.stamp_time,
      core.DateFormater['YYYY.MM.DD']);
  } catch (e) { out.dateFormat_of_missing = 'THREW ' + e.message; }
  try {
    out.dateFormat_of_correct = core.DateFormat.format(1e3 * T, core.DateFormater['YYYY.MM.DD']);
  } catch (e) { out.dateFormat_of_correct = 'THREW ' + e.message; }

  /* ---- 3. the window ---- */
  let v = null;
  try {
    v = new HandCraftView();
    core.DisplayManage.getInstance().getPopupLayer().addChild(v);
    out.opened = true;
  } catch (e) { out.opened = 'THREW ' + (e && e.message); }
  await WAIT(900);

  /* the two tab buttons are pure IMAGE skins (label = "") -- do their textures exist? */
  out.tabAssets = ['craft_type1_1_png', 'craft_type1_2_png', 'craft_type2_1_png',
    'craft_type2_2_png', 'back_craft_png', 'top_craft_png'].map((n) => {
      let has = null;
      try { has = RES.hasRes(n); } catch (e) { has = 'THREW ' + e.message; }
      let texture = null;
      try { texture = String(RES.getRes(n)); } catch (e) { texture = 'THREW ' + e.message; }
      return { name: n, hasRes: has, res: texture };
    });

  /* ---- page 0: 祈愿物 ---- */
  try { v.selectPage(0); } catch (e) { out.selectPage0 = 'THREW ' + e.message; }
  await WAIT(900);
  const page0 = findSkin('HandCraft/PrayCraftPageSkin.exml');
  out.page0_skin_found = !!page0;
  out.page0 = page0 ? collect(page0) : null;
  out.page0_rows = page0 && page0.list ? (page0.list.$children || []).length : null;
  out.page0_data = page0 && page0.list
    ? (page0.list.$children || []).map((r) => r.data) : null;

  /* ---- the 祈愿物 detail: this is where the DATE label lives ---- */
  try {
    const grp = page0 && page0.list && page0.list.$children && page0.list.$children[0]
      ? page0.list.$children[0].data : null;
    out.detailGroup = grp;
    if (grp) page0.onItemTap({ item: grp });
    out.detailOpened = !!grp;
  } catch (e) { out.detailError = 'THREW ' + (e && e.message); }
  await WAIT(900);
  const detail = findSkin('HandCraft/PrayCraftDetailViewSkin.exml');
  out.detail_skin_found = !!detail;
  if (detail) {
    const c = collect(detail);
    out.detail_texts = c.texts;
    out.detail_images = c.images;
    /* the named part the renderer writes the date into */
    (function w(n, d) {
      if (!n || d > 18) return;
      if (n.l_date && n.l_date.text !== undefined) out.detail_l_date = n.l_date.text;
      if (n.i_stamp) out.detail_i_stamp_source = String(n.i_stamp.source);
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(detail, 0);
  }

  /* close the detail so the screenshot shows the page, not the popup */
  try { detail && detail.close && detail.close(); } catch (e) { }
  await WAIT(400);

  /* ---- page 1: 印章 ---- */
  try { v.selectPage(1); } catch (e) { out.selectPage1 = 'THREW ' + e.message; }
  await WAIT(900);
  const page1 = findSkin('HandCraft/StampCraftPageSkin.exml');
  out.page1_skin_found = !!page1;
  out.page1 = page1 ? collect(page1) : null;
  out.page1_rows = page1 && page1.list ? (page1.list.$children || []).length : null;
  out.page1_data = page1 && page1.list
    ? (page1.list.$children || []).map((r) => r.data) : null;
  /* the two layer images each 印章 row draws from StampCraftDB */
  out.page1_rendererSources = [];
  if (page1 && page1.list) {
    (page1.list.$children || []).forEach((r, i) => {
      out.page1_rendererSources.push({
        i: i, data: r.data,
        i_layer0: r.i_layer0 ? String(r.i_layer0.source) : '<no part>',
        i_layer1: r.i_layer1 ? String(r.i_layer1.source) : '<no part>',
      });
    });
  }

  /* ---- the tab buttons themselves ---- */
  out.tabs = [];
  if (v && v.c_typeGroup) {
    const kids = v.c_typeGroup.$children || [];
    kids.forEach((b, i) => {
      out.tabs.push({
        i: i, label: b.label, skinName: String(b.skinName),
        kids: (b.$children || []).map((x) => ({
          cls: String(x.constructor).slice(0, 40),
          src: x.source === undefined ? '<undefined>' : String(x.source),
        })),
      });
    });
  }

  return JSON.stringify(out, null, 1);
})()
