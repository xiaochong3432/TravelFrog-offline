/* On a short phone screen the notice is taller than the viewport, so the button
   must be reachable by scrolling. Verify that it really scrolls (touch scrolling
   inside a fixed overlay can be blocked by an ancestor's touch-action) and that
   the button ends up on screen. */
const n = document.getElementById('__notice');
const out = { vp: [window.innerWidth, window.innerHeight] };
out.needsScroll = n.scrollHeight > n.clientHeight + 2;
out.scrollTopBefore = n.scrollTop;

n.scrollTop = n.scrollHeight;              // programmatic scroll
await new Promise((r) => setTimeout(r, 300));
out.scrollTopAfter = n.scrollTop;
out.canScroll = n.scrollTop > 0;

/* is the button now inside the viewport? */
const ok = document.getElementById('__notice_ok');
const r = ok.getBoundingClientRect();
out.buttonRect = [Math.round(r.top), Math.round(r.bottom)];
out.buttonVisibleAfterScroll = r.bottom <= window.innerHeight + 1 && r.top >= -1;

/* and does a REAL touch drag scroll it? (synthetic events on the overlay, not the
   canvas) */
n.scrollTop = 0;
await new Promise((res) => setTimeout(res, 200));
const fire = (type, y) => n.dispatchEvent(new TouchEvent(type, {
  bubbles: true, cancelable: true, view: window,
  touches: type === 'touchend' ? [] : [new Touch({ identifier: 1, target: n, clientX: 100, clientY: y, screenX: 100, screenY: y, pageX: 100, pageY: y })],
  targetTouches: type === 'touchend' ? [] : [new Touch({ identifier: 1, target: n, clientX: 100, clientY: y, screenX: 100, screenY: y, pageX: 100, pageY: y })],
  changedTouches: [new Touch({ identifier: 1, target: n, clientX: 100, clientY: y, screenX: 100, screenY: y, pageX: 100, pageY: y })],
}));
try {
  fire('touchstart', 400);
  fire('touchmove', 200);
  fire('touchend', 200);
} catch (e) { out.touchError = String(e && e.message); }
await new Promise((res) => setTimeout(res, 400));
out.touchScrollTop = n.scrollTop;
out.touchScrollWorks = n.scrollTop > 0;

/* wheel is what a PC user with a small window would use */
n.scrollTop = 0;
n.dispatchEvent(new WheelEvent('wheel', { bubbles: true, cancelable: true, deltaY: 300 }));
await new Promise((res) => setTimeout(res, 300));
out.wheelScrollTop = n.scrollTop;

n.scrollTop = n.scrollHeight;
await new Promise((res) => setTimeout(res, 200));
return JSON.stringify(out, null, 1);
