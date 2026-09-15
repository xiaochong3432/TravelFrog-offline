/* Drive the REAL 改名 button and capture the Action callback convention.

Two things in one run:
 1. `SocketManage.send(cmd, action)` -> AnalysisProtocol does
    `callbackFun.apply(r.data, o.data)`. `o.data` is built as an OBJECT
    (`u.data[name]=value`), and Function.prototype.apply with a non-array-like
    object passes ZERO arguments -- so the question "does the callback see the
    reply as argument 0, or as `this`?" has to be answered by experiment, not by
    reading minified code. It decides whether an unknown error code is SILENT
    (`getErrorInfo(undefined)`) or reads as SUCCESS.
 2. The 改名 / 起名 path: `RoleModel.setName()` -> `client_rename_cost` ->
    (confirm) -> `client_set_name`. AttributeView is the panel the game itself
    opens (tapping the frog), and its btn_yes handler is what the player taps. */
const out = {};

let cap = null;
try {
  core.SocketManage.getInstance().send('client_hello', new core.Action2(function (a, b) {
    cap = {
      argc: arguments.length,
      arg0code: a && a.code,
      arg1: b === undefined ? null : String(b),
      thisIsReply: !!(this && typeof this.code !== 'undefined'),
      thisKeys: this && typeof this === 'object' ? Object.keys(this).slice(0, 6) : null,
    };
  }));
} catch (e) {
  cap = { error: String(e) };
}
out.callback = cap;

const Role = core.ModelManage.getInstance().getModel(RoleModel);
out.nameBefore = Role.getName();

let viewError = null;
try {
  const v = new AttributeView();
  core.DisplayManage.getInstance().getPopupLayer().addChild(v);
  v.open();
  out.inputSeeded = v.t_name.text;
  v.t_name.text = '离线测试蛙';
  /* This is exactly the handler `addEventListener(TOUCH_TAP, this.totalTouchEvents)`
     registered on btn_yes: it calls applyInput() -> roleModel.setName(). */
  v.btn_yes.dispatchEvent(new egret.TouchEvent(egret.TouchEvent.TOUCH_TAP));
  out.panelClosed = !v.parent;
} catch (e) {
  viewError = String(e && e.stack || e);
}
out.viewError = viewError;
out.nameAfter = Role.getName();

/* The engine's own view of it, straight out of the save the shell writes. */
try {
  const raw = localStorage.getItem('save.json') || localStorage.getItem('__frog_save') || '';
  const s = raw ? JSON.parse(raw) : null;
  out.saveName = s && s.name;
  out.saveRenamed = s && s.renamed;
  out.saveClover = s && s.clover;
} catch (e) {
  out.saveError = String(e);
}
out.localStorageKeys = Object.keys(localStorage).slice(0, 8);

return JSON.stringify(out);
