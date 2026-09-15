(function () {
  var panel = document.getElementById('__save_panel');
  var out = {};
  var target = null;
  Array.prototype.some.call(panel.querySelectorAll('button'), function (b) {
    if (b.textContent === '获得全部家具') { target = b; return true; }
    return false;
  });
  if (target) target.click();
  out.pressed = !!target;
  return JSON.stringify(out);
})()
