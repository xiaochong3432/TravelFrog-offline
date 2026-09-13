#!/usr/bin/env python3
"""Unity 5.6 (SerializedFile v17) reader + TextAsset extractor.

Written from scratch (UnityPy is unavailable offline).

Layout notes discovered empirically on these files:
  * the four leading header u32s are BIG-endian; everything after offset 16 is
    little-endian;
  * unityVersion at 0x14 is NUL-terminated;
  * enableTypeTree is false, so no type trees are stored;
  * a type entry is  classID(4) stripped(1) scriptTypeIndex(2) [scriptID(16) if
    classID==114] oldTypeHash(16)  -> 23 or 39 bytes.

Usage:
  python unityread.py <file> [--text] [--list] [--types] [--name RX] [--outdir D]
"""
import struct, sys, os, re, argparse, collections

CLASS_NAMES = {
    1: 'GameObject', 4: 'Transform', 20: 'Camera', 21: 'Material', 23: 'MeshRenderer',
    28: 'Texture2D', 33: 'MeshFilter', 43: 'Mesh', 48: 'Shader', 49: 'TextAsset',
    65: 'BoxCollider', 74: 'AnimationClip', 82: 'AudioClip', 83: 'AudioListener',
    95: 'Animator', 104: 'RenderSettings', 108: 'Light', 111: 'Animation',
    114: 'MonoBehaviour', 115: 'MonoScript', 119: 'Sprite', 128: 'Font',
    129: 'PlayerSettings', 157: 'LightmapSettings', 196: 'NavMeshSettings',
    198: 'ParticleSystem', 199: 'ParticleSystemRenderer', 212: 'SpriteRenderer',
    213: 'Sprite', 222: 'CanvasRenderer', 223: 'Canvas', 224: 'RectTransform',
    225: 'CanvasGroup', 1001: 'PrefabInstance',
}


def r_i32(d, p):
    return struct.unpack_from('<i', d, p)[0]


def parse(path):
    d = open(path, 'rb').read()
    meta, fsz, ver, dataoff = struct.unpack_from('>IIII', d, 0)
    z = d.index(b'\0', 0x14)
    unity = d[0x14:z].decode('latin1')
    p = z + 1
    platform = r_i32(d, p); p += 4
    enable_tt = d[p]; p += 1
    ntypes = r_i32(d, p); p += 4
    types = []
    for _ in range(ntypes):
        cid = r_i32(d, p); p += 4
        stripped = d[p]; p += 1
        sti = struct.unpack_from('<h', d, p)[0]; p += 2
        if cid == 114:
            p += 16
        p += 16
        types.append(cid)
    info = dict(meta=meta, fsize=fsz, ver=ver, dataoff=dataoff, unity=unity,
                platform=platform, enable_type_tree=enable_tt, ntypes=ntypes,
                types_end=p, actual_size=len(d))
    # script types are stored inline in the type entries from format 17 on
    if 11 <= ver < 17:
        nscript = r_i32(d, p); p += 4 + 16 * nscript
        info['nscript'] = nscript
    nobj = r_i32(d, p); p += 4
    info['table_start'] = p
    info['nobj'] = nobj
    rows = None
    for rowsize in (23, 24, 25, 22, 26, 20):
        q = p
        cand = []
        ok = True
        try:
            for _ in range(nobj):
                pid, bs, bz, tid = struct.unpack_from('<qIIi', d, q)
                q += rowsize
                if bz == 0 or bs < dataoff or bs + bz > fsz or not (0 <= tid < ntypes):
                    ok = False
                    break
                cand.append(dict(pid=pid, off=bs, size=bz, tid=tid, cid=types[tid]))
        except Exception:
            ok = False
        if ok and cand:
            rows = cand
            info['rowsize'] = rowsize
            info['table_end'] = q
            info['max_end'] = max(r['off'] + r['size'] for r in cand)
            break
    return d, info, rows


def read_textasset(d, r):
    q = r['off']
    n = r_i32(d, q)
    if not (0 <= n < 4096):
        return None, None
    name = d[q + 4:q + 4 + n]
    q += 4 + n
    q = (q + 3) & ~3
    ln = r_i32(d, q)
    body = d[q + 4:q + 4 + ln]
    return name.decode('utf-8', 'replace'), body


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--text', action='store_true')
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--types', action='store_true')
    ap.add_argument('--name')
    ap.add_argument('--outdir')
    ap.add_argument('--maxbytes', type=int, default=6000)
    a = ap.parse_args()
    d, info, rows = parse(a.file)
    print(a.file)
    for k, v in info.items():
        print('  %s = %r' % (k, v))
    if a.types:
        print('  types:', collections.Counter(info and rows and [r['cid'] for r in rows]))
    if rows is None:
        print('  !! object table not resolved')
        return
    print('  classes:', dict(collections.Counter(CLASS_NAMES.get(r['cid'], r['cid']) for r in rows)))
    if a.list:
        for r in rows:
            print('   pid=%-22d off=%-10d size=%-9d cid=%d %s' % (r['pid'], r['off'], r['size'], r['cid'], CLASS_NAMES.get(r['cid'], '')))
    if a.text:
        rx = re.compile(a.name) if a.name else None
        for r in rows:
            if r['cid'] != 49:
                continue
            nm, body = read_textasset(d, r)
            if nm is None:
                continue
            if rx and not rx.search(nm):
                continue
            print('--- TextAsset %r pid=%d size=%d bodylen=%d' % (nm, r['pid'], r['size'], len(body)))
            if a.outdir:
                os.makedirs(a.outdir, exist_ok=True)
                fn = re.sub(r'[^\w.\-]', '_', nm) or ('pid%d' % r['pid'])
                open(os.path.join(a.outdir, fn), 'wb').write(body)
            else:
                print(body[:a.maxbytes].decode('utf-8', 'replace'))


if __name__ == '__main__':
    main()
