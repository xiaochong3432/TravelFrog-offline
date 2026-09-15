/* 决定性判据：画面上到底有没有渲染"新家具"的贴图。
   Egret 里贴图对象带 texture.textureName，直接按名字找 xw10/xw101（我们并进来的新素材）。 */
(function () {
  var out = { hits: [], total: 0, textureNames: [] };
  function walk(node, depth, acc) {
    if (!node || depth > 16) return acc;
    acc.push(node);
    var kids = node.$children || [];
    for (var i = 0; i < kids.length; i++) walk(kids[i], depth + 1, acc);
    return acc;
  }
  var all = walk(egret.MainContext.instance.stage, 0, []);
  var clsOf = function (n) { return String(n.__class__ || (n.constructor && n.constructor.name) || ''); };

  all.forEach(function (n) {
    var names = [];
    try {
      if (n.texture) {
        names.push(String(n.texture.textureName || n.texture.name || ''));
        if (n.texture.$bitmapData && n.texture.$bitmapData.name) names.push(String(n.texture.$bitmapData.name));
      }
      if (typeof n.source === 'string') names.push(n.source);
    } catch (e) { /* ignore */ }
    names.forEach(function (nm) {
      if (!nm) return;
      out.total++;
      if (out.textureNames.length < 25) out.textureNames.push(clsOf(n) + ':' + nm);
      if (/xw10_|xw101_/.test(nm)) {
        var p = n.localToGlobal ? n.localToGlobal(0, 0) : { x: -1, y: -1 };
        out.hits.push({ cls: clsOf(n), name: nm, x: Math.round(p.x), y: Math.round(p.y), visible: n.visible !== false });
      }
    });
  });
  /* 资源组：客户端摆放后会建 furniture_home 组 */
  try {
    out.hasRes_xw10 = RES.hasRes('xw10_1_1_png') && RES.hasRes('xw10_25_1_png');
    var sheet = RES.getRes('furniture_xw1_json');
    out.sheetFrames = sheet && sheet.getTexture ? ['xw10_1_png', 'xw10_25_png', 'xw101_4_png']
      .map(function (k) { return k + '=' + !!sheet.getTexture(k); }) : 'no sheet';
  } catch (e) { out.resErr = String(e && e.message); }
  return JSON.stringify(out, null, 1);
})()