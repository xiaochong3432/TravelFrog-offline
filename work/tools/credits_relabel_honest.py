#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Make the credits relabel honest.

The label turned out to be DRAWN INTO the texture (the theme defines the button as
`new eui.Image(); t.source = "button_02_png"`), so the rename is done by replacing that
texture -- setting `.label` on an eui.Image does nothing. The runtime hook stays as a
safety net for a client whose button IS a real eui.Button (one with a labelDisplay), and
now only writes when that is the case.
"""
import io
import sys

OLD = """                if (b) {
                    try {
                        if (b.label !== CREDITS_TITLE) {
                            b.label = CREDITS_TITLE;
                            hits++;
                        }
                        if (b.labelDisplay && b.labelDisplay.text !== CREDITS_TITLE) {
                            b.labelDisplay.text = CREDITS_TITLE;
                        }
                    } catch (e) { push('[credits-error]', [String(e && e.message)]); }
                }"""

NEW = """                if (b) {
                    /* The shipped button is an eui.Image whose label is baked into
                       button_02_png, so the visible name comes from that texture (see
                       tools/patch_help_button.py). Only a REAL eui.Button can be relabelled
                       at runtime -- check before writing, so this never pretends. */
                    try {
                        if (b.labelDisplay) {
                            if (b.labelDisplay.text !== CREDITS_TITLE) {
                                b.labelDisplay.text = CREDITS_TITLE;
                            }
                            if (b.label !== CREDITS_TITLE) {
                                b.label = CREDITS_TITLE;
                            }
                            hits++;
                        } else if (b.source === 'button_02_png') {
                            hits++;      /* label is in the texture; nothing to do here */
                        }
                    } catch (e) { push('[credits-error]', [String(e && e.message)]); }
                }"""

for path in sys.argv[1:]:
    text = io.open(path, encoding='utf-8').read()
    n = text.count(OLD)
    if n != 1:
        print('%s: anchor matched %d times -- left alone' % (path, n))
        continue
    io.open(path, 'w', encoding='utf-8', newline='').write(text.replace(OLD, NEW))
    print('%s: relabel made honest' % path)
