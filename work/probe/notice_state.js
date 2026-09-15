/* Report the notice's scroll state so a real, trusted wheel event (dispatched by
   the driver via CDP Input) can be judged. */
const n = document.getElementById('__notice');
if (!n) return JSON.stringify({ error: 'notice already gone' });
return JSON.stringify({
  vp: [window.innerWidth, window.innerHeight],
  scrollHeight: n.scrollHeight,
  clientHeight: n.clientHeight,
  scrollTop: n.scrollTop,
  needsScroll: n.scrollHeight > n.clientHeight + 2,
  touchAction: getComputedStyle(n).touchAction,
  buttonBottom: Math.round(document.getElementById('__notice_ok').getBoundingClientRect().bottom),
});
