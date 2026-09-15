(function () {
  /* open the 存档编辑 panel the way a player does, then press the new unlock button */
  var ball = document.getElementById('__save_ball');
  var out = { hasBall: !!ball };
  if (ball) ball.click();
  var panel = document.getElementById('__save_panel');
  out.panelShown = !!(panel && panel.style.display === 'block');
  var labels = [];
  if (panel) {
    Array.prototype.forEach.call(panel.querySelectorAll('button'), function (b) {
      labels.push(b.textContent);
    });
  }
  out.labels = labels;
  var target = null;
  if (panel) {
    Array.prototype.some.call(panel.querySelectorAll('button'), function (b) {
      if (b.textContent === '解锁图鉴+百科') { target = b; return true; }
      return false;
    });
  }
  out.pressed = !!target;
  if (target) target.click();
  return JSON.stringify(out);
})()
