"""Verify the SHIPPED APK carries the values work plus all earlier subsystems."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

for label, needle in [
    ('FROG_FAITHFUL switch', 'FROG_FAITHFUL'),
    ('ORIG recovered table', 'const ORIG = {'),
    ('pace() helper', 'const pace = (envName'),
    ('FRIEND_VISIT_COOL default', "DEF('FRIEND_VISIT_COOL', 21600)"),
    ('TRAVEL_TIME_MIN default', "DEF('TRAVEL_TIME_MIN', 60)"),
    ('FROG_DRIFTRETURNTIME', "DEF('FROG_DRIFTRETURNTIME', 10)"),
    ('CloverDestroyTime read', "DEF('CloverDestroyTime', 0.6)"),
    ('stray uses drift window', 'const stray = !!(state.travel.plan'),
    ('DRIFT_RETURN_MIN', 'const DRIFT_RETURN_MIN'),
    ('--- earlier subsystems ---', '---'),
    ('story kept', 'function rollStory'),
    ('animpicture kept', 'animpicture_use_item: ('),
    ('moment kept', 'misc_moment_unlock: ('),
    ('cooking kept', 'function cookingDealTasks'),
    ('capsule kept', 'function capsulePayload'),
    ('tutorial ok kept', 'return { ok: true }'),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-30s %d' % (label, src.count(needle) if needle != '---' else 0))

print()
print('  %-30s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
