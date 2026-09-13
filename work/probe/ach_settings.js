/* Does the engine stop wiping the client's own settings?
   The client records which titles it has already announced in
   clientSettings.achieveList and sends the whole settings object to the server on
   every change. If the engine then pushes its own defaults back (achieveList: []),
   checkNewAchieve() re-announces the OLDEST un-announced title forever. */
const um = core.ModelManage.getInstance().getModel(UserModel);
const out = {};

out.before = JSON.parse(JSON.stringify(um.getClientSettings().achieveList || []));

/* mimic what the client does after announcing a title */
um.setClientSettings('achieveList', [0, 21], true);
await new Promise((r) => setTimeout(r, 1500));            // let client_set_client land
out.afterSet = um.getClientSettings().achieveList;
out.engineStored = (() => {
  try { return window.FrogEngine ? 'n/a' : 'n/a'; } catch (e) { return 'ERR'; }
})();

/* now force a full role push, the way earning anything does */
await new Promise((res) => {
  core.SocketManage.getInstance().send('clover_load_clovers',
    new core.Action2(function () { res(); }), );
  setTimeout(res, 1500);
});
out.afterRolePush = JSON.parse(JSON.stringify(um.getClientSettings().achieveList || []));

/* and the title the popup would use */
const rm = core.ModelManage.getInstance().getModel(RoleModel);
out.earned = rm.getAchieveList();
out.curTitle = (() => { const i = rm.getAchieveInfo(rm.getUseAchieveID()); return i ? i.name : null; })();
out.anyExpired = out.earned.map((id) => rm.isAchieveExpire(id));

out.verdict = {
  survivedRolePush: JSON.stringify(out.afterSet) === JSON.stringify(out.afterRolePush),
  notResetToEmpty: (out.afterRolePush || []).length === 2,
  titlesNotExpired: out.anyExpired.every((v) => v === false),
};
return JSON.stringify(out, null, 1);
