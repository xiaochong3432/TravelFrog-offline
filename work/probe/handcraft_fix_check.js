/* handcraft_fix_check.js -- verify the two proposed fixes WITHOUT editing any file.
 *
 * The client's contract, read off main.min.js.clean:
 *   祈愿物 detail date  : l_date = DateFormat(1e3 * row.stamp_time, "YYYY.MM.DD")
 *                         (@byte 741450)  -- the engine sends `make_time` only
 *   印章 art            : r = stampData[ row.id ].state.indexOf(row.state);
 *                         r >= 0 && set layers   (@byte 748739)
 *                         stampData rows declare state [1,2,3], but the engine leaves a
 *                         finished stamp at 4  (work/run/engine/index.js:1599-1604)
 *
 * This probe wraps HandCraftModel.pray_load_grays and applies exactly those two
 * payload corrections, then reads the rendered result. The wrap lives in the page
 * only; nothing on disk is touched.
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
      try { fn(n); } catch (e) { }
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(egret.MainContext.instance.stage, 0);
  };
  const findSkin = (key) => { let hit = null; walk((n) => { if (!hit && String(n.constructor).indexOf(key) >= 0) hit = n; }); return hit; };
  const send = (cmd) => new Promise((res) => {
    let done = false;
    core.SocketManage.getInstance().send(cmd, new core.Action2(function (r) { done = true; return res(r); }));
    setTimeout(() => { if (!done) res(null); }, 3000);
  });

  const T = 1700000000;
  const now = Math.floor(Date.now() / 1000);
  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: T, u_id: 9001 },
             { id: 2, state: 1, body: '', paper: '', content: 2, make_time: now + 100000, u_id: 9002 }],
    stamps: [{ id: 109, state: 4, time: T, u_id: 9101 }],
    pending: [], seq: 9101,
  };

  /* ---------- the two candidate payload fixes ---------- */
  const M = core.ModelManage.getInstance().getModel(HandCraftModel);
  const proto = Object.getPrototypeOf(M);
  const orig = proto.pray_load_grays;
  out.patched = false;
  proto.pray_load_grays = function (e, t) {
    if (e) {
      /* FIX 1: give every wish row the field the detail card actually reads */
      (e.wishs || []).forEach((r) => { if (r.stamp_time == null) r.stamp_time = r.make_time; });
      /* FIX 2: keep a stamp's state inside the set stampData declares ([1,2,3]) */
      (e.stamps || []).forEach((r) => { r.stateRaw = r.state; r.state = Math.min(3, r.state | 0); });
    }
    out.patched = true;
    return orig.call(this, e, t);
  };

  await send('pray_load_grays');
  out.modelStamps = JSON.parse(JSON.stringify(M.getStampCraftList()));
  out.modelWishes = JSON.parse(JSON.stringify(M.getPrayCraftList()));

  const v = new HandCraftView();
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  await WAIT(1000);

  /* ---- 祈愿物: is the DATE right now? ---- */
  v.selectPage(0);
  await WAIT(1200);
  const p0 = findSkin('HandCraft/PrayCraftPageSkin.exml');
  let grp = null;
  (p0.list.$children || []).forEach((r) => { if (!grp && (r.data || []).some((x) => x.state > 3)) grp = r.data; });
  if (grp) p0.onItemTap({ item: grp });
  await WAIT(1300);
  const det = findSkin('HandCraft/PrayCraftDetailViewSkin.exml');
  if (det) {
    walk((n) => { if (n.l_date && n.l_date.text !== undefined) out.l_date_after_fix = n.l_date.text; });
    try { det.close(); } catch (e) { }
  }
  await WAIT(600);

  /* ---- 印章: is the CARD art back? ---- */
  v.selectPage(1);
  await WAIT(1200);
  const p1 = findSkin('HandCraft/StampCraftPageSkin.exml');
  const row = (p1.list.$children || [])[0];
  p1.onItemTap({ item: row.data });
  await WAIT(1600);
  const d2 = findSkin('HandCraft/StampCraftDetailViewSkin.exml');
  out.detailCards = [];
  if (d2 && d2.list) {
    (d2.list.$children || []).forEach((c, ci) => {
      out.detailCards.push({ card: ci, dataState: c.data && c.data.data && c.data.data.state,
        i_layer0: String(c.g_stamp.i_layer0.source), i_layer1: String(c.g_stamp.i_layer1.source),
        hasTexture: !!c.g_stamp.i_layer0.texture });
    });
  }
  out.rowArt = (p1.list.$children || []).map((r) => ({
    id: r.data.id, state: r.data.state,
    art: (function () { const a = []; (function w(n, d) { if (!n || d > 12) return; if (n instanceof eui.Image && /^stamp/i.test(String(n.source))) a.push(String(n.source)); const k = n.$children || []; for (let i = 0; i < k.length; i++) w(k[i], d + 1); })(r, 0); return a; })(),
  }));
  return JSON.stringify(out, null, 1);
})()
