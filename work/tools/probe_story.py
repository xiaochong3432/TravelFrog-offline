"""The story (故事) subsystem: protocol usage and the table."""
import re
import os
import json

HERE = os.path.dirname(os.path.abspath(__file__))
TU = os.path.abspath(os.path.join(HERE, '..'))
src = open(os.path.join(TU, 'run', 'web', 'js', 'main.min.js'),
           encoding='utf-8', errors='replace').read()
engine = open(os.path.join(TU, 'run', 'engine', 'index.js'), encoding='utf-8').read()

for kw in ['story_send_gift"', 'story_feedback_gift"', 'story_read_new_story"',
           'story_load']:
    hits = [m.start() for m in re.finditer(re.escape(kw), src)]
    print('=' * 74)
    print('### %s : %d hits' % (kw, len(hits)))
    print('=' * 74)
    if hits:
        print(src[max(0, hits[0] - 600):hits[0] + 400].replace('\n', ' '))
    print()

d = json.load(open(os.path.join(TU, 'run', 'engine', 'data', 'tables', 'story.json'),
                   encoding='utf-8'))
print('story.json keys:', list(d.keys()))
print('  const:', json.dumps(d.get('const'), ensure_ascii=False))
st = d.get('story') or []
print('  rows: %d' % len(st))
for r in st[:2]:
    print('   ', json.dumps(r, ensure_ascii=False)[:260])

print()
print('engine handlers:')
for kw in ['story_load', 'story_send_gift', 'story_feedback_gift', 'story_read_new_story']:
    m = re.search(r'^\s{4}' + kw + r'\s*:', engine, re.M)
    print('  %-24s %s' % (kw, 'present' if m else 'MISSING'))
