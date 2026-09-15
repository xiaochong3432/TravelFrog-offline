/* New-account experience: does a brand-new save really start at 起名?

The engine now reports guideStep = 'New' for a fresh save (the client's own
SettingsInfo default). This walks the two client-driven steps a player sees first
-- the welcome screen and the naming screen -- using the views' OWN tap handlers,
then watches the guide advance on its own (PrepareGatherClover auto-advances after
its tween; StartGatherClover auto-advances when no clover is ready).

It also reports which of the four activity buttons are visible, because MainOut
hides them while guideStep != 'Complete'. */
const U = core.ModelManage.getInstance().getModel(UserModel);
const out = { steps: [] };
const step = () => U.getClientSettings().guideStep;
out.step0 = step();

/* --- find the guide views on the display tree, by their __reflect class name --- */
function walk(node, depth, acc) {
  if (!node || depth > 8) return acc;
  const cls = node.__class__ || (node.constructor && node.constructor.name) || '';
  acc.push({ node: node, cls: String(cls) });
  const kids = node.$children || [];
  for (let i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc);
  return acc;
}
const nodes = walk(egret.MainContext.instance.stage, 0, []);
out.classesSeen = [];
const seen = {};
for (const n of nodes) {
  if (n.cls && !seen[n.cls]) { seen[n.cls] = 1; out.classesSeen.push(n.cls); }
}
out.classesSeen = out.classesSeen.slice(0, 40);
out.nodeCount = nodes.length;

/* --- 1. the welcome screen: its own callback is what advances the guide --- */
const welcome = nodes.find((n) => /Welcome/.test(n.cls) && typeof n.node.$children !== 'undefined');
if (welcome) {
  out.welcomeFound = true;
  const w = welcome.node;
  /* WelcomeView takes the callback in its constructor; the skin's own button
     dispatches a tap that the view listens for. Tap every touch-enabled child. */
  const kids = walk(w, 0, []).map((x) => x.node);
  let tapped = 0;
  for (const k of kids) {
    if (k.touchEnabled && k.dispatchEvent) {
      try { k.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP)); tapped++; } catch (e) { /* ignore */ }
    }
  }
  out.welcomeTaps = tapped;
  out.stepAfterWelcome = step();
} else {
  out.welcomeFound = false;
}

/* --- 2. the naming screen: GuideNamedView.btn_yes is the real button --- */
const named = nodes.find((n) => /GuideNamed/.test(n.cls));
if (named) {
  out.namedFound = true;
  const v = named.node;
  try {
    v.t_name.text = '新号蛙';
    v.btn_yes.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
  } catch (e) {
    out.namedError = String(e);
  }
  out.stepAfterName = step();
} else {
  out.namedFound = false;
}

/* --- 3. what the four activity buttons look like right now --- */
try {
  out.eventButtons = {};
} catch (e) { /* ignore */ }

return JSON.stringify(out);
