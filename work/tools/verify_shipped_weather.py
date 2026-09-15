"""Verify the SHIPPED APK carries the weather fix plus all earlier work."""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

for label, needle in [
    ('weather default is 1 (not 0)', 'weather: { season: 1, hoursType: 1, weather: 1 }'),
    ('old-0 default GONE (must be 0)', 'weather: { season: 1, hoursType: 1, weather: 0 }'),
    ('weather migration in loadState', 's.weather.weather = 1;'),
    ('season migration', 's.weather.season = 1;'),
    ('momentTrigger kept', 'function momentTrigger'),
    ('type-1 hook kept', 'momentTrigger(1, motionName)'),
    ('HaveItemMax clamp kept', 'const cap = Number(ORIG.haveItemMax)'),
    ('story kept', 'function rollStory'),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-34s %d' % (label, src.count(needle)))

print()
print('  %-34s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
