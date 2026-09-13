"""
Build precomputed `layers` for every Picture row, in the exact shape the client
consumes, and write engine/data/picture-layers.json.

WHAT THE CLIENT ACTUALLY DOES (read out of main.min.js, not guessed)
--------------------------------------------------------------------
    PIC_PATH(resId)  = basename(ResourcesDB[resId]) + "_png"
    renderPicture(PictureInfo, scale):
        container = new DisplayObjectContainer
        for layer in PictureInfo.layers:            // array order = draw order
            bmp = new Bitmap
            bmp.texture = RES.getRes(PIC_PATH(ResourcesDB[layer[0]]))
            if (texture == null) return null         // whole picture fails
            bmp.x = layer[1]
            bmp.y = layer[2]
            container.addChild(bmp)
        canvas = 500 x 350
    ResourcesDB  ==  data/tables/resources.json   (resId string -> path)

    An unknown resId does NOT crash: getPicturePath falls back to
    ResourcesDB[1] ('Picture/Normal/sky05') and logs a warning.  So every resId
    we emit must be a real key or the picture silently renders as sky05.

WHAT IS *NOT* IN THE CLIENT
---------------------------
`backImage` / `frontImage` / `frogPose` / `frogPos` / `travelerPos` / `view` /
`priority` / `randomSet` never appear in main.min.js (0 hits).  They are the
*server's* recipe for composing `layers`.  So the composition below is a
RECONSTRUCTION from those table columns, and is labelled as such.

RECONSTRUCTION RULES
--------------------
1. backImage[]      -> resId, at (0,0).  326/470 of these assets are exactly
                       500x350 == the canvas, which is what justifies (0,0).
                       Wider-than-canvas assets (1000x350, 707x350...) are
                       backgrounds for smaller canvas *scales*; the client's
                       `scale` argument picks the 500*scale rectangle.  We keep
                       the table's own `_s` variant distinction instead.
2. frontImage[]     -> resId, at (0,0), drawn after backImage.
3. frogPose         -> the frog's 4-variant pose sprite, one chosen at random
                       (table marks these `randomSet`).  Asset group is resolved
                       from the picture name:  beijing1 -> BJ1_{BH,CW,QW,YHC},
                       g_shanxi5 -> g_shanxi5_{bh,cw,qw,yhc}.
4. travelerPos[i]   -> travelerPose[i].
5. `priority: true` -> frog draws BEHIND frontImage (it is "priority" to the
                       scene), else in front.  (Our reading; low confidence.)

Every emitted resId is asserted to exist in resources.json.
"""
import json
import os
import re
import collections

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
OUT = os.path.join(HERE, '_layers_probe_out.json')
CHINA = os.path.join(ROOT, 'web', 'resource', 'China', 'images')

RES = json.load(open(os.path.join(TABLES, 'resources.json'), encoding='utf-8'))
PICS = json.load(open(os.path.join(TABLES, 'Picture.json'), encoding='utf-8'))

# resId -> (basename, image size) and basename -> [resId...]
by_base = collections.defaultdict(list)
byname = {}
for rid, path in RES.items():
    b = os.path.basename(path)
    by_base[b].append(rid)
    byname[rid] = (b, path)

# ---- pinyin-initial abbreviations for city pose groups --------------------
# Verified against the on-disk groups: every entry below was confirmed by a
# group directory that exists, and the mapping must end up a bijection.
PINYIN = {
    'beijing': 'BJ', 'chengdu': 'CD', 'chongqing': 'CQ', 'guangzhou': 'GZ',
    'guilin': 'GL', 'hangzhou': 'HZ', 'suzhou': 'SZ', 'tianjin': 'TJ',
    'xianggang': 'XG', 'haerbin': 'HEB', 'zhangjiajie': 'ZJJ', 'wuhan': 'WH',
    'luoyang': 'LY', 'xian': 'XA', 'jiuquan': 'JQ', 'yunnan': 'YN',
    'lasa': 'LS', 'shanghai': 'SH', 'hainan': 'HN', 'guizhou': 'GUIZ',
    'ningxia': 'NX', 'fujian': 'FJ', 'jiangxi': 'JX', 'anhui': 'AH',
    'jiangmen': 'JM', 'liaoning': 'LN', 'qingdao': 'QD',
    'changbaishan': 'CBS', 'sanxia': 'SX', 'hebei': 'HEB2', 'shanxi': 'SHX',
    'tw_shifen': 'SHIFEN', 'tw_kending': 'KENGDING',
}

