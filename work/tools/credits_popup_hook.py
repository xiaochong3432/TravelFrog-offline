#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Second net for the 制作人员 relabel.

The first net (a poll started from addViewControl) MISSES the Help panel: the client's
Help is a singleton added straight to the popup layer --
    this.questionModal = Help.getInstance();
    core.DisplayManage.getInstance().getPopupLayer().addChild(this.questionModal);
    this.questionModal.show();
-- so it never passes through the view stack. Two precise hooks instead:

  * wrap Help.prototype.show (when the class is reachable as a global), and
  * wrap the POPUP layer's addChild, relabelling any child that owns `btn_customer`
    (the same technique the shell already uses for the ad poster on the notice layer).

Idempotent. Usage: python tools/credits_popup_hook.py <shell.js> [...]
"""
import io
import sys

ANCHOR = "        window.__relabelHelpButton = relabelHelpButton;\n"

ADD = """        window.__relabelHelpButton = relabelHelpButton;

        /* The Help panel is a SINGLETON added straight to the popup layer
           (`Help.getInstance()` + getPopupLayer().addChild(...)), so it never goes through
           addViewControl and the view-open poll above cannot see it. Hook the two places
           where it actually appears. */
        function hookCreditsTargets() {
            var hooked = 0;
            try {
                var H = window.Help;
                if (H && H.prototype && H.prototype.show && !H.prototype.__creditsHooked) {
                    var oShow = H.prototype.show;
                    H.prototype.show = function () {
                        var r = oShow.apply(this, arguments);
                        try { relabelHelpButton(); } catch (e) { }
                        return r;
                    };
                    H.prototype.__creditsHooked = true;
                    hooked++;
                }
            } catch (e) { push('[credits-error]', ['Help.show hook: ' + (e && e.message)]); }
            try {
                var layer = core.DisplayManage.getInstance().getPopupLayer();
                if (layer && !layer.__creditsHooked) {
                    var oAdd = layer.addChild;
                    layer.addChild = function (child) {
                        var r = oAdd.apply(this, arguments);
                        try {
                            if (child && child.btn_customer) scheduleCreditsFix(null);
                        } catch (e) { }
                        return r;
                    };
                    layer.__creditsHooked = true;
                    hooked++;
                }
            } catch (e) { push('[credits-error]', ['popup hook: ' + (e && e.message)]); }
            return hooked;
        }
        window.__hookCreditsTargets = hookCreditsTargets;
"""

CALL_ANCHOR = "        P.__offlineChannelInstalled = true;\n"
CALL = """        /* the Help panel can appear at any time later, so both hooks are installed now */
        try { hookCreditsTargets(); } catch (e) { }

        P.__offlineChannelInstalled = true;
"""


def main():
    for path in sys.argv[1:]:
        text = io.open(path, encoding='utf-8').read()
        orig = text
        notes = []
        if 'function hookCreditsTargets' not in text:
            if ANCHOR not in text:
                print('!! %s: anchor for the hook block not found' % path)
                continue
            text = text.replace(ANCHOR, ADD, 1)
            notes.append('hook block added')
        else:
            notes.append('hook block already present')
        if 'hookCreditsTargets(); } catch (e) { }' not in text:
            if CALL_ANCHOR in text:
                text = text.replace(CALL_ANCHOR, CALL, 1)
                notes.append('install call added')
            else:
                notes.append('WARNING: install-call anchor not found')
        else:
            notes.append('install call already present')
        if text != orig:
            io.open(path, 'w', encoding='utf-8', newline='').write(text)
        enc = getattr(sys.stdout, 'encoding', None) or 'utf-8'
        print('%s: %s' % (path.encode(enc, 'replace').decode(enc, 'replace'),
                          '; '.join(notes)))


main()
