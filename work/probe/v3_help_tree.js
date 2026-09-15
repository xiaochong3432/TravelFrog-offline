(function () {
  /* Where does the visible 联系客服 text actually live inside the Help panel? */
  var out = { nodes: [], matches: [] };
  var h = null;
  try {
    h = window.Help.getInstance();
    core.DisplayManage.getInstance().getPopupLayer().addChild(h);
    h.show();
  } catch (e) { return JSON.stringify({ error: String(e && e.message) }); }

  function describe(n) {
    var d = { name: n.name || '(anon)', cls: (n.__class__ || (n.constructor && n.constructor.name) || '?') };
    try { if (typeof n.text === 'string') d.text = n.text; } catch (e) { }
    try { if (typeof n.source === 'string' && n.source) d.source = n.source; } catch (e) { }
    try { if (typeof n.label === 'string' && n.label) d.label = n.label; } catch (e) { }
    try { if (n.width) d.size = [Math.round(n.width), Math.round(n.height)]; } catch (e) { }
    try { if (typeof n.visible === 'boolean') d.visible = n.visible; } catch (e) { }
    return d;
  }

  function walk(n, path, depth) {
    if (!n || depth > 8) return;
    var kids = [];
    try { kids = n.$children || []; } catch (e) { kids = []; }
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i];
      var name = (path ? path + '.' : '') + (c.name || ('[' + i + ']'));
      var d = describe(c);
      if (d.text || d.source || d.label) out.nodes.push({ path: name, d: d });
      if (d.text && String(d.text).indexOf('客服') >= 0) out.matches.push({ path: name, d: d });
      if (d.label && String(d.label).indexOf('客服') >= 0) out.matches.push({ path: name, d: d });
      walk(c, name, depth + 1);
    }
  }
  walk(h, 'Help', 0);

  out.btnCustomer = describe(h.btn_customer);
  out.btnCustomerKeys = (function () {
    var keys = [];
    for (var k in h.btn_customer) {
      try {
        var v = h.btn_customer[k];
        if (typeof v === 'string' && v) keys.push(k + '=' + v);
      } catch (e) { }
    }
    return keys;
  })();
  out.btnCustomerChildren = (function () {
    var r = [];
    try {
      var kids = h.btn_customer.$children || [];
      for (var i = 0; i < kids.length; i++) r.push(describe(kids[i]));
    } catch (e) { }
    return r;
  })();
  out.btnAgree = describe(h.btn_agree);
  out.nodeCount = out.nodes.length;
  return JSON.stringify(out);
})()
