(function () {
  var out = { w: window.innerWidth, h: window.innerHeight, dpr: window.devicePixelRatio };
  var ball = document.getElementById('__save_ball');
  out.ball = !!ball;
  if (ball) {
    var r = ball.getBoundingClientRect();
    out.rect = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
    var cs = window.getComputedStyle(ball);
    out.style = { display: cs.display, visibility: cs.visibility, opacity: cs.opacity, z: cs.zIndex,
                  position: cs.position };
    var cx = Math.round(r.left + r.width / 2), cy = Math.round(r.top + r.height / 2);
    var top = document.elementFromPoint(cx, cy);
    out.topAt = top ? (top.id || top.tagName + '.' + top.className) : null;
    out.hit = top === ball || (ball.contains(top));
    out.inViewport = r.left >= 0 && r.top >= 0 && r.right <= window.innerWidth && r.bottom <= window.innerHeight;
  }
  var panel = document.getElementById('__save_panel');
  out.panel = !!panel;
  var c = document.querySelector('canvas');
  if (c) {
    var cr = c.getBoundingClientRect();
    out.canvas = [Math.round(cr.left), Math.round(cr.top), Math.round(cr.width), Math.round(cr.height)];
  }
  try {
    var log = window.__shellLog || window.__log || null;
    out.shellLog = log ? JSON.stringify(log).slice(0, 400) : 'no log handle';
  } catch (e) { out.shellLog = 'ERR'; }
  return JSON.stringify(out);
})()
