"""Print the client's own code around given protocol command names.

This exists because the whole method here is "read main.min.js, don't guess".
Minified code has no line breaks, so we print a window around each hit.
"""
import re
import sys
import os

HERE = os.path.dirname(os.path.abspath(__file__))
JS = os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js')

src = open(JS, encoding='utf-8', errors='replace').read()

cmds = sys.argv[1:]
if not cmds:
    cmds = ['furniture_putin_bench', 'furniture_takeout_bench',
            'furniture_putin_box', 'furniture_takeout_box',
            'furniture_replace_compost', 'furniture_replace_pocket',
            'furniture_replace_tumbler', 'furniture_replace_fur',
            'furniture_buy_shop', 'furniture_pocket_get']

win = int(os.environ.get('WIN', '700'))
for c in cmds:
    print('=' * 78)
    print('### %s' % c)
    print('=' * 78)
    hits = [m.start() for m in re.finditer(re.escape("'" + c + "'"), src)]
    hits += [m.start() for m in re.finditer(re.escape('"' + c + '"'), src)]
    if not hits:
        print('  (not found)')
        continue
    for h in hits[:3]:
        seg = src[max(0, h - win):h + win]
        print(seg.replace('\n', ' '))
        print('-' * 40)
    print()
