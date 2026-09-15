(function () {
  var panel = document.getElementById('__save_panel');
  var out = {};
  if (!panel) return JSON.stringify({ panel: false });
  var target = null;
  Array.prototype.some.call(panel.querySelectorAll('button'), function (b) {
    if (b.textContent === '获得全部家具') { target = b; return true; }
    return false;
  });
  out.pressed = !!target;
  if (target) target.click();
  return JSON.stringify(out);
})()
