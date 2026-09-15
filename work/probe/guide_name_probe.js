/* The NEW-ACCOUNT naming path (GuideNamedView), which shares `client_rename_cost`
   with the rename panel. A brand-new save could not be named at all before the
   fix: GuideNamedView.btn_yes -> RoleModel.setName() -> client_rename_cost, and
   with no handler the callback never fired, so completeCallback never ran and the
   guide never advanced past the naming step.

   Reads the branch it takes:
     e = getErrorInfo(reply.code); e && 0 == e.code ? (lucky ? "gift promised" : advance)
   `lucky` must stay falsy -- the guide promises a mailbox gift when it is truthy. */
const out = {};
let complete = 0;
let skipped = 0;

const Role = core.ModelManage.getInstance().getModel(RoleModel);
out.nameBefore = Role.getName();

let err = null;
try {
  const v = new GuideNamedView(
    function () { complete++; },
    function () { skipped++; });
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  out.prompt = v.t_name.prompt;
  out.maxChars = v.t_name.maxChars;
  v.t_name.text = '新号蛙';
  /* The guide's own 确认 handler. */
  v.btn_yes.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
} catch (e) {
  err = String(e && e.stack || e);
}
out.error = err;
out.completeCallback = complete;
out.skipCallback = skipped;
out.nameAfter = Role.getName();

try {
  const s = JSON.parse(localStorage.getItem('frog.offline.save') || 'null');
  out.saveName = s && s.name;
  out.saveRenamed = s && s.renamed;
} catch (e) { out.saveError = String(e); }

return JSON.stringify(out);
