"""Verify the SHIPPED APK carries the capsule event, that the shadowing stub is
GONE, and that all earlier work survives.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('capsule/decorate/wishpool handlers (each must be exactly 1):')
for c in ['capsule_load', 'capsule_twist', 'capsule_patch', 'capsule_fast_task',
          'capsule_get_coin', 'client_load_decorate', 'client_change_decorate',
          'wishingpool_load', 'wishingpool_wish']:
    print('  %-24s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('capsulePayload helper', 'function capsulePayload'),
    ('capsulePatch helper', 'function capsulePatch'),
    ('capsuleTaskDone helper', 'function capsuleTaskDone'),
    ('capsuleThresholdBonuses', 'function capsuleThresholdBonuses'),
    ('CAPSULE_TASK_FOR map', 'const CAPSULE_TASK_FOR'),
    ('shadowing stub REMOVED (must be 0)', 'capsule_load: () => ({ end_time: 0'),
    ('decorate kept', 'function rollDecoration'),
    ('wishPool kept', 'function wishPoolItems'),
    ('lottery kept', 'function startLotteryPhase'),
    ('drawing kept', 'guest_load_drawing: ('),
    ('album recover kept', 'album_load_recover: ('),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-36s %d' % (label, src.count(needle)))

print()
print('  %-36s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
