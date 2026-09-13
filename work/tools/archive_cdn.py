#!/usr/bin/env python3
"""Archive the live ejoy hotfix CDN (v1021) for the offline conversion.

patch.json entry format:  "<path>": {"0": "<dist_dir>", "1": "<md5>", "2": <size>}
Download URL          :  <__url__><dist_dir>/<path>
The listed md5 matches the *decompressed* content, so gzip bodies are inflated
before verification.
"""
import json, os, sys, gzip, hashlib, urllib.request, urllib.error, time
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = r"H:\AI\frog\work\cdn\v1021"
PATCH = r"H:\AI\frog\work\cdn\patch.json"
UA = "Mozilla/5.0 (Linux; Android 11) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36"

d = json.load(open(PATCH, encoding="utf8"))
BASE = d["__url__"]
files = {k: v for k, v in d.items() if not k.startswith("__")}

# also archive the top-level launcher + manifests referenced by index.html
EXTRA = [
    ("_launcher/launcherv2.js", "https://ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/launcherv2.js"),
    ("_launcher/manifest.json", BASE + "manifest.json"),
    ("_launcher/patch.json", BASE + "1020_1021/patch.json"),
]


def fetch(url, tries=4):
    last = None
    for a in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept-Encoding": "identity"})
            with urllib.request.urlopen(req, timeout=45) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            last = e
            time.sleep(1.5 * (a + 1))
    raise last


def store(relpath, body, want_md5=None):
    dst = os.path.join(ROOT, relpath.replace("/", os.sep))
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    if body[:2] == b"\x1f\x8b":
        try:
            body = gzip.decompress(body)
        except Exception:
            pass
    md5 = hashlib.md5(body).hexdigest()
    ok = (want_md5 is None) or (md5 == want_md5)
    with open(dst, "wb") as f:
        f.write(body)
    return len(body), md5, ok


def job(item):
    path, meta = item
    url = f"{BASE}{meta['0']}/{path}"
    try:
        body = fetch(url)
        size, md5, ok = store(path, body, meta["1"])
        return (path, size, md5, ok, None)
    except Exception as e:  # noqa: BLE001
        return (path, 0, "", False, str(e))


def main():
    items = sorted(files.items())
    print(f"archiving {len(items)} files from {BASE} -> {ROOT}")
    os.makedirs(ROOT, exist_ok=True)
    bad, errs, done = [], [], 0
    t0 = time.time()
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(job, it): it[0] for it in items}
        for f in as_completed(futs):
            path, size, md5, ok, err = f.result()
            done += 1
            if err:
                errs.append((path, err))
            elif not ok:
                bad.append(path)
            if done % 100 == 0:
                print(f"  {done}/{len(items)}  elapsed {time.time()-t0:.0f}s")

    for rel, url in EXTRA:
        try:
            body = fetch(url)
            size, md5, ok = store(rel, body)
            print(f"  extra {rel}: {size} bytes")
        except Exception as e:  # noqa: BLE001
            errs.append((rel, str(e)))

    print(f"\ndone in {time.time()-t0:.0f}s")
    print(f"  md5 mismatches : {len(bad)}")
    print(f"  errors         : {len(errs)}")
    for p in bad[:15]:
        print(f"    MISMATCH {p}")
    for p, e in errs[:15]:
        print(f"    ERROR    {p}: {e[:90]}")


if __name__ == "__main__":
    main()
