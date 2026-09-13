/* Second pass for 手工拼装: page renderers (they appear a frame later) plus the
   persistence leg -- pray_compose calls save(), so the amulet must still be there
   after a real reload. */
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

const wishPages = find('PrayCraftPageView');
const stampPages = find('StampCraftPageView');
out.wishPages = wishPages.length;
out.stampPages = stampPages.length;
out.wishListRows = wishPages.map((p) => (p.list ? p.list.numChildren : null));
out.stampListRows = stampPages.map((p) => (p.list ? p.list.numChildren : null));
out.wishShelfRows = wishPages.map((p) => (p.listShelf ? p.listShelf.numChildren : null));

/* persistence: the amulet granted by pray_compose, after the reload */
const amulet = E.state.items.house.find((h) => h.item_id === 1306);
out.amuletAfterReload = amulet ? amulet.count : 0;
const pieces = [8501, 8502, 8503].map((p) => {
  const row = E.state.items.house.find((h) => h.item_id === p);
  return row ? row.count : 0;
});
out.piecesAfterReload = pieces;
out.craftRowsAfterReload = (E.state.craft && E.state.craft.wishes || []).length;
out.craftStampsAfterReload = (E.state.craft && E.state.craft.stamps || []).length;

const saved = JSON.parse(localStorage.getItem('frog.offline.save') || 'null');
out.saveAmulet = (saved && saved.items && saved.items.house || [])
  .filter((h) => h.item_id === 1306).map((h) => h.count)[0] || 0;

return JSON.stringify(out);
