(function () {
  var out = {};
  var st = egret.MainContext.instance.stage;
  out.window = [window.innerWidth, window.innerHeight];
  out.stage = [st.stageWidth, st.stageHeight];
  out.scaleMode = st.scaleMode;
  out.dataScaleMode = document.documentElement.getAttribute('data-scale-mode');
  var c = document.querySelector('canvas');
  var r = c.getBoundingClientRect();
  out.canvasCss = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
  out.canvasAttr = [c.width, c.height];
  /* where does stage (0,0) and (stageWidth,stageHeight) land in CSS px? Use a UI node
     that we can also locate in the DOM-free world: the stage's own scaleX/scaleY. */
  out.stageScale = [st.scaleX, st.scaleY];

  /* the courtyard view: its design-space bounds tell us the content column */
  function find(root, needle, depth) {
    if (!root || depth > 10) return null;
    try { if (root.skinName && String(root.skinName).indexOf(needle) >= 0) return root; } catch (e) { }
    var kids = root.$children || null;
    if (!kids) return null;
    for (var i = 0; i < kids.length; i++) {
      var hit = find(kids[i], needle, depth + 1);
      if (hit) return hit;
    }
    return null;
  }
  var g = find(st, 'MainOut', 0) || find(st, 'Scene', 0) || find(st, 'main', 0);
  if (g) {
    out.viewSkin = String(g.skinName);
    out.viewBounds = [g.x, g.y, g.width, g.height];
    try {
      var gp = g.localToGlobal(0, 0);
      out.viewGlobal = [Math.round(gp.x), Math.round(gp.y)];
    } catch (e) { }
  } else {
    var kids = [];
    for (var i = 0; i < st.numChildren && i < 6; i++) {
      var ch = st.getChildAt(i);
      kids.push((ch.__class__ || ch.constructor && ch.constructor.name || '?') + ':' + ch.width);
    }
    out.topChildren = kids;
  }
  return JSON.stringify(out);
})()
