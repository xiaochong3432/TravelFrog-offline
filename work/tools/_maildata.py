from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os
D = str(PROJECT_ROOT) + "/work/run/engine/data/tables"
out = open(str(PROJECT_ROOT) + "/work/build/mail_data.txt","w",encoding="utf-8")
me = json.load(open(os.path.join(D,"MailEvent.json"), encoding="utf-8"))
out.write("MailEvent (full):\n")
out.write(json.dumps(me, ensure_ascii=False, indent=1)[:1800] + "\n")
out.close(); print("ok")
