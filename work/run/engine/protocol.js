// Auto-generated from assets/game/js/main.min.js ProtocolList
// params = argument names; needResponse = client waits for a reply
'use strict';
module.exports = {
 "notify_new_mail": {
  "needResponse": false,
  "params": [],
  "note": "push-only: registered via addProtocolCallback; absent from ProtocolList"
 },
 "adsmgr_load": {
  "needResponse": true,
  "params": []
 },
 "adsmgr_refuse": {
  "needResponse": true,
  "params": []
 },
 "adsmgr_share": {
  "needResponse": true,
  "params": [
   "ads_type"
  ]
 },
 "adsmgr_share_ads": {
  "needResponse": false,
  "params": [
   "ads_id"
  ]
 },
 "adsmgr_shop_free": {
  "needResponse": true,
  "params": []
 },
 "album_delete": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "album_delete_new": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "album_load": {
  "needResponse": true,
  "params": [
   "start",
   "count"
  ]
 },
 "album_load_all": {
  "needResponse": true,
  "params": []
 },
 "album_load_by_id_list": {
  "needResponse": true,
  "params": [
   "id_list"
  ]
 },
 "album_load_new": {
  "needResponse": true,
  "params": []
 },
 "album_load_recover": {
  "needResponse": true,
  "params": []
 },
 "album_recover": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "album_save_new": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "animpicture_add_pic": {
  "needResponse": true,
  "params": [
   "ids"
  ]
 },
 "animpicture_album_add_pic": {
  "needResponse": true,
  "params": [
   "anim_index",
   "pic_index",
   "pic_uid"
  ]
 },
 "animpicture_album_remove_pic": {
  "needResponse": true,
  "params": [
   "anim_index",
   "pic_index",
   "is_delete"
  ]
 },
 "animpicture_get_item": {
  "needResponse": true,
  "params": []
 },
 "animpicture_guide": {
  "needResponse": true,
  "params": []
 },
 "animpicture_load": {
  "needResponse": true,
  "params": []
 },
 "animpicture_open_album": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "animpicture_remove_pic": {
  "needResponse": true,
  "params": [
   "index",
   "is_delete"
  ]
 },
 "animpicture_select_pic": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "animpicture_use_item": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "annual_load": {
  "needResponse": true,
  "params": []
 },
 "annual_share": {
  "needResponse": true,
  "params": []
 },
 "calendar_get_beginer_reward": {
  "needResponse": true,
  "params": []
 },
 "calendar_get_code_reward": {
  "needResponse": true,
  "params": [
   "day"
  ]
 },
 "calendar_get_luck_reward": {
  "needResponse": true,
  "params": []
 },
 "calendar_get_st_reward": {
  "needResponse": true,
  "params": []
 },
 "calendar_load": {
  "needResponse": true,
  "params": []
 },
 "calendar_load_note": {
  "needResponse": true,
  "params": []
 },
 "calendar_task_update": {
  "needResponse": true,
  "params": []
 },
 "capsule_fast_task": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "capsule_get_coin": {
  "needResponse": true,
  "params": []
 },
 "capsule_load": {
  "needResponse": true,
  "params": []
 },
 "capsule_load_coin": {
  "needResponse": true,
  "params": []
 },
 "capsule_load_task": {
  "needResponse": true,
  "params": []
 },
 "capsule_patch": {
  "needResponse": true,
  "params": []
 },
 "capsule_twist": {
  "needResponse": true,
  "params": []
 },
 "client_add_push_id": {
  "needResponse": false,
  "params": [
   "push_id"
  ]
 },
 "client_change_decorate": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "client_confirm_event": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "client_draw_taobao": {
  "needResponse": true,
  "params": [
   "draw"
  ]
 },
 "client_get_my_wx_reward": {
  "needResponse": true,
  "params": []
 },
 "client_get_push_reward": {
  "needResponse": true,
  "params": []
 },
 "client_gm": {
  "needResponse": true,
  "params": [
   "cmd"
  ]
 },
 "client_hello": {
  "needResponse": true,
  "params": []
 },
 "client_load_all_info": {
  "needResponse": true,
  "params": []
 },
 "client_load_decorate": {
  "needResponse": true,
  "params": []
 },
 "client_load_events": {
  "needResponse": true,
  "params": []
 },
 "client_load_role": {
  "needResponse": true,
  "params": []
 },
 "client_rename_cost": {
  "needResponse": true,
  "params": []
 },
 "client_set_achieve": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "client_set_ads": {
  "needResponse": false,
  "params": [
   "support"
  ]
 },
 "client_set_channel": {
  "needResponse": false,
  "params": [
   "channel"
  ]
 },
 "client_set_channel_id": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "client_set_client": {
  "needResponse": false,
  "params": [
   "client"
  ]
 },
 "client_set_client_envinfo": {
  "needResponse": false,
  "params": [
   "info"
  ]
 },
 "client_set_icon": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "client_set_lang": {
  "needResponse": false,
  "params": [
   "lang"
  ]
 },
 "client_set_name": {
  "needResponse": true,
  "params": [
   "name"
  ]
 },
 "client_set_pic_show": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "client_set_wx_open_id": {
  "needResponse": true,
  "params": [
   "open_id"
  ]
 },
 "client_share_publicity": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "client_switch_push": {
  "needResponse": true,
  "params": [
   "turnon"
  ]
 },
 "client_switch_rank": {
  "needResponse": true,
  "params": [
   "turnon"
  ]
 },
 "client_taobao_import": {
  "needResponse": true,
  "params": [
   "taobao_uid"
  ]
 },
 "client_user_action": {
  "needResponse": false,
  "params": [
   "name"
  ]
 },
 "clover_harvest": {
  "needResponse": true,
  "params": [
   "clover_id"
  ]
 },
 "clover_harvest_resend": {
  "needResponse": true,
  "params": [
   "list"
  ]
 },
 "clover_load_clovers": {
  "needResponse": true,
  "params": []
 },
 "clover_notice_get": {
  "needResponse": true,
  "params": []
 },
 "clover_update": {
  "needResponse": true,
  "params": []
 },
 "cooking_complete_task": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "cooking_load_cooking": {
  "needResponse": true,
  "params": []
 },
 "cooking_look_ad": {
  "needResponse": true,
  "params": []
 },
 "cooking_refresh_task": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "cooking_select": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "cooking_share": {
  "needResponse": true,
  "params": []
 },
 "cooking_start_cooking": {
  "needResponse": true,
  "params": []
 },
 "encyclopedia_load": {
  "needResponse": true,
  "params": []
 },
 "encyclopedia_set_show_sub": {
  "needResponse": false,
  "params": [
   "long_id"
  ]
 },
 "furniture_buy_shop": {
  "needResponse": true,
  "params": [
   "shop_id"
  ]
 },
 "furniture_flowerpot_harvest": {
  "needResponse": true,
  "params": [
   "type",
   "index"
  ]
 },
 "furniture_load_compost": {
  "needResponse": true,
  "params": []
 },
 "furniture_load_furniture": {
  "needResponse": true,
  "params": []
 },
 "furniture_load_pocket": {
  "needResponse": true,
  "params": []
 },
 "furniture_load_tumbler": {
  "needResponse": true,
  "params": []
 },
 "furniture_pocket_get": {
  "needResponse": true,
  "params": []
 },
 "furniture_putin_bench": {
  "needResponse": true,
  "params": [
   "pos",
   "id"
  ]
 },
 "furniture_putin_box": {
  "needResponse": true,
  "params": [
   "pos",
   "id"
  ]
 },
 "furniture_replace_compost": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "furniture_replace_fur": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "furniture_replace_pocket": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "furniture_replace_tumbler": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "furniture_takeout_bench": {
  "needResponse": true,
  "params": [
   "pos"
  ]
 },
 "furniture_takeout_box": {
  "needResponse": true,
  "params": [
   "pos"
  ]
 },
 "greetcard_buy": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "greetcard_change_bg": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "greetcard_change_bless": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "greetcard_feedback_gift": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "greetcard_get_reward": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "greetcard_get_task_item": {
  "needResponse": true,
  "params": []
 },
 "greetcard_get_task_reward": {
  "needResponse": true,
  "params": []
 },
 "greetcard_load": {
  "needResponse": true,
  "params": []
 },
 "greetcard_load_count": {
  "needResponse": true,
  "params": []
 },
 "greetcard_put_tags": {
  "needResponse": true,
  "params": [
   "pos",
   "id"
  ]
 },
 "greetcard_read_new": {
  "needResponse": false,
  "params": []
 },
 "greetcard_send": {
  "needResponse": true,
  "params": []
 },
 "greetcard_send_gift": {
  "needResponse": false,
  "params": [
   "index",
   "gift"
  ]
 },
 "greetcard_stock": {
  "needResponse": true,
  "params": []
 },
 "guest_accept_invit": {
  "needResponse": true,
  "params": [
   "is_accept"
  ]
 },
 "guest_confirm": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "guest_finish": {
  "needResponse": false,
  "params": []
 },
 "guest_load": {
  "needResponse": true,
  "params": []
 },
 "guest_load_drawing": {
  "needResponse": true,
  "params": []
 },
 "guest_lock_bag": {
  "needResponse": true,
  "params": []
 },
 "guest_putin_bag": {
  "needResponse": true,
  "params": [
   "pos",
   "id"
  ]
 },
 "guest_serve": {
  "needResponse": false,
  "params": [
   "id",
   "item_id"
  ]
 },
 "guest_set_expire_time": {
  "needResponse": false,
  "params": [
   "time"
  ]
 },
 "guest_takeout_bag": {
  "needResponse": true,
  "params": [
   "pos"
  ]
 },
 "hall_enter_game": {
  "needResponse": true,
  "params": []
 },
 "hall_gen_token": {
  "needResponse": true,
  "params": [
   "account"
  ]
 },
 "hall_hello": {
  "needResponse": true,
  "params": []
 },
 "hall_leave_game": {
  "needResponse": false,
  "params": []
 },
 "hall_login": {
  "needResponse": true,
  "params": [
   "token"
  ]
 },
 "hall_reconnect": {
  "needResponse": true,
  "params": [
   "token",
   "account"
  ]
 },
 "hall_report_remote_addr": {
  "needResponse": false,
  "params": [
   "remote_addr",
   "local_addr"
  ]
 },
 "item_buy": {
  "needResponse": true,
  "params": [
   "shop_id"
  ]
 },
 "item_gacha": {
  "needResponse": true,
  "params": [
   "is_reward"
  ]
 },
 "item_load_handbook": {
  "needResponse": true,
  "params": []
 },
 "item_load_items": {
  "needResponse": true,
  "params": []
 },
 "item_load_select_gift": {
  "needResponse": true,
  "params": []
 },
 "item_load_shop_info": {
  "needResponse": true,
  "params": []
 },
 "item_putin_bag": {
  "needResponse": true,
  "params": [
   "pos",
   "item_id"
  ]
 },
 "item_putin_desk": {
  "needResponse": true,
  "params": [
   "pos",
   "item_id"
  ]
 },
 "item_redeem_prize": {
  "needResponse": false,
  "params": [
   "prize_id"
  ]
 },
 "item_select_gift": {
  "needResponse": true,
  "params": [
   "index_list"
  ]
 },
 "item_set_bag_completed": {
  "needResponse": false,
  "params": [
   "completed"
  ]
 },
 "item_takeout_bag": {
  "needResponse": true,
  "params": [
   "pos"
  ]
 },
 "item_takeout_desk": {
  "needResponse": true,
  "params": [
   "pos"
  ]
 },
 "item_update": {
  "needResponse": true,
  "params": []
 },
 "item_update_ticket": {
  "needResponse": true,
  "params": []
 },
 "item_use_gift_code": {
  "needResponse": true,
  "params": [
   "gift_code"
  ]
 },
 "koto_arrive": {
  "needResponse": true,
  "params": []
 },
 "koto_dir_compass": {
  "needResponse": true,
  "params": [
   "dir"
  ]
 },
 "koto_get_items": {
  "needResponse": true,
  "params": []
 },
 "koto_info": {
  "needResponse": false,
  "params": []
 },
 "koto_load": {
  "needResponse": true,
  "params": []
 },
 "koto_load_path": {
  "needResponse": true,
  "params": []
 },
 "koto_random_compass": {
  "needResponse": true,
  "params": []
 },
 "koto_refresh": {
  "needResponse": true,
  "params": []
 },
 "koto_start_advance": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "lottery_confirm_reward": {
  "needResponse": true,
  "params": []
 },
 "lottery_load": {
  "needResponse": true,
  "params": []
 },
 "lottery_open": {
  "needResponse": true,
  "params": []
 },
 "lottery_select": {
  "needResponse": true,
  "params": [
   "list"
  ]
 },
 "mail_ejoy_active_code": {
  "needResponse": true,
  "params": [
   "ticket"
  ]
 },
 "mail_load": {
  "needResponse": true,
  "params": []
 },
 "mail_load_mails": {
  "needResponse": true,
  "params": [
   "start",
   "count",
   "is_clear"
  ]
 },
 "mail_open": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "mail_read": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "misc_moment_load": {
  "needResponse": true,
  "params": []
 },
 "misc_moment_unlock": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "museum_load": {
  "needResponse": true,
  "params": []
 },
 "museumday_arrive": {
  "needResponse": true,
  "params": []
 },
 "museumday_dir_compass": {
  "needResponse": true,
  "params": [
   "dir"
  ]
 },
 "museumday_get_items": {
  "needResponse": true,
  "params": []
 },
 "museumday_info": {
  "needResponse": false,
  "params": []
 },
 "museumday_inspire": {
  "needResponse": true,
  "params": []
 },
 "museumday_load": {
  "needResponse": true,
  "params": []
 },
 "museumday_load_path": {
  "needResponse": true,
  "params": []
 },
 "museumday_random_compass": {
  "needResponse": true,
  "params": []
 },
 "museumday_refresh": {
  "needResponse": true,
  "params": []
 },
 "museumday_start_advance": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "other_req_touch": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "partycake_answer": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "partycake_get_mate": {
  "needResponse": true,
  "params": []
 },
 "partycake_light": {
  "needResponse": true,
  "params": []
 },
 "partycake_load": {
  "needResponse": true,
  "params": []
 },
 "partycake_load_mate": {
  "needResponse": true,
  "params": []
 },
 "partycake_load_qa": {
  "needResponse": true,
  "params": []
 },
 "partycake_load_task": {
  "needResponse": true,
  "params": []
 },
 "partycake_make": {
  "needResponse": true,
  "params": [
   "layer"
  ]
 },
 "partycake_reward_light": {
  "needResponse": true,
  "params": []
 },
 "partycake_reward_make": {
  "needResponse": true,
  "params": []
 },
 "partycake_reward_qa": {
  "needResponse": true,
  "params": []
 },
 "partycake_reward_share": {
  "needResponse": true,
  "params": [
   "index"
  ]
 },
 "pray_compose": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "pray_confirm_make_box": {
  "needResponse": false,
  "params": []
 },
 "pray_load_grays": {
  "needResponse": true,
  "params": []
 },
 "rank_get_intro": {
  "needResponse": true,
  "params": [
   "type",
   "duration",
   "uid"
  ]
 },
 "rank_like": {
  "needResponse": false,
  "params": [
   "type",
   "duration",
   "uid"
  ]
 },
 "rank_load": {
  "needResponse": true,
  "params": [
   "type",
   "duration",
   "start",
   "count"
  ]
 },
 "recharge_cancel_pay": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "recharge_change": {
  "needResponse": true,
  "params": []
 },
 "recharge_load": {
  "needResponse": true,
  "params": []
 },
 "recharge_load_gift": {
  "needResponse": true,
  "params": []
 },
 "recharge_ready_pay": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "recharge_update_num": {
  "needResponse": true,
  "params": []
 },
 "recharge_water": {
  "needResponse": true,
  "params": []
 },
 "share_get_reward": {
  "needResponse": true,
  "params": [
   "id",
   "is_get"
  ]
 },
 "share_load": {
  "needResponse": true,
  "params": []
 },
 "springcard_buy": {
  "needResponse": true,
  "params": []
 },
 "springcard_change_bg": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "springcard_change_bless": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "springcard_get_reward": {
  "needResponse": true,
  "params": []
 },
 "springcard_get_share_tags": {
  "needResponse": true,
  "params": [
   "share_code"
  ]
 },
 "springcard_get_task_item": {
  "needResponse": true,
  "params": []
 },
 "springcard_get_task_reward": {
  "needResponse": true,
  "params": []
 },
 "springcard_load": {
  "needResponse": true,
  "params": []
 },
 "springcard_load_count": {
  "needResponse": true,
  "params": []
 },
 "springcard_put_tags": {
  "needResponse": true,
  "params": [
   "pos",
   "id"
  ]
 },
 "springcard_send": {
  "needResponse": true,
  "params": []
 },
 "springcard_share_tags": {
  "needResponse": true,
  "params": [
   "tags_id"
  ]
 },
 "story_feedback_gift": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "story_load": {
  "needResponse": true,
  "params": []
 },
 "story_read_new_story": {
  "needResponse": false,
  "params": []
 },
 "story_send_gift": {
  "needResponse": false,
  "params": [
   "id",
   "gift"
  ]
 },
 "task_client_pro": {
  "needResponse": false,
  "params": [
   "param"
  ]
 },
 "task_get_list_reward": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "task_get_reward": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "task_load": {
  "needResponse": true,
  "params": []
 },
 "task_load_list": {
  "needResponse": true,
  "params": []
 },
 "travel_album_to_gift": {
  "needResponse": true,
  "params": [
   "picture_id"
  ]
 },
 "travel_bag_to_gift": {
  "needResponse": true,
  "params": [
   "item_id"
  ]
 },
 "travel_gift_delete_album": {
  "needResponse": true,
  "params": [
   "id"
  ]
 },
 "travel_gift_to_album": {
  "needResponse": true,
  "params": [
   "picture_id"
  ]
 },
 "travel_gift_to_bag": {
  "needResponse": true,
  "params": [
   "item_id"
  ]
 },
 "travel_load_gift": {
  "needResponse": true,
  "params": []
 },
 "travel_load_note": {
  "needResponse": true,
  "params": []
 },
 "travel_read_note": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "tutorial_step_ask_award": {
  "needResponse": false,
  "params": []
 },
 "tutorial_step_ask_award_q": {
  "needResponse": true,
  "params": []
 },
 "tutorial_step_open_door": {
  "needResponse": false,
  "params": []
 },
 "tutorial_step_open_door_q": {
  "needResponse": true,
  "params": []
 },
 "visit_load": {
  "needResponse": true,
  "params": []
 },
 "visit_open": {
  "needResponse": false,
  "params": []
 },
 "visit_set_carpet": {
  "needResponse": false,
  "params": [
   "id"
  ]
 },
 "visit_set_expire_time": {
  "needResponse": false,
  "params": [
   "time"
  ]
 },
 "wishingpool_load": {
  "needResponse": true,
  "params": []
 },
 "wishingpool_wish": {
  "needResponse": true,
  "params": []
 }
};
