"""Verify the SHIPPED APK carries the animpicture subsystem plus all earlier work."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('animpicture handlers (each must be exactly 1):')
for c in ['animpicture_load', 'animpicture_guide', 'animpicture_get_item',
          'animpicture_select_pic', 'animpicture_open_album',
          'animpicture_album_add_pic', 'animpicture_album_remove_pic',
          'animpicture_remove_pic', 'animpicture_use_item']:
    print('  %-30s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('ANIM table loaded', 'tables.animpictureData'),
    ('animPayload helper', 'function animPayload'),
    ('animStartPhase helper', 'function animStartPhase'),
    ('animPhaseCount helper', 'function animPhaseCount'),
    ('phase gate reply', 'return { phase }'),
    ('animPicture state', 'animPicture: {'),
    ('old stub REMOVED (must be 0)', 'animpicture_load: () => ({ pic_list: [] })'),
    ('moment kept', 'misc_moment_unlock: ('),
    ('cooking kept', 'function cookingDealTasks'),
    ('tutorial ok kept', 'return { ok: true }'),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-32s %d' % (label, src.count(needle)))

print()
print('  %-32s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
