"""The lottery subsystem: protocol signatures, the model, and lotteryData.json."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol entries: lottery_* and item_gacha / item_redeem_prize')
print('=' * 78)
for key in ['lottery_load:', 'item_gacha:', 'item_redeem_prize:']:
    m = re.search(re.escape(key), src)
    print('%-22s %s' % (key, src[m.start():m.start() + 130].replace('\n', ' ') if m else 'NOT FOUND'))
print()

for pat, win, limit in [(r'LotteryModel', 1200, 1),
                        (r'lottery_open', 420, 2),
                        (r'lottery_select', 420, 2),
                        (r'lottery_confirm_reward', 420, 2)]:
    print('=' * 78)
    print('### %s' % pat)
    print('=' * 78)
    seen = set()
    n = 0
    for mm in re.finditer(pat, src):
        seg = src[max(0, mm.start() - win):mm.start() + win].replace('\n', ' ')
        if seg[:50] in seen:
            continue
        seen.add(seg[:50])
        print(seg)
        print('-' * 40)
        n += 1
        if n >= limit:
            break
    print()

T = os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables')
d = json.load(open(os.path.join(T, 'lotteryData.json'), encoding='utf-8'))
print('--- lotteryData.json (%s, %d) ---' % (type(d).__name__, len(d)))
print(json.dumps(d, ensure_ascii=False)[:900])
