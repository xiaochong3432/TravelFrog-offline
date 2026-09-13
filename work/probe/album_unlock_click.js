(function () {
  /* The reported bug: after 解锁明信片 the album showed blank/transparent cards until a
     restart. A card is drawn from `layers`, so check the client's own model. */
  var out = {};
  var panel = document.getElementById('__save_panel');
  var target = null;
  Array.prototype.some.call(panel.querySelectorAll('button'), function (b) {
    if (b.textContent === '解锁全部明信片') { target = b; return true; }
    return false;
  });
  out.pressed = !!target;
  if (target) target.click();
  return JSON.stringify(out);
})()
