/* The visitor view WITH a real visitor: does it still throw?

`VisitorView.open` is:
    e = visitorModel.getVisitorData()
    t_name = e.name
    t_id   = e.partner.toString()
    t_area = getVisitorInfo(e.getProvince()).DisplayName
    t_title= roleModel.getAchieveInfo(e.title).name      <-- throws if the title id has
                                                             no row in the Achieve table
So both the province lookup and the TITLE lookup can blow up while the view's skin is
already on screen -- which is exactly "black window with an X in the corner".

This drives the engine's own visitor roll (no hand-made payload), pushes visit_load, and
reports the title/province values against the tables the client will consult. */
const out = {};
const E = window.__engine;
const now = Math.floor(Date.now() / 1000);

E.state.guest = null;
for (let i = 0; i < 400 && !E.state.visitor; i++) {
  E.state.visitorNextRollAt = 1;
  E.state.visitorCoolUntil = 0;
  E.tick();
}
out.engineVisitor = E.state.visitor
  ? { province: E.state.visitor.province, title: E.state.visitor.title,
      name: E.state.visitor.name, partner: E.state.visitor.partner }
  : null;
E.dispatch('visit_load', {});

const M = core.ModelManage.getInstance();
const VM = M.getModel(VisitorModel);
const RM = M.getModel(RoleModel);
const vd = VM.getVisitorData();
out.clientVisitorData = vd ? {
  name: vd.name, title: vd.title, partner: vd.partner,
  province: typeof vd.getProvince === 'function' ? vd.getProvince() : vd.province,
} : null;

/* what the two table lookups the view performs will return */
try {
  const info = VM.getVisitorInfo(vd.getProvince());
  out.visitorInfo = info ? { DisplayName: info.DisplayName, Icon: info.Icon } : 'UNDEFINED';
} catch (e) { out.visitorInfo = 'THREW ' + String(e && e.message || e); }
try {
  const ach = RM.getAchieveInfo(vd.title);
  out.achieve = ach ? { id: ach.id, name: ach.name } : 'UNDEFINED';
} catch (e) { out.achieve = 'THREW ' + String(e && e.message || e); }

/* and now the real thing */
try {
  core.PageManage.getInstance().addViewControl(VisitorViewController,
    core.ViewLayerType.WindowLayer);
  out.openResult = 'opened';
} catch (e) {
  out.openResult = 'THREW ' + String(e && e.message || e);
}
return JSON.stringify(out);
