/* Read the live calendar view's OWN labels and the position of its today-marker,
   instead of trusting OCR of a screenshot. */
core.PageManage.getInstance().addViewControl(CalendarViewControl, core.ViewLayerType.WindowLayer);
await new Promise((r) => setTimeout(r, 2500));

const stage = egret.MainContext.instance.stage;
let view = null;
(function walk(n, d) {
  if (d > 12 || !n || view) return;
  for (const c of (n.$children || [])) {
    let s = '';
    try { s = String(c.constructor); } catch (e) { }
    if (/CalendarSkin\.exml/.test(s)) { view = c; return; }
    walk(c, d + 1);
    if (view) return;
  }
})(stage, 0);
if (!view) return JSON.stringify({ error: 'calendar view not found' });

const out = { texts: [], labels: {}, today: null, cells: [] };
for (const k in view) {
  if (k.charAt(0) === '$') continue;
  let p;
  try { p = view[k]; } catch (e) { continue; }
  if (!p || typeof p !== 'object') continue;
  if (typeof p.text === 'string' && p.text) out.labels[k] = p.text;
  if (typeof p.source === 'string' && p.source) out.labels[k + '.src'] = p.source;
}
if (view.imageToday) {
  const g = view.imageToday.localToGlobal(0, 0);
  out.today = { x: Math.round(g.x), y: Math.round(g.y), vis: view.imageToday.visible };
}
/* every Label under the view, with the content coordinates it sits at */
(function walk2(n, d) {
  if (d > 10 || !n) return;
  for (const c of (n.$children || [])) {
    if (c instanceof egret.TextField && c.text) {
      const g = c.localToGlobal(0, 0);
      out.texts.push({ t: c.text, x: Math.round(g.x), y: Math.round(g.y) });
    }
    walk2(c, d + 1);
  }
})(view, 0);
out.texts.sort((a, b) => (a.y - b.y) || (a.x - b.x));

/* what the client thinks the day-grid geometry is */
const cm = core.ModelManage.getInstance().getModel(CalendarModel);
out.grid = {
  firstWeek: cm.getMonthFirstWeek(),
  maxDay: cm.getMonthMaxDay(),
  serverDay: new Date(core.Time.getServerTime() * 1000).getDate(),
  createDay: core.ModelManage.getInstance().getModel(RoleModel).getCreateDay(),
};
return JSON.stringify(out, null, 1);
