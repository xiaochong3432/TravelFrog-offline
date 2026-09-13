#!/usr/bin/env python3
"""Find what pops the "new title" notification, and the help/exit menu buttons."""
import re

JS = r"H:\AI\frog\work\run\web\js\main.min.js"
THEME = r"H:\AI\frog\work\run\web\js\default.thm.js"

with open(JS, encoding="utf-8", errors="replace") as fh:
    s = fh.read()
with open(THEME, encoding="utf-8", errors="replace") as fh:
    th = fh.read()

for pat in [r"RoleEventType\.loadRole", r"AchieveTips", r"AchieveGet", r"TitleGet",
            r"getAchieveList\(\)\.length"]:
    hits = list(re.finditer(pat, s))
    print("=" * 16, pat, "(%d)" % len(hits))
    for m in hits[:5]:
        a, b = max(0, m.start() - 420), min(len(s), m.end() + 420)
        print("  JS @%d ...%s..." % (m.start(), s[a:b].replace("\n", " ")))
        print()

# the theme: which skins exist for achievements, and what does the help menu contain?
print("=" * 16, "theme: skins mentioning Achieve / Title / Help / Menu")
for m in re.finditer(r"generateEUI\.paths\['([^']+)'\]\s*=\s*(?:window\.)?(\$?[A-Za-z0-9_$]+)", th):
    p = m.group(1)
    if re.search(r"Achieve|Title|Help|Menu|Setting|System", p):
        print("   %-62s %s" % (p, m.group(2)))

print()
print("=" * 16, "theme: literal labels that look like menu entries")
for m in re.finditer(r't\.text = "([^"]{2,14})"', th):
    t = m.group(1)
    if re.search(r"协议|客服|退出|帮助|设置|联系|声明|隐私|礼包|兑换|公告|关于", t):
        cls = None
        decls = list(re.finditer(r"window\.(\$?[A-Za-z0-9_$]+)\s*=\s*\(function", th[:m.start()]))
        if decls:
            cls = decls[-1].group(1)
        paths = [mm.group(1) for mm in re.finditer(
            r"generateEUI\.paths\['([^']+)'\]\s*=\s*(?:window\.)?" + re.escape(cls or "@@") + r"\b", th)]
        print("   %-12s cls=%-18s skin=%s" % (t, cls, paths[0] if paths else "?"))
