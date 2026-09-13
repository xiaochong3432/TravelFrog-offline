"""The tutorial (新手引导) flow -- does a brand-new save stall on it?"""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

print('=' * 78)
print('### protocol entries')
print('=' * 78)
for key in ['tutorial_step_open_door:', 'tutorial_step_ask_award:',
            'client_load_all_info:', 'guideStep']:
    m = re.search(re.escape(key), src)
    print('%-28s %s' % (key, src[m.start():m.start() + 130].replace('\n', ' ')
                        if m else 'NOT FOUND'))
print()

for pat, win, limit in [(r'tutorial_step_open_door', 600, 2),
                        (r'tutorial_step_ask_award', 600, 2),
                        (r'GuideStep', 300, 3),
                        (r'guideStep', 300, 4)]:
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
    if n == 0:
        print('  (no match)')
    print()
