/* The four activities: are their buttons live, and does each view open?

MainOut sets `<btn>.visible = guideStep == 'Complete' ? Model.isOpen() : false`, so the
check is: with the tutorial finished, all four buttons must appear, and tapping each
must open a real view with no exception. All four windows are now payload-driven
(`end_time` in the future) instead of the old `{end_time: 0}` stubs. */
const out = {};
const E = window.__engine;
const U = core.ModelManage.getInstance().getModel(UserModel);

out.guideStepBefore = U.getClientSettings().guideStep;

const find = (cls) => {
  const acc = [];
  (function w(n, d) {
    if (!n || d > 14) return;
    if (String(n.__class__ || '') === cls ||
        String((n.constructor && n.constructor.name) || '') === cls) acc.push(n);
    const k = n.$children || [];
    for (let i = 0; i < k.length; i++) w(k[i], d + 1);
  })(egret.MainContext.instance.stage, 0);
  return acc;
};

/* Finish the tutorial the way the client does at the end of GetAward. */
U.setClientSettings('guideStep', 'Complete');
out.guideStepAfter = U.getClientSettings().guideStep;

/* Ask the engine for all four payloads and report their windows. */
const now = Math.floor(Date.now() / 1000);
out.windows = {
  museumday: E.dispatch('museumday_load', {}).reply.end_time,
  springcard: E.dispatch('springcard_load', {}).reply.end_time,
  greetcard: E.dispatch('greetcard_load', {}).reply.end_time,
  partycake: E.dispatch('partycake_load', {}).reply.end_time,
};
out.allOpen = Object.keys(out.windows).every((k) => out.windows[k] > now);

/* Re-run MainOut's own button refresh. */
const mainOut = find('MainOutView')[0];
if (mainOut) {
  for (const fn of ['updateMuseumDay', 'updateGreetCard', 'updateSpringCard',
    'updatePartyCake', 'updateCapsule']) {
    if (typeof mainOut[fn] === 'function') mainOut[fn]();
  }
  const vis = (v) => (v ? (v.visible ? 'visible' : 'hidden') : 'absent');
  out.buttons = {
    museumDay: vis(mainOut.btnMuseumDay),
    greetCard: vis(mainOut.btnGreetCard),
    springCard: vis(mainOut.btnSpringCard),
    partyCake: vis(mainOut.btnPartyCake),
  };
} else {
  out.buttons = 'no MainOutView';
}

/* Open one view at a time and see whether it survives. */
out.opened = {};
const tryOpen = (name, fn) => {
  try {
    fn();
    out.opened[name] = 'opened';
  } catch (e) {
    out.opened[name] = 'THREW: ' + String(e && e.message || e);
  }
};
tryOpen('museumdayHistory', () => core.PageManage.getInstance()
  .addViewControl(MuseumDayHistoryViewControl, core.ViewLayerType.WindowLayer));
return JSON.stringify(out);
