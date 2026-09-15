"""Verify the SHIPPED APK carries the 友情绘本 (drawing) subsystem plus all
earlier work. Nonsense CONTROL marker must be ABSENT.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('drawing handlers:')
for c in ['guest_load_drawing', 'guest_accept_invit', 'guest_lock_bag',
          'guest_putin_bag', 'guest_takeout_bag']:
    print('  %-24s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('drawingPayload helper', 'function drawingPayload'),
    ('drawingGuestIds helper', 'function drawingGuestIds'),
    ('nextCollectible helper', 'function nextCollectible'),
    ('maybeDrawing roll', 'function maybeDrawing'),
    ('DRAWING_BOOK_ID 7001', 'DRAWING_BOOK_ID = 7001'),
    ('shared-row guard (g >= 0)', 'Number.isFinite(g) && g >= 0'),
    ('shared-row guard (g !== -1)', 'g !== guestId && g !== -1'),
    ('visitorPayload kept', 'function visitorPayload'),
    ('album recover kept', 'album_load_recover: ('),
    ('giftBoxPayload kept', 'function giftBoxPayload'),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-30s %d' % (label, src.count(needle)))

print()
print('  %-30s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
