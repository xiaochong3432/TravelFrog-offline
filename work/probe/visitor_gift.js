/* The visitor's gift paper (`i_gift`) opens VisitorGiftViewController.

   Our engine fills the gift with `visitor.provinceList[province].OtherGiftID`, which is
   100000 / 100001 -- but the Item table's own 三叶草 / 兑奖券 rows are 200000 / 200001.
   If the gift view looks the id up in ItemDB and prints its name, a missing row means
   `undefined.name` -> throw -> the skin is already on screen, so the player sees a BLACK
   window with a close X. This checks both the table lookup and the view itself. */
const out = {};
const E = window.__engine;
const M = core.ModelManage.getInstance();
const VM = M.getModel(VisitorModel);
const DM = Tabikaeru.DataManager.instance();

for (let i = 0; i < 400 && !E.state.visitor; i++) {
  E.state.visitorNextRollAt = 1;
  E.state.visitorCoolUntil = 0;
  E.tick();
}
core.SocketManage.getInstance().send('visit_load', new core.Action2(function (r) {
  out.reply = r && r.visitor ? { gift: r.visitor.gift } : null;
}));

const vd = VM.getVisitorData();
out.gift = vd ? vd.gift : null;
out.itemDbHas = {};
for (const id of [100000, 100001, 200000, 200001]) {
  try {
    const row = DM.ItemDB.get(id);
    out.itemDbHas[id] = row ? { name: row.name, type: row.type } : 'UNDEFINED';
  } catch (e) { out.itemDbHas[id] = 'THREW ' + String(e && e.message || e); }
}

try {
  core.PageManage.getInstance().addViewControl(VisitorGiftViewController,
    core.ViewLayerType.WindowLayer);
  out.openResult = 'opened';
} catch (e) {
  out.openResult = 'THREW ' + String(e && e.message || e);
}
return JSON.stringify(out);
