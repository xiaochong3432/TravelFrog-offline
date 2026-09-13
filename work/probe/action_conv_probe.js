/* Decisive: what exactly does an Action callback receive?

`core.Action2` appears to be a WRAPPER CLASS with its own `apply` method, not a
plain function, so `Function.prototype.apply` reasoning does not settle it. We
send two commands whose replies we know exactly and serialise the raw arguments:
  clover_load_clovers -> our engine replies with the clovers object
  museum_load         -> our engine replies { museum_list: [] }
If argument 0 is the REPLY, an unknown error code makes `getErrorInfo(a.code)`
return undefined; if argument 0 is the request PARAM, `a.code` is undefined for
number params and the same conclusion follows for a different reason. */
const out = {};

function capture(cmd, params) {
  const rec = { cmd: cmd, argv: null, argc: null, thisType: null, thisKeys: null };
  const action = new core.Action2(function (a, b) {
    rec.argc = arguments.length;
    try {
      rec.argv = Array.prototype.slice.call(arguments).map(function (v) {
        if (v === undefined) return '<undefined>';
        if (v === null) return null;
        const t = typeof v;
        if (t === 'number' || t === 'string' || t === 'boolean') return v;
        try { return JSON.parse(JSON.stringify(v)); } catch (e) { return '<' + t + ' unserialisable>'; }
      });
    } catch (e) { rec.argv = '<err ' + e + '>'; }
    rec.thisType = typeof this;
    if (this && typeof this === 'object' && this !== window) {
      try { rec.thisKeys = Object.keys(this).slice(0, 8); } catch (e) { rec.thisKeys = null; }
    }
  }, this);
  try {
    if (params === undefined) {
      core.SocketManage.getInstance().send(cmd, action);
    } else {
      core.SocketManage.getInstance().send(cmd, action, params);
    }
  } catch (e) {
    rec.sendError = String(e);
  }
  return rec;
}

out.clover = capture('clover_load_clovers');
out.museum = capture('museum_load');
/* a command we answer with a REAL nonzero code for an id that cannot exist */
out.albumDelete = capture('album_delete', 999999);
/* client_rename_cost: the reply the 改名 flow reads `n.clover` from */
out.renameCost = capture('client_rename_cost');

return JSON.stringify(out);
