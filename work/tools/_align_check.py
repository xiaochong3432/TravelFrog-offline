"""Walk the real local file headers to measure true data-offset alignment.

The central directory's `extra` length need not equal the local header's, so a
CD-based calculation lies about alignment.  This walks local headers directly.
"""
import struct

ZIP64_EXTRA = 0x0001


def walk_local(path):
    d = open(path, "rb").read()
    off = 0
    out = []
    while True:
        if d[off:off + 4] != b"PK\x03\x04":
            break
        method = struct.unpack_from("<H", d, off + 8)[0]
        csize = struct.unpack_from("<I", d, off + 18)[0]
        usize = struct.unpack_from("<I", d, off + 22)[0]
        nlen, elen = struct.unpack_from("<HH", d, off + 26)
        name = d[off + 30:off + 30 + nlen].decode("utf-8", "replace")
        extra = d[off + 30 + nlen:off + 30 + nlen + elen]
        dataoff = off + 30 + nlen + elen
        real_csize, real_usize = csize, usize
        p = 0
        while p + 4 <= len(extra):
            hid, hsz = struct.unpack_from("<HH", extra, p)
            if hid == ZIP64_EXTRA and csize == 0xFFFFFFFF:
                q = p + 4
                real_usize = struct.unpack_from("<Q", extra, q)[0]; q += 8
                real_csize = struct.unpack_from("<Q", extra, q)[0]; q += 8
            p += 4 + hsz
        out.append({
            "name": name, "method": method, "dataoff": dataoff,
            "csize": real_csize, "usize": real_usize,
            "local_extra": elen, "extra": extra,
        })
        off = dataoff + real_csize
    return d, out


def extra_ids(extra):
    ids, p = [], 0
    while p + 4 <= len(extra):
        hid, hsz = struct.unpack_from("<HH", extra, p)
        ids.append((hex(hid), hsz))
        p += 4 + hsz
    return ids


for path in [r"H:\AI\frog\base.apk", r"H:\AI\frog\dist\TravelFrog-offline.apk"]:
    d, res = walk_local(path)
    print("==", path)
    print("   local entries walked:", len(res))
    viol = [r for r in res if r["method"] == 0 and r["dataoff"] % 4 != 0]
    print("   STORED entries misaligned (mod4 != 0):", len(viol))
    for r in viol[:6]:
        print("      ", r["name"], r["dataoff"] % 4)
    print("   entries with non-empty LOCAL extra:",
          sum(1 for r in res if r["local_extra"] > 0))
    ids = {}
    for r in res:
        for hid, hsz in extra_ids(r["extra"]):
            ids[hid] = ids.get(hid, 0) + 1
    print("   local extra field ids seen:", ids)
    for t in ["resources.arsc", "AndroidManifest.xml", "classes.dex"]:
        for r in res:
            if r["name"] == t:
                print(f"   {t}: method={r['method']} dataoff={r['dataoff']} "
                      f"mod4={r['dataoff'] % 4} local_extra={r['local_extra']}B "
                      f"extra_ids={extra_ids(r['extra'])}")
