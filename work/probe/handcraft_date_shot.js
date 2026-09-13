/* handcraft_date_shot.js -- leave the FINISHED 祈愿物 detail card open so a screenshot
 * shows the date slot, which reads `stamp_time` (main.min.js.clean @741450) while the
 * engine's wish rows only carry `make_time` -> the label renders "NaN.NaN.NaN".
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

  const T = 1700000000;                       // would format to 2023.11.15
  const now = Math.floor(Date.now() / 1000);
  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: T, u_id: 9001 },
             { id: 2, state: 1, body: '', paper: '', content: 2, make_time: now + 100000, u_id: 9002 }],
    stamps: [],
    pending: [], seq: 9002,
  };
  await new Promise((res) => {
    let done = false;
    core.SocketManage.getInstance().send('pray_load_grays', new core.Action2(function (r) { done = true; return res(r); }));
    setTimeout(() => { if (!done) res(null); }, 3000);
  });

  const v = new HandCraftView();
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  await WAIT(1000);
  v.selectPage(0);                                  // tab 1 = 祈愿物
  await WAIT(1300);
  const p0 = findSkin('HandCraft/PrayCraftPageSkin.exml');
  let grp = null;
  (p0.list.$children || []).forEach((r) => { if (!grp && (r.data || []).some((x) => x.state > 3)) grp = r.data; });
  if (grp) p0.onItemTap({ item: grp });
  await WAIT(1800);

  const det = findSkin('HandCraft/PrayCraftDetailViewSkin.exml');
  const out = { detOpen: !!det, group: grp };
  if (det) walk((n) => { if (n.l_date && n.l_date.text !== undefined) out.l_date = n.l_date.text; });
  out.expectedIfReadMakeTime = '2023.11.15';
  return JSON.stringify(out);
})()
