/* The 称号 list must show REAL names for earned titles, not the client's own
   "??????" placeholder. Read the item views' own labels after opening the list the
   same way the 名片/属性 page does. */
const rm = core.ModelManage.getInstance().getModel(RoleModel);
const out = {};

out.earnedIds = rm.getAchieveList();
out.achieveTime = rm.achieveTime;
out.useAchieveID = rm.getUseAchieveID();
out.curAchieveRaw = rm.useAchieveID;
out.isExpired = (() => { try { return out.earnedIds.map((id) => rm.isAchieveExpire(id)); } catch (e) { return 'ERR ' + e.message; } })();
out.achieveInfoForCur = (() => {
  const info = rm.getAchieveInfo(out.useAchieveID);
  return info ? info.name : null;
})();

/* open the list view exactly like the 名片 page does */
let v = null;
try {
  v = new AchieveView(new core.Action1(function () { }));
  v.open();
  out.opened = true;
} catch (e) {
  out.opened = 'THREW ' + (e && e.message);
}
await new Promise((r) => setTimeout(r, 800));

if (v && v.viewList) {
  const titles = v.viewList.map((iv) => iv.t_achieve.text);
  out.itemCount = titles.length;
  out.questionMarkCount = titles.filter((t) => t === '??????').length;
  out.namedCount = titles.filter((t) => t !== '??????').length;
  out.firstNamed = titles.filter((t) => t !== '??????').slice(0, 8);
  out.firstTitles = titles.slice(0, 8);
  /* do the earned ones come first and carry names? */
  out.earnedShownAsName = out.earnedIds.every((id) => {
    const info = rm.getAchieveInfo(id);
    return info && titles.indexOf(info.name) !== -1;
  });
}
return JSON.stringify(out, null, 1);
