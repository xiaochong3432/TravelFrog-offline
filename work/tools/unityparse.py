#!/usr/bin/env python3
"""Minimal Unity SerializedFile (version 5.6 / format 17) reader.

Written from scratch because UnityPy is unavailable offline.

Usage:
  python unityparse.py <file> [--list] [--types] [--text] [--dump-class N] [--name RX]
"""
import struct, sys, os, argparse

CLASS_NAMES = {
    1: 'GameObject', 2: 'Component', 4: 'Transform', 20: 'Camera', 21: 'Material',
    23: 'MeshRenderer', 27: 'Texture', 28: 'Texture2D', 29: 'OcclusionCullingSettings',
    33: 'MeshFilter', 43: 'Mesh', 48: 'Shader', 49: 'TextAsset', 65: 'BoxCollider',
    74: 'AnimationClip', 82: 'AudioClip', 83: 'AudioListener', 95: 'Animator',
    104: 'RenderSettings', 108: 'Light', 111: 'Animation', 114: 'MonoBehaviour',
    115: 'MonoScript', 119: 'Sprite', 128: 'Font', 129: 'PlayerSettings',
    156: 'TerrainData', 157: 'LightmapSettings', 158: 'LightProbeGroup',
    159: 'LightProbeProxyVolume', 196: 'NavMeshSettings', 198: 'ParticleSystem',
    199: 'ParticleSystemRenderer', 212: 'SpriteRenderer', 213: 'Sprite',
    222: 'CanvasRenderer', 223: 'Canvas', 224: 'RectTransform', 225: 'CanvasGroup',
    128: 'Font', 1001: 'Prefab', 1002: 'EditorExtensionImpl',
}


class R:
    def __init__(self, d, pos=0, be=False):
        self.d = d
        self.p = pos
        self.be = be

    def u8(self):
        v = self.d[self.p]; self.p += 1; return v

    def u16(self):
        v, = struct.unpack_from('>H' if self.be else '<H', self.d, self.p); self.p += 2; return v

    def i16(self):
        v, = struct.unpack_from('>h' if self.be else '<h', self.d, self.p); self.p += 2; return v

    def u32(self):
        v, = struct.unpack_from('>I' if self.be else '<I', self.d, self.p); self.p += 4; return v

    def i32(self):
        v, = struct.unpack_from('>i' if self.be else '<i', self.d, self.p); self.p += 4; return v

    def i64(self):
        v, = struct.unpack_from('>q' if self.be else '<q', self.d, self.p); self.p += 8; return v

    def skip(self, n):
        self.p += n

    def align(self, n=4):
        r = self.p % n
        if r:
            self.p += n - r

    def string(self):
        n = self.i32()
        if n < 0 or n > 1 << 24:
            raise ValueError('bad string len %d at %d' % (n, self.p - 4))
        raw = self.d[self.p:self.p + n]
        self.p += n
        self.align(4)
        return raw.decode('utf-8', 'replace')


def parse(path, verbose=False):
    d = open(path, 'rb').read()
    h = R(d)
    meta_size = h.u32() if False else struct.unpack_from('>I', d, 0)[0]
    file_size = struct.unpack_from('>I', d, 4)[0]
    version = struct.unpack_from('>I', d, 8)[0]
    data_offset = struct.unpack_from('>I', d, 12)[0]
    r = R(d, 16)
    endianess = r.u8(); r.skip(3)
    z = d.index(b'\0', r.p)
    unity_ver = d[r.p:z].decode('latin1')
    r.p = z + 1
    target_platform = r.i32()
    enable_type_tree = r.u8()
    info = dict(meta_size=meta_size, file_size=file_size, version=version,
                data_offset=data_offset, endianess=endianess, unity=unity_ver,
                platform=target_platform, type_tree=enable_type_tree)
    # type table
    ntypes = r.i32()
    types = []
    for _ in range(ntypes):
        cid = r.i32()
        stripped = r.u8()
        sti = r.i16()
        if cid == 114:
            r.skip(16)
        r.skip(16)  # old type hash
        if enable_type_tree:
            raise SystemExit('type trees present - not implemented')
        types.append(dict(class_id=cid, stripped=stripped, script_type_index=sti))
    # type table: locate the object table by brute force (type trees make the
    # exact byte length awkward to compute, and we do not need the type trees
    # for flat classes such as TextAsset).
    info['ntypes'] = ntypes
    rows2, table_start, objrows = find_object_table(d, ntypes, data_offset, file_size)
    info['table_start'] = table_start
    info['nobj'] = rows2[0] if rows2 else None
    info['row_size'] = rows2[1] if rows2 else None
    return d, info, types, objrows


def find_object_table(d, ntypes, data_offset, file_size):
    """Search the metadata region for a self-consistent object table."""
    for rowoff in (0, 2, -2, 4):
        for s in range(600, min(data_offset, 60000)):
            try:
                nobj, = struct.unpack_from('<i', d, s)
            except struct.error:
                break
            if nobj <= 0 or nobj > 200000:
                continue
            p = s + 4
            ok = True
            rows = []
            for i in range(nobj):
                if p + 24 > data_offset + 64:
                    ok = False
                    break
                pid, bs, bz, tid = struct.unpack_from('<qIIi', d, p)
                p += 24 + rowoff
                if tid < 0 or tid >= ntypes or bz == 0 or bs < data_offset or bs + bz > file_size:
                    ok = False
                    break
                rows.append(dict(path_id=pid, off=bs, size=bz, tid=tid))
            if not ok or not rows:
                continue
            if max(r['off'] + r['size'] for r in rows) < file_size - 4096:
                continue
            return (nobj, 24 + rowoff), s, rows
    return None, None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('file')
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--types', action='store_true')
    ap.add_argument('--text', action='store_true')
    ap.add_argument('--all-classes', action='store_true')
    ap.add_argument('--name', help='regex filter on TextAsset name')
    a = ap.parse_args()
    d, info, types, rows = parse(a.file)
    import collections
    print(a.file)
    for k, v in info.items():
        print('  %s = %r' % (k, v))
    cnt = collections.Counter(t['class_id'] for t in types)
    if a.types or a.all_classes:
        for i, t in enumerate(types):
            print(f'  type[{i}] class={t["class_id"]} {CLASS_NAMES.get(t["class_id"], "?")} stripped={t["stripped"]}')
    if rows is None:
        print('  !! object table layout not resolved')
        return
    for r_ in rows:
        r_['cid'] = types[r_['tid']]['class_id']
    cc = collections.Counter(r['cid'] for r in rows)
    print('  object classes:', {f'{k}:{CLASS_NAMES.get(k,"?")}': v for k, v in cc.most_common()})
    if a.list:
        for r_ in rows[:400]:
            print(f'   pid={r_["path_id"]:<20} off={r_["off"]:<10} size={r_["size"]:<9} cid={r_["cid"]} {CLASS_NAMES.get(r_["cid"],"")}')
    if a.text:
        import re
        rx = re.compile(a.name) if a.name else None
        for r_ in rows:
            if r_['cid'] != 49:
                continue
            try:
                rr = R(d, r_['off'])
                nm = rr.string()
                data = d[rr.p:r_['off'] + r_['size']]
                ln = struct.unpack_from('<i', data, 0)[0]
                body = data[4:4 + ln]
            except Exception as e:
                print('   err', r_['path_id'], e)
                continue
            if rx and not rx.search(nm):
                continue
            print(f'--- TextAsset {nm!r} pid={r_["path_id"]} size={r_["size"]} bodylen={len(body)}')
            print(body[:3000].decode('utf-8', 'replace'))


if __name__ == '__main__':
    main()
