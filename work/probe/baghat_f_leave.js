/* 出屋（= 点"出门"），等 MainOut 真正装上，再读 MainIn 那个**视图实例**的帽子状态。
   这一步证明"帽子还在"是那个缓存的 MainInView 实例没有被重算，而不是什么常驻元素。 */
(function () {
  var pm = core.PageManage.getInstance();
  var L = core.ViewLayerType.SceneLayer, HR = core.RemoveViewType.HideBefore;
  var out = {};
  var vBefore = null;
  var c0 = pm.getControl(MainInController, L);
  vBefore = c0 ? c0.getView() : null;
  out.beforeLeave = {
    viewFound: !!vBefore,
    frogCap_visible: vBefore && vBefore.frogCap ? vBefore.frogCap.visible : 'no-view',
  };
  pm.addViewControl(MainOutController, L, HR);
  var t0 = Date.now();
  return new Promise(function (resolve) {
    var iv = setInterval(function () {
      var outCtl = pm.getControl(MainOutController, L);
      if ((outCtl && outCtl.getView()) || Date.now() - t0 > 12000) {
        clearInterval(iv);
        out.waitedForCourtyardMs = Date.now() - t0;
        var c1 = pm.getControl(MainInController, L);
        var v1 = c1 ? c1.getView() : null;
        out.afterLeave = {
          courtyardViewOnStage: !!(outCtl && outCtl.getView() && outCtl.getView().stage),
          sameMainInInstance: !!v1 && v1 === vBefore,
          mainInViewStillOnStage: !!(v1 && v1.stage),
          frogCap_visible: v1 && v1.frogCap ? v1.frogCap.visible : 'no-view',
        };
        resolve(JSON.stringify(out, null, 1));
      }
    }, 250);
  });
})()
