import re

d = open(r'H:\AI\frog\work\base\assets\game\js\main.min.js', 'rb').read().decode('utf8', 'replace')
out = []
for p in ['cloverPow', 'flagValue', 'taste', 'rowItemId', 'CharaDB', 'aniName', 'rndPos']:
    ms = list(re.finditer(re.escape(p), d))
    out.append('== %s  hits=%d' % (p, len(ms)))
    for m in ms[:4]:
        out.append('   [%d] %s' % (m.start(), d[max(0, m.start() - 200):m.start() + 200].replace('\n', ' ')))
open(r'H:\AI\frog\work\spec\out_charafields.txt', 'w', encoding='utf8').write('\n'.join(out))
print('\n'.join(out))
