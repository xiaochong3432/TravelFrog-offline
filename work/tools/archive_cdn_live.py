#!/usr/bin/env python3
"""Archive every file the live hotfix CDN still serves, into work/cdn/live/<band>/.

WHY THIS IS URGENT: the CDN host answered 200 for the v1.0.21 paths, so the content
our v1.0.20 build lacks is still downloadable -- but the game shut down on
2026-12-08 and this server will not be there forever. patch.json is the CDN's own
file list (946 entries with md5 + size), so this downloads exactly that set and
verifies every byte against the recorded md5: a mismatch is reported, never
silently kept.

URL shape, verified by hand on one file before writing this:
    <base>/<band>/<path>          e.g. .../1020_1021/resource/China/images/.../u_month4.png
    base = https://ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android/

Usage:
    python tools/archive_cdn_live.py [--limit N] [--only-band 1020_1021] [--jobs 4]
"""
from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import argparse
import concurrent.futures
import hashlib
import io
import json
import os
import sys
import urllib.error
import urllib.request

ROOT = str(PROJECT_ROOT)
CDN = os.path.join(ROOT, "work", "cdn")
LIVE = os.path.join(CDN, "live")
BASE = "https://ali-lxqw-hotfix.ejoy.com/c1_client/release/lingxi/android"

ap = argparse.ArgumentParser()
ap.add_argument("--limit", type=int, default=0)
ap.add_argument("--only-band", default=None)
ap.add_argument("--jobs", type=int, default=4)
args = ap.parse_args()

patch = json.load(open(os.path.join(CDN, "patch.json"), encoding="utf-8"))
files = {k: v for k, v in patch.items() if not k.startswith("__")}
if args.only_band:
    files = {k: v for k, v in files.items() if v.get("0") == args.only_band}
if args.limit:
    files = dict(list(files.items())[:args.limit])

log = io.StringIO()


def say(s):
    log.write(s + "\n")
    print(s, flush=True)


say("archiving %d files (%d jobs)" % (len(files), args.jobs))
total_want = sum(int(v.get("2") or 0) for v in files.values())
say("expected payload: %.1f MB" % (total_want / 1048576))

ok = skipped = failed = 0
bad_md5 = []
got_bytes = 0
lock = None


def fetch(item):
    global ok, skipped, failed, got_bytes
    name, info = item
    band = info.get("0") or "unknown"
    want_md5 = info.get("1")
    dest = os.path.join(LIVE, band, name.replace("/", os.sep))
    if os.path.isfile(dest):
        with open(dest, "rb") as fh:
            data = fh.read()
        if hashlib.md5(data).hexdigest() == want_md5:
            skipped += 1
            return
    url = "%s/%s/%s" % (BASE, band, name)
    try:
        with urllib.request.urlopen(url, timeout=60) as r:
            data = r.read()
    except Exception as e:
        failed += 1
        say("  FAIL %s  (%s)" % (name, e))
        return
    got = hashlib.md5(data).hexdigest()
    if want_md5 and got != want_md5:
        bad_md5.append((name, want_md5, got))
        say("  MD5 MISMATCH %s" % name)
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as fh:
        fh.write(data)
    ok += 1
    got_bytes += len(data)
    if (ok + skipped + failed) % 50 == 0:
        say("  ... %d/%d" % (ok + skipped + failed, len(files)))


with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
    list(pool.map(fetch, sorted(files.items())))

say("")
say("downloaded %d, already present %d, failed %d, md5 mismatches %d"
    % (ok, skipped, failed, len(bad_md5)))
say("new bytes: %.1f MB" % (got_bytes / 1048576))
for n, w, g in bad_md5[:10]:
    say("   MISMATCH %s want=%s got=%s" % (n, w, g))

sys.stdout = open(os.path.join(ROOT, "work", "logs", "cdn_archive.txt"), "w", encoding="utf-8")
sys.stdout.write(log.getvalue())
