/* StartGatherClover 的推进条件（客户端源码）：
     if (guideStep == StartGatherClover) {
       收的这棵 element == 1（四叶草）-> guideCallback() 推进
       台上 viewList 收空            -> guideCallbackComplete() 推进
     }
   所以要收的是"引导台上那几棵"，走它自己的 onRequestHarves（touch 路径调的就是它）。 */
(function () {
  var U = core.ModelManage.getInstance().getModel(UserModel);
  var out = { step: U.getClientSettings().guideStep };

  function walk(node, depth, acc) {
    if (!node || depth > 12) return acc;
    acc.push(node);
    var kids = node.$children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc);
    return acc;
  }
  var all = walk(egret.MainContext.instance.stage, 0, []);
  var target = all.find(function (n) { return n && typeof n.onRequestHarves === 'function'; });
  out.found = !!target;
  if (!target) return JSON.stringify(out);

  var vl = target.viewList || [];
  out.viewListLen = vl.length;
  out.infos = vl.map(function (v) { return v && v.info ? (v.info.clover_id + ':el' + v.info.element) : '-'; });

  var asked = 0;
  for (var i = vl.length - 1; i >= 0; i--) {
    try { target.onRequestHarves(vl[i].info); asked++; } catch (e) { out.err = String(e && e.message); }
  }
  out.asked = asked;
  out.stepAfterAsk = U.getClientSettings().guideStep;
  return JSON.stringify(out);
})()