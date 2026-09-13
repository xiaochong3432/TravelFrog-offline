(function () {
  /* Same origin, same profile: truncate the stored save the way a killed browser
     or a half-finished write would, then reload so the engine boots against it. */
  var K = 'frog.offline.save';
  var v = localStorage.getItem(K);
  if (!v) return { error: 'no primary save in this origin' };
  var cut = v.slice(0, Math.min(60, v.length));
  localStorage.setItem(K, cut);
  setTimeout(function () { location.reload(); }, 60);
  return {
    damagedLen: cut.length,
    damagedHead: cut,
    reloadScheduled: true,
    keys: Object.keys(localStorage).filter(function (k) { return k.indexOf(K) === 0; }),
  };
})()
