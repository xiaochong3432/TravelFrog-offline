"""Verify the SHIPPED APK carries the cooking subsystem, that the shadowing stub
is GONE, and that all earlier work survives.
"""
import zipfile
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('cooking/capsule handlers (each must be exactly 1):')
for c in ['cooking_load_cooking', 'cooking_select', 'cooking_complete_task',
          'cooking_refresh_task', 'cooking_start_cooking', 'cooking_look_ad',
          'cooking_share', 'capsule_load', 'capsule_twist', 'capsule_patch',
          'capsule_fast_task', 'capsule_get_coin']:
    print('  %-24s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('cookingDish helper', 'function cookingDish'),
    ('cookingDealTasks helper', 'function cookingDealTasks'),
    ('cookingTaskProgress helper', 'function cookingTaskProgress'),
    ('COOKING_TASK_FOR map', 'const COOKING_TASK_FOR'),
    ('COOKING_BLOCKED_TYPES', 'COOKING_BLOCKED_TYPES = [2, 8]'),
    ('shadowing stub REMOVED (must be 0)', 'cooking_load_cooking: () => ({ task_list: [] })'),
    ('capsule kept', 'function capsulePayload'),
    ('decorate kept', 'function rollDecoration'),
    ('wishPool kept', 'function wishPoolItems'),
    ('drawing kept', 'guest_load_drawing: ('),
    ('album recover kept', 'album_load_recover: ('),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-36s %d' % (label, src.count(needle)))

print()
print('  %-36s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
