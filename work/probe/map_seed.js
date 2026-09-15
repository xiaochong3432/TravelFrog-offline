(function () {
  /* Does the persisted save actually carry the key map.html reads, and does a
     province in it really turn the card green? Seeded through localStorage, which
     is the same file the engine reloads. */
  var out = {};
  var raw = window.localStorage.getItem('frog.offline.save');
  out.saveBytes = raw ? raw.length : 0;
  var save = {};
  try { save = JSON.parse(raw || '{}'); } catch (e) { out.parseErr = String(e.message); }
  out.rootKeys = Object.keys(save).length;
  out.hasKey = Object.prototype.hasOwnProperty.call(save, 'acquireProvinces');
  out.before = save.acquireProvinces || null;

  function syncJson(url) {
    var x = new XMLHttpRequest();
    x.open('GET', url, false);
    x.send(null);
    return JSON.parse(x.responseText);
  }
  var data = syncJson('map_data.json');
  var pick = [data.provinces[0], data.provinces[2]];
  out.seed = pick.map(function (p) { return p.province + ':' + p.name; });

  save.acquireProvinces = pick.map(function (p) { return p.province; });
  window.localStorage.setItem('frog.offline.save', JSON.stringify(save));

  var f = document.getElementById('__map_frame');
  if (f) f.contentWindow.location.reload();
  out.reloaded = !!f;
  return JSON.stringify(out);
})()
