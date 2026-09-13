/* Verify the calendar's own month geometry against a real calendar, for every
   month of 2026..2028. My redraw uses CalendarModel.getMonthFirstWeek()/
   getMonthMaxDay() and the client's cell formula, so if a 2027 month is drawn with
   the wrong weekday column, the bug is in ONE of these:
     * the client's helpers (then diff against a JS reference below),
     * my column->weekday-name mapping.
   Both are checked here for real, by faking the server clock per month. */
const ref = (y, m, d) => new Date(y, m - 1, d);
const trueLen = (y, m) => new Date(y, m, 0).getDate();               // last day of month m
const trueFirstWeek = (y, m) => { const w = ref(y, m, 1).getDay(); return w === 0 ? 7 : w; };

const CAL_WEEK = ['一', '二', '三', '四', '五', '六', '日'];          // my header
const NAMES = ['', '一', '二', '三', '四', '五', '六', '日'];
const WD = ['日', '一', '二', '三', '四', '五', '六'];                // Date.getDay() -> name

const cm = core.ModelManage.getInstance().getModel(CalendarModel);
const realNow = core.Time.getServerTime;
const rows = [];
let bad = 0;

for (const y of [2026, 2027, 2028]) {
  for (let m = 1; m <= 12; m++) {
    // pin the clock to the 15th of that month so month/day getters are unambiguous
    const ts = Math.floor(ref(y, m, 15).getTime() / 1000);
    core.Time.getServerTime = function () { return ts; };
    const firstWeek = cm.getMonthFirstWeek();
    const maxDay = cm.getMonthMaxDay();
    const expLen = trueLen(y, m);
    const expFirst = trueFirstWeek(y, m);

    // what MY drawing does: day N sits in column ((firstWeek-1) + N-1) % 7
    const lead = firstWeek - 1;
    const colOfDay = (n) => (lead + n - 1) % 7;
    const day1Name = CAL_WEEK[colOfDay(1)];
    const trueDay1Name = WD[ref(y, m, 1).getDay()];

    const okLen = maxDay === expLen;
    const okFirst = firstWeek === expFirst;
    const okName = day1Name === trueDay1Name;

    // also check the last day lands on the right column
    const lastCol = colOfDay(expLen);
    const lastTrue = WD[ref(y, m, expLen).getDay()];
    const okLast = (maxDay >= expLen) ? CAL_WEEK[lastCol] === lastTrue : false;

    if (!(okLen && okFirst && okName && okLast)) {
      bad++;
      rows.push({ y, m, firstWeek, expFirst, maxDay, expLen, day1Name, trueDay1Name,
                  lastCol, lastTrue, okLen, okFirst, okName, okLast });
    }
  }
}
core.Time.getServerTime = realNow;

/* and the engine's own reward schedule: which days carry an icon? */
const load = core.SocketManage.getInstance().send
  ? await new Promise((res) => {
      core.SocketManage.getInstance().send('calendar_load',
        new core.Action2(function (r) { res(r); }), );
      setTimeout(() => res(null), 3000);
    })
  : null;
const stDays = load ? Object.keys(load.st_days || {}).map(Number) : [];
const luckyDays = load ? Object.keys(load.lucky_days || {}).map(Number) : [];
const covered = new Set(stDays.concat(luckyDays));

return JSON.stringify({
  mismatchingMonths: bad,
  detail: rows.slice(0, 12),
  calendarLoad: load ? {
    stDays: stDays.length, luckyDays: luckyDays.length,
    maxCovered: covered.size ? Math.max.apply(null, Array.from(covered)) : 0,
    minCovered: covered.size ? Math.min.apply(null, Array.from(covered)) : 0,
  } : null,
}, null, 1);
