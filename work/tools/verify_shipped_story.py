"""Verify the SHIPPED APK carries the story subsystem plus all earlier work."""
import zipfile
import re
import os

APK = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..',
                   'dist', 'TravelFrog-offline.apk')
z = zipfile.ZipFile(APK)
src = z.read('assets/game/__offline-engine.js').decode('utf-8')
print('engine chars : %d\n' % len(src))

print('story handlers (each must be exactly 1):')
for c in ['story_load', 'story_send_gift', 'story_read_new_story',
          'story_feedback_gift']:
    print('  %-26s %d' % (c, src.count(c + ': (')))

print()
for label, needle in [
    ('STORY table loaded', 'tables) || {}).story'),
    ('friend_choice_percent used', 'friend_choice_percent'),
    ('rollStory helper', 'function rollStory'),
    ('storyBook state', 'storyBook: {'),
    ('old stub REMOVED (must be 0)', 'story_load: () => ({ stories: [], new_story_id: 0 })'),
    ('animpicture kept', 'animpicture_use_item: ('),
    ('moment kept', 'misc_moment_unlock: ('),
    ('cooking kept', 'function cookingDealTasks'),
    ('picture-layers inlined', "define('./data/picture-layers.json'"),
]:
    print('  %-34s %d' % (label, src.count(needle)))

print()
print('  %-34s %d  (must be 0)' % ('CONTROL absent', src.count('zzz_must_not_exist_zzz')))
