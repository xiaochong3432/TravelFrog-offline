"""Move the STORY helper block out of the state object to module level."""
import sys

P = r'H:\AI\frog\work\run\engine\index.js'
s = open(P, encoding='utf-8').read()

START = '  /* ---- 故事 (StoryModel) ---'
ENDMARK = '    book.newId = id;\n    return id;\n  }\n'
i = s.find(START)
j = s.find(ENDMARK)
if i < 0 or j < 0:
    print('markers not found', i, j)
    sys.exit(1)
k = j + len(ENDMARK)
block = s[i:k]
s2 = s[:i] + s[k:]

anchor = '  const ANIM = (gamedata.tables && gamedata.tables.animpictureData) || {};'
a = s2.find(anchor)
if a < 0:
    print('anchor not found')
    sys.exit(1)
s3 = s2[:a] + block + '\n' + s2[a:]
open(P, 'w', encoding='utf-8', newline='').write(s3)
print('moved %d chars; file %d chars' % (len(block), len(s3)))

# sanity: storyBook must still be a STATE key (4-space indent)
import re
for m in re.finditer(r'^\s{4}storyBook\s*:', s3, re.M):
    print('storyBook at line', s3[:m.start()].count('\n') + 1)
