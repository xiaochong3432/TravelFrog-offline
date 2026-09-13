/* Open each activity's own view in turn and count what rendered.

The four windows are payload-driven now, so this is the check that each opens with a
real body instead of the old closed stub. Views are opened through PageManage (the
same call the button handler makes) and removed again so the next one starts clean. */
const out = {};
const find = (cls) => {
  const acc = [];
  (function w(n, d) {
    if (!n || d > 14) return;
    if (String(n.__class__ || '') === cls) acc.push(n);
    const k = n.$children || [];
    for (let i = 0; i < k.length; i++) w(k[i], d + 1);
  })(egret.MainContext.instance.stage, 0);
  return acc;
};
const countNodes = () => find('eui.Image').length + find('eui.Label').length;

const V = core.ViewLayerType.WindowLayer;
const open = (name, cls) => {
  const before = countNodes();
  try {
    core.PageManage.getInstance().addViewControl(cls, V);
    out[name] = { ok: true, nodesBefore: before, nodesAfter: countNodes() };
  } catch (e) {
    out[name] = { ok: false, error: String(e && e.message || e) };
  }
  try { core.PageManage.getInstance().removeControl(cls, V); } catch (e) { /* ignore */ }
};

out.order = [];
open('greetCard', GreetCardViewControl);
open('springCard', SpringCardViewControl);
open('partyCake', PartyCakeViewControl);
open('museumDayExplore', MuseumDayExploreViewControl);
open('capsule', CapsuleViewControl);

/* Leave the cake open for the screenshot (the driver takes it next). */
try {
  core.PageManage.getInstance().addViewControl(PartyCakeViewControl, V);
  out.leftOpen = 'partyCake';
} catch (e) {
  out.leftOpen = 'THREW ' + String(e && e.message || e);
}
return JSON.stringify(out);
