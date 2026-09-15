/* Real-page proof of the album layer contract (v2).

   Hooks egret.RenderTexture.prototype.drawToTexture -- the single call the
   client's own album renderer makes:
       Tabikaeru.getPictureTexture(pic, scale)
         -> container.removeChildren()
         -> for each layer: new egret.Bitmap, texture = RES.getRes(PIC_PATH(resId)),
            bitmap.x = layer[1], bitmap.y = layer[2], container.addChild(bitmap)
         -> drawToTexture(container, new egret.Rectangle(0,0,500,350), scale)
   The hook records the container's children (x, y, w, h, texture name) BEFORE
   delegating, so the numbers are exactly what the shipped client computed.

   Textures must be preloaded first (Tabikaeru.loadPicture), otherwise getRes
   returns null and the client bails out with `return null` before drawing. */
(async function () {
  var out = { hook: false, notes: [] };
  window.__layerDraws = [];

  if (!window.__rtHooked) {
    window.__rtHooked = true;
    var RT = egret.RenderTexture.prototype;
    var orig = RT.drawToTexture;
    RT.drawToTexture = function (disp, rect, scale) {
      try {
        if (disp && disp.$children && disp.$children.length) {
          window.__layerDraws.push({
            rect: rect ? [rect.x, rect.y, rect.width, rect.height] : null,
            scale: (scale === undefined ? 1 : scale),
            kids: disp.$children.map(function (c) {
              return {
                x: c.x, y: c.y, w: c.width, h: c.height,
                t: String((c.texture && (c.texture.textureName || c.texture.name)) || '')
              };
            })
          });
        }
      } catch (e) { out.notes.push('hook: ' + e); }
      return orig.apply(this, arguments);
    };
    out.hook = true;
  }

  var eng = window.__engine;
  if (!eng) { out.err = 'no window.__engine'; return JSON.stringify(out); }

  var rep = eng.dispatch('album_load', { start: 1 }).reply;
  out.albumSizeBefore = (rep.pictures || []).length;
  try {
    var gm = eng.dispatch('client_gm', { cmd: 'unlock_pictures' }).reply;
    out.gm = gm && (gm.info || gm.succeed);
  } catch (e) { out.notes.push('gm: ' + e); }
  rep = eng.dispatch('album_load', { start: 1 }).reply;
  out.albumSize = (rep.pictures || []).length;

  var want = [100, 104, 205, 2134];
  var byPic = {};
  (rep.pictures || []).forEach(function (p) {
    if (want.indexOf(p.pic_id) >= 0 && !byPic[p.pic_id]) byPic[p.pic_id] = p;
  });
  out.found = Object.keys(byPic).map(Number);
  out.layersFromEngine = {};
  Object.keys(byPic).forEach(function (k) { out.layersFromEngine[k] = byPic[k].layers; });

  out.clientDraw = {};
  var keys = Object.keys(byPic);
  for (var i = 0; i < keys.length; i++) {
    var k = keys[i], pic = byPic[k];
    try {
      await Tabikaeru.loadPicture(pic);          /* preload the textures */
      var before = window.__layerDraws.length;
      var tex = Tabikaeru.getPictureTexture(pic, 2);   /* scale 2 => no cache */
      out.clientDraw[k] = {
        gotTexture: !!tex,
        rect: window.__layerDraws.length > before
          ? window.__layerDraws[window.__layerDraws.length - 1].rect : null,
        kids: window.__layerDraws.length > before
          ? window.__layerDraws[window.__layerDraws.length - 1].kids : null
      };
    } catch (e) { out.clientDraw[k] = { err: String(e && e.message) }; }
  }
  return JSON.stringify(out);
})()
