/* Calibrate the tap path: report the canvas geometry and the screen point that
   __egretTap derives, then tap the save-editor button (a known, obvious target)
   so we can tell whether synthetic taps reach Egret at all. */
const cvs = document.querySelectorAll('canvas');
const dpr = window.devicePixelRatio || 1;
const info = [];
for (let i = 0; i < cvs.length; i++) {
  const c = cvs[i];
  const r = c.getBoundingClientRect();
  info.push({
    i, canvas: c.width + 'x' + c.height,
    css: Math.round(r.width) + 'x' + Math.round(r.height),
    at: Math.round(r.left) + ',' + Math.round(r.top),
    scaleX: r.width / (c.width / dpr),
  });
}
const out = {
  dpr, canvasCount: cvs.length, canvas: info,
  isMobile: egret.Capabilities.isMobile,
  os: egret.Capabilities.os,
  stage: (() => { const s = egret.MainContext.instance.stage; return Math.round(s.stageWidth) + 'x' + Math.round(s.stageHeight) + ' scale=' + s.scaleX + ',' + s.scaleY; })(),
};
/* where does the gm node live, and what does __egretTap compute for it? */
const g = window.__egretFind(['gm']);
out.gm = g;
if (g.length && cvs.length) {
  const r = cvs[0].getBoundingClientRect();
  const cx = g[0].x + g[0].w / 2, cy = g[0].y + g[0].h / 2;
  out.gmCenter = [cx, cy];
  out.gmScreen = [r.left + cx * (r.width / (cvs[0].width / dpr)),
                  r.top + cy * (r.height / (cvs[0].height / dpr))];
}
out.tapResult = window.__egretTap((g[0] ? g[0].x + g[0].w / 2 : 30), (g[0] ? g[0].y + g[0].h / 2 : 430));
return JSON.stringify(out, null, 1);
