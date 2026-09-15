/* Calendar verification, done the unambiguous way.

   The earlier version searched the grid for a cell whose TEXT equals the day
   number. That is ambiguous: a month grid also shows the previous month's tail and
   the next month's head, so "1" appears in two cells and the search could return
   the wrong one -- which produced a fake "31 of 31 weekdays wrong" for a month that
   was actually perfect.

   Instead: derive the cell from the CLIENT'S OWN formula (day 1 sits at column
   firstWeek-1 of row 0, each cell 73x65), then assert
     * my number in that cell equals the day,
     * the column's weekday NAME matches the real weekday of that date,
     * a reward icon is present in the same cell,
   for every day of the month. */
const WD = ['日', '一', '二', '三', '四', '五', '六'];
const NAMES = ['一', '二', '三', '四', '五', '六', '日'];
const RealNow = Date.now;

function findCalView() {
  let v = null;
  (function walk(n, d) {
    if (d > 12 || !n || v) return;
    for (const c of (n.$children || [])) {
      let s = '';
      try { s = String(c.constructor); } catch (e) { }
      if (s.indexOf('CalendarSkin.exml') >= 0) { v = c; return; }
      walk(c, d + 1);
      if (v) return;
    }
  })(egret.MainContext.instance.stage, 0);
  return v;
}

async function checkMonth(y, m, dayOfMonth) {
  const ms = new Date(y, m - 1, dayOfMonth, 12, 0, 0).getTime();
  Date.now = function () { return ms; };
  core.Time.getServerTime = function () { return Math.floor(ms / 1000); };
  const load = await new Promise((res) => {
    core.SocketManage.getInstance().send('calendar_load',
      new core.Action2(function (r) { res(r); }), );
    setTimeout(() => res(null), 1800);
  });
  if (!core.PageManage.getInstance().getControl(CalendarViewControl, core.ViewLayerType.WindowLayer)) {
    core.PageManage.getInstance().addViewControl(CalendarViewControl, core.ViewLayerType.WindowLayer);
  }
  await new Promise((r) => setTimeout(r, 2200));

  const view = findCalView();
  const maxDay = new Date(y, m, 0).getDate();
  const firstWeek = (() => { const w = new Date(y, m - 1, 1).getDay(); return w === 0 ? 7 : w; })();
  const res = { y, m, maxDay, realFirstWeekday: WD[new Date(y, m - 1, 1).getDay()], firstWeek };
  res.scheduled = load
    ? Object.keys(load.st_days || {}).length + Object.keys(load.lucky_days || {}).length : 0;
  if (!view) { res.err = 'no view'; return res; }
  res.clientFirstWeek = core.ModelManage.getInstance().getModel(CalendarModel).getMonthFirstWeek();
  res.clientMaxDay = core.ModelManage.getInstance().getModel(CalendarModel).getMonthMaxDay();

  /* my numbers, keyed by cell */
  const cell = {};
  const texts = view.__offlineCalText;
  if (texts) {
    for (const t of texts.$children) {
      if (t.y < 0) continue;
      cell[Math.round(t.x / 73) + ',' + Math.round((t.y - 4) / 65)] = t.text;
    }
  }
  /* the client's 60x60 reward icons, keyed by cell */
  const icons = {};
  if (view.groupReward) {
    for (const c of view.groupReward.$children) {
      if (Math.round(c.width) === 60) {
        icons[Math.round((c.x - 6) / 73) + ',' + Math.round((c.y - 2) / 65)] = true;
      }
    }
  }

  const lead = firstWeek - 1;
  let numberBad = 0, weekdayBad = 0, iconBad = 0;
  const examples = [];
  for (let d = 1; d <= maxDay; d++) {
    const e = lead + d - 1;
    const key = (e % 7) + ',' + Math.floor(e / 7);
    const got = cell[key];
    if (got !== String(d)) { numberBad++; if (examples.length < 4) examples.push({ d, key, got }); }
    if (NAMES[e % 7] !== WD[new Date(y, m - 1, d).getDay()]) weekdayBad++;
    if (!icons[key]) iconBad++;
  }
  res.numberWrongCell = numberBad;
  res.weekdayMismatch = weekdayBad;
  res.daysWithoutIcon = iconBad;
  res.examples = examples;
  res.iconCells = Object.keys(icons).length;
  const ring = view.imageToday;
  if (ring) {
    const rk = Math.round(ring.x / 73) + ',' + Math.round(ring.y / 65);
    res.ringOn = cell[rk] || null;
    res.ringCorrect = res.ringOn === String(dayOfMonth);
    res.ringCell = rk;
  }
  return res;
}

const out = [];
for (let m = 1; m <= 12; m++) out.push(await checkMonth(2027, m, 15));
out.push(await checkMonth(2026, 9, 11));
out.push(await checkMonth(2028, 2, 29));       // leap year
out.push(await checkMonth(2027, 12, 31));      // year end
Date.now = RealNow;

/* A compact one-line-per-month table: nested JSON through the driver's console
   pipe has been mangled more than once, and this is trivial to read. */
const lines = ['y-m      maxD fW cFW sched numWrong wkBad noIcon ring'];
for (const r of out) {
  lines.push([
    (r.y + '-' + r.m).padEnd(8), String(r.maxDay).padStart(4),
    String(r.firstWeek).padStart(3), String(r.clientFirstWeek).padStart(4),
    String(r.scheduled).padStart(5), String(r.numberWrongCell).padStart(8),
    String(r.weekdayMismatch).padStart(5), String(r.daysWithoutIcon).padStart(6),
    String(r.ringCorrect) + (r.ringCell ? ' @' + r.ringCell : ''),
  ].join(' '));
  for (const e of (r.examples || []).slice(0, 3)) {
    lines.push('          day ' + e.d + ' -> cell ' + e.key + ' holds "' + e.got + '"');
  }
}
const bad = out.filter((r) => r.err || r.numberWrongCell || r.weekdayMismatch
  || r.daysWithoutIcon || r.ringCorrect === false || r.scheduled !== r.maxDay
  || r.clientFirstWeek !== r.firstWeek || r.clientMaxDay !== r.maxDay);
lines.push('');
lines.push('months checked: ' + out.length + ',   BAD: ' + bad.length
  + (bad.length ? '  -> ' + bad.map((r) => r.y + '-' + r.m).join(', ') : ''));
return lines.join('\n');

