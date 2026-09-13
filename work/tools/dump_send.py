#!/usr/bin/env python3
"""Print the SocketManage.send() envelope construction, wrapped for readability."""
import re

d = open(r"H:\AI\frog\work\socketmanage.txt", encoding="utf8").read()
i = d.find("t.prototype.send=function")
seg = d[i:i + 2200]
# naive wrap for readability
seg = re.sub(r'([;,{}])', r'\1\n', seg)
open(r"H:\AI\frog\work\sm_send.txt", "w", encoding="utf8").write(seg)
print(seg[:2600])
