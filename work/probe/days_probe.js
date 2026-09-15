/* What renders the "N天" counter on the main scene, and why is it a huge number?
   It reads 3649天 on a one-day-old save, which cannot be "days played". */
const stage = egret.MainContext.instance.stage;
const found = [];
(function walk(n, d) {
  if (d > 16 || !n) return;
  for (const c of (n.$children || [])) {
    if (c instanceof egret.TextField && c.text && /\d+\s*天/.test(c.text)) {
      const chain = [];
      let p = c, k = 0;
      while (p && k < 6) {
        let s = '';
        try { s = String(p.constructor); } catch (e) { }
        const m = /getSkinsPath\("([^"]+)"\)/.exec(s);
        chain.push(m ? m[1] : ('<' + s.slice(0, 26) + '>'));
        p = p.parent;
        k++;
      }
      let g = null;
      try { g = c.localToGlobal(0, 0); } catch (e) { }
      found.push({
        text: c.text, name: c.name || '', chain,
        xy: g ? Math.round(g.x) + ',' + Math.round(g.y) : '?',
        size: c.size,
      });
    }
    walk(c, d + 1);
  }
})(stage, 0);

/* the likely sources, read straight from the models */
const sources = {};
try {
  const rm = core.ModelManage.getInstance().getModel(RoleModel);
  sources.createDay = rm.getCreateDay();
  sources.createTime = rm.createTime;
} catch (e) { sources.createDay = 'ERR ' + e.message; }
try {
  sources.serverTime = core.Time.getServerTime();
  sources.offsetDayNow = core.getOffsetDay(core.Time.getServerTime(), sources.createTime);
} catch (e) { /* ignore */ }

return JSON.stringify({ found, sources }, null, 1);
