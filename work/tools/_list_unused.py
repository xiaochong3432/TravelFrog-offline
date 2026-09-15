"""Print the UNUSED define.json scalars with their ORIGINAL values."""
import json
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
d = json.load(open(os.path.join(ROOT, 'run', 'engine', 'data', 'define.json'),
                   encoding='utf-8'))['scalars']
src = open(os.path.join(ROOT, 'run', 'engine', 'index.js'), encoding='utf-8').read()

unused = [k for k in sorted(d) if ("'%s'" % k) not in src]
print('unused scalars: %d\n' % len(unused))
for k in unused:
    print('  %-34s %s' % (k, repr(d[k])[:76]))
