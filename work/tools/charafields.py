from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

d = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js", 'rb').read().decode('utf8', 'replace')
out = []
for p in ['cloverPow', 'flagValue', 'taste', 'rowItemId', 'CharaDB', 'aniName', 'rndPos']:
    ms = list(re.finditer(re.escape(p), d))
    out.append('== %s  hits=%d' % (p, len(ms)))
    for m in ms[:4]:
        out.append('   [%d] %s' % (m.start(), d[max(0, m.start() - 200):m.start() + 200].replace('\n', ' ')))
open(str(PROJECT_ROOT) + "/work/spec/out_charafields.txt", 'w', encoding='utf8').write('\n'.join(out))
print('\n'.join(out))
