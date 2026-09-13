#!/usr/bin/env python3
"""Dump the login-phase response handlers (client_hello / hall_gen_token / hall_login)."""
import re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

out = []
i = d.find("t.prototype.client_hello=function")
seg = d[i - 1200:i + 2600]
out.append("===== login-phase handlers (UserModel / NetworkControl) =====")
out.append(re.sub(r'([;{}])', r'\1\n', seg))

j = d.find("client_load_role=function", 210000)
out.append("\n\n===== client_load_role (model side) =====")
out.append(re.sub(r'([;{}])', r'\1\n', d[j:j + 3200]))

txt = "\n".join(out)
open(r"H:\AI\frog\work\login_flow.txt", "w", encoding="utf8").write(txt)
print(f"wrote work/login_flow.txt ({len(txt)} chars)")
