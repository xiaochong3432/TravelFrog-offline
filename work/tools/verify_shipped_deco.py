"""Verify the SHIPPED APK carries the decoration subsystem plus all earlier work.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('handlers (each must be exactly 1):')
for c in ['client_load_decorate', 'client_change_decorate',
          'wishingpool_load', 'wishingpool_wish']:
    print('  %-26s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('addDecoration helper', 'function addDecoration'),
    ('rollDecoration helper', 'function rollDecoration'),
    ('DECORATIONS from table', 'tables.decoration'),
    ('decoration state', 'decoration: { hasList'),
    ('trip hook calls rollDecoration', 'const flower = rollDecoration()'),
    ('wishPoolItems kept', 'function wishPoolItems'),
    ('lottery helpers kept', 'function startLotteryPhase'),
    ('drawing kept', 'guest_load_drawing: ('),
    ('visitor kept', 'visit_open: ('),
    ('album recover kept', 'album_load_recover: ('),
    ('giftBoxPayload kept', 'function giftBoxPayload'),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-32s %d' % (label, src.count(needle)))

print()
print('  %-32s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
