(function () {
  var panel = document.getElementById('__save_panel');
  var out = {};
  function save() {
    try { return JSON.parse(window.localStorage.getItem('frog.offline.save') || '{}'); }
    catch (e) { return {}; }
  }
  var s = save();
  out.after = {
    clover: s.clover, ticket: s.ticket,
    pictures: (s.pictures || []).length, name: s.name,
  };
  out.note = panel.querySelectorAll(':scope > div')[1].textContent;
  /* what the client MODELS say, i.e. is the album live too? */
  try {
    var travel = core.ModelManage.getInstance().getModel(window.TravelModel);
    out.albumCount = travel.getPictureCount ? travel.getPictureCount() : null;
  } catch (e) { out.albumErr = String(e && e.message); }
  return JSON.stringify(out);
})()
