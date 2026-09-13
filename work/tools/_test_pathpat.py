# -*- coding: utf-8 -*-
"""Self-test for _pathpat (the marker detector used by the portability tools)."""
import io
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _pathpat as pp  # noqa: E402

BS = chr(92)
FS = chr(47)
CANDIDATES = [
    ('X = r"' + 'H:' + BS + 'AI' + BS + 'frog' + BS + 'work' + BS + 'x"', True),
    ('Y = "H:' + FS + 'AI' + FS + 'frog' + FS + 'base.apk"', True),
    ('Z = "H:' + BS + BS + 'AI' + BS + BS + 'frog' + BS + BS + 'work"', True),
    ('W = "H:' + BS + 'AI' + BS + 'frog"', True),
    ('nothing to see', False),
    ('/home/user/frog/work', False),
]

fails = 0
for text, expect_hit in CANDIDATES:
    hit = pp.has_root_marker(text)
    stripped = pp.strip_marker(text)
    print('%-46s hit=%-5s -> %s' % (text.replace(BS, '\\')[:44], hit, stripped.replace(BS, '\\')))
    if hit != expect_hit:
        print('   !! expected hit=%s' % expect_hit)
        fails += 1

# the regex used against one line of source
line = 'APK = r"' + 'H:' + BS + 'AI' + BS + 'frog' + BS + 'base.apk"'
print('regex finds:', pp.relative_re().findall(line), '(expect 1)')
if len(pp.relative_re().findall(line)) != 1:
    fails += 1

print('self-test:', 'OK' if not fails else 'FAIL(%d)' % fails)
sys.exit(1 if fails else 0)
