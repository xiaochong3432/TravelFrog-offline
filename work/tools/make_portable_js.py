#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Portability pass for the JavaScript and PowerShell helpers: same convention as
make_portable.py, but for the other languages.

    node-style (CJS)  const PROJECT_ROOT = require('path').resolve(__dirname, '..', '..')
    ESM (.mjs)        const PROJECT_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
    PowerShell        $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Every literal that named the workspace root becomes an expression built from it.

    python work/tools/make_portable_js.py            # dry run
    python work/tools/make_portable_js.py --apply    # rewrite (originals backed up)
    python work/tools/make_portable_js.py --check    # syntax check only
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BACKUP = os.path.join(ROOT, 'work', 'portable-backup')

TARGETS = [
    ('work/check_save_robustness.js', 1),
    ('work/tools/ach_coverage.js', 2),
    ('work/tools/eab_decode.js', 2),
    ('work/compare-capabilities.mjs', 1),
    ('work/diff-client-builds.mjs', 1),
    ('work/diff-runs.mjs', 1),
    ('work/fetch-raw.mjs', 1),
    ('work/probe-our-windows.mjs', 1),
    ('work/probe-their-gameplay.mjs', 1),
    ('fetch_lot.ps1', 0),
    ('work/tools/fetch.ps1', 2),
    ('work/tools/fetch2.ps1', 2),
    ('work/tools/test_launcher_port.ps1', 2),
]

#: extra scripts discovered on the fly (probe helpers, one-off debuggers…)
SKIP_DIRS = {'.git', '__pycache__', 'resource', 'node_modules', 'shots', 'build',
             'jdk', 'jre', 'bt', 'plat', 'adb', 'cdn', 'jp_apk', 'logs', 'raw',
             'extracted', 'full', 'base', 'merge-backup', 'spec', 'jsdiff',
             'compare-eab', 'compare-res', 'from-their-apk', 'conv', 'portable-backup',
             'v3web', 'v3check'}


def discover():
    """Every .js/.mjs under work/ that is not inside a skipped directory."""
    found = []
    for dp, dn, fn in os.walk(os.path.join(ROOT, 'work')):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in sorted(fn):
            if not f.endswith(('.js', '.mjs')):
                continue
            p = os.path.join(dp, f)
            depth = len(os.path.relpath(p, ROOT).split(os.sep)) - 1
            found.append((os.path.relpath(p, ROOT).replace(os.sep, '/'), depth))
    return found

ROOT_RX_JS = re.compile(r"""(['"`])((?:[^'"`\\]|\\.)*?H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog(?:[^'"`]*?))\1""",
                        re.I)
ROOT_RX_PS = re.compile(r"""(['"])((?:[^'"]*?)H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog(?:[^'"]*?))\1""",
                        re.I)


def rest_of(body):
    m = re.search(r'H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog', body, re.I)
    rest = body[m.end():]
    rest = rest.replace('\\\\', '\\').replace('\\', '/').lstrip('/')
    return rest


