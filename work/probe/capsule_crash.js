/* Reproduce the 扭蛋机 crash and capture the real stack.
   The client turns an uncaught error into Reload.JSError ("呱呱，吃坏肚子了"),
   so the error must reach window.onerror -- collect it here AND let the driver's
   Runtime.exceptionThrown subscription see it too. */
window.__errs = [];
window.addEventListener('error', function (e) {
  window.__errs.push({
    msg: e.message,
    at: (e.filename || '') + ':' + (e.lineno || 0) + ':' + (e.colno || 0),
    stack: e.error && e.error.stack ? String(e.error.stack).split('\n').slice(0, 8).join(' | ') : null,
  });
});

/* also wrap the egret entry points the client uses, so a swallowed throw shows up */
const out = { steps: [] };
function tryStep(name, fn) {
  try { fn(); out.steps.push(name + ': ok'); }
  catch (e) { out.steps.push(name + ': THREW ' + (e && e.message)); }
}

out.proto = tryStep('capsule_load', () => {
  const r = core.SocketManage.getInstance().send('capsule_load',
    new core.Action2(function (d) { out.capsuleLoad = d; }), );
  return r;
});
await new Promise((r) => setTimeout(r, 1500));
out.capsuleLoadKeys = out.capsuleLoad ? Object.keys(out.capsuleLoad) : null;
out.capsuleLoad = out.capsuleLoad || null;

/* the model the view reads */
out.modelData = (() => {
  try {
    const m = core.ModelManage.getInstance().getModel(CapsuleModel);
    return { end_time: m.data.end_time, coin: m.data.coin, patch_num: m.data.patch_num,
             task_list: m.data.task_list, reward_list: m.data.reward_list,
             isOpen: (() => { try { return m.isOpen(); } catch (e) { return 'THREW ' + e.message; } })() };
  } catch (e) { return 'ERR ' + e.message; }
})();

out.hasCtrl = typeof window.CapsuleViewControl;
out.errsBeforeOpen = window.__errs.slice();

/* THIS is what the garden button does */
out.open = tryStep('open CapsuleViewControl', () => {
  core.PageManage.getInstance().addViewControl(CapsuleViewControl, core.ViewLayerType.WindowLayer);
});
await new Promise((r) => setTimeout(r, 2500));

out.views = (window.__egretViews ? window.__egretViews() : []).map((v) => v.skin);
out.errs = window.__errs;
out.probeLogTail = (window.__probeLog || []).slice(-14);
return JSON.stringify(out, null, 1);
