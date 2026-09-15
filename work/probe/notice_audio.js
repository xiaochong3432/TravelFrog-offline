/* Observable check of the audio gate: egret tracks active sound channels through
   egret.sys.$pushSoundChannel, so counting calls to it tells us whether Music.play
   actually reached the audio layer -- not merely whether it threw. */
const out = {};
const pushes = { whileNoticeUp: 0, afterDismiss: 0 };
const origPush = egret.sys.$pushSoundChannel;
egret.sys.$pushSoundChannel = function () {
  pushes[out.phase === 'up' ? 'whileNoticeUp' : 'afterDismiss'] += 1;
  return origPush.apply(this, arguments);
};

const notice = document.getElementById('__notice');
out.noticeUpBefore = !!notice;
out.musicPlaySourceHasGuard = /__noticeDismissed/.test(String(Music.play));

out.phase = 'up';
try { Music.play('SE_Cursor'); } catch (e) { out.upError = String(e && e.message); }
await new Promise((r) => setTimeout(r, 400));

/* now dismiss and try the same call */
document.getElementById('__notice_ok').click();
await new Promise((r) => setTimeout(r, 800));
out.phase = 'after';
try { Music.play('SE_Cursor'); } catch (e) { out.afterError = String(e && e.message); }
await new Promise((r) => setTimeout(r, 400));

out.channels = pushes;
out.verdict = (pushes.whileNoticeUp === 0 && pushes.afterDismiss > 0)
  ? 'PASS: silent while the notice is up, audible after dismissal'
  : ('CHECK: up=' + pushes.whileNoticeUp + ' after=' + pushes.afterDismiss);
out.noticeRemoved = !document.getElementById('__notice');
out.gameViews = (window.__egretViews ? window.__egretViews() : []).map((v) => v.skin);
return JSON.stringify(out, null, 1);
