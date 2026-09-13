/* Full child order of the calendar view, in PAINT order (index 0 = bottom),
   plus the size/position of each, so the replacement layer can be slotted in
   with the right z-order. */
const stage = egret.MainContext.instance.stage;
let view = null;
(function walk(n, d) {
  if (d > 14 || !n || view) return;
  for (const c of (n.$children || [])) {
    let s = '';
    try { s = String(c.constructor); } catch (e) { }
    if (s.indexOf('CalendarSkin.exml') >= 0) { view = c; return; }
    walk(c, d + 1);
    if (view) return;
  }
})(stage, 0);
if (!view) return JSON.stringify({ error: 'no view' });

const kids = [];
for (let i = 0; i < view.numChildren; i++) {
  const c = view.getChildAt(i);
  kids.push({
    i,
    wh: Math.round(c.width) + 'x' + Math.round(c.height),
    xy: Math.round(c.x) + ',' + Math.round(c.y),
    kids: c.$children ? c.$children.length : 0,
    vis: c.visible,
    isGroupDay: c === view.groupDay,
    isGroupReward: c === view.groupReward,
    holdsImagePic: !!(view.imagePic && c === view.imagePic.parent),
    numKidsOfImagePicParent: 0,
  });
}
const wrap = view.imagePic ? view.imagePic.parent : null;

/* what are groupDay's own cells? (are they drawing anything?) */
const cells = [];
if (view.groupDay) {
  for (let i = 0; i < Math.min(3, view.groupDay.numChildren); i++) {
    const c = view.groupDay.getChildAt(i);
    cells.push({
      i, cls: String(c.constructor).slice(9, 40),
      alpha: c.alpha, vis: c.visible,
      src: c.source || null,
      wh: Math.round(c.width) + 'x' + Math.round(c.height),
    });
  }
}
return JSON.stringify({
  viewSize: Math.round(view.width) + 'x' + Math.round(view.height),
  kids,
  imagePic: view.imagePic ? {
    xy: view.imagePic.x + ',' + view.imagePic.y,
    wh: view.imagePic.width + 'x' + view.imagePic.height,
    parentKids: wrap ? wrap.numChildren : null,
    inParentIndex: wrap ? wrap.getChildIndex(view.imagePic) : null,
  } : null,
  groupDayXYWH: view.groupDay ? [view.groupDay.x, view.groupDay.y, view.groupDay.width, view.groupDay.height] : null,
  groupRewardXYWH: view.groupReward ? [view.groupReward.x, view.groupReward.y, view.groupReward.width, view.groupReward.height] : null,
  cells,
}, null, 1);
