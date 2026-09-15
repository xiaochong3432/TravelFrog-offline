"""Verify the SHIPPED APK carries the wishing pool, that the never-open stub is
GONE, and that all earlier work survives.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('handlers (each must be exactly 1):')
for c in ['wishingpool_load', 'wishingpool_wish', 'lottery_load', 'lottery_open',
          'lottery_select', 'lottery_confirm_reward']:
    print('  %-26s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('wishPoolItems helper', 'function wishPoolItems'),
    ('refreshWishingPool helper', 'function refreshWishingPool'),
    ('wishingPool state', 'wishingPool: {'),
    ('never-open stub REMOVED (must be 0)', 'wishingpool_load: () => ({ end_time: 0 })'),
    ('lottery helpers kept', 'function startLotteryPhase'),
    ('drawing kept', 'guest_load_drawing: ('),
    ('visitor kept', 'visit_open: ('),
    ('album recover kept', 'album_load_recover: ('),
    ('giftBoxPayload kept', 'function giftBoxPayload'),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-34s %d' % (label, src.count(needle)))

print()
print('  %-34s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
