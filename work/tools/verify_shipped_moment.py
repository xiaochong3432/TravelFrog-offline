"""Verify the SHIPPED APK carries the moment fix plus all earlier work."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('handlers (each must be exactly 1):')
for c in ['misc_moment_load', 'misc_moment_unlock', 'tutorial_step_open_door_q',
          'tutorial_step_ask_award_q', 'cooking_load_cooking', 'capsule_load']:
    print('  %-28s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('moments state', 'moments: []'),
    ('tutorial ok:true x2', 'return { ok: true }'),
    ('moment stub REMOVED (must be 0)', 'misc_moment_load: () => ({ list: [] })'),
    ('cooking kept', 'function cookingDealTasks'),
    ('capsule kept', 'function capsulePayload'),
    ('decorate kept', 'function rollDecoration'),
    ('drawing kept', 'guest_load_drawing: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-34s %d' % (label, src.count(needle)))

print()
print('  %-34s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
