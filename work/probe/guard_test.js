/* Does the new net turn "black window + X" into a named toast?

`VisitorViewController` opened with NO visitor data is the exact repro of the reported
shape: the skin goes up, `VisitorView.open()` throws on `data.title`/`.name`, and the
player is left staring at a black panel. With the shell's new guard the view must be
closed again and a toast must name the skin. */
const out = {};
const M = core.ModelManage.getInstance();
const VM = M.getModel(VisitorModel);

/* make sure there is no visitor so the view really does throw */
out.hadVisitor = !!VM.getVisitorData();
VM.visitorData = null;

window.__probeLog.length = 0;
let result = 'no-throw';
try {
  const r = core.PageManage.getInstance().addViewControl(VisitorViewController,
    core.ViewLayerType.WindowLayer);
  result = r === null ? 'guard-returned-null' : 'opened-normally';
} catch (e) {
  result = 'THREW OUT TO CALLER ' + String(e && e.message || e);
}
out.result = result;

/* what did the shell log, and is a toast on screen? */
out.log = (window.__probeLog || []).filter((e) => e && String(e.tag || '').indexOf('view-failed') >= 0)
  .map((e) => String(e.text || e).slice(0, 200));
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
out.visitorViewLeftOnStage = find('VisitorView').length;
return JSON.stringify(out);
