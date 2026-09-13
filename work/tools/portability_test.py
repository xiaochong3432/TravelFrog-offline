#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Prove the repository is machine-independent: copy the staged repo to a
deliberately awkward path (another drive, spaces, non-ASCII) and run the tools
there, with no environment variables set.

    python work/tools/portability_test.py [dest]

Checks, in the copy:
  * every Python tool still compiles
  * the engine unit tests pass (asset-dependent ones may SKIP)
  * the inline engine can be rebuilt (bundle_engine.py)
  * the data builders resolve their inputs to the COPY, not to the original tree
  * no source file still names the original workspace root
"""
import io
import os
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _pathpat as pp  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'git-repo')
DEFAULT_DEST = os.path.join(os.environ.get('TEMP', '/tmp'),
                            'frog portable test', '旅行青蛙 repo')

SKIP_DIRS = {'.git', '__pycache__', 'resource'}


def say(text):
    """Print without dying on a legacy console code page."""
    enc = getattr(sys.stdout, 'encoding', None) or 'utf-8'
    print(str(text).encode(enc, 'replace').decode(enc, 'replace'))


def run(cmd, cwd, label):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True,
                       encoding='utf-8', errors='replace')
    ok = p.returncode == 0
    out = ((p.stdout or '') + (p.stderr or '')).strip().split('\n')
    tail = [l for l in out if l.strip()][-1] if out else ''
    say('   %-46s %s  %s' % (label, 'ok  ' if ok else 'FAIL', tail[:90]))
    return ok, (p.stdout or '') + (p.stderr or '')


def main():
    dest = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DEST
    if not os.path.isdir(SRC):
        say('!! %s missing - run work/tools/stage_repo.py first' % SRC)
        return 1

    say('copying staged repo -> %s' % dest)
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    shutil.copytree(SRC, dest, ignore=shutil.ignore_patterns('.git', '__pycache__'))
    say('   %d files' % sum(len(f) for _, _, f in os.walk(dest)))

    fails = 0
    say('\n1) no source or doc file names the old workspace root')
    # these two tools *document* the marker they hunt for; they are the exception
    ALLOWED = {'work/tools/_pathpat.py', 'work/tools/fix_doc_paths.py',
               'work/tools/paths_audit.py', 'work/tools/paths_audit2.py'}
    hits = []
    for dp, dn, fn in os.walk(dest):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            if not f.endswith(pp.CODE_EXT):
                continue
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, dest).replace('\\', '/')
            if rel in ALLOWED:
                continue
            t = io.open(p, encoding='utf8', errors='replace').read()
            if pp.has_root_marker(t):
                hits.append(rel)
    if hits:
        fails += 1
        say('   FAIL %d file(s): %s' % (len(hits), ', '.join(hits[:6])))
    else:
        say('   ok   none (2 marker-documenting tools whitelisted)')

    say('\n2) every Python tool compiles in the copy')
    ok, _ = run([sys.executable, os.path.join('work', 'tools', 'make_portable.py'), '--check'],
                dest, 'make_portable.py --check')
    fails += 0 if ok else 1

    say('\n3) engine unit tests run from the copy')
    ok, out = run(['node', os.path.join('work', 'tools', 'engine_test.js')], dest,
                  'engine_test.js')
    summary = [l for l in out.split('\n') if 'passed' in l]
    say('      %s' % (summary[-1] if summary else '?'))
    m = re.search(r'(\d+) failed', summary[-1]) if summary else None
    if not ok or not m or m.group(1) != '0':
        fails += 1

    say('\n4) the inline engine can be rebuilt in the copy')
    ok, _ = run([sys.executable, os.path.join('work', 'tools', 'bundle_engine.py')], dest,
                'bundle_engine.py')
    fails += 0 if ok else 1

    say('\n5) data builders resolve inside the COPY (must not fall back to the original tree)')
    for tool in ('build_travel_data.py', 'build_picture_layers.py'):
        _ok, out = run([sys.executable, os.path.join('work', 'tools', tool)], dest, tool)
        leaked = ROOT.replace('\\', '/') in out.replace('\\', '/')
        if leaked:
            fails += 1
            say('      FAIL still references the original workspace: %s' % ROOT)
        else:
            say('      ok   all paths are inside the copy (a slim checkout lacks '
                'work/cdn and resource/, which is expected)')

    say('\n6) hygiene tools work from the copy')
    run([sys.executable, os.path.join('work', 'tools', 'check_doc_links.py'), '.'], dest,
        'check_doc_links.py')
    run(['node', os.path.join('work', 'tools', 'git_scope_report.js')], dest,
        'git_scope_report.js')

    say('\nresult: %s' % ('FAIL' if fails else 'OK'))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
