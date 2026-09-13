#!/usr/bin/env python3
"""Apply the offline-build patches to work/run/web (idempotent, from pristine source).

Always starts from js/main.min.js.clean (extracted straight from base.apk) so the
result is reproducible regardless of how many times this runs.

Patches, all deliberate parts of the offline port:
  1. enterGame gate      - GameConfig.activate is only ever set by a native-SDK
                           lifecycle resume, which does not happen in a browser.
  2. season key clamp    - only season11..season44 bundles ship; the "00" default
                           (before weather data arrives) requests files that do
                           not exist.
"""
import os, sys, shutil

WEB = r"H:\AI\frog\work\run\web"
MAIN = os.path.join(WEB, "js", "main.min.js")
CLEAN = MAIN + ".clean"

PATCHES = [
    # NOTE: the original build gated scene entry on
    #   this.loadComplete && isSyncComplete() && GameConfig.activate
    # We deliberately do NOT neutralise that gate: it is what guarantees the role
    # payload (and therefore guideStep) has been applied before MainOutView runs
    # checkGuide(). Punching it out caused a race where checkGuide() saw the
    # default guideStep "New" and opened the Welcome/开始 screen.
    # GameConfig.activate is supplied by the offline shell instead.
    (
        # The season resource groups that actually ship are season11..season44.
        # Any other key (notably the "00" default before weather data arrives)
        # makes the client request mainout_season00_* files that do not exist.
        "season key clamp",
        'getSeasonKey=function(){return this.data.season+""+this.data.hours_type}',
        'getSeasonKey=function(){var a=this.data.season,b=this.data.hours_type;'
        'return a>=1&&a<=4&&b>=1&&b<=4?a+""+b:"11"}',
    ),
]


def main():
    if not os.path.exists(CLEAN):
        print(f"missing pristine baseline: {CLEAN}")
        print("  extract it with:  python work/tools/zipx.py base.apk extract "
              "\"assets/game/js/main.min.js\" work/pristine")
        return 1
    text = open(CLEAN, "rb").read().decode("utf8")
    print(f"baseline: {CLEAN} ({len(text)} chars)")
    applied = 0
    for name, old, new in PATCHES:
        n = text.count(old)
        if n == 0:
            print(f"  [MISS] {name}: anchor not found (build drift?)")
            continue
        text = text.replace(old, new)
        applied += n
        print(f"  [ok]   {name}: {n} replacement(s)")
    open(MAIN, "wb").write(text.encode("utf8"))
    print(f"  wrote {MAIN}  ({applied} total replacements)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
