/* Test the HELP MENU BUTTONS, not the views behind them.
   Last round I opened UserAgreementViewController/CustomerViewController directly
   and declared them fine -- but Help routes those taps through BaseChannel, whose
   TestChannel does not override them, so the buttons were dead. This probe fires
   the page's channel methods exactly as Help.totalTouchEvents does, then looks at
   what actually appeared. */
const out = {};
const bc = BaseChannel.getInstance();
out.channelClass = String(bc.constructor).slice(9, 40);
out.methods = {};
for (const m of ['openAgreement', 'openPrivacy', 'open_custom_service', 'logout']) {
  out.methods[m] = typeof bc[m];
  out.methods[m + '_patched'] = !!(BaseChannel.prototype.__offlineChannelInstalled);
}

function findView(key) {
  let v = null;
  (function walk(n, d) {
    if (d > 14 || !n || v) return;
    for (const c of (n.$children || [])) {
      let s = '';
      try { s = String(c.constructor); } catch (e) { }
      if (s.indexOf(key) >= 0) { v = c; return; }
      walk(c, d + 1);
      if (v) return;
    }
  })(egret.MainContext.instance.stage, 0);
  return v;
}
function texts(root) {
  const o = [];
  (function walk(n, d) {
    if (d > 14 || !n) return;
    for (const c of (n.$children || [])) {
      if (c instanceof egret.TextField && c.text) o.push(c.text);
      walk(c, d + 1);
    }
  })(root, 0);
  return o;
}

/* ---- 协议 (Help.btn_agree) ---- */
try { bc.openAgreement(); } catch (e) { out.agreementThrew = String(e && e.message); }
await new Promise((r) => setTimeout(r, 2600));
const ua = findView('UserAgreementViewSkin.exml');
out.agreement = ua ? {
  opened: true,
  textNodes: texts(ua).length,
  totalChars: texts(ua).join('').length,
  first: texts(ua).filter((t) => t.length > 6).slice(0, 2),
  state: ua.currentState,
} : { opened: false };
try { core.PageManage.getInstance().removeControl(UserAgreementViewControl, core.ViewLayerType.NoticeLayer); } catch (e) { }
await new Promise((r) => setTimeout(r, 900));

/* ---- 联系客服 (Help.btn_customer) ---- */
let svcPromise = null;
try { svcPromise = bc.open_custom_service(); } catch (e) { out.serviceThrew = String(e && e.message); }
out.serviceReturnsThenable = !!(svcPromise && typeof svcPromise.then === 'function');
if (out.serviceReturnsThenable) { out.serviceResolved = await svcPromise.then(() => true, () => false); }
await new Promise((r) => setTimeout(r, 2000));
const cv = findView('Menu/Customer.exml');
out.customer = cv ? {
  opened: true,
  texts: texts(cv).filter((t) => t.length > 3),
} : { opened: false };
try { core.PageManage.getInstance().removeControl(CustomerViewController, core.ViewLayerType.NoticeLayer); } catch (e) { }

/* ---- 退出游戏 (Help.btn_exit) ----
   Do NOT actually call it on PC: it would try to close the tab and end the probe.
   Report only what it would do. */
out.exitPlan = {
  nativeBridgePresent: !!(window.FrogNative && FrogNative.exitApp),
  willCallWindowClose: true,
  note: 'not invoked here: it closes the page and would kill the probe',
};
out.probeLog = (window.__probeLog || []).filter((l) => /shell|agreement|kefu|exit/.test(l)).slice(-6);
return JSON.stringify(out, null, 1);
