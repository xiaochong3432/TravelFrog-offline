#!/usr/bin/env python3
"""Map EXML skin classes in default.thm.js to their skin paths, and report which
skin uses a given image (e.g. share_btn3_png).

The theme file is generated as:
    var $exmlClass139 = (function (_super) { ... })(eui.Skin);
    generateEUI.paths['resource/.../AdsGiftSkin.exml'] = $exmlClass139;
so the class -> path link is a separate statement further down.

Usage:
    python tools/skinmap.py share_btn3_png
    python tools/skinmap.py --list Ads
"""
import argparse
import os
import re

DEFAULT = r"H:\AI\frog\work\run\web\js\default.thm.js"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("needle", nargs="?", default=None)
    ap.add_argument("--file", default=DEFAULT)
    ap.add_argument("--list", default=None, help="list skin paths containing this")
    args = ap.parse_args()

    with open(args.file, encoding="utf-8", errors="replace") as fh:
        t = fh.read()

    # class assigned to each skin path. NOTE the real form is
    #   generateEUI.paths['...exml'] = window.$exmlClass1 = (function (_super){
    # so the class is behind a `window.` prefix -- matching only a bare
    # identifier silently found zero mappings the first time round.
    path_of_class = {}
    for m in re.finditer(
            r"generateEUI\.paths\['([^']+)'\]\s*=\s*(?:window\.)?(\$?[A-Za-z0-9_$]+)", t):
        path_of_class[m.group(2)] = m.group(1)

    # find the class that encloses a given offset. The generated form is
    #   generateEUI.paths['...'] = window.$exmlClassN = (function (_super) { ... }
    # i.e. the class is a window property, NOT a `var` -- looking for
    # "var $exmlClassN" finds an unrelated earlier declaration instead.
    def class_at(offset):
        decls = list(re.finditer(r"window\.(\$?exmlClass\d+|\$?[A-Za-z0-9_$]+)\s*=\s*\(function", t[:offset]))
        return decls[-1].group(1) if decls else None

    if args.needle:
        hits = list(re.finditer(re.escape(args.needle), t))
        print("=== '%s' (%d hits) ===" % (args.needle, len(hits)))
        for m in hits:
            cls = class_at(m.start())
            print("  @%d  class=%s  skin=%s" % (m.start(), cls, path_of_class.get(cls, '?')))

    if args.list:
        print("=== skin paths containing '%s' ===" % args.list)
        for cls, p in sorted(path_of_class.items(), key=lambda kv: kv[1]):
            if args.list in p:
                print("  %-58s %s" % (p, cls))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
