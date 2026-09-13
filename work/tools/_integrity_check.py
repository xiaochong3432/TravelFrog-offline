import hashlib, zipfile
orig = zipfile.ZipFile(r"H:\AI\frog\base.apk")
new  = zipfile.ZipFile(r"H:\AI\frog\dist\TravelFrog-offline.apk")
on, nn = set(orig.namelist()), set(new.namelist())

sig_old = {n for n in on if n.upper().startswith("META-INF/") and n.upper().endswith((".SF",".RSA",".DSA",".EC")) or n.upper()=="META-INF/MANIFEST.MF"}
sig_new = {n for n in nn if n.upper().startswith("META-INF/") and n.upper().endswith((".SF",".RSA",".DSA",".EC")) or n.upper()=="META-INF/MANIFEST.MF"}
print("old sig files:", sorted(sig_old))
print("new sig files:", sorted(sig_new))

only_old = on - nn
only_new = nn - on
print("\nonly in original:", sorted(only_old))
print("only in new     :", len(only_new), sorted(only_new)[:6])

same = diff = 0
diffs = []
for n in sorted(on & nn):
    if n.startswith("assets/game/"):
        continue
    if n in sig_old or n in sig_new:
        continue
    a = hashlib.sha256(orig.read(n)).hexdigest()
    b = hashlib.sha256(new.read(n)).hexdigest()
    if a == b: same += 1
    else:
        diff += 1; diffs.append(n)
print(f"\nnon-game shared entries byte-identical: {same}")
print(f"non-game shared entries DIFFERENT     : {diff} {diffs[:8]}")
