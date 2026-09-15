#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""<repo>/...`, so any checkout on another
machine (or on Linux/macOS) failed immediately. The convention applied here is

    PROJECT_ROOT = Path(__file__).resolve().parents[2]      # <repo>/work/tools/x.py

and every literal that named the workspace root becomes an expression built from
it; paths inside comments and docstrings become prose `<repo>/...`.

    python work/tools/make_portable.py            # dry run: print what would change
    python work/tools/make_portable.py --apply    # rewrite (originals backed up)
    python work/tools/make_portable.py --apply --compile   # + py_compile check

Backups go to work/portable-backup/<path> so a bad rewrite can be undone.
"""
import argparse
import io
import os
import re
import shutil
import sys
import tokenize
import token as tokmod

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TOOLS = os.path.join(ROOT, 'work', 'tools')
BACKUP = os.path.join(ROOT, 'work', 'portable-backup')

# the literal we are replacing, in any escaping/spelling style
ROOT_RX = re.compile(r'H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog', re.I)

PREAMBLE_MARK = 'PROJECT_ROOT = _PortablePath(__file__).resolve().parents['


def preamble_for(depth):
    return (
        'from pathlib import Path as _PortablePath\n'
        '# 仓库根：按本文件自身位置推导（深度 %d），不写死任何绝对路径 ——\n'
        '# 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。\n'
        '%s%d]\n' % (depth, PREAMBLE_MARK, depth)
    )


def decoded_string(token_text):
    """Split `r"..."` into (prefix, quote, body) without interpreting escapes."""
    m = re.match(r'([rbfuRBFU]*)("""|\'\'\'|"|\')', token_text)
    if not m:
        return None
    prefix, quote = m.group(1), m.group(2)
    body = token_text[len(m.group(0)):len(token_text) - len(quote)]
    return prefix, quote, body


def unescape_backslashes(body):
    """<repo>/work` matches too."""
    return body.replace('\\\\', '\\')


def split_root(body):
    """-> (before, rest_after_root) or None."""
    m = ROOT_RX.search(body)
    if not m:
        m = ROOT_RX.search(unescape_backslashes(body))
        if not m:
            return None
        body2 = unescape_backslashes(body)
        m = ROOT_RX.search(body2)
        rest = body2[m.end():]
    else:
        rest = body[m.end():]
    rest = rest.replace('\\\\', '\\').replace('\\', '/')
    rest = rest.lstrip('/')
    return rest


def offset(lines, row, col):
    return sum(len(l) + 1 for l in lines[:row - 1]) + col


def line_text(lines, row):
    return lines[row - 1]


def standalone_string(tokens, i):
    """True when the STRING token stands alone as a statement (docstring/prose)."""
    prev = tokens[i - 1].type if i > 0 else tokmod.NEWLINE
    nxt = tokens[i + 1].type if i + 1 < len(tokens) else tokmod.NEWLINE
    return nxt in (tokmod.NEWLINE, tokmod.NL, tokmod.ENDMARKER) and \
        prev in (tokmod.NEWLINE, tokmod.NL, tokmod.INDENT, tokmod.DEDENT, tokmod.ENCODING)


def has_preamble(text):
    return 'PROJECT_ROOT' in text and '_PortablePath' in text


def insert_preamble(text, depth=2):
    """Insert after the module docstring / shebang, else at the very top."""
    lines = text.split('\n')
    # skip shebang / coding cookie / leading comments
    i = 0
    while i < len(lines) and (lines[i].startswith('#') or not lines[i].strip()):
        i += 1
    # skip a module docstring
    if i < len(lines):
        stripped = lines[i].lstrip()
        for q in ('"""', "'''"):
            if stripped.startswith(q):
                if stripped.count(q) >= 2 and len(stripped) > 3:
                    i += 1
                else:
                    i += 1
                    while i < len(lines) and q not in lines[i]:
                        i += 1
                    i += 1
                break
    lines.insert(i, preamble_for(depth).rstrip('\n'))
    return '\n'.join(lines)


