(function () {
  var out = {};
  var h = null;
  try {
    h = window.Help.getInstance();
    core.DisplayManage.getInstance().getPopupLayer().addChild(h);
    h.show();
  } catch (e) { return JSON.stringify({ error: String(e && e.message) }); }
  var b = h.btn_customer;
  out.usesTexture = b ? b.source : null;
  out.visible = b ? b.visible : null;
  out.inLayout = b ? b.includeInLayout : null;
  try {
    var g = b.localToGlobal(0, 0);
    out.globalPos = [Math.round(g.x), Math.round(g.y)];
    out.size = [Math.round(b.width), Math.round(b.height)];
  } catch (e) { out.posError = String(e && e.message); }
  /* what else is on screen at the same place (are they stacked?) */
  out.siblings = [];
  try {
    var sibs = (b.parent && b.parent.$children) || [];
    for (var i = 0; i < sibs.length; i++) {
      var s = sibs[i];
      if (!s.visible) continue;
      var p = s.localToGlobal(0, 0);
      out.siblings.push({ cls: s.__class__, src: s.source || null,
        pos: [Math.round(p.x), Math.round(p.y)], size: [Math.round(s.width), Math.round(s.height)] });
    }
  } catch (e) { out.sibError = String(e && e.message); }
  out.panelSize = [Math.round(h.width), Math.round(h.height)];
  return JSON.stringify(out);
})()
