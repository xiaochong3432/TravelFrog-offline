/* Drive visit_load through the CLIENT's own socket so the reply really reaches the model,
   then open the visitor view.

   My earlier probe called engine.dispatch() directly, which returns the payload but
   pushes nothing to the page -- so `getVisitorData()` was null for a reason that had
   nothing to do with the payload. The client path is `SocketManage.send(cmd, action)`. */
const out = {};
const E = window.__engine;
const M = core.ModelManage.getInstance();
const VM = M.getModel(VisitorModel);
const RM = M.getModel(RoleModel);

for (let i = 0; i < 400 && !E.state.visitor; i++) {
  E.state.visitorNextRollAt = 1;
  E.state.visitorCoolUntil = 0;
  E.tick();
}
out.engineVisitor = E.state.visitor
  ? { province: E.state.visitor.province, title: E.state.visitor.title } : null;

let replied = null;
core.SocketManage.getInstance().send('visit_load', new core.Action2(function (r) {
  replied = r;
}));
out.repliedKeys = replied ? Object.keys(replied) : null;

const vd = VM.getVisitorData();
out.clientVisitorData = vd ? {
  name: vd.name, title: vd.title, partner: vd.partner,
  province: vd.getProvince(), city: vd.getCity(), carpet: vd.carpet,
  gift: vd.gift, expireIn: vd.expire_time - Math.floor(Date.now() / 1000),
} : null;

if (vd) {
  const info = VM.getVisitorInfo(vd.getProvince());
  out.visitorInfo = info ? { DisplayName: info.DisplayName, Icon: info.Icon } : 'UNDEFINED';
  const ach = RM.getAchieveInfo(vd.title);
  out.achieve = ach ? { id: ach.id, name: ach.name } : 'UNDEFINED';
  const res = vd.food !== undefined ? VM.getVisitorResInfo(vd.food) : null;
  out.visitorRes = res || 'UNDEFINED';
}

/* now the actual view */
try {
  core.PageManage.getInstance().addViewControl(VisitorViewController,
    core.ViewLayerType.WindowLayer);
  out.openResult = 'opened';
} catch (e) {
  out.openResult = 'THREW ' + String(e && e.message || e);
}
return JSON.stringify(out);