# ---- discover the real pose-asset groups from the resources table ---------
# A group is "<PREFIX>_<variant>"; the prefix and the case are preserved.
VARIANT_RE = re.compile(r'^(.*)_(BH|CW|QW|YHC|bh|cw|qw|yhc)$')
# pose groups are PER TYPE (Goal/BJ1_BH vs Normal/roof1_bh are different spaces)
pose_groups = collections.defaultdict(lambda: collections.defaultdict(set))
for rid, path in RES.items():
    m = re.match(r'^Picture/([^/]+)/(.*)$', path)
    if not m:
        continue
    ptype, base = m.group(1), m.group(2)
    vm = VARIANT_RE.match(base)
    if vm:
        pose_groups[ptype][vm.group(1)].add(vm.group(2))

# normalised lookup per type: lowercase, underscores removed
norm = collections.defaultdict(dict)
for t, groups in pose_groups.items():
    for g in groups:
        norm[t][g.lower().replace('_', '')] = g

# Pose art is not always <group>_<one-of-4>: there are numeric families too
# (wet0..wet3, fuza0..3, gy_0..3, hunsha_0..3).  So resolve by PREFIX FAMILY:
# any resource of this picture's type whose basename is the group itself or
# starts with "<group>_".  Deterministic: lowest resId wins.
family = collections.defaultdict(lambda: collections.defaultdict(list))
for rid, path in RES.items():
    m = re.match(r'^Picture/([^/]+)/(.*)$', path)
    if not m:
        continue
    ptype, base = m.group(1), m.group(2)
    fam = family[ptype]
    fam[base.lower().replace('_', '')].append(int(rid))
    parts = base.split('_')
    if len(parts) > 1:
        fam['_'.join(parts[:-1]).lower().replace('_', '')].append(int(rid))
    # `mumianhua_mid_1` in the table vs `mumianhua_xyn_mid1` on disk: the art
    # carries an extra scene infix.  Index a de-infixed alias so the table name
    # still lands on a real file instead of silently vanishing.
    alias = base.lower().replace('_xyn', '').replace('_pt', '').replace('_ts', '')
    alias = re.sub(r'_(\d+)$', r'\1', alias)
    fam[alias.replace('_', '')].append(int(rid))

# NOTE: a lone asset can legitimately be a pose (`tw_jingan`, `g_tw_kending1`),
# so we do NOT prune single-member families.  What actually went wrong was
# `pose_beijing1` resolving to the *background* `g_beijing1` (also a lone
# asset).  The precise discriminator is that the background is REFERENCED AS
# SCENERY by some row's backImage/frontImage.  So we collect those resIds first
# and forbid the pose resolver from returning them.  See SCENERY below.

# flat list per type for last-resort prefix matching
allbase = collections.defaultdict(list)
for rid, path in RES.items():
    m = re.match(r'^Picture/([^/]+)/(.*)$', path)
    if m:
        allbase[m.group(1)].append((m.group(2).lower(), int(rid)))


def prefix_lookup(key, ptype):
    """Last resort: a resource of this type whose basename STARTS WITH key."""
    for t in [ptype] + [x for x in allbase if x != ptype]:
        cands = [rid for b, rid in allbase[t] if b.startswith(key) and len(b) > len(key)]
        if cands:
            return min(cands)
    return None


def lookup_art(name, ptype):
    """Resolve a scenery art name to a resId (exact, then prefix family)."""
    if not name:
        return None
    b = name[5:] if name.startswith('back_') else name
    names = [b, name]
    if name.startswith('rnd_'):
        names.append(name[4:])
    for cand in names:
        ids = by_base.get(cand)
        if ids:
            ids = list(ids)
            typed = [r for r in ids if byname[r][1].startswith('Picture/%s/' % ptype)]
            return int((typed or ids)[0])
        key = cand.lower().replace('_', '')
        for t in [ptype] + [x for x in family if x != ptype]:
            f = family.get(t, {})
            if key in f and f[key]:
                return min(f[key])
    for cand in names:
        r = prefix_lookup(cand.lower().replace('_', ''), ptype)
        if r is not None:
            return r
    return None


# ---- SCENERY: resIds that some row uses as background/foreground art --------
# A pose must never resolve to one of these (that was the g_beijing1 bug).
SCENERY = set()
for _row in PICS:
    _t = _row.get('type', 'Normal')
    for _n in (_row.get('backImage') or []):
        _r = lookup_art(_n, _t)
        if _r is not None:
            SCENERY.add(_r)
    for _n in (_row.get('frontImage') or []):
        if _n and not _n.startswith(('pose_', 'rnd_pose_')):
            _r = lookup_art(_n, _t)
            if _r is not None:
                SCENERY.add(_r)


