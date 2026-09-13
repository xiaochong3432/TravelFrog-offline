(function () {
  function findView(root, needle, depth) {
    if (!root || depth > 12) return null;
    try {
      if (root.skinName && String(root.skinName).indexOf(needle) >= 0) return root;
    } catch (e) { }
    var kids = root.$children || null;
    if (!kids) return null;
    for (var i = 0; i < kids.length; i++) {
      var r = findView(kids[i], needle, depth + 1);
      if (r) return r;
    }
    return null;
  }
  var v = findView(egret.MainContext.instance.stage, 'Album/Album.exml', 0);
  var out = { found: !!v };
  if (!v) return JSON.stringify(out);
  out.travelMapURL = v.travelMapURL;
  out.visible = v.travelMapBtn ? v.travelMapBtn.visible : 'no btn';
  out.inLayout = v.travelMapBtn ? v.travelMapBtn.includeInLayout : 'no btn';
  try {
    var act = v.getModel(window.ActivityModel).getActivity('travelmap');
    out.activity = act ? JSON.stringify(act.params) : null;
  } catch (e) { out.activity = 'ERR ' + e.message; }
  /* where the button sits, so the tap can be aimed at it */
  if (v.travelMapBtn) {
    var g = v.travelMapBtn.localToGlobal(0, 0);
    out.btnGlobal = [Math.round(g.x), Math.round(g.y)];
    out.btnSize = [v.travelMapBtn.width, v.travelMapBtn.height];
    var c = document.getElementById('egretCanvas') || document.querySelector('canvas');
    if (c) {
      var r = c.getBoundingClientRect();
      out.canvas = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
      out.stage = [egret.MainContext.instance.stage.stageWidth, egret.MainContext.instance.stage.stageHeight];
      out.tapAt = [
        Math.round(r.left + (g.x + v.travelMapBtn.width / 2) * (r.width / egret.MainContext.instance.stage.stageWidth)),
        Math.round(r.top + (g.y + v.travelMapBtn.height / 2) * (r.height / egret.MainContext.instance.stage.stageHeight)),
      ];
    }
  }
  return JSON.stringify(out);
})()
