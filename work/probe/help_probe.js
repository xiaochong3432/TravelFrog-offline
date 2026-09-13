/* The user asked whether 协议 / 联系客服 / 礼包码兑换 are now dead. Check each one
   by actually opening it and reading what rendered -- not by reading the code. */
const out = {};

function openAndRead(ctrl, skinKey, waitMs) {
  return new Promise(async (resolve) => {
    const before = snapshot();
    try {
      core.PageManage.getInstance().addViewControl(ctrl, core.ViewLayerType.NoticeLayer);
    } catch (e) {
      resolve({ error: 'addViewControl threw: ' + (e && e.message) });
      return;
    }
    await new Promise((r) => setTimeout(r, waitMs));
    const view = findView(skinKey);
    const texts = view ? collectText(view) : [];
    resolve({
      opened: !!view,
      textCount: texts.length,
      totalChars: texts.join('').length,
      sample: texts.filter((t) => t.length > 3).slice(0, 6),
      before, 
    });
    try { core.PageManage.getInstance().removeControl(ctrl, core.ViewLayerType.NoticeLayer); } catch (e) { }
  });
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
function collectText(root) {
  const out = [];
  (function walk(n, d) {
    if (d > 14 || !n) return;
    for (const c of (n.$children || [])) {
      if (c instanceof egret.TextField && c.text) out.push(c.text);
      walk(c, d + 1);
    }
  })(root, 0);
  return out;
}
function snapshot() { return 'n/a'; }

out.globals = Object.keys(window).filter((k) => /^(UserAgreement|Customer|Custom|Cdkey)/.test(k));
out.remoteArgsCustomer = (GameConfig.remoteArgs && GameConfig.remoteArgs.customer) || null;

/* resolve the controller classes by whatever name they actually have */
const UA = window.UserAgreementViewControl || window.UserAgreementViewController;
const CU = window.CustomerViewController || window.CustomerViewControl;
const CK = window.CdkeyViewController || window.CdkeyViewControl;
out.using = { UA: typeof UA, CU: typeof CU, CK: typeof CK };

/* 协议 */
out.userAgreement = UA ? await openAndRead(UA, 'UserAgreementViewSkin.exml', 2500) : 'no class';
/* 联系客服 */
out.customer = CU ? await openAndRead(CU, 'Menu/Customer.exml', 2000) : 'no class';
/* 礼包码兑换 */
out.cdkey = CK ? await openAndRead(CK, 'Cdkey', 2000) : 'no class';

/* does the newcomer code path exist in the shipped table? */
out.beginnerCodes = (() => {
  try {
    const t = Tabikaeru.DataManager.instance().calendarData.get('beginner');
    return Object.keys(t).map((k) => ({ day: k, code: t[k].code, item: t[k].item_id }));
  } catch (e) { return 'ERR ' + e.message; }
})();
out.createDay = (() => { try { return core.ModelManage.getInstance().getModel(RoleModel).getCreateDay(); } catch (e) { return 'ERR'; } })();

return JSON.stringify(out, null, 1);
