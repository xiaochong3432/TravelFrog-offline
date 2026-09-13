#!/usr/bin/env python3
"""Report the current offline-build state."""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os, json

WEB = str(PROJECT_ROOT) + "/work/run/web"
MAIN = os.path.join(WEB, "js", "main.min.js")
d = open(MAIN, encoding="utf8").read()

checks = [
    # The enterGame gate must stay INTACT: it is what sequences scene creation
    # after the role payload, so checkGuide() sees guideStep=Complete rather than
    # the default "New" (which would open the Welcome/开始 screen).
    ("enterGame gate left intact (sequencing)", 'true&&(Music.play("BGM_Default"' not in d),
    ("season key clamp patched", "a>=1&&a<=4&&b>=1&&b<=4" in d),
    ("season-gate bypass removed", "Promise.resolve()).then(function(){ResourceLoader" not in d),
    ("pristine baseline kept", os.path.exists(MAIN + ".clean")),
    ("index.html points at local launcher", 'loadSingleScript("launcher.js' in open(os.path.join(WEB, "index.html"), encoding="utf8").read()),
    ("offline shell script present", os.path.exists(os.path.join(WEB, "__probe.js"))),
    ("route B engine bundle present", os.path.exists(os.path.join(WEB, "__offline-engine.js"))),
    ("index.html loads engine bundle",
     '__offline-engine.js' in open(os.path.join(WEB, "index.html"), encoding="utf8").read()),
]
for name, ok in checks:
    print(f"  [{'ok ' if ok else 'MISS'}] {name}")

cfg = json.load(open(os.path.join(WEB, "resource", "China", "config", "gameConfig.json"), encoding="utf8"))
print(f"  channelType = {cfg['channelType']}  useNode = {cfg['useNode']}  "
      f"gameServer = {cfg['serverList'][cfg['useNode']]['gameServer']}")

save = str(PROJECT_ROOT) + "/work/run/save/save.json"
if os.path.exists(save):
    s = json.load(open(save, encoding="utf8"))
    print(f"  save: clover={s['clover']} ticket={s['ticket']} uid={s['uid']} clovers={len(s['clovers'])} slots")
