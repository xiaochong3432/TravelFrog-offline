from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import os, re
pats = [b"is_offline_game", b"index.html", b"file:///android_asset", b"assets/game",
        b"MainActivity", b"EjoyWebViewActivity", b"lxqw", b"login", b"Login",
        b".html"]
d = str(PROJECT_ROOT) + "/work/build/dex"
for f in sorted(os.listdir(d)):
    data = open(os.path.join(d, f), "rb").read()
    print("==", f, len(data))
    for p in pats:
        c = data.count(p)
        if c:
            print(f"   {p.decode():26s} {c}")
