#!/usr/bin/env python3
"""Tidy-ups after installing the ball: drop the duplicate installOfflineAds() call the
earlier patch left in the watchdog, and replace a silly string-substitution colour."""
import io
import re

P = r"H:\AI\frog\work\run\web\__probe.js"
src = io.open(P, encoding="utf-8").read()

# 1. duplicate call inside the watchdog
dup = "        try { installOfflineAds(); } catch (e) { }\n            try { installOfflineAds(); } catch (e) { }\n"
if src.count(dup) == 1:
    src = src.replace(dup, "        try { installOfflineAds(); } catch (e) { }\n")
    print("duplicate installOfflineAds() removed")
else:
    # fall back to a regex in case the indentation differs
    hits = list(re.finditer(r"( *try \{ installOfflineAds\(\); \} catch \(e\) \{ \}\n)+", src))
    for h in hits:
        block = h.group(0)
        lines = [l for l in block.strip("\n").split("\n")]
        if len(lines) > 1:
            src = src[:h.start()] + lines[0] + "\n" + src[h.end():]
            print("collapsed %d duplicate calls" % (len(lines) - 1))
            break

# 2. the colour hack
bad = "'margin-top:8px;word-break:break-all;color:#6b6season'.replace('season', '553');"
good = "'margin-top:8px;word-break:break-all;color:#6b6553';"
if src.count(bad) == 1:
    src = src.replace(bad, good)
    print("colour literal cleaned")

io.open(P, "w", encoding="utf-8").write(src)
print("installOfflineAds call sites:", src.count("installOfflineAds();"))

# 3. does the file still parse?
import subprocess
check = r"H:\AI\frog\work\tools\check_shell.js"
io.open(check, "w", encoding="utf-8").write(
    "const fs=require('fs');\n"
    "const t=fs.readFileSync(process.argv[2],'utf8');\n"
    "try { new Function(t); console.log('shell parses OK; ball:', t.includes('__save_ball'),"
    " 'panel:', t.includes('__save_panel'), 'travel_now:', t.includes('travel_now')); }\n"
    "catch (e) { console.log('SYNTAX ERROR: ' + e.message); process.exit(1); }\n")
r = subprocess.run(["node", check, P], capture_output=True, text=True)
print(r.stdout.strip() or r.stderr.strip())
