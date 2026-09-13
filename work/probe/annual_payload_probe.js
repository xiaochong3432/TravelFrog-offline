/* annual_payload_probe.js -- why did stamp_num read 0 after seeding state.craft?
 * Isolates: is engine.state live? does annual_load see the seeded craft? is the model's
 * cacheData the answer to MY send, or a login-time push?
 *
 * IIFE expression, no trailing semicolon.
 */
(async () => {
  const out = {};
  const E = window.__engine;
  const now = Math.floor(Date.now() / 1000);

  out.before_craft = JSON.parse(JSON.stringify(E.state.craft || null));

  E.state.craft = {
    wishes: [{ id: 1, state: 4, body: 101, paper: 1001, content: 1, make_time: 1700000000, u_id: 1 },
             { id: 2, state: 4, body: 102, paper: 1002, content: 2, make_time: 1700000100, u_id: 2 }],
    stamps: [{ id: 109, state: 4, time: 1700000000, u_id: 3 },
             { id: 207, state: 4, time: 1700000100, u_id: 4 }],
    pending: [], seq: 4,
  };
  out.after_craft = JSON.parse(JSON.stringify(E.state.craft));

  /* 1. direct dispatch -- what does the handler itself compute? */
  try {
    const r = E.dispatch('annual_load', {});
    out.dispatchReply = r && r.reply ? r.reply : r;
  } catch (e) { out.dispatchErr = String(e); }
  /* the state as the engine sees it right after that dispatch */
  out.craft_after_dispatch = JSON.parse(JSON.stringify(E.state.craft || null));

  /* 2. the socket path the client actually uses */
  out.socketReply = await new Promise((res) => {
    let done = false;
    core.SocketManage.getInstance().send('annual_load', new core.Action2(function (x) { done = true; return res(x); }));
    setTimeout(() => { if (!done) res('<no reply in 3s>'); }, 3000);
  });
  out.cacheData = JSON.parse(JSON.stringify(
    core.ModelManage.getInstance().getModel(AnnualReviewModel).cacheData || null));
  out.craft_after_socket = JSON.parse(JSON.stringify(E.state.craft || null));

  /* 3. what does the engine's own save file say about craft? (persisted truth) */
  try {
    out.saveReport = E.state.__saveReport || null;
  } catch (e) { out.saveReport = 'THREW'; }
  return JSON.stringify(out, null, 1);
})()
