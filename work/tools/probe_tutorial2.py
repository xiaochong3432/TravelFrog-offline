"""What the client expects from the four tutorial commands."""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

for key in ['tutorial_step_open_door_q"', 'tutorial_step_ask_award_q"',
            'tutorial_step_open_door"', 'tutorial_step_ask_award"']:
    print('=' * 78)
    print('### send("%s")' % key.strip('"'))
    print('=' * 78)
    hits = [m.start() for m in re.finditer(re.escape(key), src)]
    if not hits:
        print('  (no sender found)')
    for h in hits[:3]:
        print(src[max(0, h - 420):h + 420].replace('\n', ' '))
        print('-' * 40)
    print()

print('=' * 78)
print('### guideStep writers (who advances the guide?)')
print('=' * 78)
seen = set()
n = 0
for m in re.finditer(r'guideStep\s*=', src):
    seg = src[max(0, m.start() - 260):m.start() + 200].replace('\n', ' ')
    if seg[:50] in seen:
        continue
    seen.add(seg[:50])
    print(seg)
    print('-' * 40)
    n += 1
    if n >= 4:
        break