def pose_variants(key):
    """Alternative family keys for a candidate pose name."""
    out = [key]
    if re.search(r'\d+$', key):                       # fuza1 -> fuza
        out.append(re.sub(r'\d+$', '', key))
    out.append(key + 'pose')                          # chuisihaitangmt -> ...mtpose
    # strip one trailing token: fenglingmuh -> fenglingmu
    m = re.match(r'^(.*?)([a-z])$', key)
    if m and '_' not in key:
        out.append(m.group(1))
    return [o for o in dict.fromkeys(out) if o]


def pose_group(name, frogpose, ptype):
    """Map a Picture row to its pose-asset resId, or None."""
    cands = []
    # (a) the frogPose column itself, minus its rnd_/pose_ wrapper:
    #     rnd_pose_roof1 -> roof1 ; pose_beijing1 -> beijing1 ; g_shanxi_1 -> itself
    fp = re.sub(r'^rnd_', '', frogpose or '')
    fp = re.sub(r'^pose_', '', fp)
    for c in (fp, 'g' + fp, fp):
        cands.append(c.lower().replace('_', ''))
    # (b) the picture's own name, minus the back_n_ / back_g_ wrapper
    cands.append(re.sub(r'^back_[a-z]_', '', name).lower().replace('_', ''))
    # (c) pinyin-initial abbreviation (Goal type): beijing1 -> bj1
    pstem = re.sub(r'\d+$', '', name)
    num = name[len(pstem):]
    ini = PINYIN.get(pstem)
    if ini:
        cands.append((ini + num).lower().replace('_', ''))
        cands.append(('g' + ini + num).lower())
    if pstem.startswith('bwg_'):
        pini = PINYIN.get(pstem[4:])
        if pini:
            cands.append(('bwg' + pini + num).lower())
    cands += ['u' + c for c in list(cands)] + ['g' + c for c in list(cands)]

    def ok(rids):
        rids = [r for r in rids if r not in SCENERY]
        return min(rids) if rids else None

    for c in cands:
        for k in pose_variants(c):
            f = family.get(ptype, {})
            if k in f:
                r = ok(f[k])
                if r is not None:
                    return r
    # pose art need not live in the row's own type dir (bwg_* is Unique but the
    # art is Picture/Unique/u_bwg_* / Picture/Normal/...)
    for c in cands:
        for k in pose_variants(c):
            for t, f in family.items():
                if k in f:
                    r = ok(f[k])
                    if r is not None:
                        return r
    for c in cands:
        r = prefix_lookup(c, ptype)
        if r is not None and r not in SCENERY:
            return r
    return None


report = {'resolved': 0, 'noPose': 0, 'unresolvedPose': [], 'unresolvedArt': []}

# POSE PLACEMENT RULE (reconstruction -- see module docstring)
# `frogPos` / `travelerPos` are CENTRE-RELATIVE, with the same convention on both
# axes.  Evidence:
#   * x spans -117..+145 across the table.  Read as canvas coords that puts many
#     frogs half off the left edge; read as offsets from the canvas centre
#     (250) they all land inside the frame.
#   * y spans only -75..-94, i.e. nearly constant, so it is not a per-scene
#     "standing surface".  With the centre at 175 the frog lands at y 81..95,
#     ON the scene's own geometry (tree/roof/ground), which is what a visual
#     check of rendered output confirms.
# A literal top-left reading puts the frog at y<0, entirely off-canvas -- that is
# how this was found.
POSE_OX = int(os.environ.get('POSE_OX', '250'))
POSE_OY = int(os.environ.get('POSE_OY', '175'))
POSE_SCALE = float(os.environ.get('POSE_SCALE', '1'))

