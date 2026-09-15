from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import zipfile
z = zipfile.ZipFile(str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk")
eng = z.read("assets/game/__offline-engine.js")
print(f"  __offline-engine.js {len(eng):,} bytes")
for probe in [b"Frogpattern", b"friendly", b"encyclopediaPayload", b"furniture_flowerpot_harvest", b"task_get_reward", b"checkAchievements", b"rollGuestGift", b"define.json"]:
    print(f"    {probe.decode():32s} {'present' if probe in eng else 'ABSENT'}")
print(f"  index.html {z.getinfo('assets/game/index.html').file_size:,} bytes")
