/* Faithful reproduction of the player's sequence:
     open the calendar  ->  close it  ->  the date changes (or they set the clock)
     ->  open it again
   and check whether the CLIENT's own overlay (today-ring + reward icons) moves with
   the new date, or stays where the first open put it. My redrawn numbers always
   follow the clock, so a stale overlay shows the ring and icons under the WRONG
   dates -- which is exactly "日期和星期不对应". */
const WD = ['日', '一', '二', '三', '四', '五', '六'];
const NAMES = ['一', '二', '三', '四', '五', '六', '日'];
const RealNow = Date.now;
const CL = core.ViewLayerType.WindowLayer;

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

function snapshot() {
  const view = findCalView();
  const out = { viewSame: null };
  if (!view) return out;
  const cell = {};
  const texts = view.__offlineCalText;
  if (texts) {
    for (const t of texts.$children) {
      if (t.y < 0) continue;
      cell[Math.round(t.x / 73) + ',' + Math.round((t.y - 4) / 65)] = t.text;
    }
  }
  out.myLayerMonth = view.__offlineCalMonth;
  const icons = {};
  if (view.groupReward) {
    for (const c of view.groupReward.$children) {
      if (Math.round(c.width) === 60) {
        icons[Math.round((c.x - 6) / 73) + ',' + Math.round((c.y - 2) / 65)] = true;
      }
    }
  }
  out.iconCells = Object.keys(icons).length;
  out.iconSample = Object.keys(icons).slice(0, 4);
  const ring = view.imageToday;
  if (ring) {
    const rk = Math.round(ring.x / 73) + ',' + Math.round(ring.y / 65);
    out.ringCell = rk;
    out.numberUnderRing = cell[rk] || null;
  }
  out.rewardChildren = view.groupReward ? view.groupReward.numChildren : -1;
  out.textLayers = view.groupDay
    ? view.groupDay.$children.filter((c) => c.name === 'offlineCalendarText').length : -1;
  return out;
}

function freeze(y, m, d) {
  const ms = new Date(y, m - 1, d, 12, 0, 0).getTime();
  Date.now = function () { return ms; };
  core.Time.getServerTime = function () { return Math.floor(ms / 1000); };
}

async function loadCal() {
  return await new Promise((res) => {
    core.SocketManage.getInstance().send('calendar_load', new core.Action2(function (r) { res(r); }), );
    setTimeout(() => res(null), 1500);
  });
}

const out = { steps: [] };

/* ---- open #1 : 2026-09-11 ---- */
freeze(2026, 9, 11);
await loadCal();
core.PageManage.getInstance().addViewControl(CalendarViewControl, CL);
await new Promise((r) => setTimeout(r, 2600));
out.first = snapshot();
out.first.today = '2026-09-11';
out.first.realWeekdayOfToday = WD[new Date(2026, 8, 11).getDay()];

/* ---- close ---- */
core.PageManage.getInstance().removeControl(CalendarViewControl, CL);
await new Promise((r) => setTimeout(r, 900));
out.afterClose = { stillThere: !!findCalView() };

/* ---- the date moves to 2027-03-15, then reopen ---- */
freeze(2027, 3, 15);
await loadCal();
core.PageManage.getInstance().addViewControl(CalendarViewControl, CL);
await new Promise((r) => setTimeout(r, 2600));
out.second = snapshot();
out.second.today = '2027-03-15';
out.second.realWeekdayOfToday = WD[new Date(2027, 2, 15).getDay()];

/* ---- verdict ---- */
out.verdict = {
  ringMovedToNewDay: out.first.ringCell !== out.second.ringCell,
  ringCorrectFirst: out.first.numberUnderRing === '11',
  ringCorrectSecond: out.second.numberUnderRing === '15',
  myNumbersFollowClock: out.second.myLayerMonth === 3,
  iconCountFirst: out.first.iconCells,
  iconCountSecond: out.second.iconCells,
  textLayersAccumulated: out.second.textLayers,
};
Date.now = RealNow;
return JSON.stringify(out, null, 1);
