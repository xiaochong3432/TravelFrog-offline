(function () {
  var wrap = document.getElementById('__map_overlay');
  var out = { overlay: !!wrap };
  if (!wrap) return JSON.stringify(out);
  var f = document.getElementById('__map_frame');
  out.frameSrc = f ? f.getAttribute('src') : null;
  try {
    var d = f.contentDocument;
    out.frameReady = d && d.readyState;
    out.cards = d.querySelectorAll('#grid .card').length;
    out.here = d.querySelectorAll('#grid .card.here').length;
    out.museums = d.querySelectorAll('#grid .museum').length;
    out.countText = d.getElementById('count') ? d.getElementById('count').textContent : null;
    var imgs = d.querySelectorAll('#grid img');
    out.imgs = imgs.length;
    out.imgsLoaded = Array.prototype.filter.call(imgs, function (i) { return i.naturalWidth > 0; }).length;
    out.imgsHidden = Array.prototype.filter.call(imgs, function (i) { return i.style.visibility === 'hidden'; }).length;
    out.firstCard = d.querySelector('#grid .card .p') ? d.querySelector('#grid .card .p').textContent : null;
    out.hereNames = Array.prototype.map.call(d.querySelectorAll('#grid .card.here .p'),
      function (e) { return e.textContent; }).join(',');
  } catch (e) {
    out.frameErr = String(e && e.message);
  }
  return JSON.stringify(out);
})()
