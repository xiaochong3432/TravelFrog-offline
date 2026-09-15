/* Why did the calendar redraw bail out? Report each precondition. */
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

const out = {
  viewFound: !!view,
  hooksInstalled: !!(window.core && core.PageManage && core.PageManage.getInstance()._offlineHooked),
  hasRebuild: typeof window.__rebuildCalendar,
  calCtrl: typeof window.CalendarViewControl,
};
if (view) {
  out.hasImagePic = !!view.imagePic;
  out.hasGroupDay = !!view.groupDay;
  out.sameParent = !!(view.imagePic && view.groupDay &&
    view.imagePic.parent && view.imagePic.parent === view.groupDay.parent);
  out.alreadyDone = !!view.__offlineCalDone;
  out.imagePic = view.imagePic ? [view.imagePic.x, view.imagePic.y, view.imagePic.width, view.imagePic.height] : null;
  out.groupDay = view.groupDay ? [view.groupDay.x, view.groupDay.y, view.groupDay.width, view.groupDay.height] : null;
  out.childCount = view.numChildren;
}
try { out.rebuildResult = window.__rebuildCalendar(); } catch (e) { out.rebuildError = String(e && e.stack || e); }
out.log = (window.__probeLog || []).filter((l) => l.indexOf('[calendar') >= 0 || l.indexOf('[shell') >= 0).slice(-8);
return JSON.stringify(out, null, 1);
