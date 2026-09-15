(function () {
  var K = 'frog.offline.save';
  var B = K + '::save.json.bak';
  var v = localStorage.getItem(K);
  if (!v) return { error: 'no primary save in this origin' };
  /* What a killed browser leaves behind: a JSON document cut off mid-write. */
  var cut = v.slice(0, Math.min(60, v.length));
  localStorage.setItem(K, cut);
  return {
    damagedLen: cut.length,
    damagedHead: cut,
    primaryIsValidJson: (function () { try { JSON.parse(cut); return true; } catch (e) { return false; } })(),
    bakClover: JSON.parse(localStorage.getItem(B)).clover,
    keys: Object.keys(localStorage).filter(function (k) { return k.indexOf(K) === 0; }),
  };
})()
