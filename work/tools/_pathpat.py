# -*- coding: utf-8 -*-
"""Canonical detection of "this file names the old workspace root".

Written without regular expressions and without escape sequences on purpose: the
marker contains backslashes, and every layer that re-encodes it (JSON, Python
literals, shells) is a chance to get it wrong -- which is exactly how a previous
scanner ended up reporting dozens of false positives.

    from _pathpat import has_root_marker, RELATIVE_RE, strip_marker
"""
import re

BS = chr(92)          # backslash
FS = chr(47)          # forward slash

#: plain substring markers, matched case-insensitively
MARKERS = (
    'h:' + FS + 'ai' + FS + 'frog',
    'h:' + BS + 'ai' + BS + 'frog',
)


def normalize(text):
    """Backslashes to forward slashes, runs collapsed, lower-cased.

    Collapsing matters: the same marker can be written with single backslashes
    (a raw string), doubled backslashes (an escaped literal) or forward slashes,
    and every spelling has to be recognised.
    """
    out = text.replace(BS, FS).lower()
    while FS + FS in out:
        out = out.replace(FS + FS, FS)
    return out


def has_root_marker(text):
    return MARKERS[0] in normalize(text)


def count_markers(text):
    return normalize(text).count(MARKERS[0])


def strip_marker(text):
    """<repo>/work/x -> work/x ; a bare root becomes <repo>."""
    out = []
    i = 0
    low = normalize(text)
    marker = MARKERS[0]
    while True:
        j = low.find(marker, i)
        if j < 0:
            out.append(text[i:])
            break
        out.append(text[i:j])
        k = j + len(marker)
        # consume the separator(s) and the rest of the path
        while k < len(text) and text[k] in (BS, FS):
            k += 1
        start = k
        while k < len(text) and text[k] not in ' \t\r\n`"\'()[],;':
            k += 1
        rest = text[start:k].replace(BS, FS)
        out.append(rest if rest else '<repo>')
        i = k
    return ''.join(out)


#: a file extension we care about when scanning a tree
CODE_EXT = ('.py', '.js', '.mjs', '.ps1', '.cs', '.java', '.cmd', '.bat', '.md')

#: directories that never need scanning (generated / vendored / huge)
SKIP_DIRS = {'.git', '__pycache__', 'resource', 'node_modules', 'shots', 'build',
             'portable-backup'}

_RE_CACHE = {}


def relative_re():
    """A regex that matches the marker with any mixture of separators."""
    if 'rx' not in _RE_CACHE:
        sep = '[' + BS + BS + BS + BS + '|' + BS + BS + '|' + FS + ']'
        _RE_CACHE['rx'] = re.compile('H:' + sep + '+AI' + sep + '+frog', re.I)
    return _RE_CACHE['rx']
