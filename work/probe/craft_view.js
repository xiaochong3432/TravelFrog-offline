/* Open the 手工 window the way the game does, so the NEXT probe (a frame later) can
   count the two pages' rows. The window fed by pray_load_grays is the user-visible
   surface of the craft feature, so "does it have content?" is the rendering leg. */
const out = {};
try {
  const v = new HandCraftView();
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  out.opened = true;
  out.hasPageContainer = !!v.pageContainer;
  out.tabGroup = !!v.c_typeGroup;
  /* select page 1 explicitly, then request the data the pages render from */
  if (v.selectPage) v.selectPage(0);
} catch (e) {
  out.error = String(e && e.stack || e);
}
try {
  core.SocketManage.getInstance().send('pray_load_grays');
  out.requested = true;
} catch (e) {
  out.requestError = String(e);
}
return JSON.stringify(out);