def backup(path):
    rel = os.path.relpath(path, ROOT)
    dst = os.path.join(BACKUP, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if not os.path.isfile(dst):
        shutil.copy2(path, dst)


def preamble_js(text, depth, esm):
    """只补该文件缺的那几行 —— 有些文件把 import 写在注释块之后，
    盲目插入会造成 'Identifier path has already been declared'。"""
    if esm:
        lines = []
        if not re.search(r"from\s+'node:path'|require\('path'\)", text):
            lines.append("import path from 'node:path';")
        if 'fileURLToPath' not in text:
            lines.append("import { fileURLToPath } from 'node:url';")
        if lines:
            lines.append('')
        expr = ("path.resolve(path.dirname(fileURLToPath(import.meta.url))"
                + (', ' + ', '.join(["'..'"] * depth) if depth else '') + ')')
        lines.append('// 仓库根：按本文件自身位置推导，不写死绝对路径')
        lines.append('const PROJECT_ROOT = %s;' % expr)
    else:
        lines = ['// 仓库根：按本文件自身位置推导，不写死绝对路径']
        expr = ("require('path').resolve(__dirname"
                + (', ' + ', '.join(["'..'"] * depth) if depth else '') + ')')
        lines.append('const PROJECT_ROOT = %s;' % expr)
    # insert after the last leading import/require block
    src_lines = text.split('\n')
    i = 0
    while i < len(src_lines) and (src_lines[i].startswith('#!') or not src_lines[i].strip()):
        i += 1
    while i < len(src_lines) and re.match(r"\s*(import |const .*=\s*require\(|let .*=\s*require\()",
                                          src_lines[i]):
        i += 1
    src_lines[i:i] = [''] + lines
    return '\n'.join(src_lines)


def preamble_ps(depth):
    expr = '$PSScriptRoot' if depth == 0 else \
        'Split-Path -Parent (' * depth + '$PSScriptRoot' + ')' * depth
    return ('# 仓库根：按脚本自身位置推导，不写死绝对路径\n'
            '$ProjectRoot = %s\n' % expr)


def read_text(path):
    """Read a file, remembering whether it had a UTF-8 BOM (it must stay at offset 0)."""
    text = io.open(path, encoding='utf8', errors='replace').read()
    had_bom = text.startswith('\ufeff')
    return (text[1:] if had_bom else text), had_bom


def write_text(path, text, had_bom):
    if had_bom:
        text = '\ufeff' + text.lstrip('\ufeff')
    io.open(path, 'w', encoding='utf8', newline='').write(text)


def repair_bom(path):
    text, had_bom = read_text(path)
    if had_bom and '\ufeff' not in text:
        return False
    if not had_bom and '\ufeff' not in text:
        return False
    backup(path)
    write_text(path, text, True)
    return True


def is_node_program(text):
    """True when the file is a standalone Node script rather than a page fragment.

    work/probe/ also holds snippets that cdp_drive evaluates INSIDE the game page
    (they use `core`, `egret`, top-level await). Those must not receive a Node
    preamble, and `node --check` is not a valid syntax check for them.
    """
    head = '\n'.join(text.split('\n')[:25])
    return ('require(' in head) or ('import ' in head and ' from ' in head) \
        or text.startswith('#!')


def fix_js(path, depth, apply_changes):
    text, had_bom = read_text(path)
    if not re.search(r'H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog', text, re.I):
        return None
    esm = path.endswith('.mjs') or bool(re.search(r'^\s*import .* from ', text, re.M))
    node_program = is_node_program(text)

    def repl(m):
        quote, body = m.group(1), m.group(2)
        rest = rest_of(body)
        if quote == '`':
            return quote + '${PROJECT_ROOT}' + (('/' + rest) if rest else '') + quote
        if not node_program:
            # a page fragment has no filesystem context: leave an explicit
            # placeholder instead of a path that only worked on one machine
            return quote + '<repo>' + (('/' + rest) if rest else '') + quote
        return 'PROJECT_ROOT + ' + quote + '/' + rest + quote if rest else 'PROJECT_ROOT'

    new = ROOT_RX_JS.sub(repl, text)
    n = len(ROOT_RX_JS.findall(text))
    if not apply_changes:
        return 'would change %d literal(s)%s' % (n, '' if node_program else ' (page fragment)')
    added = node_program and 'PROJECT_ROOT' not in text
    if added:
        new = preamble_js(new, depth, esm)
    backup(path)
    write_text(path, new, had_bom)
    return 'changed %d literal(s)%s' % (
        n, ' + preamble' if added else (' (page fragment: placeholder only)' if not node_program else ''))


def fix_ps(path, depth, apply_changes):
    text, had_bom = read_text(path)
    if not re.search(r'H:(?:\\\\|\\|/)+AI(?:\\\\|\\|/)+frog', text, re.I):
        return None

    def repl(m):
        rest = rest_of(m.group(2))
        return "(Join-Path $ProjectRoot '%s')" % rest

    new = ROOT_RX_PS.sub(repl, text)
    n = len(ROOT_RX_PS.findall(text))
    if not apply_changes:
        return 'would change %d literal(s)' % n
    if '$ProjectRoot' not in text:
        lines = new.split('\n')
        i = 0
        while i < len(lines) and lines[i].startswith('#'):
            i += 1
        lines[i:i] = preamble_ps(depth).split('\n')
        new = '\n'.join(lines)
    backup(path)
    write_text(path, new, had_bom)
    return 'changed %d literal(s)' % n


def syntax_check(path):
    if path.endswith(('.js', '.mjs')):
        r = subprocess.run(['node', '--check', path], capture_output=True, text=True)
        return r.returncode == 0, (r.stderr or '').strip().split('\n')[0]
    if path.endswith('.ps1'):
        ps = ("$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile("
              "'%s',[ref]$null,[ref]$e); if($e.Count){ $e[0].Message } else { 'ok' }"
              % path.replace("'", "''"))
        last = ''
        for shell in ('pwsh', 'powershell'):
            try:
                r = subprocess.run([shell, '-NoProfile', '-Command', ps],
                                   capture_output=True, text=True)
            except FileNotFoundError:
                last = '%s not found' % shell
                continue
            out = (r.stdout or '').strip()
            return out == 'ok', out or (r.stderr or '').strip().split('\n')[0]
        return False, last or 'no powershell available'
    return True, ''


BROWSER_FILES = [
    'work/tools/cdp_drive.js', 'work/tools/cdp_console.js', 'work/tools/cdp_probe.js',
    'work/tools/cdp_shot.js', 'work/tools/save_persist_test.js',
    'work/tools/save_restart_test.js',
]

# The replacement lives in a .inc file on purpose: it contains double backslashes
# and a regex literal, and generating that text through nested escaping is exactly
# how it got corrupted once already.
BROWSER_INC = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           '_browser_resolver.js.inc')

