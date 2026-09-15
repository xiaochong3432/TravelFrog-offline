/* Persistence leg for the rename fix, run AFTER a real location.reload().

Reads the save the shell writes (`frog.offline.save`), the client model, and the
panel itself -- the 名字 the player sees in the input box is the rendering leg. */
const out = {};
try {
  const raw = localStorage.getItem('frog.offline.save');
  const s = raw ? JSON.parse(raw) : null;
  out.saveName = s && s.name;
  out.saveRenamed = s && s.renamed;
  out.saveClover = s && s.clover;
} catch (e) {
  out.saveError = String(e);
}

const Role = core.ModelManage.getInstance().getModel(RoleModel);
out.modelName = Role.getName();

/* The quoted price the 改名 flow reads: a save that has already been renamed
   must now be quoted RENAME_CLOVER, otherwise every restart hands out a free
   rename again. */
let quoted = null;
core.SocketManage.getInstance().send('client_rename_cost', new core.Action2(function (r) {
  quoted = r && r.clover;
}));
out.quotedClover = quoted;

let shown = null;
try {
  const v = new AttributeView();
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  v.open();
  shown = v.t_name.text;
} catch (e) {
  shown = '<err ' + e + '>';
}
out.panelInput = shown;

return JSON.stringify(out);
