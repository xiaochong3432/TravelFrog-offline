(function () {
  var ok = document.getElementById('__notice_ok');
  var n = document.getElementById('__notice');
  var out = { hadOk: !!ok, hadNotice: !!n };
  if (ok) ok.click();
  out.dismissed = !!window.__noticeDismissed;
  out.noticeStillShown = !!(n && n.offsetParent !== null);
  return JSON.stringify(out);
})()
