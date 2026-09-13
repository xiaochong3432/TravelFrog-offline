/* Why is the client's VisitorModel empty after we push visit_load? */
const out = {};
const E = window.__engine;

for (let i = 0; i < 400 && !E.state.visitor; i++) {
  E.state.visitorNextRollAt = 1;
  E.state.visitorCoolUntil = 0;
  E.tick();
}
out.engineVisitor = E.state.visitor ? {
  province: E.state.visitor.province, city: E.state.visitor.city,
  title: E.state.visitor.title, name: E.state.visitor.name,
  expireIn: E.state.visitor.expire_time - Math.floor(Date.now() / 1000),
} : null;

const payload = E.dispatch('visit_load', {}).reply;
out.payloadKeys = payload ? Object.keys(payload) : null;
out.payloadVisitor = payload && payload.visitor ? payload.visitor : null;
out.payloadAcquireLen = payload && payload.acquire ? payload.acquire.length : null;

const VM = core.ModelManage.getInstance().getModel(VisitorModel);
out.modelKeys = Object.keys(VM);
out.visitorData = VM.visitorData
  ? { name: VM.visitorData.name, title: VM.visitorData.title, city: VM.visitorData.city,
      province: VM.visitorData.getProvince(), carpet: VM.visitorData.carpet }
  : null;
out.acquireLen = (VM.acquireList || []).length;

/* does the listener exist at all on the socket layer? */
try {
  out.hasListener = core.SocketManage.getInstance().HasEventListener
    ? core.SocketManage.getInstance().HasEventListener('visit_load') : 'no HasEventListener';
} catch (e) { out.hasListener = 'THREW ' + String(e && e.message || e); }

/* deliver the push again, but watch what the model does */
try {
  const before = !!VM.visitorData;
  core.SocketManage.getInstance().dispatchEvent(
    new core.Event('visit_load', payload));
  out.manualDispatch = { before, after: !!VM.visitorData };
} catch (e) {
  out.manualDispatch = 'THREW ' + String(e && e.message || e);
}
return JSON.stringify(out);
