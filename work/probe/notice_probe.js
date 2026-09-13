/* Verify the rights notice: it must be on screen BEFORE the game interface,
   block the game, silence it, and disappear on tap so the game is then usable. */
const out = {};
const n = document.getElementById('__notice');
out.noticePresent = !!n;
out.dismissedFlag = window.__noticeDismissed;
if (n) {
  const cs = getComputedStyle(n);
  const r = n.getBoundingClientRect();
  out.style = { background: cs.backgroundColor, color: cs.color, zIndex: cs.zIndex };
  out.rect = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
  out.viewport = [window.innerWidth, window.innerHeight];
  // is it the topmost element at the centre of the screen, i.e. does it really
  // swallow input meant for the stage?
  const mid = document.elementFromPoint(Math.round(window.innerWidth / 2), Math.round(window.innerHeight / 2));
  out.topmostAtCentreInsideNotice = !!(mid && n.contains(mid));
  out.heading = (n.querySelector('h1') || {}).textContent || null;
  out.body = Array.from(n.querySelectorAll('h1,h2,p,button')).map((e) => e.tagName + ': ' + e.textContent.trim());
  out.scrollHeight = n.scrollHeight;
  out.scrolls = n.scrollHeight > n.clientHeight + 2;
}
/* is the game actually running behind it? */
out.engineReady = !!window.FrogEngine;
out.gameViewsBehind = (window.__egretViews ? window.__egretViews() : []).map((v) => v.skin);

/* Music must be silent until the player taps. Spy on the ORIGINAL by counting how
   many times the wrapper lets a call through. */
out.musicSuppressedProbe = (() => {
  try {
    if (!window.Music || !Music.play) return 'no Music';
    Music.play('SE_Cursor');            // would normally dispatch to the client
    return 'called while notice up (should have been swallowed)';
  } catch (e) { return 'THREW ' + e.message; }
})();

/* dismiss it the way the player does */
out.clicked = false;
const ok = document.getElementById('__notice_ok');
if (ok) { ok.click(); out.clicked = true; }
await new Promise((r) => setTimeout(r, 1200));
out.afterClick = {
  dismissedFlag: window.__noticeDismissed,
  noticeStillThere: !!document.getElementById('__notice'),
  gameViews: (window.__egretViews ? window.__egretViews() : []).map((v) => v.skin),
};
return JSON.stringify(out, null, 1);
