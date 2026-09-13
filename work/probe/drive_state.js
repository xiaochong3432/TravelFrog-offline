/* Report the dates that matter, straight from the running client.
   Run via: node tools/cdp_drive.js --step in:work/probe/drive_state.js */
const o = {};
const T = (f) => { try { return f(); } catch (e) { return 'ERR ' + e.message; } };

o.tzOffsetMin = new Date().getTimezoneOffset();
o.systemLocal = T(() => {
  const d = new Date();
  return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate() + ' ' + d.getHours() + ':' + d.getMinutes();
});
o.systemUTC = T(() => new Date().toISOString());

o.serverTime = T(() => core.Time.getServerTime());
o.clientDate = T(() => {
  const d = new Date(core.Time.getServerTime() * 1000);   // what CalendarView uses
  return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate() + ' dom=' + d.getDate() +
    ' month=' + (d.getMonth() + 1) + ' dow=' + d.getDay();
});
/* the client's own day frame: BaseTime = 2000-01-01 00:00 UTC+8 */
o.cnDayIndex = T(() => Math.floor((core.Time.getServerTime() - 946656000) / 86400));
o.cnZeroHourLocal = T(() => {
  const z = core.getZeroHours(core.Time.getServerTime(), 0);
  const d = new Date(z * 1000);
  return 'ts=' + z + ' local=' + d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate() + ' ' +
    d.getHours() + ':' + d.getMinutes();
});
o.cnTomorrowLocal = T(() => {
  const z = core.getZeroHours(core.Time.getServerTime(), 1);
  const d = new Date(z * 1000);
  return 'ts=' + z + ' local=' + d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate() + ' ' +
    d.getHours() + ':' + d.getMinutes();
});

/* RoleModel, reached through the live model manager */
o.createDay = T(() => core.ModelManage.getInstance().getModel(RoleModel).getCreateDay());
o.createTimeStored = T(() => core.ModelManage.getInstance().getModel(RoleModel).createTime);

/* Calendar model state as the client holds it */
o.calMonth = T(() => core.ModelManage.getInstance().getModel(CalendarModel).getMonthFirstWeek());
o.calMaxDay = T(() => core.ModelManage.getInstance().getModel(CalendarModel).getMonthMaxDay());
o.calData = T(() => JSON.stringify(core.ModelManage.getInstance().getModel(CalendarModel).data).slice(0, 600));

/* Engine save, if the shell exposes it */
o.engineState = T(() => {
  if (!window.FrogEngine) return 'no FrogEngine';
  const k = Object.keys(window.FrogEngine);
  let st = null;
  try { st = window.FrogEngine.getState ? window.FrogEngine.getState() : null; } catch (e) { }
  return 'keys=' + k.join(',') + ' createTime=' + (st ? st.createTime : 'n/a');
});

return JSON.stringify(o, null, 1);
