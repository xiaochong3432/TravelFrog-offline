import zipfile, re, hashlib, os
apk = zipfile.ZipFile(r"H:\AI\frog\dist\TravelFrog-offline.apk")
web = r"H:\AI\frog\work\run\web"
names = set(apk.namelist())

# 1) every source file under work\run\web must be in the APK as assets/game/**
missing, differ, same = [], [], 0
src_files = 0
for root, dirs, files in os.walk(web):
    for f in files:
        p = os.path.join(root, f)
        rel = os.path.relpath(p, web).replace("\\", "/")
        src_files += 1
        arc = "assets/game/" + rel
        if arc not in names:
            missing.append(rel); continue
        a = hashlib.sha256(open(p, "rb").read()).hexdigest()
        b = hashlib.sha256(apk.read(arc)).hexdigest()
        if a == b: same += 1
        else: differ.append(rel)
print(f"source files under work\\run\\web : {src_files}")
print(f"  present & byte-identical      : {same}")
print(f"  MISSING from APK              : {len(missing)} {missing[:5]}")
print(f"  DIFFERENT content             : {len(differ)} {differ[:5]}")

# 2) patches / launcher present inside the APK
idx = apk.read("assets/game/index.html").decode("utf-8", "replace")
main = apk.read("assets/game/js/main.min.js").decode("utf-8", "replace")
print("\nindex.html loads __probe.js      :", "__probe.js" in idx)
print("index.html loads __offline-engine:", "__offline-engine.js" in idx)
print("season clamp present in main.min.js:",
      "a>=1&&a<=4&&b>=1&&b<=4" in main)
print("bogus 'true&&' gate present        :", "true&&" in main)
print("enterGame gate intact              :",
      "isSyncComplete()" in main and "GameConfig.activate" in main)
for extra in ["assets/game/__offline-engine.js", "assets/game/__probe.js"]:
    print(f"{extra}: {apk.getinfo(extra).file_size} bytes")
