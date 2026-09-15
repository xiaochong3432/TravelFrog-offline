(function () {
  var ball = document.getElementById('__save_ball');
  var panel = document.getElementById('__save_panel');
  var out = { ball: !!ball, panel: !!panel };
  if (ball) {
    var r = ball.getBoundingClientRect();
    out.ballRect = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
    out.saved = window.localStorage.getItem('frog.offline.ball');
    out.title = ball.title;
  }
  if (panel) {
    out.panelShown = panel.style.display === 'block';
    out.panelLeft = panel.style.left;
    out.panelTop = panel.style.top;
    out.panelScrollH = panel.scrollHeight;
    out.labels = Array.prototype.map.call(panel.querySelectorAll('button'),
      function (b) { return b.textContent; });
    out.hasNameInput = !!panel.querySelector('input[type=text]');
    out.noteText = panel.querySelectorAll(':scope > div')[1].textContent;
  }
  out.window = [window.innerWidth, window.innerHeight];
  return JSON.stringify(out);
})()
