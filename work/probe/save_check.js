(function () {
  var e = window.__engine;
  if (!e) return { error: 'no engine yet' };
  var K = 'frog.offline.save';
  var text = document.body.innerText || '';
  /* open the ball -> 存档编辑 panel -> press 存档状态, then read what it printed */
  var panelText = '';
  try {
    var ball = document.getElementById('__save_ball');
    if (ball) {
      ball.click();
      var panel = document.getElementById('__save_panel');
      var btns = panel ? panel.querySelectorAll('button') : [];
      for (var i = 0; i < btns.length; i++) {
        if (btns[i].textContent === '存档状态') { btns[i].click(); break; }
      }
      panelText = panel ? (panel.innerText || '') : '';
    }
  } catch (err) { panelText = 'panel error: ' + err; }
  return {
    clover: e.state.clover,
    name: e.state.name,
    report: e.state.__saveReport,
    info: (typeof e.saveInfo === 'function') ? e.saveInfo() : null,
    bannerShown: text.indexOf('已经自动从') >= 0,
    bannerExcerpt: text.slice(0, 300),
    panelShowsLocation: panelText.indexOf('主档：') >= 0,
    panelExcerpt: panelText.slice(panelText.indexOf('主档：'), panelText.indexOf('主档：') + 260),
    keys: Object.keys(localStorage).filter(function (k) { return k.indexOf(K) === 0; }),
  };
})()
