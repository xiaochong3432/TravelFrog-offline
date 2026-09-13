from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import hashlib, os
paths = {
 "work/base (dump_handlers target)": str(PROJECT_ROOT) + "/work/base/assets/game/js/main.min.js",
 "shipped pristine (.clean)":        str(PROJECT_ROOT) + "/work/run/web/js/main.min.js.clean",
 "shipped patched":                  str(PROJECT_ROOT) + "/work/run/web/js/main.min.js",
}
out = open(str(PROJECT_ROOT) + "/work/build/client_compare.txt","w",encoding="utf-8")
for label, p in paths.items():
    if not os.path.exists(p):
        out.write(f"{label}: MISSING ({p})\n"); continue
    b = open(p,"rb").read()
    out.write(f"{label}\n  {p}\n  {len(b):,} bytes  sha256={hashlib.sha256(b).hexdigest()[:16]}\n")
    for marker in [b"shopData", b"season", b"item_load_shop_info", b"__probe", b"getSeasonKey"]:
        out.write(f"    {marker.decode():24s} {b.count(marker)}\n")
    out.write("\n")
# are the two the same modulo the known patch?
a = open(paths["work/base (dump_handlers target)"],"rb").read()
c = open(paths["shipped pristine (.clean)"],"rb").read()
out.write(f"identical: {a == c}\n")
out.write(f"len diff: {len(c) - len(a):,} bytes\n")
out.close()
print("written")
