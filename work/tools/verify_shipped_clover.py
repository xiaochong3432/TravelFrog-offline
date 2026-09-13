"""Verify the SHIPPED APK carries the clover rule guarantees plus all earlier work."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

for label, needle in [
    ('clover span re-roll', 'slot.rebirth_span = rollCloverRebirth()'),
    ('normal-distribution roll', 'function rollCloverRebirth'),
    ('cloverStatus guard', 'function cloverStatus'),
    ('CLOVER_REBIRTH_MEAN 7200', 'CLOVER_REBIRTH_MEAN = 7200'),
    ('four-leaf 1%', 'FOUR_LEAF_CHANCE = 0.01'),
    ('FROG_FAITHFUL kept', 'FROG_FAITHFUL'),
    ('story kept', 'function rollStory'),
    ('animpicture kept', 'animpicture_use_item: ('),
    ('moment kept', 'misc_moment_unlock: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-28s %d' % (label, src.count(needle)))

print()
print('  %-28s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
