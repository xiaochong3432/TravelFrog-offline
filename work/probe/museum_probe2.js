/* Second pass: renderers are created on the frame AFTER the collection is set, so
   count them here (the notice page has been dismissed by the driver by now). */
const out = {};
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

const lists = find('MuseumListView');
out.listViews = lists.length;
if (lists.length) {
  const lv = lists[0];
  out.listRows = lv.listMuseum ? lv.listMuseum.numChildren : null;
  out.listMuseumData = (lv.listMuseumData || []).map((d) => ({
    id: d.id, pics: (d.pic_list || []).length, cols: (d.collections || []).length,
  }));
}

const pages = find('MuseumPage');
out.detailPages = pages.length;
out.detailSlots = pages.map((p) => ({
  picturesVisible: (p.pictures || []).map((x) => !!x.visible),
  collectStates: (p.collects || []).map((x) => x.currentState),
  collectImages: (p.collects || []).map((x) => String(x.image && x.image.source)),
  ticket: String(p.imgTicket && p.imgTicket.source),
}));

/* the notice overlay must be gone, or the screenshot shows it instead of the game */
const n = document.getElementById('__notice');
out.noticePresent = !!n;
out.noticeDismissed = !!window.__noticeDismissed;
return JSON.stringify(out);
