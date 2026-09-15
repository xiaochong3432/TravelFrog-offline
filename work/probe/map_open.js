(function () {
  /* Which of the classes this fix touches are reachable from page scope? */
  var out = {
    hasAlbumController: typeof window.AlbumController,
    hasAlbumView: typeof window.AlbumView,
    hasTravelMapController: typeof window.TravelMapController,
    hasActivityModel: typeof window.ActivityModel,
    hasBaseChannel: typeof window.BaseChannel,
    noticed: !!window.__noticeDismissed,
    views: (window.__views || []).length,
  };
  try {
    out.annInfoSource = String(BaseChannel.prototype.getAnnInfo).slice(0, 120);
  } catch (e) { out.annInfoSource = 'ERR ' + e.message; }
  try {
    /* the activity request the album makes; must now answer travelmap */
    BaseChannel.getInstance().getAnnInfo({ type: 'activity', tags: ['travelmap'] }).then(function (r) {
      window.__mapAnnResult = r;
    });
    out.annCall = 'sent';
  } catch (e) { out.annCall = 'ERR ' + (e && e.message); }
  try {
    core.PageManage.getInstance().addViewControl(window.AlbumController, core.ViewLayerType.WindowLayer);
    out.opened = true;
  } catch (e) { out.opened = 'ERR ' + (e && e.stack || e); }
  return JSON.stringify(out);
})()
