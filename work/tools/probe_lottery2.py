import re
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

m = re.search(r'LotteryState;!function', src)
print('=== LotteryState ===')
print(src[m.start():m.start() + 300].replace('\n', ' ') if m else 'NOT FOUND')
print()

needle = "addProtocolCallback('lottery_load')"
i = src.find(needle)
if i < 0:
    needle = 'addProtocolCallback("lottery_load")'
    i = src.find(needle)
print('=== the model that binds lottery_load ===')
j = src.rfind('var LotteryModel', 0, i) if i > 0 else -1
if j > 0:
    print(src[j:j + 800].replace('\n', ' '))
else:
    print(src[max(0, i - 1000):i + 300].replace('\n', ' '))
print()

d = json.load(open(os.path.join(HERE, '..', 'run', 'engine', 'data', 'tables',
                                'lotteryData.json'), encoding='utf-8'))
print('lotteryData top keys:', list(d.keys()))
for k in d:
    v = d[k]
    print('  %-14s %s len=%d' % (k, type(v).__name__, len(v)))
    if k != 'select_list':
        print('     sample:', json.dumps(v, ensure_ascii=False)[:400])
