/* Museum 图鉴: does the detail page stop showing grey slots?

Before: `museum_load` answered `{museum_list: []}`, so every postcard slot stayed
hidden and every collectible showed the client's own "question_png" placeholder.
Now the engine reports, per museum, which of that museum's postcards and
collectibles the player owns -- and the LIST page is rendered from the client's own
table, so the check is: the list populates, and after granting one postcard and one
collectible the detail page's slots light up.

Legs: rendering (view + slots) / state (engine + model) / persistence (localStorage
after a real reload, checked by the second probe). */
const out = {};
const E = window.__engine;

/* 1. the engine's answer for this save */
const raw = E.dispatch('museum_load', {}).reply;
out.engineMuseums = raw.museum_list.map((m) => ({ id: m.id, pics: m.pic_list.length, cols: m.collections.length }));

/* 2. grant one postcard + one collectible of the first OPEN museum, then re-ask */
const T = E.gamedata ? null : null;
const table = (window.FrogEngine && window.FrogEngine.gamedata) || null;
const museumTable = (E.state && null) || null;
out.note = 'rows below come from the local table via the client';

/* museum 1 (江西省博物馆): pic ids 2109/2110/3063, collections 34..37 */
E.state.pictures.push({ id: 90001, pic_id: 2109, read: 0, new: 1 });
E.state.handbook.collections.push(34);
const raw2 = E.dispatch('museum_load', {}).reply;
const m1 = raw2.museum_list.find((m) => m.id === 1);
out.afterGrant = { pic_list: m1.pic_list, collections: m1.collections };
out.otherMuseumsStillEmpty = raw2.museum_list.filter((m) => m.id !== 1)
  .every((m) => m.pic_list.length === 0 && m.collections.length === 0);

/* 3. open the real list view and count what it renders */
try {
  core.PageManage.getInstance().addViewControl(MuseumListViewControl,
    core.ViewLayerType.WindowLayer, core.RemoveViewType.HideBefore);
  const find = (cls) => {
    const acc = [];
    (function w(n, d) {
      if (!n || d > 12) return;
      acc.push(n);
      const k = n.$children || [];
      for (let i = 0; i < k.length; i++) w(k[i], d + 1);
    })(egret.MainContext.instance.stage, 0);
    return acc.filter((n) => String(n.__class__ || '') === cls ||
      String(n.constructor && n.constructor.name || '') === cls);
  };
  const lists = find('MuseumListView');
  out.listViewPresent = lists.length > 0;
  if (lists.length) {
    const lv = lists[0];
    out.listRows = lv.listMuseum ? lv.listMuseum.numChildren : null;
    out.listMuseumData = (lv.listMuseumData || []).map((d) => ({
      id: d.id, pics: (d.pic_list || []).length, cols: (d.collections || []).length,
    }));
    out.pageLabel = lv.currentPage ? lv.currentPage.text : null;
    out.maxPage = lv.maxPage ? lv.maxPage.text : null;
    /* open the detail page for museum 1 the way a tap does */
    try {
      core.PageManage.getInstance().addViewControl(MuseumViewControl,
        core.ViewLayerType.WindowLayer, null,
        { list: lv.listMuseumData, selectedIndex: 0 });
      out.detailOpened = true;
    } catch (e) {
      out.detailError = String(e);
    }
  }
} catch (e) {
  out.viewError = String(e && e.stack || e);
}

/* 4. how many MuseumPage renderers exist and how many picture boxes are visible */
try {
  const acc = [];
  (function w(n, d) {
    if (!n || d > 14) return;
    if (String(n.__class__ || '') === 'MuseumPage') acc.push(n);
    const k = n.$children || [];
    for (let i = 0; i < k.length; i++) w(k[i], d + 1);
  })(egret.MainContext.instance.stage, 0);
  out.detailPages = acc.length;
  out.detailSlots = acc.map((p) => ({
    picturesVisible: (p.pictures || []).map((x) => !!x.visible),
    collectStates: (p.collects || []).map((x) => x.currentState),
  }));
} catch (e) {
  out.detailCountError = String(e);
}

return JSON.stringify(out);
