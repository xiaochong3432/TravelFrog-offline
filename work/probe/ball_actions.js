(function () {
  var panel = document.getElementById('__save_panel');
  var out = {};
  function btn(label) {
    var t = null;
    Array.prototype.some.call(panel.querySelectorAll('button'), function (b) {
      if (b.textContent === label) { t = b; return true; }
      return false;
    });
    return t;
  }
  function save() {
    try { return JSON.parse(window.localStorage.getItem('frog.offline.save') || '{}'); }
    catch (e) { return {}; }
  }
  var s0 = save();
  out.before = {
    clover: s0.clover, ticket: s0.ticket,
    pictures: (s0.pictures || []).length, name: s0.name,
  };

  var b1 = btn('解锁全部明信片');
  if (b1) b1.click();
  var b2 = btn('三叶草 +1000');
  if (b2) b2.click();

  var inp = panel.querySelector('input[type=text]');
  var b3 = btn('改名');
  if (inp && b3) { inp.value = '瓜瓜改名测试'; b3.click(); }

  out.pressed = { pictures: !!b1, clover: !!b2, rename: !!b3, hadInput: !!inp };
  return JSON.stringify(out);
})()
