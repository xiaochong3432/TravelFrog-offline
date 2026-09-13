"""Verify the SHIPPED APK carries the postcard-layers work.

Checks the bundled engine inside dist/TravelFrog-offline.apk for the module and
the call sites, plus a nonsense CONTROL marker that must be ABSENT -- otherwise a
probe that always returns true would look like a pass.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')

z = zipfile.ZipFile(APK)
entries = [n for n in z.namelist() if 'offline-engine' in n]
print('engine entry : %s' % entries)
src = z.read(entries[0]).decode('utf-8')
print('engine chars : %d' % len(src))
print()

CHECKS = {
    "picture-layers module declared": "define('./data/picture-layers.json'",
    "engine requires the table": "require('./data/picture-layers.json')",
    "withLayers() present": "function withLayers",
    "album_load hydrated": "pictures: state.pictures.map(withLayers)",
    "travel_load_gift hydrated (x3)": "pictures: state.pictures.map(withLayers)",
    "BJ1_QW layer resId": '"Picture/Goal/BJ1_QW"',
    "define.json still inlined": "define('./data/define.json'",
    "gamedata.json still inlined": "define('./data/gamedata.json'",
}
for label, needle in CHECKS.items():
    print('  %-32s %d' % (label, src.count(needle)))

print()
CONTROL = 'zzz_this_marker_must_not_exist_zzz'
print('  %-32s %d  (must be 0)' % ('CONTROL absent', src.count(CONTROL)))
