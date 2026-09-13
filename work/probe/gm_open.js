(function () {
  /* The advanced console must still open from the panel: its row was rewritten. */
  var panel = document.getElementById('__save_panel');
  var out = {};
  function find(root, needle, depth) {
    if (!root || depth > 14) return null;
    try { if (root.skinName && String(root.skinName).indexOf(needle) >= 0) return root; } catch (e) { }
    var kids = root.$children || null;
    if (!kids) return null;
    for (var i = 0; i < kids.length; i++) {
      var hit = find(kids[i], needle, depth + 1);
      if (hit) return hit;
    }
    return null;
  }
  out.beforeGM = !!find(egret.MainContext.instance.stage, 'Gm/GM.exml', 0);
  var btn = null;
  Array.prototype.some.call(panel.querySelectorAll('button'), function (b) {
    if (b.textContent === '指令台（高级）') { btn = b; return true; }
    return false;
  });
  if (btn) btn.click();
  var gm = find(egret.MainContext.instance.stage, 'Gm/GM.exml', 0);
  out.opened = !!gm;
  if (gm) {
    out.hasInput = !!gm.t_context;
    out.prompt = gm.t_context ? gm.t_context.prompt : null;
    out.panelHidden = panel.style.display === 'none';
  }
  return JSON.stringify(out);
})()
