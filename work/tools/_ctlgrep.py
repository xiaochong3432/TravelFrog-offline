from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
raw = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js","rb").read()
for pat in [b"colorBall", b"gachaColorBall", b"color_ball"]:
    print(f"  {pat.decode():16s} {raw.count(pat)}")
i = raw.find(b"colorBall")
print("  first colorBall context:", raw[i-70:i+40].decode("utf-8","replace") if i>=0 else "n/a")
