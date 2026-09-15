#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Estimate the language bar GitHub would show for a repository, and list the files
that still count — so a wrong-looking percentage can be traced to a missing
.gitattributes rule instead of guessed at.

This is an APPROXIMATION of github/linguist: it maps extensions to languages, then
applies the linguist-* attributes from .gitattributes (vendored / generated /
documentation / detectable) and linguist's own "prose" exclusion (Markdown and
friends never appear in the language bar). It does not run linguist's content
heuristics, so treat the numbers as "what still counts", not as exact bytes.

    python work/tools/lang_stats.py <repo-root> [--top 15]
"""
import argparse
import collections
import fnmatch
import io
import os
import re
import subprocess
import sys

# extension -> language (only what this repository actually contains, plus a few
# common ones so the tool is reusable)
LANG = {
    '.py': 'Python', '.pyw': 'Python',
    '.js': 'JavaScript', '.mjs': 'JavaScript', '.cjs': 'JavaScript', '.jsx': 'JavaScript',
    '.ts': 'TypeScript', '.json': 'JSON', '.json5': 'JSON',
    '.html': 'HTML', '.htm': 'HTML', '.css': 'CSS',
    '.ps1': 'PowerShell', '.psm1': 'PowerShell',
    '.bat': 'Batchfile', '.cmd': 'Batchfile',
    '.sh': 'Shell', '.bash': 'Shell',
    '.java': 'Java', '.cs': 'C#', '.c': 'C', '.h': 'C', '.cpp': 'C++',
    '.rb': 'Ruby', '.go': 'Go', '.rs': 'Rust', '.php': 'PHP',
    '.md': 'Markdown', '.markdown': 'Markdown', '.rst': 'reStructuredText',
}

#: linguist classifies these as prose/documentation by default -> never in the bar
PROSE = {'Markdown', 'reStructuredText', 'Textile', 'Org', 'AsciiDoc'}

#: unknown extensions are simply not counted
UNKNOWN_EXT = {'.txt', '.out', '.inc', '.clean', '.orig', '.log', '.dump', '.bak',
               '.pem', '.pk8', '.eab', '.atlas', '.fnt'}

BINARY_EXT = {'.png', '.jpg', '.jpeg', '.gif', '.mp3', '.mp4', '.apk', '.zip',
              '.jar', '.so', '.dex', '.exe', '.ttf'}


def parse_gitattributes(root):
    """-> list of (pattern, {attr: True/False}) in file order (later wins)."""
    path = os.path.join(root, '.gitattributes')
    if not os.path.isfile(path):
        return []
    rules = []
    for line in io.open(path, encoding='utf-8', errors='replace'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        pattern, rest = parts[0], parts[1:]
        attrs = {}
        for tok in rest:
            if tok.startswith('-'):
                attrs[tok[1:]] = False
            elif '=' in tok:
                name, val = tok.split('=', 1)
                attrs[name] = val.lower() not in ('false', '0', 'no')
            else:
                attrs[tok] = True
        rules.append((pattern, attrs))
    return rules


def match(pattern, rel):
    """gitattributes-style match (supporting ** and a leading/trailing pattern)."""
    p = pattern.lstrip('/')
    if p.endswith('/'):
        p += '**'
    if fnmatch.fnmatch(rel, p):
        return True
    if '/' not in p and fnmatch.fnmatch(os.path.basename(rel), p):
        return True
    # '**' spans directories in fnmatch too, but a bare dir needs its contents
    if fnmatch.fnmatch(rel, p + '/*'):
        return True
    return False


def attrs_for(rules, rel):
    out = {}
    for pattern, attrs in rules:
        if match(pattern, rel):
            out.update(attrs)
    return out


def main():
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap = argparse.ArgumentParser()
    ap.add_argument('root', nargs='?', default=os.path.join(here, 'git-repo'))
    ap.add_argument('--top', type=int, default=15)
    args = ap.parse_args()
    root = os.path.abspath(args.root)

    rules = parse_gitattributes(root)
    # GitHub 只统计**默认分支里被跟踪的文件**，所以这里也用 git 的清单；
    # 不在 git 仓库里时才退回遍历工作区（否则本地未跟踪的资源会被算进去）。
    tracked = None
    try:
        out = subprocess.run(['git', '-C', root, 'ls-files', '-z'],
                             capture_output=True, check=True).stdout.decode('utf-8', 'replace')
        tracked = [p for p in out.split('\0') if p]
    except Exception:
        tracked = None

    per_lang = collections.Counter()
    counted = []
    excluded = collections.Counter()

    def consider(rel, size):
        ext = os.path.splitext(rel)[1].lower()
        a = attrs_for(rules, rel)
        lang = LANG.get(ext)
        if ext in BINARY_EXT or ext in UNKNOWN_EXT or not lang:
            excluded['unknown/binary'] += size
            return
        if a.get('linguist-vendored') or a.get('linguist-generated') \
                or a.get('linguist-documentation'):
            excluded['attribute'] += size
            return
        if a.get('linguist-detectable') is False:
            excluded['not detectable'] += size
            return
        if lang in PROSE:
            excluded['prose (documentation)'] += size
            return
        per_lang[lang] += size
        counted.append((size, rel, lang))

    if tracked is not None:
        for rel in tracked:
            p = os.path.join(root, rel)
            if os.path.isfile(p):
                consider(rel.replace(os.sep, '/'), os.path.getsize(p))
    else:
        for dp, dn, fn in os.walk(root):
            dn[:] = [d for d in dn if d != '.git']
            for f in fn:
                p = os.path.join(dp, f)
                consider(os.path.relpath(p, root).replace(os.sep, '/'), os.path.getsize(p))

    total = sum(per_lang.values()) or 1
    print('language bar this .gitattributes would produce (%s):' % root)
    for lang, size in per_lang.most_common():
        print('   %-14s %8.1f KB  %5.1f%%' % (lang, size / 1024, 100.0 * size / total))
    print('   %-14s %8.1f KB' % ('TOTAL', total / 1024))
    print('\nexcluded: ' + ', '.join('%s %.1f MB' % (k, v / 1048576)
                                     for k, v in excluded.most_common()))

    print('\nbiggest files that still count:')
    for size, rel, lang in sorted(counted, reverse=True)[:args.top]:
        print('   %8.1f KB  %-14s %s' % (size / 1024, lang, rel))
    return 0


if __name__ == '__main__':
    sys.exit(main())
