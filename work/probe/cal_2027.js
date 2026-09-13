/* Freeze the client clock at a chosen date, then open the calendar.
   `window.__CAL_AT` = 'YYYY-MM-DD' (set by a preceding --step eval). */
const at = (window.__CAL_AT || '2027-03-15').split('-').map(Number);
const ts = Math.floor(new Date(at[0], at[1] - 1, at[2], 12, 0, 0).getTime() / 1000);
window.__frozenTs = ts;
core.Time.getServerTime = function () { return ts; };

/* the engine's own clock has to move too, or the reward schedule stays on today's
   month -- rebuild the calendar payload after freezing */
await new Promise((res) => {
  core.SocketManage.getInstance().send('calendar_load',
    new core.Action2(function (r) { res(r); }), );
  setTimeout(res, 2000);
});

core.PageManage.getInstance().addViewControl(CalendarViewControl, core.ViewLayerType.WindowLayer);
await new Promise((r) => setTimeout(r, 3000));

const cm = core.ModelManage.getInstance().getModel(CalendarModel);
const ref = new Date(at[0], at[1] - 1, at[2]);
const WD = ['日', '一', '二', '三', '四', '五', '六'];
const out = {
  frozenAt: at.join('-'),
  clientToday: new Date(ts * 1000).toString().slice(0, 15),
  isRealWeekdayOfToday: WD[ref.getDay()],
  firstWeek: cm.getMonthFirstWeek(),
  maxDay: cm.getMonthMaxDay(),
  realMaxDay: new Date(at[0], at[1], 0).getDate(),
  realFirstWeekday: (() => { const w = new Date(at[0], at[1] - 1, 1).getDay(); return WD[w]; })(),
  grid: null,
  overlayRewards: null,
};

/* what my redraw put in each cell, and where the client put the reward icons */
const stage = egret.MainContext.instance.stage;
let view = null;
(function walk(n, d) {
  if (d > 12 || !n || view) return;
  for (const c of (n.$children || [])) {
    let s = '';
    try { s = String(c.constructor); } catch (e) { }
    if (s.indexOf('CalendarSkin.exml') >= 0) { view = c; return; }
    walk(c, d + 1);
    if (view) return;
  }
})(stage, 0);

if (view) {
  const rows = [];
  const texts = view.__offlineCalText;
  if (texts) {
    const byCell = {};
    for (const t of texts.$children) {
      if (t.y < 0) continue;                       // the header rows
      byCell[Math.round(t.x / 73) + ',' + Math.round((t.y - 4) / 65)] = t.text;
    }
    for (let r = 0; r < 6; r++) {
      const line = [];
      for (let c = 0; c < 7; c++) line.push(byCell[c + ',' + r] || '.');
      rows.push(line.join(' '));
    }
  }
  out.grid = rows;
  const ring = view.imageToday;
  out.ringCell = ring ? [Math.round(ring.x / 73), Math.round(ring.y / 65)] : null;
  out.rewardIconCount = (view.groupReward ? view.groupReward.numChildren : 0);
}
return JSON.stringify(out, null, 1);
