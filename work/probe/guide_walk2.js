/* Step 2 of the new-account walk: after the welcome tween, GuideNamedView has been
   re-parented onto the scene. Drive it, then report the guide step AND whether the
   four activity buttons became visible (MainOut shows them only once the guide is
   Complete, so this is also the check that the guide is not stuck). */
const U = core.ModelManage.getInstance().getModel(UserModel);
const out = {};
out.stepBefore = U.getClientSettings().guideStep;

function walk(node, depth, acc) {
  if (!node || depth > 12) return acc;
  acc.push(node);
  const kids = node.$children || [];
  for (let i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc);
  return acc;
}
const all = walk(egret.MainContext.instance.stage, 0, []);
out.nodeCount = all.length;
const clsOf = (n) => String(n.__class__ || (n.constructor && n.constructor.name) || '');

const mainOut = all.find((n) => clsOf(n) === 'MainOutView');
const named = all.find((n) => clsOf(n) === 'GuideNamedView');
out.namedFound = !!named;
out.welcomeStillThere = all.some((n) => clsOf(n) === 'WelcomeView');

if (named) {
  try {
    out.prompt = named.t_name.prompt;
    out.seeded = named.t_name.text;
    named.t_name.text = '新号蛙';
    named.btn_yes.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
    out.driveError = null;
  } catch (e) {
    out.driveError = String(e && e.stack || e);
  }
  out.roleName = core.ModelManage.getInstance().getModel(RoleModel).getName();
}
out.stepAfter = U.getClientSettings().guideStep;

/* What the four activity buttons look like right now. Their visibility is
   `guideStep == 'Complete' && Model.isOpen()`. */
function vis(v) {
  if (!v) return 'absent';
  return v.visible ? (v.includeInLayout === false ? 'visible(no-layout)' : 'visible') : 'hidden';
}
if (mainOut) {
  out.buttons = {
    museumDay: vis(mainOut.btnMuseumDay),
    greetCard: vis(mainOut.btnGreetCard),
    springCard: vis(mainOut.btnSpringCard),
    partyCake: vis(mainOut.btnPartyCake),
    capsule: vis(mainOut.btnCapsule),
    annualReview: vis(mainOut.annualReviewBtn),
  };
} else {
  out.buttons = 'no MainOutView';
}

try {
  out.saveName = JSON.parse(localStorage.getItem('frog.offline.save') || 'null').name;
} catch (e) { /* ignore */ }
return JSON.stringify(out);
