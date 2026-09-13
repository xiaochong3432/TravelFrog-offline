#!/usr/bin/env python3
"""Dump the core SocketManage / ServiceDispatcher implementation (wire format)."""
import re

JS = r"H:\AI\frog\work\base\assets\game\js\main.min.js"
d = open(JS, "rb").read().decode("utf8", "replace")

i = d.find("e.SocketManage=t,__reflect")
print("===== SocketManage class =====")
print(d[i - 6000:i + 400])
