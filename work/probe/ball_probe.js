/* 存档编辑 ball: is the debug square gone, and do the buttons work? */
const out = {};
const E = window.__engine;

const ball = document.getElementById('__save_ball');
const panel = document.getElementById('__save_panel');
out.ballPresent = !!ball;
out.panelPresent = !!panel;
if (ball) {
  const r = ball.getBoundingClientRect();
  out.ballRect = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
  out.ballCenter = [Math.round(r.left + r.width / 2), Math.round(r.top + r.height / 2)];
}
if (panel) out.panelVisible = getComputedStyle(panel).display !== 'none';
out.oldToolsGone = !document.getElementById('__save_tools');

/* the client's own debug entry is driven by showGM; make sure it is off in the config */
out.showGM = (function () {
  try { return String(GameConfig.showGM); } catch (e) { return 'no GameConfig'; }
})();

out.frogStatus = E.state.frog.status;
out.bagPacked = (E.state.items.bag || []).filter((v) => v !== -1).length;
out.waitingForBag = !!E.state.travel.waitingForBag;
return JSON.stringify(out);
