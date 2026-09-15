from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import collections, zipfile
for p in [str(PROJECT_ROOT) + "/base.apk", str(PROJECT_ROOT) + "/dist/TravelFrog-offline.apk"]:
    z = zipfile.ZipFile(p)
    names = z.namelist()
    dup = [n for n, c in collections.Counter(names).items() if c > 1]
    print("==", p)
    print("   entries:", len(names), " unique:", len(set(names)), " duplicates:", len(dup))
    for n in dup[:10]:
        print("     DUP:", n)
    bad = [n for n in names if n.startswith("/") or "\\" in n or ".." in n.split("/")]
    print("   suspicious names:", len(bad), bad[:5])
    # required-for-install members
    for t in ["AndroidManifest.xml", "resources.arsc"]:
        print(f"   has {t}:", t in names)
    print("   META-INF entries:", [n for n in names if n.upper().startswith("META-INF/")])
