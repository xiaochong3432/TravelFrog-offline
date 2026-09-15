"""
Resolve Picture-table layer NAMES to real asset URLs.

Discovery: `resources.json` (1268 entries) is NOT the asset manifest -- it is a
partial resId->path table.  The real, complete manifest is the Egret bundle
manifest `resource/China/default.res.json` (4512 entries, each {url,type,name}).

Layer names in Picture.json are short art names (sky05, cloud01, back_g_beijing1).
The city/museum backgrounds live under images/Picture/<Picture.type>/ with the
`back_` prefix stripped:   back_g_beijing1 -> images/Picture/Goal/g_beijing1.png

This script measures how many of the distinct layer names can be resolved, and
by which strategy, WITHOUT guessing -- every strategy must be an exact
filename match against an authoritative manifest.
"""
import json
import os
import re
import collections
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
CHINA = os.path.join(ROOT, 'web', 'resource', 'China')

manifest = json.load(open(os.path.join(CHINA, 'default.res.json'), encoding='utf-8'))
resources = manifest['resources']
pictures = json.load(open(os.path.join(TABLES, 'Picture.json'), encoding='utf-8'))

# ---- authoritative index from the bundle manifest -------------------------
# url -> url ; basename(no ext) -> [urls]
by_base = collections.defaultdict(list)
for r in resources:
    url = r['url']
    base = os.path.splitext(os.path.basename(url))[0]
    by_base[base].append(url)
    # Egret also registers "name": "<base>_png" -- index that too so a layer
    # name that happens to be a res *name* still resolves.
    by_base[r['name']].append(url)


def cands(name, ptype):
    """Exact-match candidate asset names, most specific first."""
    out = []
    # 1. back_g_beijing1 -> g_beijing1   (city / museum backgrounds)
    m = re.match(r'^back_(.+)$', name)
    if m:
        out.append(m.group(1))
    # 2. raw name as-is
    out.append(name)
    # 3. rnd_pose_roof1 -> pose_roof1  (server picks one of a random set)
    m = re.match(r'^rnd_(.+)$', name)
    if m:
        out.append(m.group(1))
    return out


def resolve(name, ptype):
    """Return (url, strategy) or (None, None). Exact matches only."""
    if not name:
        return None, None
    for c in cands(name, ptype):
        # prefer the directory that matches this picture's type
        hits = by_base.get(c) or []
        pref = [u for u in hits if '/Picture/%s/' % ptype in u]
        if pref:
            return pref[0], 'typed'
        if hits:
            return hits[0], 'anydir'
    return None, None


used = collections.Counter()
strat = collections.Counter()
miss = []
per_pic_ok = 0
per_pic_partial = 0
per_pic_none = 0

sample_rows = []
for row in pictures:
    ptype = row.get('type', '')
    names = []
    for k in ('backImage', 'frontImage'):
        names += [n for n in (row.get(k) or []) if n]
    for k in ('frogPose', 'frogPose_s', 'effect'):
        if row.get(k):
            names.append(row[k])
    names += [n for n in (row.get('travelerPose') or []) if n]

    ok = 0
    for n in set(names):
        used[n] += 1
        url, s = resolve(n, ptype)
        if url:
            ok += 1
            strat[s] += 1
        else:
            miss.append((row.get('name'), ptype, n))
    if names and ok == len(set(names)):
        per_pic_ok += 1
    elif ok:
        per_pic_partial += 1
    else:
        per_pic_none += 1

total_names = sum(used.values())
print('Picture rows              : %d' % len(pictures))
print('layer-name occurrences    : %d' % total_names)
print('distinct layer names      : %d' % len(used))
print('resolved occurrences      : %d (%.1f%%)' % (sum(strat.values()),
      100.0 * sum(strat.values()) / max(1, total_names)))
print('  by strategy             : %s' % dict(strat))
print()
print('pictures fully resolvable : %d' % per_pic_ok)
print('pictures partially        : %d' % per_pic_partial)
print('pictures none resolvable  : %d' % per_pic_none)
print()
mc = collections.Counter(n for _, _, n in miss)
print('distinct UNRESOLVED names : %d' % len(mc))
for n, c in mc.most_common(25):
    print('   %-34s x%d' % (n, c))
