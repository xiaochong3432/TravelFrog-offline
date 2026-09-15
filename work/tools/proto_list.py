from pathlib import Path as _PortablePath
# 仓库根：本文件位于 <仓库根>/work/tools/ 下，因此向上两级。
# 不写死任何绝对路径 —— 换机器 / 换系统（Windows、Linux、macOS）都能直接跑。
PROJECT_ROOT = _PortablePath(__file__).resolve().parents[2]
import json

t = open(str(PROJECT_ROOT) + "/work/run/engine/protocol.js", encoding='utf8').read()
i = t.index('{')
d = json.loads(t[i:t.rindex('}') + 1])

names = ['guest_load','guest_load_drawing','guest_confirm','guest_accept_invit','guest_serve',
         'guest_putin_bag','guest_takeout_bag','guest_lock_bag','guest_finish','guest_set_expire_time',
         'mail_load','mail_load_mails','mail_open','mail_read','mail_ejoy_active_code',
         'task_load','task_load_list','task_get_reward','task_get_list_reward','task_client_pro',
         'calendar_load','calendar_load_note','calendar_task_update','calendar_get_luck_reward',
         'calendar_get_st_reward','calendar_get_beginer_reward','calendar_get_code_reward',
         'story_load','story_read_new_story','story_send_gift','story_feedback_gift',
         'lottery_load','lottery_open','lottery_select','lottery_confirm_reward',
         'encyclopedia_load','encyclopedia_set_show_sub','notify_new_mail','visit_load',
         'item_gacha','item_update','item_update_ticket','clover_update','item_use_gift_code']

lines = []
for n in names:
    v = d.get(n)
    if not v:
        lines.append('%-28s MISSING' % n)
    else:
        lines.append('%-28s needResponse=%s params=%s' % (n, v['needResponse'], v['params']))
open(str(PROJECT_ROOT) + "/work/spec/out_proto.txt", 'w', encoding='utf8').write('\n'.join(lines))
print('\n'.join(lines))
