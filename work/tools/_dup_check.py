import collections, zipfile
for p in [r"H:\AI\frog\base.apk", r"H:\AI\frog\dist\TravelFrog-offline.apk"]:
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