def fix_file(path, apply_changes, depth=2):
    with io.open(path, encoding='utf8', errors='replace') as fh:
        text = fh.read()
    had_bom = text.startswith('\ufeff')
    if had_bom:
        text = text[1:]
    if 'H:' not in text and not ROOT_RX.search(text):
        return None
    lines = text.split('\n')
    edits = []          # (start, end, replacement, kind)
    code_hits = 0
    prose_hits = 0
    comment_hits = 0

    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError) as e:
        return ('tokenize-failed: %s' % e, 0, 0, 0)

    for i, t in enumerate(toks):
        kind = tokmod.tok_name.get(t.type, '')
        if kind in ('STRING', 'FSTRING_MIDDLE'):
            body = t.string
            if kind == 'STRING':
                parts = decoded_string(body)
                if not parts:
                    continue
                prefix, quote, inner = parts
                if 'b' in prefix.lower():
                    continue
            else:
                prefix, quote, inner = '', '', body
            rest = split_root(inner)
            if rest is None:
                continue
            start = offset(lines, t.start[0], t.start[1])
            end = offset(lines, t.end[0], t.end[1])
            if kind == 'FSTRING_MIDDLE':
                repl = '{PROJECT_ROOT}' + (('/' + rest) if rest else '')
                edits.append((start, end, repl, 'fstring'))
                code_hits += 1
                continue
            if standalone_string(toks, i) and 'f' not in prefix.lower():
                repl = (quote + '<repo>' + (('/' + rest) if rest else '') + quote)
                edits.append((start, end, repl, 'prose'))
                prose_hits += 1
                continue
            if 'f' in prefix.lower():
                repl = (prefix + quote + '{PROJECT_ROOT}'
                        + (('/' + rest) if rest else '') + quote)
                edits.append((start, end, repl, 'fstring'))
                code_hits += 1
                continue
            expr = 'str(PROJECT_ROOT)' + ((' + "' + '/' + rest + '"') if rest else '')
            edits.append((start, end, expr, 'code'))
            code_hits += 1
        elif kind == 'COMMENT' and ROOT_RX.search(t.string):
            new = ROOT_RX.sub('<repo>', t.string)
            new = new.replace('\\\\', '/').replace('\\', '/')
            start = offset(lines, t.start[0], t.start[1])
            end = offset(lines, t.end[0], t.end[1])
            edits.append((start, end, new, 'comment'))
            comment_hits += 1

    if not edits:
        return None
    if not apply_changes:
        return ('would change: %d code, %d prose, %d comment'
                % (code_hits, prose_hits, comment_hits), code_hits, prose_hits, comment_hits)

    if os.path.isfile(path):
        rel = os.path.relpath(path, ROOT)
        dst = os.path.join(BACKUP, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.isfile(dst):
            shutil.copy2(path, dst)

    # apply from the end so earlier offsets stay valid
    chars = list(text)
    for start, end, repl, _kind in sorted(edits, key=lambda e: -e[0]):
        chars[start:end] = list(repl)
    out = ''.join(chars)
    if code_hits and not has_preamble(out):
        out = insert_preamble(out, depth)
    if had_bom:
        out = '\ufeff' + out.lstrip('\ufeff')
    with io.open(path, 'w', encoding='utf8', newline='') as fh:
        fh.write(out)
    return ('changed: %d code, %d prose, %d comment'
            % (code_hits, prose_hits, comment_hits), code_hits, prose_hits, comment_hits)


def repair_bom(path):
    """A UTF-8 BOM must sit at offset 0; an earlier rewrite moved it into the body
    of files that got a preamble inserted. Put it back."""
    with io.open(path, encoding='utf8', errors='replace') as fh:
        text = fh.read()
    if '\ufeff' not in text:
        return False
    if text.startswith('\ufeff') and text.count('\ufeff') == 1:
        return False
    fixed = '\ufeff' + text.replace('\ufeff', '')
    rel = os.path.relpath(path, ROOT)
    dst = os.path.join(BACKUP, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.isfile(dst):
        shutil.copy2(path, dst)
    with io.open(path, 'w', encoding='utf8', newline='') as fh:
        fh.write(fixed)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true', help='write the changes')
    ap.add_argument('--compile', action='store_true', help='syntax-check every rewritten file')
    ap.add_argument('--check', action='store_true', help='syntax-check every tool script, no rewriting')
    ap.add_argument('--fix-bom', action='store_true', help='move a stray BOM back to offset 0')
    ap.add_argument('--only', default='', help='substring filter on the file name')
    args = ap.parse_args()

    # (path, depth): depth = how many levels the file sits below the repo root,
    # i.e. the index into Path(__file__).resolve().parents
    targets = []
    for f in sorted(os.listdir(TOOLS)):
        if f.endswith('.py') and args.only in f:
            targets.append((os.path.join(TOOLS, f), 2))
    work_dir = os.path.join(ROOT, 'work')
    for f in sorted(os.listdir(work_dir)):
        if f.endswith('.py') and args.only in f:
            targets.append((os.path.join(work_dir, f), 1))
    # archived one-off helpers kept as evidence (work/spec/_dumps/)
    dumps = os.path.join(ROOT, 'work', 'spec', '_dumps')
    if os.path.isdir(dumps):
        for f in sorted(os.listdir(dumps)):
            if f.endswith('.py') and args.only in f:
                targets.append((os.path.join(dumps, f), 3))

    if args.fix_bom:
        n = 0
        for p, _depth in targets:
            if repair_bom(p):
                n += 1
        print('BOM repaired in %d files' % n)
        return 0

    changed = []
    skipped = []
    for p, depth in targets:
        res = fix_file(p, args.apply, depth)
        if res is None:
            continue
        msg = res[0]
        rel = os.path.relpath(p, ROOT)
        if msg.startswith('tokenize-failed'):
            skipped.append((rel, msg))
            continue
        changed.append((rel, msg))

    print('%s %d files' % ('rewrote' if args.apply else 'would rewrite', len(changed)))
    for rel, msg in changed[:40]:
        print('   %-52s %s' % (rel, msg))
    if len(changed) > 40:
        print('   ... and %d more' % (len(changed) - 40))
    if skipped:
        print('\ncould not tokenize (needs manual look):')
        for rel, msg in skipped:
            print('   %-52s %s' % (rel, msg))

    if args.check or (args.compile and args.apply):
        bad = []
        check_list = [os.path.relpath(p, ROOT) for p, _d in targets]
        for rel in check_list:
            p = os.path.join(ROOT, rel)
            try:
                # utf-8-sig: a leading BOM is legal in a source FILE, but not when
                # the text is handed to compile() as a str.
                src = io.open(p, encoding='utf-8-sig', errors='replace').read()
                compile(src, p, 'exec')          # syntax only, writes nothing
            except SyntaxError as e:
                bad.append((rel, 'line %s: %s' % (e.lineno, e.msg)))
        print('\nsyntax check: %d ok, %d failed' % (len(check_list) - len(bad), len(bad)))
        for rel, msg in bad:
            print('   FAIL %-46s %s' % (rel, msg))
        return 1 if bad else 0
    return 0


if __name__ == '__main__':
    sys.exit(main())
