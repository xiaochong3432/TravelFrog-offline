"""Read-only: recover the OFFICIAL postcard composition from the game's own
photograph-GIF spine data and compare it with our picture-layers.json.

Why this is ground truth
------------------------
`animpictureData.json` maps a Picture row to a spine "gif" set:
    {"100":1, "104":2, "2000":3}
and the gif's slots are named after the very same art the Picture table lists
(gif_2 = picture 104 = back_n_beach3 whose backImage is
 ["sky04","rnd_sea","rnd_mou_back","flower01","earth"], and gif_2_bg1's slots are
 sky04 / sea01 / mou_back01 / flower01 / earth).  So the spine file is the
 game's own placement of the *same* art in the *same* 500x350 album frame.

Conventions used (each validated against a self-evident case, see PRINTS below):
  * screen_x =  x_spine          (bone world x + attachment-local x)
  * screen_y = -y_spine          (spine is Y-up; skeleton bboxes sit on
                                  [0,500]x[0,350] with y negated, e.g.
                                  gif_2_bg1 sky04 mesh -> exactly 0..500 / 0..350)
  * region attachment: (x,y) is the region CENTRE in bone-local space
      - validated by gif_1_bg1 slot `bg` (502x352) whose centre is (249.99,175.03)
        i.e. the exact middle of the 500x350 frame.
  * mesh attachment: the vertex pairs are bone-local coordinates.

Usage: python work/probe/official_layout_probe.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', 'run'))
TABLES = os.path.join(ROOT, 'engine', 'data', 'tables')
SPINE = os.path.join(ROOT, 'web', 'resource', 'China', 'animation', 'gif_photo')

OURS = json.load(open(os.path.join(ROOT, 'engine', 'data', 'picture-layers.json'),
                      encoding='utf-8'))
PICS = {str(r['id']): r for r in json.load(
    open(os.path.join(TABLES, 'Picture.json'), encoding='utf-8'))}
ANIM = json.load(open(os.path.join(TABLES, 'animpictureData.json'), encoding='utf-8'))

GIFS = {
    '1': ['gif_1/gif_1_bg1', 'gif_1/gif_1_bg2', 'gif_1/gif_1_role_qw'],
    '2': ['gif_2/gif_2_bg1', 'gif_2/gif_2_fg1', 'gif_2/gif_2_role_qw',
          'gif_2/gif_2_bg2'],
    '3': ['gif_3/gif_3_bg1', 'gif_3/gif_3_tree', 'gif_3/gif_3_shidun',
          'gif_3/gif_3_role_qw'],
}


def bone_world(j):
    by = {}
    for b in j.get('bones') or []:
        by[b['name']] = b
    cache = {}

    def wy(n):
        if n in cache:
            return cache[n]
        b = by.get(n)
        if not b:
            cache[n] = (0.0, 0.0)
            return cache[n]
        x, y = float(b.get('x') or 0), float(b.get('y') or 0)
        if b.get('parent'):
            px, py = wy(b['parent'])
            x, y = x + px, y + py
        cache[n] = (x, y)
        return cache[n]

    for n in by:
        wy(n)
    return cache


def load(f):
    return json.load(open(os.path.join(SPINE, f + '.json'), encoding='utf-8'))


def placements(f):
    """[(slotName, attachmentName, screenTopLeftX, screenTopLeftY, w, h, isRole)]"""
    j = load(f)
    bw = bone_world(j)
    atts = (j.get('skins') or [{}])[0].get('attachments') or {}
    out = []
    for s in j.get('slots') or []:
        slot, bone = s['name'], s['bone']
        cand = atts.get(slot) or {}
        an = s.get('attachment') or (list(cand)[0] if cand else None)
        a = cand.get(an) if an else None
        if not a:
            continue
        bx, by = bw.get(bone, (0.0, 0.0))
        if a.get('type') in ('mesh', 'path'):
            v = a.get('vertices') or []
            if len(v) < 4:
                continue
            xs = v[0::2]
            ys = v[1::2]
            x0, x1 = min(xs) + bx, max(xs) + bx
            y0, y1 = min(ys) + by, max(ys) + by
            # screen: y flips
            out.append((slot, an, x0, -y1, x1 - x0, y1 - y0))
        else:
            w, h = float(a.get('width') or 0), float(a.get('height') or 0)
            cx, cy = bx + float(a.get('x') or 0), by + float(a.get('y') or 0)
            out.append((slot, an, cx - w / 2, -(cy + h / 2), w, h))
    return out


def main():
    print('animpictureData pic_map: %s' % json.dumps(ANIM['pic_map']))
    print()
    for pid, gid in sorted(ANIM['pic_map'].items(), key=lambda kv: int(kv[0])):
        row = PICS[pid]
        print('=' * 100)
        print('picture %s  (%s, type=%s)' % (pid, row['name'], row['type']))
        print('  backImage  = %s' % json.dumps(row['backImage'], ensure_ascii=False))
        print('  frontImage = %s' % json.dumps(row['frontImage'], ensure_ascii=False))
        print('  frogPose   = %s   frogPos = %s' % (row['frogPose'], row['frogPos']))
        fp = row['frogPos']
        print('  -> 250+frogPos.x = %s | 350+frogPos.y = %s | 175+frogPos.y (OURS) = %s'
              % (250 + fp['x'], 350 + fp['y'], 175 + fp['y']))
        print()
        print('  --- official placement recovered from the gif spine (%s) ---' % gid)
        for name in GIFS[str(gid)]:
            for slot, an, x, y, w, h in placements(name):
                print('    %-28s slot=%-22s official top-left=(%7.2f,%7.2f) size=%gx%g'
                      % (os.path.basename(name), slot, x, y, w, h))
        print()
        rec = OURS.get(pid)
        print('  --- what our picture-layers.json emits ---')
        if not rec:
            print('    (no record)')
        else:
            for l in rec['layers']:
                rid, x, y = l['layer']
                tag = 'POSE' if 'scale' in l else ''
                print('    resId=%-6s top-left=(%4d,%4d) %s'
                      % (rid, x, y, tag))
        print()


if __name__ == '__main__':
    main()
