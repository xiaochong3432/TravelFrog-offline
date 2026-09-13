#!/usr/bin/env python3
"""Find the rename UI: the view whose applyInput() calls roleModel.setName().

We want to drive the real BUTTON, not just the model, so we need the class names
of the panel that owns `t_name` (its input) and `btn_yes`.
"""
import io
import os
import re
import sys

ROOT = r"H:\AI\frog\work"
C = io.open(os.path.join(ROOT, "run", "web", "js", "main.min.js"),
            encoding="utf-8", errors="replace").read()

out = io.StringIO()
i = C.find("applyInput=function")
# walk backwards for the nearest `var X=function(e){function t(){`
seg = C[max(0, i - 9000):i]
names = re.findall(r"var ([A-Za-z_][A-Za-z0-9_]*)=function\(e\)\{function t\(\)", seg)
out.write("view class before applyInput: %s\n" % names[-3:])
out.write(C[max(0, i - 1500):i + 900].replace("\n", " ") + "\n\n")

out.write("=== role model class (owns setName/getName) ===\n")
j = C.find("t.prototype.setUseAchieveID=function")
seg2 = C[max(0, j - 12000):j]
m = re.findall(r"var ([A-Za-z_][A-Za-z0-9_]*)=function\(e\)\{function t\(\)\{var t=[^;]{0,120}", seg2)
out.write("candidates: %s\n" % m[-4:])
for mm in re.finditer(r"var ([A-Za-z_][A-Za-z0-9_]*)=function\(e\)\{function t\(\)\{[^\n]{0,200}", C):
    if "frogMotion=-1" in mm.group(0):
        out.write("ROLE MODEL = %s\n   %s\n" % (mm.group(1), mm.group(0)[:300]))

out.write("\n=== who opens the rename panel? ===\n")
for kw in ["applyInput", "openRoleView", "RoleViewControl", "RenameView"]:
    out.write("%s: %d hits\n" % (kw, C.count(kw)))

sys.stdout = io.open(os.path.join(ROOT, "logs", "rename_ui.txt"), "w", encoding="utf-8")
sys.stdout.write(out.getvalue())
print("wrote logs/rename_ui.txt")
