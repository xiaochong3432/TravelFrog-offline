from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import re

d = open(str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js", 'rb').read().decode('utf8', 'replace')
pats = ['FRIEND_VISIT_RNDPER', 'FRIEND_VISIT_RNDSEC', 'FRIEND_VISIT_COOL',
        'FRIEND_VISIT_ACTCOUNT', 'FRIEND_RNDPOS_MAX', 'FRIEND_ITEM_DEBUFF',
        'FRIEND_GIFTPER_NORMAL', 'FRIEND_GIFTPER_RARE', 'FRIEND_GIFTFIX',
        'FRIEND_GIFTBOUNUS', 'StartCloverPoint', 'DAYTIME_COUNT', 'FourLeafCloverID',
        'SHOP_TICKET_PER', 'PrizeClover', 'PRIZE_WHITE_ID']
out = []
for p in pats:
    ms = list(re.finditer(re.escape(p), d))
    out.append('== %-24s hits=%d' % (p, len(ms)))
    for m in ms:
        out.append('   [%d] %s' % (m.start(), d[max(0, m.start() - 120):m.start() + 160].replace('\n', ' ')))
open(str(PROJECT_ROOT) + "/work/spec/out_friendconst.txt", 'w', encoding='utf8').write('\n'.join(out))
print('\n'.join(out))
