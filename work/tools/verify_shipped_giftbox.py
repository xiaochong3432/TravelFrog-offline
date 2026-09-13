"""Verify the SHIPPED APK carries the gift box subsystem (and still carries the
earlier furniture + postcard-layers work).

Includes a nonsense CONTROL marker that must be ABSENT.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')

z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d' % len(src))
print()

print('gift box handlers:')
for c in ['travel_bag_to_gift', 'travel_gift_to_bag', 'travel_album_to_gift',
          'travel_gift_to_album', 'travel_gift_delete_album', 'travel_read_note',
          'item_select_gift']:
    print('  %-28s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('giftBoxCount helper', 'function giftBoxCount'),
    ('giftBoxPayload helper', 'function giftBoxPayload'),
    ('addGiftSpecialty helper', 'function addGiftSpecialty'),
    ('ALBUM_MAX from define', "DEF('ALBUM_MAX'"),
    ('SPECIALTY_MAX from define', "DEF('SPECIALTY_MAX'"),
    ('code 101 branch', 'code: 101'),
    ('code 102 branch', 'code: 102'),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('withLayers kept', 'function withLayers'),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-32s %d' % (label, src.count(needle)))

print()
print('  %-32s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
