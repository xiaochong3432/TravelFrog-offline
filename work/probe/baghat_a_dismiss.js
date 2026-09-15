/* 关掉权利声明遮罩（不点它游戏画面虽然也在跑，但截图会被黑底盖住）。 */
(function () {
  var n = document.getElementById('__notice');
  if (!n) return JSON.stringify({ notice: 'already gone', dismissed: window.__noticeDismissed });
  var btn = document.getElementById('__notice_ok') || n.querySelector('button');
  if (!btn) return JSON.stringify({ notice: 'present but no button' });
  btn.click();
  return JSON.stringify({
    notice: 'clicked',
    gone: !document.getElementById('__notice'),
    dismissed: window.__noticeDismissed,
    href: location.href,
  });
})()
