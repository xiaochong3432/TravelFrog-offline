/* The bench sits to the LEFT of the house door and opens 工作台 (FurnitureBenchView).
   On a fresh save it is empty and renders fine. The report is about a save WITH
   something on the bench, so place furniture through the engine, let the client accept it
   over its own socket, then open the view.

   Also reports which furniture rows have art registered, because a missing `res`/`icon`
   is what would turn the panel black. */
const out = {};
const E = window.__engine;
const M = core.ModelManage.getInstance();
const DM = Tabikaeru.DataManager.instance();
const FD = DM.FurnitureDB;

/* candidate furniture: the first rows that are benched-placeable (type 1 slots) */
const list = FD.list ? FD.list() : [];
out.furnitureRows = list.length;
const pick = list.filter((r) => r && r.res && r.res.length
  && String(r.res[0]) !== '').slice(0, 4).map((r) => r.id);
out.picked = pick;

/* put the first two on the bench through the engine, then let the CLIENT pull */
const placed = [];
for (let i = 0; i < pick.length && i < 2; i++) {
  const r = E.dispatch('furniture_putin_bench', { pos: i + 1, id: pick[i] });
  placed.push({ id: pick[i], reply: r.reply });
}
out.placed = placed;

/* client-side: ask the engine over the socket so the reply reaches the model */
core.SocketManage.getInstance().send('furniture_load_furniture', new core.Action2(function (r) {
  out.loadedKeys = r ? Object.keys(r) : null;
}));
const FM = M.getModel(FurnitureModel);
try {
  out.clientBench = FM.getBenchData ? JSON.stringify(FM.getBenchData()).slice(0, 200) : 'no getBenchData';
} catch (e) { out.clientBench = 'THREW ' + String(e && e.message || e); }

/* do the placed items have art? */
out.art = {};
for (const id of pick.slice(0, 2)) {
  const row = FD.get(id);
  out.art[id] = row ? { name: row.name, res: row.res, icon: row.icon } : 'UNDEFINED';
}

try {
  core.PageManage.getInstance().addViewControl(FurnitureBenchViewController,
    core.ViewLayerType.WindowLayer);
  out.openResult = 'opened';
} catch (e) {
  out.openResult = 'THREW ' + String(e && e.message || e);
}
return JSON.stringify(out);
