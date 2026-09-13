/* The paper between the workbench and the door: the ad-notice poster.

Its handler opens AdsVideoView (the video player) when the channel is ChannelType.Test,
which is how this build runs -- and offline that player is a black screen that only
closes on video END or its own X, with nothing thrown. The new shell guard replaces it
with the branch the client itself takes when a video ends (adsmgr_share{ads_type:1},
i.e. the daily gift arrives by mail).

This taps the real button and reports: who handled it, what the engine replied, whether
an AdsVideoView reached the notice layer, and how many mails the player now has. */
const out = {};
const E = window.__engine;

let mainOut = null;
(function find(n, d) {
  if (!n || d > 14 || mainOut) return;
  let src = '';
  try { src = String(n.constructor && n.constructor.toString()); } catch (e) { /* */ }
  if (/getSkinsPath\("MainOut\/MainOut\.exml"\)/.test(src)) { mainOut = n; return; }
  const k = n.$children || [];
  for (let i = 0; i < k.length; i++) find(k[i], d + 1);
})(egret.MainContext.instance.stage, 0);
if (!mainOut) return JSON.stringify({ error: 'no MainOut' });

out.btnFound = !!mainOut.adsNoticeBtn;
out.btnVisible = mainOut.adsNoticeBtn ? !!mainOut.adsNoticeBtn.visible : null;
out.layerPatched = !!(window.core && core.DisplayManage &&
  core.DisplayManage.getInstance().getNoticeLayer().__adsPatched);

const mailsBefore = (E.state.mails || []).length;
const viewsBefore = (window.__views || []).length;

/* a REAL tap on the poster (Egret hit-tests it, exactly like a finger) */
try {
  mainOut.adsNoticeBtn.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
  out.tapped = true;
} catch (e) {
  out.tapped = 'THREW ' + String(e && e.message || e);
}

const added = (window.__views || []).slice(viewsBefore).filter((v) => v.op === 'add');
out.addedViews = added.map((v) => String(v.fp).slice(0, 90));
out.adsVideoOnStage = (function () {
  let found = 0;
  (function w(n, d) {
    if (!n || d > 14) return;
    if (String(n.__class__ || '') === 'AdsVideoView') found++;
    const k = n.$children || [];
    for (let i = 0; i < k.length; i++) w(k[i], d + 1);
  })(egret.MainContext.instance.stage, 0);
  return found;
})();
out.mailsBefore = mailsBefore;
out.mailsAfter = (E.state.mails || []).length;
out.lastMail = (E.state.mails || []).slice(-1)[0]
  ? JSON.stringify((E.state.mails || []).slice(-1)[0]).slice(0, 200) : null;
return JSON.stringify(out);
