(function () {
  var out = {};
  try {
    out.hasEngine = typeof window.FrogEngine;
    out.hasCreate = !!(window.FrogEngine && window.FrogEngine.createEngine);
    var e = window.FrogEngine.createEngine({ savePath: 'save.json' });
    out.created = !!e;
    out.api = Object.keys(e).slice(0, 12);
    var s = e.exportSave();
    out.exported = s && typeof s === 'object';
    s.clover = 7777;
    var wrote = e.importSave(s);
    out.importOk = wrote;
    out.stored = window.localStorage.getItem('frog.offline.save') ?
      JSON.parse(window.localStorage.getItem('frog.offline.save')).clover : null;
  } catch (err) {
    out.error = String(err && (err.stack || err.message || err));
  }
  return JSON.stringify(out);
})()
