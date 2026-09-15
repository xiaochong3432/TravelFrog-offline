from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re
p = str(PROJECT_ROOT) + "/work/run/engine/protocol.js"
src = open(p, encoding="utf-8").read()
if "notify_new_mail" in src:
    print("already present")
else:
    # push-only message: the client registers a handler but never sends it
    entry = (' "notify_new_mail": {\n'
             '  "needResponse": false,\n'
             '  "params": [],\n'
             '  "note": "push-only: registered via addProtocolCallback; absent from ProtocolList"\n'
             ' },\n')
    src = src.replace("module.exports = {\n", "module.exports = {\n" + entry, 1)
    open(p, "w", encoding="utf-8").write(src)
    print("added notify_new_mail to protocol.js")
