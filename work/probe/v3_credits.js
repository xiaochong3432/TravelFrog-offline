(function () {
  /* Verify the three handover changes in the live payload. */
  var out = {};
  var doc = document;

  /* 1. the rights notice's 声明人 */
  var sign = doc.querySelector('#__notice .__sign');
  out.noticeSign = sign ? sign.textContent : '(no __sign element)';
  out.noticeTitle = (function () {
    var t = doc.getElementById('__notice_title');
    return t ? t.textContent : null;
  })();

  /* 2. the help menu button label + the credits panel behind it */
  out.hasHelpClass = typeof window.Help;
  var HelpCls = window.Help;
  var opened = false;
  try {
    var h = HelpCls.getInstance();
    core.DisplayManage.getInstance().getPopupLayer().addChild(h);
    h.show();
    opened = true;
    out.helpShown = !!h.visible;
    out.btnCustomerLabel = h.btn_customer ? h.btn_customer.label : '(no btn_customer)';
    out.btnAgreeLabel = h.btn_agree ? h.btn_agree.label : '(no btn_agree)';
    out.labelDisplay = h.btn_customer && h.btn_customer.labelDisplay
      ? h.btn_customer.labelDisplay.text : null;
  } catch (e) {
    out.helpError = String(e && (e.stack || e.message));
  }
  out.helpOpened = opened;

  /* tapping it must show OUR panel, not the operator's contact screen */
  try {
    BaseChannel.getInstance().open_custom_service();
  } catch (e) {
    out.serviceError = String(e && e.message);
  }
  var panel = doc.getElementById('__credits');
  out.creditsPanel = !!panel;
  if (panel) {
    out.creditsText = panel.textContent.replace(/\s+/g, ' ').trim();
    out.creditsLines = Array.prototype.map.call(panel.querySelectorAll('div'),
      function (d) { return d.textContent; }).slice(0, 6);
    out.hasClose = !!doc.getElementById('__credits_close');
  }
  return JSON.stringify(out);
})()
