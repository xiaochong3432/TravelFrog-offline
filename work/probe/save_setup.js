(function () {
  var e = window.__engine;
  if (!e) return { error: 'no engine yet' };
  var K = 'frog.offline.save';
  var B = K + '::save.json.bak';
  var out = { start: e.state.clover };
  e.dispatch('client_gm', { cmd: 'set_clover 1234' });
  out.save1 = e.save();
  out.after1 = { clover: e.state.clover, primaryLen: localStorage.getItem(K).length, bak: localStorage.getItem(B) != null };
  e.dispatch('client_gm', { cmd: 'set_clover 4321' });
  out.save2 = e.save();
  out.after2 = {
    clover: e.state.clover,
    primaryClover: JSON.parse(localStorage.getItem(K)).clover,
    bakClover: JSON.parse(localStorage.getItem(B)).clover,
    tmp: localStorage.getItem(K + '::save.json.tmp') != null,
  };
  out.keys = Object.keys(localStorage).filter(function (k) { return k.indexOf(K) === 0; });
  out.report = e.state.__saveReport;
  out.bannerShowing = !!document.querySelector('div[style*="2147483646"]');
  return out;
})()
