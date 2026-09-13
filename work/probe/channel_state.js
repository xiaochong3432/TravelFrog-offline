/* What channel is the client running as, and what does that imply?
   ChannelType.Test (1) is the developers' own no-SDK path: every share/ad gate
   short-circuits to a direct protocol call instead of the WeChat SDK. If the
   channel is anything else, those buttons try to open the SDK and dead-end. */
const out = {};
out.channel = GameConfig.channel;
out.channelName = ['Undefined', 'Test', 'Alipay', 'Ejoy', 'WXgame', 'End'][GameConfig.channel];
out.language = GameConfig.language;
out.version = GameConfig.version;
out.quickShare = GameConfig.quickShare;
out.remoteArgs = GameConfig.remoteArgs || null;
out.serverURL = GameConfig.serverURL;
out.showAnnualReview = (() => { try { return GameConfig.getAdminConfig('showAnnualReview'); } catch (e) { return 'ERR ' + e.message; } })();
out.decorateOpen = GameConfig.decorate_open;

/* the share/ad gates the player actually touches */
out.baseChannel = (() => {
  const b = BaseChannel.getInstance();
  return {
    cls: String(b.constructor).slice(9, 40),
    supportAds: (() => { try { return b.supportAds(); } catch (e) { return 'ERR ' + e.message; } })(),
    channelId: (() => { try { return b.getChannelId(''); } catch (e) { return 'ERR'; } })(),
  };
})();

/* current AdsModel state as the client holds it */
out.adsData = (() => {
  try { return core.ModelManage.getInstance().getModel(AdsModel).data; } catch (e) { return 'ERR ' + e.message; }
})();

/* can the daily ad-gift popup appear at all? */
out.canPopAds = (() => {
  try { return core.ModelManage.getInstance().getModel(AdsModel).canPopAds(); } catch (e) { return 'ERR ' + e.message; }
})();

/* what the furniture shop currently offers, incl. the type-998 welfare rows */
out.furnShop = (() => {
  try {
    const m = core.ModelManage.getInstance().getModel(FurnitureModel);
    const list = m.getShopData().shop_list;
    return list.filter((r) => {
      const row = Tabikaeru.DataManager.instance().FurnitureShopDB.get(r.shop_id);
      return row && row.type === 998;
    }).slice(0, 6).map((r) => {
      const row = Tabikaeru.DataManager.instance().FurnitureShopDB.get(r.shop_id);
      return { shop_id: r.shop_id, item_id: r.item_id, num: r.num, type: row.type, price: row.price, limit: row.limit };
    });
  } catch (e) { return 'ERR ' + e.message; }
})();
out.furnShopOpen = (() => {
  try { return core.ModelManage.getInstance().getModel(FurnitureModel).serverData.shop; } catch (e) { return 'ERR ' + e.message; }
})();
return JSON.stringify(out, null, 1);
