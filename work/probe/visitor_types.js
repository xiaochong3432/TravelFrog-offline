/* Which visitor view classes exist as globals, and does the visitor view render?

Tapping a visitor at the door calls `VisitorViewController` (and the gift paper calls
`VisitorGiftViewController`). If one of those renders black in this build, that is the
reported "black screen with an X". This reports which names resolve, then opens them. */
const out = { types: {} };
const names = ['VisitorViewController', 'VisitorGiftViewController', 'VisitorView',
  'VisitorGiftView', 'InviteView', 'FurnitureBenchView', 'TravelNoteController',
  'TravelMapController', 'WebViewController', 'PublicityMapViewControl'];
for (const n of names) {
  let t = 'undefined';
  try { t = typeof eval(n); } catch (e) { t = 'ERR'; }
  out.types[n] = t;
}

const openOne = (name) => {
  try {
    const cls = eval(name);
    core.PageManage.getInstance().addViewControl(cls, core.ViewLayerType.WindowLayer);
    return 'opened';
  } catch (e) {
    return 'THREW ' + String(e && e.message || e);
  }
};
out.openVisitor = out.types.VisitorViewController === 'function'
  ? openOne('VisitorViewController') : 'skipped';
return JSON.stringify(out);
