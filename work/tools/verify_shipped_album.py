"""Verify the SHIPPED APK carries the album management + gift box + furniture +
postcard-layers work. Nonsense CONTROL marker must be ABSENT.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('album handlers:')
for c in ['album_load', 'album_load_all', 'album_load_by_id_list', 'album_load_new',
          'album_load_recover', 'album_save_new', 'album_delete_new',
          'album_delete', 'album_recover']:
    print('  %-26s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('code 75 (album full)', 'code: 75'),
    ('code 101 (gift->album)', 'code: 101'),
    ('code 102 (gift box full)', 'code: 102'),
    ('file_pending escape hatch', "'file_pending'"),
    ('albumPending state', 'albumPending: []'),
    ('giftBox state', 'giftBox: { pictures'),
    ('giftBoxPayload kept', 'function giftBoxPayload'),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('withLayers kept', 'function withLayers'),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-30s %d' % (label, src.count(needle)))

print()
print('  %-30s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
