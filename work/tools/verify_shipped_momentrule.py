"""Verify the SHIPPED APK carries the moment-trigger rule plus all earlier work."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

for label, needle in [
    ('momentTrigger helper', 'function momentTrigger'),
    ('guestResName helper', 'function guestResName'),
    ('type-1 hook (frog motion)', 'momentTrigger(1, motionName)'),
    ('type-3 hook (guest)', 'momentTrigger(3, gres)'),
    ('type-4 hook (shop)', "momentTrigger(4, 'drummer')"),
    ('HaveItemMax clamp kept', 'const cap = Number(ORIG.haveItemMax)'),
    ('trimMails kept', 'function trimMails'),
    ('story kept', 'function rollStory'),
    ('animpicture kept', 'animpicture_use_item: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-30s %d' % (label, src.count(needle)))

print()
print('  %-30s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
