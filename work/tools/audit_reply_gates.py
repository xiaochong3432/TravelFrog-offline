"""Find protocol commands whose CLIENT callback gates a FLOW on a reply field.

The tutorial bug was exactly this shape: the handler did not exist, so the reply
was `{}`, `i.ok` was undefined, and the client re-entered a view forever.

This scans main.min.js for `send("<cmd>", new core.ActionN(function (X) { ... }))`
and reports which reply FIELDS the callback reads -- so we can tell "missing
reward" (harmless) from "the UI never proceeds" (a stall).

Usage: python audit_reply_gates.py [--unimpl]
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..'))
JS = os.path.join(ROOT, 'run', 'web', 'js', 'main.min.js')
ENGINE = os.path.join(ROOT, 'run', 'engine', 'index.js')

src = open(JS, encoding='utf-8', errors='replace').read()
engine = open(ENGINE, encoding='utf-8').read()

protocol = None
pj = os.path.join(ROOT, 'run', 'engine', 'protocol.json')
if os.path.exists(pj):
    protocol = json.load(open(pj, encoding='utf-8'))
if not protocol:
    # the authoritative list lives in the engine's own protocol module
    import subprocess
    out = subprocess.run(
        ['node', '-e', "process.stdout.write(JSON.stringify(require('./run/engine/protocol')))"],
        cwd=ROOT, capture_output=True, text=True)
    protocol = json.loads(out.stdout)

cmds = sorted(protocol.keys())
unimpl = [c for c in cmds if not re.search(r'(^|[\s,{])' + re.escape(c) + r'\s*:', engine, re.M)]

# Find, for one command, the reply fields its callback reads.
FIELD_RE = re.compile(r'(?<![A-Za-z0-9_.])(?:i|n|e|r|t|o|a|s|c)\s*\.\s*([a-z_][a-z0-9_]*)')


def reply_fields(cmd):
    out = {}
    for m in re.finditer(re.escape('"' + cmd + '"'), src):
        seg = src[m.start():m.start() + 900]
        cm = re.search(r'new core\.Action\d\(function\s*\(([^)]*)\)\s*\{', seg)
        if not cm:
            continue
        argnames = [a.strip() for a in cm.group(1).split(',') if a.strip()]
        if not argnames:
            continue
        first = argnames[0]
        body = seg[cm.end():cm.end() + 700]
        for fm in re.finditer(r'(?<![A-Za-z0-9_.])' + re.escape(first) + r'\s*\.\s*([a-z_][a-z0-9_]*)', body):
            f = fm.group(1)
            out[f] = out.get(f, 0) + 1
    return out


targets = unimpl if ('--unimpl' in sys.argv or True) else cmds
print('commands with NO handler: %d\n' % len(unimpl))
print('%-30s %s' % ('command', 'reply fields the client reads'))
print('-' * 78)
interesting = []
for c in targets:
    f = reply_fields(c)
    if not f:
        continue
    keys = ','.join(sorted(f.keys()))
    print('%-30s %s' % (c, keys))
    # a flow gate is a boolean-ish field read as a condition
    for k in f:
        if k in ('ok', 'state', 'code', 'type', 'id', 'day', 'num', 'count', 'index'):
            interesting.append((c, k, keys))
            break
print()
print('candidates worth a closer look (boolean/id-style gates):')
for c, k, keys in interesting:
    print('  %-28s reads %s   [%s]' % (c, k, keys))
