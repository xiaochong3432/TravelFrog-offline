/* 1. hide the scene's notification banner and the dimming layers so the
      calendar can be inspected cleanly;
   2. dump the redrawn day numbers next to the game's own today-ring position,
      which is the alignment that actually matters. */
const stage = egret.MainContext.instance.stage;
let calView = null;
const hidden = [];

(function walk(n, d) {
  if (d > 14 || !n) return;
  for (const c of (n.$children || [])) {
    let s = '';
    try { s = String(c.constructor); } catch (e) { }
    if (s.indexOf('CalendarSkin.exml') >= 0) calView = c;
    if (/MainOut\/Notification\.exml/.test(s) && c.visible) { c.visible = false; hidden.push('Notification'); }
    walk(c, d + 1);
  }
})(stage, 0);

const out = { hidden, viewFound: !!calView };
if (!calView) return JSON.stringify(out);

/* the today-ring lives in groupReward */
const ring = calView.imageToday;
out.ring = ring ? { x: ring.x, y: ring.y, w: ring.width, h: ring.height, vis: ring.visible } : null;
out.grid = calView.groupDay ? { x: calView.groupDay.x, y: calView.groupDay.y } : null;

const texts = calView.__offlineCalText;
out.textsFound = !!texts;
if (texts) {
  const items = [];
  for (let i = 0; i < texts.numChildren; i++) {
    const t = texts.getChildAt(i);
    items.push({ t: t.text, x: Math.round(t.x), y: Math.round(t.y), w: Math.round(t.width) });
  }
  out.count = items.length;
  out.header = items.filter((i) => i.y < 0);
  out.days = items.filter((i) => i.y >= 0).map((i) => i.t);
  /* which number the ring covers, per the same geometry the client uses */
  const col = Math.round((ring.x - 0) / 73);
  const row = Math.round((ring.y - 0) / 65);
  out.ringCell = { col, row, index: row * 7 + col };
  const plain = items.filter((i) => i.y >= 0);
  out.numberUnderRing = plain[(row * 7 + col)] ? plain[row * 7 + col].t : null;
  out.ringCellXY = { x: col * 73, y: row * 65 };
}
return JSON.stringify(out, null, 1);
