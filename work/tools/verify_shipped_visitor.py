"""Verify the SHIPPED APK carries the visitor subsystem plus all earlier work.
Nonsense CONTROL marker must be ABSENT.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('visit handlers:')
for c in ['visit_load', 'visit_open', 'visit_set_carpet', 'visit_set_expire_time']:
    print('  %-24s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('visitorPayload helper', 'function visitorPayload'),
    ('pickVisitor helper', 'function pickVisitor'),
    ('maybeVisitor roll', 'function maybeVisitor'),
    ('GIFT_CLOVER_ID 100000', 'GIFT_CLOVER_ID = 100000'),
    ('GIFT_TICKET_ID 100001', 'GIFT_TICKET_ID = 100001'),
    ('VISITOR_TABLE from visitors.json', 'visitors) || {}).provinceList'),
    ('acquireProvinces state', 'acquireProvinces: []'),
    ('album 9 handlers (spot)', 'album_load_recover: ('),
    ('code 75 kept', 'code: 75'),
    ('giftBoxPayload kept', 'function giftBoxPayload'),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-34s %d' % (label, src.count(needle)))

print()
print('  %-34s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
