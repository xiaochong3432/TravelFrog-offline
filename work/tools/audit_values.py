"""Numerical audit: which engine constants come from the original table, and
which ones are OUR choices?

The objective says "参考日版单机版与公开资料确定数值与规则", so the honest
deliverable is a table that separates:
  (a) values READ from define.json (the original server's own tuning table that
      shipped inside the client) -- these are restored;
  (b) values taken from the client's code/table literals (e.g. 7001, 100000,
      200001, 500x350);
  (c) values WE chose (offline pacing, prize pools, payout rates) -- these must
      never be presented as recovered;
  (d) define.json keys we consume but the file does NOT contain (a silent
      fallback bug: DEF() would quietly use our default).
"""
import json
import os
import re
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
ENGINE = os.path.join(ROOT, 'run', 'engine', 'index.js')
DEFINE = os.path.join(ROOT, 'run', 'engine', 'data', 'define.json')

src = open(ENGINE, encoding='utf-8').read()
define = json.load(open(DEFINE, encoding='utf-8'))
scalars = define.get('scalars', {})
maps = define.get('maps', {})

print('define.json: %d scalars, %d maps' % (len(scalars), len(maps)))
print()

# (a) DEF('KEY', fallback) usages
used = []
for m in re.finditer(r"DEF\(\s*'([A-Za-z0-9_]+)'\s*,\s*([^)]+)\)", src):
    used.append((m.group(1), m.group(2).strip(),
                 src[:m.start()].count('\n') + 1))
print('=== (a) values read from define.json via DEF() ===')
print('%-34s %-18s %-8s %s' % ('KEY', 'fallback', 'line', 'in define.json?'))
missing = []
for k, fb, ln in used:
    ok = k in scalars or k in maps
    if not ok:
        missing.append((k, ln, fb))
    print('  %-32s %-18s %-8d %s' % (k, fb, ln, 'yes' if ok else '*** NO ***'))
print()
if missing:
    print('  !! DEF() keys NOT in define.json (our fallback is silently used):')
    for k, ln, fb in missing:
        print('     %s (line %d, fallback %s)' % (k, ln, fb))
else:
    print('  every DEF() key exists in define.json -- no silent fallback')
print()

# (c) our own pacing / rate constants
print('=== (c) constants WE chose (not recovered) ===')
ours = []
for m in re.finditer(r'^const ([A-Z][A-Z0-9_]*)\s*=\s*(?:Number\()?process\.env\.([A-Z0-9_]+)\s*\|\|\s*([^)\n;]+)',
                     src, re.M):
    ours.append((m.group(1), m.group(2), m.group(3).strip()))
for name, env, dflt in ours:
    print('  %-32s env %-24s default %s' % (name, env, dflt))
print('  total: %d env-overridable knobs' % len(ours))
print()

# (d) define.json keys nothing consumes -- candidates for a mis-implemented feature
#
# NOTE: the engine reads SCALARS as DEF('KEY', ...) (quoted) but MAPS as
# `defineData.maps.KEY` / `maps.KEY` (UNQUOTED dot access). An earlier version of
# this audit only looked for the quoted form and therefore reported 24 of 25 maps
# as unused -- completely wrong. Check both forms.
print('=== (d) define.json keys the engine never reads ===')
import re as _re

txt = src


def reads(name):
    if ("'%s'" % name) in txt:
        return True
    return _re.search(r'(?:maps|defineData\.maps)\.' + _re.escape(name) + r'\b', txt) is not None


unused = [k for k in sorted(scalars) if not reads(k)]
unused_maps = [k for k in sorted(maps) if not reads(k)]
print('  scalars: %d of %d unused' % (len(unused), len(scalars)))
for i in range(0, len(unused), 6):
    print('    ' + ', '.join(unused[i:i + 6]))
print('  maps: %d of %d unused' % (len(unused_maps), len(maps)))
print('    ' + (', '.join(unused_maps) if unused_maps else '(none)'))
print()

# ---------------------------------------------------------------------------
# Which of those unused values are ACTIONABLE?
#
# A reusable test learned from four dead ends (CloverDestroyTime, ComposeId,
# every Tutorial* value, SHOP_TICKET_PER, PrizeClover): a value that appears
# exactly ONCE in main.min.js -- inside the Tabikaeru.Define literal itself --
# is never read by the client.  Its meaning lived in the server, so it is NOT
# recoverable and must not be guessed.  A value that appears MORE than once is
# read by real client code, so the rule it drives can be read out of that code.
# ---------------------------------------------------------------------------
CLIENT_JS = os.path.join(ROOT, 'run', 'web', 'js', 'main.min.js')
cj = open(CLIENT_JS, encoding='utf-8', errors='replace').read()


def client_reads(name):
    return cj.count(name) > 1


a = [k for k in (unused + unused_maps) if client_reads(k)]
b = [k for k in (unused + unused_maps) if not client_reads(k)]
print('=== actionable vs dead ends ===')
print('  (A) READ by client code -> the rule is recoverable (%d):' % len(a))
for i in range(0, len(a), 4):
    print('      ' + ', '.join(a[i:i + 4]))
print('  (B) Define-literal ONLY -> server-side, NOT recoverable (%d):' % len(b))
for i in range(0, len(b), 4):
    print('      ' + ', '.join(b[i:i + 4]))
