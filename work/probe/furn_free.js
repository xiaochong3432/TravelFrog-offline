/* Exercise the exact call the 分享拿福利 button makes.
   FurnitureAdsView.showShare() -> shareCallback() -> (Test channel) n(true) +
   AdsModel.req_share(4); n(true) is FurnitureModel.requestBuy(shop_id). Run that
   buy step against the live engine and report whether the good is actually
   granted, or whether the call dies somewhere. */
const fm = core.ModelManage.getInstance().getModel(FurnitureModel);
const um = core.ModelManage.getInstance().getModel(UserModel);
const im = core.ModelManage.getInstance().getModel(ItemModel);

const out = {
  cloverBefore: um.getClover(),
  itemId: 20101,
  ownedBefore: im.getHaveItem(20101),
  shopRow: null,
};

const db = Tabikaeru.DataManager.instance().FurnitureShopDB;
const row = db.get(7003);
out.shopRow = row ? { item_id: row.item_id, price: row.price, type: row.type, limit: row.limit, shop_limit: row.shop_limit } : null;

/* send exactly what requestBuy sends, and capture the raw reply */
out.rawReply = await new Promise((resolve) => {
  core.SocketManage.getInstance().send('furniture_buy_shop',
    new core.Action2(function (r) { resolve(r); }), 7003);
  setTimeout(() => resolve('<no reply within 3s>'), 3000);
});

/* now the real client path, to see whether ITS callback fires */
out.clientCallbackFired = await new Promise((resolve) => {
  let done = false;
  try {
    fm.requestBuy(7003, new core.Action1(function () { done = true; resolve(true); }));
  } catch (e) {
    resolve('THREW ' + (e && e.message));
  }
  setTimeout(() => { if (!done) resolve(false); }, 3000);
});

out.cloverAfter = um.getClover();
out.ownedAfter = im.getHaveItem(20101);
out.engineLog = (window.__probeLog || []).filter((l) => /furniture_buy_shop|广告|adsmgr|share/.test(l)).slice(-6);
return JSON.stringify(out, null, 1);
