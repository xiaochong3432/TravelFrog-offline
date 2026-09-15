"""Print the full text of the client's setBenchTool / setBenchItem bodies."""
import re
import os

HERE = os.path.dirname(os.path.abspath(__file__))
src = open(os.path.join(HERE, '..', 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()

for fn in ['setBenchTool', 'setBenchItem', 'setCompostItem', 'requestBuy',
           'request_pocket_get', 'requestReplaceFur']:
    i = src.find('prototype.' + fn + '=')
    if i < 0:
        i = src.find('.' + fn + '=function')
    if i < 0:
        print('### %s : NOT FOUND' % fn)
        continue
    # take a generous slice and cut at the next "prototype." boundary
    j = src.find('prototype.', i + 20)
    seg = src[i:j if j > 0 else i + 1400]
    print('=' * 78)
    print('### %s' % fn)
    print('=' * 78)
    print(seg[:1400])
    print()
