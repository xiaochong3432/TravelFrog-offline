"""Verify the SHIPPED APK carries the tutorial fix plus all earlier work."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('tutorial handlers (each must be exactly 1):')
for c in ['tutorial_step_open_door', 'tutorial_step_open_door_q',
          'tutorial_step_ask_award', 'tutorial_step_ask_award_q']:
    print('  %-28s %d' % (c, src.count(c + ': (')))

print()
# the stall fix: the ONLY thing that matters is that both _q handlers return ok:true
print('  ok:true occurrences (must be >= 2): %d' % src.count('return { ok: true }'))
print()
for label, needle in [
    ('guide state', 'guide: { doorOpened'),
    ('cooking kept', 'function cookingDealTasks'),
    ('capsule kept', 'function capsulePayload'),
    ('decorate kept', 'function rollDecoration'),
    ('wishPool kept', 'function wishPoolItems'),
    ('drawing kept', 'guest_load_drawing: ('),
    ('album recover kept', 'album_load_recover: ('),
    ('furniture_buy_shop kept', 'furniture_buy_shop: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-32s %d' % (label, src.count(needle)))

print()
print('  %-32s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
