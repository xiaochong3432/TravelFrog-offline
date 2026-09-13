#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Exhaustive scan of a repository for anything that identifies THIS machine.

Unlike paths_audit2.py / show_leftovers.py (source extensions, heavy dirs skipped),
this walks EVERY file — binary assets included — and reports:

  MACHINE  the old workspace root, in any spelling: single backslashes (raw
           string), doubled backslashes (escaped literal), forward slashes, or the
           UTF-16LE form inside a binary
  USER     the local Windows profile (drive-letter + Users + account name) or a
           temp directory
  DRIVE    another drive-absolute path that is NOT a well-known OS/tool location

Well-known locations are reported separately as OK, because scripts legitimately
fall back to them (a browser under Program Files, the .NET compiler under Windows,
/usr/bin and /Applications on POSIX). The marker itself is built here from chr()
codes, so this file never contains the string it hunts for.

    python work/tools/scan_machine_paths.py <repo-root> [--git]

Exit code 1 when MACHINE / USER / DRIVE findings exist, so it can gate a commit.
"""
import argparse
import io
import os
import re
import sys

BS = chr(92)
FS = chr(47)
USER = os.environ.get('USERNAME') or os.environ.get('USER') or ''

MARKER_TEXT = 'H:' + BS + 'AI' + BS + 'frog'
MARKER_FWD = 'h:' + FS + 'ai' + FS + 'frog'

# A drive-absolute path, but only when it really starts a path: not preceded by a
# letter (that would make it the tail of a URL like http://127.0.0.1/) and followed
# by a separator and a name.
DRIVE_RX = re.compile(r'(?<![A-Za-z0-9])[A-Za-z]:[\\/][A-Za-z0-9_.\-\\/ ]{2,}')

#: acceptable, portable fallbacks / placeholders (matched against a normalised
#: line: backslashes collapsed, so `C:\\Program Files` and `C:\Program Files` both hit)
OK_RX = re.compile(
    r'<repo>|<仓库根>|<path>|/path/to|d:/your|'
    r'[a-z]:/program files|[a-z]:/windows\b|/windows/|%windir%|%programfiles%|'
    r'[a-z]:/android|frog_|android_home|java_home', re.I)

#: things that must never ship
USER_RX = re.compile(r'[A-Za-z]:[\\/]{1,2}Users[\\/]|AppData[\\/]{1,2}Local[\\/]{1,2}Temp', re.I)
USER_NAME_RX = re.compile(
    (r'/Users/' + re.escape(USER) + r'/|/home/' + re.escape(USER) + r'/'), re.I) if USER else None

#: an escape sequence inside a printed format string ("...delta=%d:\n      ours")
FORMAT_RX = re.compile(r'[\\]{1,2}[nrt"\'\\]')

SKIP_DIRS = {'.git', '__pycache__'}
BINARY_EXT = {'.png', '.jpg', '.jpeg', '.gif', '.mp3', '.mp4', '.eab', '.apk',
              '.zip', '.so', '.jar', '.dex', '.ttf', '.fnt', '.atlas', '.pk8', '.pem'}


def norm(text):
    out = text.replace(BS, FS).lower()
    while FS + FS in out:
        out = out.replace(FS + FS, FS)
    return out


def scan_bytes(data):
    """Marker hits in a raw blob: ASCII, forward-slash spelling, and UTF-16LE.

    This runs for EVERY file (not just the binary ones) because a text-named file
    can still be UTF-16 — which is exactly how two archived PowerShell error dumps
    slipped past a UTF-8-only scan.
    """
    hits = []
    low = data.lower()
    for text, label in ((MARKER_TEXT, 'ascii'), (MARKER_FWD, 'ascii-fwd')):
        if text.encode('utf-8') in low:
            hits.append(label)
    if MARKER_TEXT.encode('utf-16-le') in low:
        hits.append('utf16le')
    if USER:
        for name in ('users', 'home'):
            probe = (name + FS + USER).encode('utf-8')
            if probe in low:
                hits.append('user-profile')
                break
    return hits


def main():
    here = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap = argparse.ArgumentParser()
    ap.add_argument('root', nargs='?', default=os.path.join(here, 'git-repo'))
    ap.add_argument('--git', action='store_true', help='also scan .git')
    args = ap.parse_args()
    root = os.path.abspath(args.root)
    if args.git:
        SKIP_DIRS.discard('.git')

    machine = []
    users = []
    drives = []
    ok_hits = 0
    n_files = 0

    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in SKIP_DIRS]
        for f in fn:
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, root).replace(os.sep, '/')
            n_files += 1
            # byte scan first: catches UTF-16 and binary payloads regardless of name
            try:
                with io.open(p, 'rb') as fh:
                    blob = fh.read()
            except OSError:
                blob = b''
            byte_hits = scan_bytes(blob) if blob else []
            if byte_hits:
                (users if 'user-profile' in byte_hits else machine).append(
                    (rel, 'bytes: ' + ', '.join(byte_hits)))
            if os.path.splitext(f)[1].lower() in BINARY_EXT:
                continue
            try:
                text = io.open(p, encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            for i, line in enumerate(text.split('\n'), 1):
                low = norm(line)
                if MARKER_FWD in low:
                    machine.append((rel, 'L%d: %s' % (i, line.strip()[:120])))
                    continue
                if USER_RX.search(line) or (USER_NAME_RX and USER_NAME_RX.search(line)):
                    users.append((rel, 'L%d: %s' % (i, line.strip()[:120])))
                    continue
                for m in DRIVE_RX.finditer(line):
                    got = m.group(0).strip()
                    if OK_RX.search(norm(got)) or OK_RX.search(low):
                        ok_hits += 1
                        continue
                    if FORMAT_RX.search(got):
                        ok_hits += 1          # escape sequence in a format string
                        continue
                    drives.append((rel, 'L%d: %s' % (i, got[:100])))

    def dump(title, rows, limit=30):
        print('\n== %s: %d' % (title, len(rows)))
        for rel, l in rows[:limit]:
            print('   %-50s %s' % (rel, l))
        if len(rows) > limit:
            print('   ... and %d more' % (len(rows) - limit))

    print('scanned %d files under %s' % (n_files, root))
    dump('MACHINE (old workspace root)', machine)
    dump('USER (profile / temp path)', users)
    dump('DRIVE (absolute path, not a known tool location)', drives)
    print('\n(accepted fallbacks, e.g. Program Files / Windows / Android SDK: %d)' % ok_hits)

    bad = len(machine) + len(users) + len(drives)
    print('\nresult: %s (%d findings)' % ('FOUND' if bad else 'CLEAN', bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
