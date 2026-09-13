import re

d = open(r'H:\AI\frog\work\base\assets\game\js\main.min.js', 'rb').read().decode('utf8', 'replace')
pats = ['calendar_get_st_reward', 'calendar_get_luck_reward', 'calendar_get_beginer_reward',
        'calendar_get_code_reward', 'encyclopedia_set_show_sub', 'guest_finish',
        'story_read_new_story', 'guest_lock_bag', 'guest_accept_invit', 'story_feedback_gift',
        'task_get_reward', 'item_gacha', 'story_send_gift']
out = []
for p in pats:
    out.append('== ' + p)
    for m in re.finditer(re.escape('"' + p + '"'), d):
        out.append('   ' + repr(d[m.start():m.start() + 200]))
open(r'H:\AI\frog\work\spec\out_sendargs.txt', 'w', encoding='utf8').write('\n'.join(out))
print('\n'.join(out))
