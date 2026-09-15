/* Click the ball's buttons for real (DOM clicks) and report the effect.

Which action runs is decided by `window.__ballAction`: go / home / status. */
const out = {};
const E = window.__engine;
const panel = document.getElementById('__save_panel');
const action = window.__ballAction || 'status';

const buttons = panel ? Array.prototype.slice.call(panel.querySelectorAll('button')) : [];
out.buttons = buttons.map((b) => b.textContent);
out.before = { status: E.state.frog.status, waiting: !!E.state.travel.waitingForBag };

const find = (label) => buttons.filter((b) => b.textContent.indexOf(label) >= 0)[0];
if (action === 'go') {
  const b = find('立刻出门');
  if (b) { b.click(); out.clicked = '立刻出门'; } else { out.clicked = 'button not found'; }
} else if (action === 'home') {
  const b = find('立刻回家');
  if (b) { b.click(); out.clicked = '立刻回家'; } else { out.clicked = 'button not found'; }
}
out.after = { status: E.state.frog.status };
out.msg = panel ? String(panel.querySelector('div:nth-child(2)') && '' ) : '';
/* the panel's own status line is the LAST small div; capture its text */
const divs = panel ? Array.prototype.slice.call(panel.querySelectorAll('div')) : [];
out.statusLine = divs.map((d) => d.textContent).filter((s) => /完成|失败|出门|回家|出发/.test(s))
  .slice(-2);
return JSON.stringify(out);
