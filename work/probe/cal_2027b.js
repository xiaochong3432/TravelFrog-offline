/* Faithful clock freeze: BOTH the client clock (core.Time.getServerTime) and the
   engine's (nowSec() -> Date.now()) must move together, otherwise the displayed
   month and the reward schedule come from different months and the test lies.
   Set window.__CAL_AT = 'YYYY-MM-DD' with a preceding --step eval.

   Then compare, for every day of the month:
     * the NUMBER my redraw puts in a cell, and
     * the WEEKDAY that cell's column means,
   against the real calendar -- and check the today-ring sits on today. */
const at = (window.__CAL_AT || '2027-03-15').split('-').map(Number);
const ms = new Date(at[0], at[1] - 1, at[2], 12, 0, 0).getTime();
window.__frozenMs = ms;
const RealNow = Date.now;
Date.now = function () { return ms; };                       // engine clock
core.Time.getServerTime = function () { return Math.floor(ms / 1000); };

const WD = ['日', '一', '二', '三', '四', '五', '六'];
const NAMES = ['一', '二', '三', '四', '五', '六', '日'];    // my header, Monday-first
const ref = (d) => new Date(at[0], at[1] - 1, d);

/* reload the calendar so the payload is built at the frozen time */
const load = await new Promise((res) => {
  core.SocketManage.getInstance().send('calendar_load',
    new core.Action2(function (r) { res(r); }), );
  setTimeout(() => res(null), 2500);
});

core.PageManage.getInstance().addViewControl(CalendarViewControl, core.ViewLayerType.WindowLayer);
await new Promise((r) => setTimeout(r, 3000));

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

const maxDay = new Date(at[0], at[1], 0).getDate();
const out = {
  frozenAt: at.join('-'),
  todayRealWeekday: WD[ref(at[2]).getDay()],
  monthDays: maxDay,
  firstWeekdayReal: WD[ref(1).getDay()],
  scheduleCovered: load ? Object.keys(load.st_days || {}).length
                        + Object.keys(load.lucky_days || {}).length : null,
  scheduleMaxDay: load ? Math.max.apply(null, Object.keys(load.st_days || {})
                        .concat(Object.keys(load.lucky_days || {})).map(Number)) : null,
};
out.scheduledDays = load ? Object.keys(load.st_days || {}).concat(Object.keys(load.lucky_days || {})).map(Number).sort((a, b) => a - b) : null;

/* the numbers my redraw placed, keyed by cell */
if (!view) { out.error = 'calendar view not found'; Date.now = RealNow; return JSON.stringify(out, null, 1); }
const texts = view.__offlineCalText;
const cell = {};
if (texts) {
  for (const t of texts.$children) {
    if (t.y < 0) continue;
    cell[Math.round(t.x / 73) + ',' + Math.round((t.y - 4) / 65)] = t.text;
  }
}
/* For each in-month day, where does the number sit and is that column the real
   weekday? Also: is there a reward icon in that same cell? */
const icons = {};
if (view.groupReward) {
  for (const c of view.groupReward.$children) {
    if (Math.round(c.width) === 60) {                 // the 60x60 reward icon
      icons[Math.round((c.x - 6) / 73) + ',' + Math.round((c.y - 2) / 65)] = true;
    }
  }
}
const wrong = [];
for (let day = 1; day <= maxDay; day++) {
  const trueName = WD[ref(day).getDay()];
  let found = null;
  for (const k in cell) {
    if (cell[k] === String(day)) { found = k; break; }
  }
  if (!found) { wrong.push({ day, reason: 'number not drawn' }); continue; }
  const col = Number(found.split(',')[0]);
  if (NAMES[col] !== trueName) {
    wrong.push({ day, col: NAMES[col], trueName, cell: found });
  }
  if (!icons[found]) wrong.push({ day, reason: 'no reward icon in its cell', cell: found });
}
out.mismatches = wrong.length;
out.mismatchDetail = wrong.slice(0, 10);
out.iconCells = Object.keys(icons).length;

const ring = view.imageToday;
out.ringCell = ring ? [Math.round(ring.x / 73), Math.round(ring.y / 65)] : null;
const ringDay = out.ringCell ? cell[out.ringCell[0] + ',' + out.ringCell[1]] : null;
out.ringSitsOnDay = ringDay;
out.ringCorrect = String(at[2]) === String(ringDay);

Date.now = RealNow;
return JSON.stringify(out, null, 1);
