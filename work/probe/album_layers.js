(function () {
  var out = {};
  var travel = null;
  try { travel = core.ModelManage.getInstance().getModel(window.TravelModel); }
  catch (e) { out.err = String(e && e.message); return JSON.stringify(out); }
  var list = travel.getPictureInfoList ? travel.getPictureInfoList() : [];
  out.count = travel.getPictureCount ? travel.getPictureCount() : null;
  out.entries = list.length;
  var withLayers = 0, without = 0, noLayersIds = [];
  for (var i = 0; i < list.length; i++) {
    var p = list[i];
    if (!p) continue;
    if (p.layers && p.layers.length) withLayers++;
    else { without++; if (noLayersIds.length < 12) noLayersIds.push(p.pic_id); }
  }
  out.withLayers = withLayers;
  out.withoutLayers = without;
  out.withoutPicIds = noLayersIds;
  out.note = document.getElementById('__save_panel').querySelectorAll(':scope > div')[1].textContent;
  return JSON.stringify(out);
})()
