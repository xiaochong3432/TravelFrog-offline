(async function () {
  /* 1) B1 诊断：客户端 errcode 表里有没有 code 0（GuideNamedView 的 if (e) 依赖它）
     2) B2 验证：走客户端自己的 socket 买 家具店 1/2 号行（工具套装/材料套装），
        看 item_gift_open 是否收到、道具是否真的进了 house。 */
  var sleep = function (ms) { return new Promise(function (r) { setTimeout(r, ms); }); };
  for (var w = 0; w < 60 && !window.__engine; w++) await sleep(500);
  var out = {};

  /* --- 1) errcode 表 --- */
  try {
    var ec = RES.getRes('errcode_json');
    out.errcodeLoaded = !!ec;
    out.errcodeRows = ec ? (ec.length || Object.keys(ec).length) : 0;
    if (ec) {
      var arr = Array.isArray(ec) ? ec : Object.keys(ec).map(function (k) { return ec[k]; });
      out.codes = arr.map(function (r) { return Number(r.code); });
      out.hasCode0 = out.codes.indexOf(0) >= 0;
      out.row0 = arr.filter(function (r) { return Number(r.code) === 0; })[0] || null;
      /* 客户端自己的查表行为（这才是 GuideNamedView 真正看到的东西） */
      var mm = core.ModelManage.getInstance().getModel(MessageModel);
      out.getErrorInfo_0 = mm.getErrorInfo(0) || null;
      out.getErrorInfo_5 = mm.getErrorInfo(5) || null;
      out.getErrorInfo_61 = mm.getErrorInfo(61) || null;
    }
  } catch (e) { out.errcodeErr = String(e); }

  /* --- 2) 买 1/2 号行 --- */
  var eng = window.__engine;
  if (!eng) return out;
  eng.dispatch('client_gm', { cmd: 'set_clover 99999' });
  var sm = core.SocketManage.getInstance();
  out.buys = {};
  for (var i = 0; i < 2; i++) {
    var sid = [1, 2][i];
    var reply = null, giftOpen = null;
    /* item_gift_open 是推送：临时挂一个监听把内容记下来 */
    var origHandler = eng.state ? null : null;
    sm.send('furniture_buy_shop', new core.Action2(function (r) { reply = r; }), sid);
    await sleep(900);
    /* 主动读一次模型，确认到账 */
    var itemModel = core.ModelManage.getInstance().getModel(ItemModel);
    out.buys['row' + sid] = {
      code: reply && reply.code,
      have10201: itemModel.getHouseItemCount(10201),
      have10202: itemModel.getHouseItemCount(10202),
      have10001: itemModel.getHouseItemCount(10001),
      have5001: itemModel.getHouseItemCount(5001),
      have5002: itemModel.getHouseItemCount(5002),
      giftPopupOpen: !!core.PageManage.getInstance().getControl(GiftPackageViewController, core.ViewLayerType.NoticeLayer),
    };
  }
  /* 礼物弹窗有没有真的亮过：看它是否在控制栈里（读完就关掉） */
  var gp = core.PageManage.getInstance().getControl(GiftPackageViewController, core.ViewLayerType.NoticeLayer);
  out.giftPopupPresent = !!gp;
  if (gp) { try { core.PageManage.getInstance().removeControl(GiftPackageViewController, core.ViewLayerType.NoticeLayer); } catch (e) { } }
  return out;
})()
