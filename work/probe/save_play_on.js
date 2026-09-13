(function () {
  var e = window.__engine;
  if (!e) return { error: 'no engine yet' };
  var K = 'frog.offline.save';
  var text = document.body.innerText || '';
  var restored = e.state.clover;
  /* play on: one GM action through the client's own path, then confirm it landed */
  e.dispatch('client_gm', { cmd: 'add_clover 1' });
  var onDisk = null;
  try { onDisk = JSON.parse(localStorage.getItem(K)).clover; } catch (err) { onDisk = 'unreadable'; }
  return {
    restoredClover: restored,
    afterAction: e.state.clover,
    primaryClover: onDisk,
    report: e.state.__saveReport,
    bannerVisible: text.indexOf('已经自动从') >= 0,
    noticeGone: text.indexOf('我已阅读，进入游戏') < 0,
    bannerText: text.slice(text.indexOf('存档提醒'), text.indexOf('存档提醒') + 200),
  };
})()
