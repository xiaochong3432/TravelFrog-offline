"""Verify the SHIPPED APK carries the furniture subsystem (and still carries the
postcard layers work).

Includes a nonsense CONTROL marker that must be ABSENT, so a probe that always
matched would not look like a pass.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')

z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d' % len(src))
print()

CHECKS = [
    'furniture_putin_bench', 'furniture_takeout_bench',
    'furniture_putin_box', 'furniture_takeout_box',
    'furniture_replace_fur', 'furniture_replace_tumbler',
    'furniture_replace_compost', 'furniture_replace_pocket',
    'furniture_buy_shop', 'furniture_pocket_get',
]
for c in CHECKS:
    # handlers are written as unquoted object-literal keys: `name: (d) => {`
    print("  handler %-28s %d" % (c, src.count(c + ': (') + src.count("'%s':" % c)))

print()
for label, needle in [
    ('applyReplaceOther helper', 'function applyReplaceOther'),
    ('benchSlotFor helper', 'function benchSlotFor'),
    ('furnitureShopList helper', 'function furnitureShopList'),
    ('FURNITURE_SHOP built', 'const FURNITURE_SHOP'),
    ('FURNITURE_BY_ID built', 'const FURNITURE_BY_ID'),
    ('picture-layers still inlined', "define('./data/picture-layers.json'"),
    ('define.json still inlined', "define('./data/define.json'"),
    ('withLayers still present', 'function withLayers'),
]:
    print('  %-32s %d' % (label, src.count(needle)))

print()
print('  %-32s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
