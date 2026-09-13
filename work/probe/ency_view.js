(function () {
  /* Open the 百科 page the way the menu does and count what actually renders. */
  var out = {};
  try {
    core.PageManage.getInstance().addViewControl(window.EncyViewControl, core.ViewLayerType.WindowLayer);
    out.opened = true;
  } catch (e) {
    out.openErr = String(e && e.stack || e);
    return JSON.stringify(out);
  }
  function find(root, needle, depth) {
    if (!root || depth > 12) return null;
    try { if (root.skinName && String(root.skinName).indexOf(needle) >= 0) return root; } catch (e) { }
    var kids = root.$children || null;
    if (!kids) return null;
    for (var i = 0; i < kids.length; i++) {
      var hit = find(kids[i], needle, depth + 1);
      if (hit) return hit;
    }
    return null;
  }
  var v = find(egret.MainContext.instance.stage, 'Ency/EncySkin.exml', 0);
  out.found = !!v;
  if (!v) return JSON.stringify(out);
  out.itemList = v.itemList.length;
  out.listItems = v.list.dataProvider ? v.list.dataProvider.length : null;
  out.selected = v.list.selectedIndex;
  out.name = v.lbName ? v.lbName.text : null;
  out.subs = v.listSub.dataProvider ? v.listSub.dataProvider.length : null;
  out.desc = v.listDesc.dataProvider ? v.listDesc.dataProvider.length : null;
  out.pics = v.listPic.dataProvider ? v.listPic.dataProvider.length : null;
  out.picLength = v.picLength;
  var enabled = [];
  for (var i = 0; i < v.tab.numChildren; i++) {
    enabled.push(!!v.tab.getChildAt(i).enabled);
  }
  out.tabsEnabled = enabled;
  out.realEntries = v.itemList.filter(function (r) { return r && r.id; }).length;
  return JSON.stringify(out);
})()