EDGE_RX = re.compile(r"^const EDGE = .*$", re.M)


def browser_js():
    return io.open(BROWSER_INC, encoding='utf-8').read().rstrip('\n')


def fix_browser_paths(apply_changes):
    for rel in BROWSER_FILES:
        p = os.path.join(ROOT, rel.replace('/', os.sep))
        if not os.path.isfile(p):
            print('   MISSING %s' % rel)
            continue
        text, had_bom = read_text(p)
        if 'FROG_BROWSER' in text:
            print('   %-46s already portable' % rel)
            continue
        if not EDGE_RX.search(text):
            print('   %-46s no EDGE constant' % rel)
            continue
        if not apply_changes:
            print('   %-46s would replace the EDGE constant' % rel)
            continue
        backup(p)
        write_text(p, EDGE_RX.sub(lambda _m: browser_js(), text, count=1), had_bom)
        print('   %-46s replaced EDGE constant' % rel)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apply', action='store_true')
    ap.add_argument('--check', action='store_true')
    ap.add_argument('--fix-bom', action='store_true', help='move a stray BOM back to offset 0')
    ap.add_argument('--browser', action='store_true', help='make the Edge/Chrome path portable')
    args = ap.parse_args()

    # fixed list + everything discovered under work/ (probe helpers, debuggers…)
    all_targets = list(TARGETS) + [t for t in discover() if t not in TARGETS]

    if args.browser:
        fix_browser_paths(args.apply)
        return 0

    if args.fix_bom:
        n = 0
        for rel, _depth in all_targets:
            p = os.path.join(ROOT, rel.replace('/', os.sep))
            if os.path.isfile(p) and repair_bom(p):
                print('   BOM repaired: %s' % rel)
                n += 1
        print('BOM repaired in %d files' % n)
        return 0

    if args.check:
        bad = 0
        skipped = 0
        for rel, _depth in all_targets:
            p = os.path.join(ROOT, rel.replace('/', os.sep))
            if not os.path.isfile(p):
                print('   MISSING %s' % rel)
                bad += 1
                continue
            text = io.open(p, encoding='utf-8-sig', errors='replace').read()
            if p.endswith(('.js', '.mjs')) and not is_node_program(text):
                skipped += 1
                continue          # page fragment: checked by loading it in the browser
            ok, msg = syntax_check(p)
            print('   %-46s %s' % (rel, 'ok' if ok else 'FAIL ' + msg))
            bad += 0 if ok else 1
        print('syntax check: %d ok, %d failed, %d skipped (page fragments)'
              % (len(all_targets) - bad - skipped, bad, skipped))
        return 1 if bad else 0

    for rel, depth in all_targets:
        p = os.path.join(ROOT, rel.replace('/', os.sep))
        if not os.path.isfile(p):
            print('   MISSING %s' % rel)
            continue
        res = fix_ps(p, depth, args.apply) if p.endswith('.ps1') else fix_js(p, depth, args.apply)
        if res is None:
            continue
        print('   %-46s %s' % (rel, res))
    return 0


if __name__ == '__main__':
    sys.exit(main())
