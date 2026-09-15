"""Verify the SHIPPED APK carries the caps work plus all earlier subsystems."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

for label, needle in [
    ('HaveItemMax clamp', 'const cap = Number(ORIG.haveItemMax)'),
    ('trimMails helper', 'function trimMails'),
    ('MAIL_MAX on read path', 'trimMails();\n      return state.mails;'),
    ('reply reports credited', 'Math.max(0, after - before)'),
    ('clover roll kept', 'function rollCloverRebirth'),
    ('FROG_FAITHFUL kept', 'FROG_FAITHFUL'),
    ('story kept', 'function rollStory'),
    ('animpicture kept', 'animpicture_use_item: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-30s %d' % (label, src.count(needle)))

print()
print('  %-30s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
