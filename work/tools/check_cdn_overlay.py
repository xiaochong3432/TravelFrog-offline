#!/usr/bin/env python3
"""Are the archived CDN (v1021) files present in the shipped web tree / APK?

Compares each patch.json entry against work/run/web by md5.
"""
import json, hashlib, os, collections

PATCH = r"H:\AI\frog\work\cdn\patch.json"
CDN = r"H:\AI\frog\work\cdn\v1021"
WEB = r"H:\AI\frog\work\run\web"

d = json.load(open(PATCH, encoding="utf8"))
files = {k: v for k, v in d.items() if not k.startswith("__")}
print(f"patch.json entries: {len(files)}")

same = diff = missing = 0
diff_list = []
missing_list = []
for path, meta in files.items():
    want = meta["1"]
    local = os.path.join(WEB, path.replace("/", os.sep))
    if not os.path.isfile(local):
        missing += 1
        if len(missing_list) < 10:
            missing_list.append(path)
        continue
    got = hashlib.md5(open(local, "rb").read()).hexdigest()
    if got == want:
        same += 1
    else:
        diff += 1
        if len(diff_list) < 15:
            diff_list.append((path, meta["0"], os.path.getsize(local), meta["2"]))

print(f"\n  identical to v1021 : {same}")
print(f"  DIFFERENT (old)    : {diff}")
print(f"  missing locally    : {missing}")

print("\n--- examples that differ (i.e. we currently ship the OLD version) ---")
for p, distdir, lsize, csize in diff_list:
    print(f"  {p:<58} cdn_dir={distdir:<12} local={lsize:>9,} cdn={csize:>9,}")

if missing_list:
    print("\n--- examples missing ---")
    for p in missing_list:
        print("  ", p)

# the headline files
print("\n--- key files ---")
for k in ("js/main.min.js", "js/default.thm.js", "index.html", "manifest.json",
          "js/ejoySDK.min.js", "js/spine.min.js"):
    if k in files:
        local = os.path.join(WEB, k.replace("/", os.sep))
        got = hashlib.md5(open(local, "rb").read()).hexdigest() if os.path.isfile(local) else "(missing)"
        print(f"  {k:<24} local_md5={got[:12]}  cdn_md5={files[k]['1'][:12]}  "
              f"{'SAME' if got == files[k]['1'] else 'DIFFERENT'}")
