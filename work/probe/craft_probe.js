/* 手工拼装: does the window actually have content, and does the 三拼 produce an amulet?

Legs:
  rendering  - HandCraftView's two pages (祈愿木牌 / 印章) must render rows
  state      - pray_compose consumes one of each 木片 and grants the amulet
  (persistence is covered by probe/craft_probe2.js after a real reload) */
const out = {};
const E = window.__engine;
const find = (cls) => {
  const acc = [];
  (function w(n, d) {
    if (!n || d > 14) return;
    if (String(n.__class__ || '') === cls ||
        String((n.constructor && n.constructor.name) || '') === cls) acc.push(n);
    const k = n.$children || [];
    for (let i = 0; i < k.length; i++) w(k[i], d + 1);
  })(egret.MainContext.instance.stage, 0);
  return acc;
};

/* ---- 1. the engine's payload ---- */
const grays = E.dispatch('pray_load_grays', {}).reply;
out.wishRows = grays.wishs.length;
out.stampRows = grays.stamps.length;
out.boxes = grays.boxes.length;
out.sampleWish = grays.wishs[0];
out.sampleStamp = grays.stamps[0];
/* make one piece finish, so wish_new can be checked too */
E.state.craft.wishes[0].state = 3;
E.state.craft.wishes[0].make_time = 1;
const grays2 = E.dispatch('pray_load_grays', {}).reply;
out.finishedWish = grays2.wishs.find((w) => w.state > 3) || null;
out.wishNew = grays2.wish_new;

/* ---- 2. the window itself ---- */
try {
  const v = new HandCraftView();
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  out.viewOpened = true;
  out.pages = v.pageContainer ? v.pageContainer.getNumPages() : null;
  core.PageManage.getInstance().addViewControl(HandCraftViewController,
    core.ViewLayerType.WindowLayer);
} catch (e) {
  out.viewError = String(e && e.stack || e);
}

/* ---- 3. give the player the three 木片 and drive the model's own compose call ---- */
const PIECES = [8501, 8502, 8503];
for (const p of PIECES) {
  const cur = E.state.items.house.find((h) => h.item_id === p);
  if (cur) cur.count += 1; else E.state.items.house.push({ item_id: p, count: 1 });
}
out.beforeAmulet = 0;
const before = E.dispatch('item_load_items', {}).reply;
out.houseHasPiecesBefore = PIECES.map((p) => {
  const row = E.state.items.house.find((h) => h.item_id === p);
  return row ? row.count : 0;
});

let reply = null;
core.ModelManage.getInstance().getModel(HandCraftModel)
  .req_compose(5502, new core.Action2(function (r) { reply = r; }));
out.reply = reply;
out.houseHasPiecesAfter = PIECES.map((p) => {
  const row = E.state.items.house.find((h) => h.item_id === p);
  return row ? row.count : 0;
});
const amulet = E.state.items.house.find((h) => h.item_id === 1306);
out.amuletCount = amulet ? amulet.count : 0;

return JSON.stringify(out);
