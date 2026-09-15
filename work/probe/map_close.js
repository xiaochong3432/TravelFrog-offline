(function () {
  var b = document.getElementById('__map_close');
  var out = { hadClose: !!b };
  if (b) b.click();
  out.overlayAfter = !!document.getElementById('__map_overlay');
  /* the game must still be running behind it: same stage, same view count */
  try {
    out.stage = [egret.MainContext.instance.stage.stageWidth, egret.MainContext.instance.stage.stageHeight];
    out.views = (window.__views || []).length;
  } catch (e) { out.err = String(e && e.message); }
  return JSON.stringify(out);
})()
