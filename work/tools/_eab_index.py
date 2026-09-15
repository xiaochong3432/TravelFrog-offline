from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json, os, struct
WEB = str(PROJECT_ROOT) + "/work/run/web"
out = open(str(PROJECT_ROOT) + "/work/build/eab_index.txt", "w", encoding="utf-8")
EAB = b"\x89EAB"
for dp, _dn, fns in os.walk(WEB):
    for fn in fns:
        if not fn.lower().endswith(".eab"):
            continue
        p = os.path.join(dp, fn)
        d = open(p, "rb").read()
        if d[:4] != EAB:
            continue
        magic = d[:8]
        try:
            idxlen = struct.unpack_from("<I", d, 8)[0]
            man = json.loads(d[12:12+idxlen].decode("utf-8"))
            enc = "plain"
        except Exception:
            enc = "ENCRYPTED(0x%02x)" % (magic[6] if len(magic) > 6 else 0)
            man = []
        names = [e.get("n") for e in man]
        rel = os.path.relpath(p, WEB).replace("\\", "/")
        out.write(f"{rel}  [{enc}]  {len(names)} entries\n")
        if names:
            out.write(f"    {names[:18]}\n")
        hits = [n for n in names if n and ("Area" in n or "Travel" in n or "Node" in n)]
        if hits:
            out.write(f"    *** AREA/TRAVEL: {hits}\n")
out.close()
print("written")
