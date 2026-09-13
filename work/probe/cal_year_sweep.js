/* Sweep every month of 2027 (and a few of 2026/2028), with BOTH clocks frozen,
   and report for each month: how many days the engine scheduled, whether every
   in-month number sits under its real weekday, whether every day has a reward
   icon, and whether the today-ring lands on today. */
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
  const scheduled = load
    ? Object.keys(load.st_days || {}).length + Object.keys(load.lucky_days || {}).length : 0;
  const res = { y, m, maxDay, scheduled };
  if (!view) { res.err = 'no view'; return res; }

  const cell = {};
  const texts = view.__offlineCalText;
  if (texts) {
    for (const t of texts.$children) {
      if (t.y < 0) continue;
      cell[Math.round(t.x / 73) + ',' + Math.round((t.y - 4) / 65)] = t.text;
    }
  }
  const icons = {};
  if (view.groupReward) {
    for (const c of view.groupReward.$children) {
      if (Math.round(c.width) === 60) {
        icons[Math.round((c.x - 6) / 73) + ',' + Math.round((c.y - 2) / 65)] = true;
      }
    }
  }
  let weekdayBad = 0, iconBad = 0, missing = 0;
  for (let d = 1; d <= maxDay; d++) {
    let key = null;
    for (const k in cell) if (cell[k] === String(d)) { key = k; break; }
    if (!key) { missing++; continue; }
    const col = Number(key.split(',')[0]);
    if (NAMES[col] !== WD[new Date(y, m - 1, d).getDay()]) weekdayBad++;
    if (!icons[key]) iconBad++;
  }
  res.drawnNumbers = maxDay - missing;
  res.weekdayMismatch = weekdayBad;
  res.daysWithoutIcon = iconBad;
  res.iconCells = Object.keys(icons).length;
  const ring = view.imageToday;
  if (ring) {
    const rc = [Math.round(ring.x / 73), Math.round(ring.y / 65)];
    res.ringOn = cell[rc[0] + ',' + rc[1]] || null;
    res.ringCorrect = res.ringOn === String(dayOfMonth);
  }
  return res;
}

const out = [];
for (let m = 1; m <= 12; m++) out.push(await checkMonth(2027, m, 15));
out.push(await checkMonth(2026, 9, 11));
out.push(await checkMonth(2028, 2, 29));      // leap year, 29 days
Date.now = RealNow;
return JSON.stringify({
  months: out,
  bad: out.filter((r) => r.err || r.weekdayMismatch || r.daysWithoutIcon || r.ringCorrect === false
                          || r.drawnNumbers !== r.maxDay || r.scheduled !== r.maxDay),
}, null, 1);
