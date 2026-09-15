/* Two consecutive months in ONE session, dumping the actual number grid, because
   the single-month test passed and the multi-month sweep failed: something is
   carried over between months, or the grid is shifted. */
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

async function look(y, m) {
  const ms = new Date(y, m - 1, 15, 12, 0, 0).getTime();
  Date.now = function () { return ms; };
  core.Time.getServerTime = function () { return Math.floor(ms / 1000); };
  await new Promise((res) => {
    core.SocketManage.getInstance().send('calendar_load', new core.Action2(() => res()), );
    setTimeout(res, 1500);
  });
  if (!core.PageManage.getInstance().getControl(CalendarViewControl, core.ViewLayerType.WindowLayer)) {
    core.PageManage.getInstance().addViewControl(CalendarViewControl, core.ViewLayerType.WindowLayer);
  }
  await new Promise((r) => setTimeout(r, 2200));

  const view = findCalView();
  const out = { y, m, layers: [], gridRaw: [], ringCell: null, today: 15 };
  if (!view) return out;
  out.layers = (view.groupDay ? view.groupDay.$children.length : -1);
  out.rebuildMonth = view.__offlineCalMonth;
  const texts = view.__offlineCalText;
  out.textLayerPresent = !!texts && !!texts.parent;
  if (texts) {
    const cells = [];
    for (const t of texts.$children) {
      cells.push([t.text, Math.round(t.x), Math.round(t.y)]);
    }
    out.rawCells = cells.slice(0, 12);
    out.cellCount = cells.length;
    const grid = [];
    for (let r = 0; r < 6; r++) {
      const line = [];
      for (let c = 0; c < 7; c++) {
        const hit = cells.find((x) => Math.round(x[1] / 73) === c && Math.round((x[2] - 4) / 65) === r);
        line.push(hit ? hit[0] : '.');
      }
      grid.push(line.join(' '));
    }
    out.grid = grid;
  }
  /* how many text layers are alive under groupDay? */
  if (view.groupDay) {
    out.textLayers = view.groupDay.$children.filter((c) => c.name === 'offlineCalendarText').length;
  }
  const ring = view.imageToday;
  out.ringCell = ring ? [Math.round(ring.x / 73), Math.round(ring.y / 65)] : null;
  out.weekdayOfFirst = WD[new Date(y, m - 1, 1).getDay()];
  out.expectedFirstWeek = (() => { const w = new Date(y, m - 1, 1).getDay(); return w === 0 ? 7 : w; })();
  out.clientFirstWeek = core.ModelManage.getInstance().getModel(CalendarModel).getMonthFirstWeek();
  return out;
}

const out = [];
out.push(await look(2027, 1));
out.push(await look(2027, 2));
out.push(await look(2027, 3));
Date.now = RealNow;
return JSON.stringify(out, null, 1);
