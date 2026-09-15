(function () {
  /* Simulate the APK's JavascriptInterface, then press 导出存档 three ways. */
  var out = { phases: [] };
  var panel = document.getElementById('__save_panel');
  function note() { return panel.querySelectorAll(':scope > div')[1].textContent; }
  function press(label) {
    var t = null;
    Array.prototype.some.call(panel.querySelectorAll('button'), function (b) {
      if (b.textContent === label) { t = b; return true; }
      return false;
    });
    if (t) t.click();
    return !!t;
  }
  document.getElementById('__save_ball').click();
  out.pressed = press('导出存档');       /* PC path first: no bridge yet */
  out.phases.push({ what: 'no-bridge-blob', note: note() });

  var calls = [];
  window.FrogNative = {
    platform: function () { return 'android'; },
    exportSave: function (name, json) {
      calls.push({ name: name, bytes: String(json).length });
      return '内部存储/Download/' + name;      /* API 29+ answer */
    },
  };
  press('导出存档');
  out.phases.push({ what: 'bridge-location', note: note(), calls: calls.slice() });

  calls.length = 0;
  window.FrogNative.exportSave = function (name, json) {
    calls.push({ name: name, bytes: String(json).length });
    return 'PICKER';                            /* older Android: dialog opened */
  };
  press('导出存档');
  out.phases.push({ what: 'bridge-picker', note: note() });

  /* ...and the dialog's answer arrives later through the callback */
  if (window.__saveExported) window.__saveExported('内部存储/Download/选好的位置.json');
  out.phases.push({ what: 'picker-answered', note: note() });

  /* cancel / failure must NOT read as success */
  if (window.__saveExportFailed) window.__saveExportFailed('已取消');
  out.phases.push({ what: 'cancelled', note: note() });

  window.FrogNative.exportSave = function () { return ''; };
  press('导出存档');
  out.phases.push({ what: 'bridge-failed', note: note() });

  out.hasCallbacks = {
    exported: typeof window.__saveExported,
    failed: typeof window.__saveExportFailed,
  };
  delete window.FrogNative;
  return JSON.stringify(out);
})()