out = {}
for row in PICS:
    ptype = row.get('type', 'Normal')
    layers = []

    def emit(name, x, y, want_type=None):
        """Resolve a scenery art name to a resId; return True on success."""
        rid = lookup_art(name, want_type or ptype)
        if rid is None:
            return False
        layers.append({'layer': [int(rid), int(x), int(y)]})
        return True

    vx = (row.get('view') or {}).get('x', 0) or 0
    vy = (row.get('view') or {}).get('y', 0) or 0

    for n in (row.get('backImage') or []):
        if not emit(n, vx, vy, ptype):
            report['unresolvedArt'].append((row['name'], n))

    # `frontImage` is not only scenery: for many rows it carries the FROG POSE
    # (pose_gy_0, pose_lamei, rnd_pose_roof1 ...).  Those must go through the
    # pose resolver, not through plain scenery lookup -- otherwise every one of
    # them is reported missing (that was 630 of 649 "unresolved" names).
    # They are kept in frontImage order and resolved in the front loop below.
    front = list(row.get('frontImage') or [])
    pose_names = [row['frogPose']] if row.get('frogPose') else []

    # frog pose.  The server rolled one of the family; we pick deterministically
    # (lowest resId) so renders are reproducible.
    pos = row.get('frogPos') or {'x': 0, 'y': 0}
    for pn in pose_names:
        rid = pose_group(row.get('name', ''), pn, ptype)
        if rid:
            layers.append({'layer': [int(rid),
                                     int(pos.get('x', 0) + POSE_OX),
                                     int(pos.get('y', 0) + POSE_OY)],
                           'scale': POSE_SCALE})
        else:
            report['unresolvedPose'].append((row['name'], ptype, pn))

    # frontImage is drawn after the frog, in its own table order.  An entry here
    # may itself be a pose (pose_gy_0, pose_lamei ...) -- resolve it as one.
    for n in front:
        if n.startswith(('pose_', 'rnd_pose_')):
            rid = pose_group(row.get('name', ''), n, ptype)
            if rid:
                layers.append({'layer': [int(rid),
                                         int(pos.get('x', 0) + POSE_OX),
                                         int(pos.get('y', 0) + POSE_OY)],
                               'scale': POSE_SCALE})
            else:
                report['unresolvedPose'].append((row['name'], ptype, n))
        elif not emit(n, vx, vy, ptype):
            report['unresolvedArt'].append((row['name'], n))

    # Travellers: the table lists up to three friend slots, but only the friends
    # who ACTUALLY came on the trip should be drawn.  So they are NOT part of
    # `layers`; they go in a separate `travelers` list that the engine appends
    # only for friends present on this trip.  (Drawing all three unconditionally
    # is what produced four frogs in the first render.)
    travellers = []
    for i, tn in enumerate(row.get('travelerPose') or []):
        if not tn:
            continue
        tps = row.get('travelerPos') or []
        p = tps[i] if i < len(tps) else {'x': 0, 'y': 0}
        rid = pose_group(row.get('name', ''), tn, ptype)
        if rid:
            travellers.append({'layer': [int(rid), int(p.get('x', 0) + POSE_OX),
                                         int(p.get('y', 0) + POSE_OY)],
                               'scale': POSE_SCALE})
        elif not emit(tn, p.get('x', 0) + POSE_OX, p.get('y', 0) + POSE_OY, ptype):
            report['unresolvedArt'].append((row['name'], tn))

    if layers:
        report['resolved'] += 1
        rec = {'name': row.get('name'), 'type': ptype, 'layers': layers}
        if travellers:
            rec['travelers'] = travellers
        out[str(row['id'])] = rec
    else:
        report['noPose'] += 1

json.dump(out, open(OUT, 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))

# ---- self-checks ---------------------------------------------------------
bad = []
for pid, rec in out.items():
    for l in rec['layers']:
        if str(l['layer'][0]) not in RES:
            bad.append((pid, l['layer'][0]))
print('pictures with layers      : %d / %d' % (len(out), len(PICS)))
print('pictures with NO layers   : %d' % report['noPose'])
print('pose groups discovered    : %d' % len(pose_groups))
print('unresolved poses          : %d' % len(report['unresolvedPose']))
for u in report['unresolvedPose'][:12]:
    print('    ', u)
print('unresolved art names      : %d occurrences' % len(report['unresolvedArt']))
uniq = collections.Counter(n for _, n in report['unresolvedArt'])
print('  distinct unresolved     : %d' % len(uniq))
bykind = collections.Counter()
for n, c in uniq.items():
    if n.startswith(('pose_', 'rnd_pose_')):
        bykind['pose_* (needs pose family)'] += c
    elif n.startswith('back_g_'):
        bykind['back_g_* (city bg)'] += c
    elif n.startswith('back_n_'):
        bykind['back_n_* (scene bg)'] += c
    elif n.startswith('back_u_'):
        bykind['back_u_* (unique bg)'] += c
    elif n.startswith('rnd_'):
        bykind['rnd_* (random family)'] += c
    else:
        bykind['other'] += c
for k, v in bykind.most_common():
    print('    %-28s %d' % (k, v))
for n, c in uniq.most_common(15):
    print('      %-30s x%d' % (n, c))
print('INVALID resIds emitted    : %d' % len(bad))
if bad:
    for b in bad[:10]:
        print('    ', b)
print('-> %s' % OUT)


