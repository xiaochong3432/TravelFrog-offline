/* Verify the three button families the user reported as dead:
     (a) 充值   -- RechargeModel.pay(packId) -> BaseChannel.pay(shopID)
     (b) 分享   -- AdsModel.req_share(type, cb)
     (c) 免费商品 -- furniture welfare goods (separate probe)
   Everything is read back from the live client, not from the engine's own logs. */
const um = core.ModelManage.getInstance().getModel(UserModel);
const rm = core.ModelManage.getInstance().getModel(RechargeModel);
const am = core.ModelManage.getInstance().getModel(AdsModel);

const out = { steps: [] };
const log = () => (window.__probeLog || []).slice(-40);

out.showPay = um.getShowPay();
out.cloverBefore = um.getClover();

/* ---- (b) the share/ad payload the client receives ---- */
out.adsBefore = JSON.parse(JSON.stringify(am.data));
out.canPopAds = am.canPopAds();

/* ---- (a) 充值: pay pack 1 (shopID 1001, 400 clover) ---- */
const payResult = await new Promise((resolve) => {
  let n = 0;
  const t = setInterval(() => {
    n++;
    if (um.getClover() !== out.cloverBefore) { clearInterval(t); resolve('reward credited after ' + n * 100 + 'ms'); }
    if (n > 40) { clearInterval(t); resolve('NO CHANGE after 4s'); }
  }, 100);
  try {
    rm.pay(1);
    out.steps.push('rm.pay(1) called');
  } catch (e) {
    clearInterval(t);
    resolve('THREW ' + (e && e.message));
  }
});
out.payOutcome = payResult;
out.cloverAfter = um.getClover();
out.rechargeData = JSON.parse(JSON.stringify(rm.data));

/* ---- (b) 分享: type 2 (the AdsGift popup's share button) ---- */
const shareResult = await new Promise((resolve) => {
  core.SocketManage.getInstance().send('adsmgr_share',
    new core.Action2(function (r) { resolve(r); }), 2);
  setTimeout(() => resolve('<no reply within 3s>'), 3000);
});
out.shareReply = shareResult;
out.giftGetAfterShare = am.data.gift_get;
out.mailsAfterShare = im_mailCount();
function im_mailCount() {
  try { return core.ModelManage.getInstance().getModel(TravelModel).getMailList().length; } catch (e) { return 'ERR ' + e.message; }
}

/* reload the ad payload the way the client does at boot */
const loadReply = await new Promise((resolve) => {
  core.SocketManage.getInstance().send('adsmgr_load',
    new core.Action2(function (r) { resolve(r); }), );
  setTimeout(() => resolve('<no reply within 3s>'), 3000);
});
out.adsLoadReply = loadReply;
out.adsAfter = JSON.parse(JSON.stringify(am.data));

out.log = log().filter((l) => /\[pay\]|\[shell\]|recharge|adsmgr|邮箱/.test(l));
return JSON.stringify(out, null, 1);
