local M = {}

-- 这些是声网的事件
M.ON_JOIN_CHANNEL_SUCC = 'on_join_channel_succ'
M.ON_JOIN_CHANNEL_FAIL = 'on_join_channel_fail'
M.ON_REOIN_CHANNEL_SUCC = 'on_rejoin_channel_succ'
M.ON_LEAVE_CHANNEL_SUCC = 'on_leave_channel_succ'
M.ON_LEAVE_CHANNEL_FAIL = 'on_leave_channel_fail'
M.ON_USER_JOINED = 'on_user_joined'
M.ON_USER_LEAVE = 'on_user_leave'
M.ON_USER_MUTED = 'on_user_muted'
M.ON_CONNECTION_INTERRUPT = 'on_connection_interrupt'
M.ON_CONNECTION_BANNED = 'on_conncetion_banned'
M.ON_CONNECTION_LOST = 'on_connection_lost'
M.ON_VOLUME_INDICATION = 'on_volume_indication'

--[[
    on_lastmile_quality(quality)
    参数quality，类型int，各个value表示的含义如下：
    0: 网络质量未知。
    1: 网络质量极好。
    2: 用户主观感觉和 excellent 差不多，但码率可能略低于 excellent。
    3: 用户主观感受有瑕疵但不影响沟通。
    4: 勉强能沟通但不顺畅。
    5: 网络质量非常差，基本不能沟通。
    6: 完全无法沟通。
    7: 暂时无法检测网络质量（未使用）。
    8: 网络质量检测已开始还没完成。
--]]
M.ON_LASTMILE_QUALITY = 'on_lastmile_quality'

--[[
    on_lastmile_probe_result(result)
    参数result，类型table：
    result.rtt 	    往返时延 (ms)
    result.state 	质量探测结果的状态，1: 表示本次 last mile 质量探测的结果是完整的
                                     2: 表示本次 last mile 质量探测未进行带宽预测，因此结果不完整。一个可能的原因是测试资源暂时受限。
                                     3: 未进行 last mile 质量探测。一个可能的原因是网络连接中断。
    result.uplink_report.packet_loss_rate 	    上行网络质量报告，丢包率
    result.uplink_report.jitter 	            上行网络质量报告，网络抖动 (ms)
    result.uplink_report.available_bandwidth 	上行网络质量报告，可用网络带宽预估 (bps)
    result.downlink_report.packet_loss_rate 	下行网络质量报告，丢包率
    result.downlink_report.jitter 	            下行网络质量报告，网络抖动 (ms)
    result.downlink_report.available_bandwidth 	下行网络质量报告，可用网络带宽预估 (bps)
--]]
M.ON_LASTMILE_PROBE_RESULT = 'on_lastmile_probe_result'

M.ON_AUDIO_QUALITY = 'on_audio_quality'

M.ON_CONNECTION_STATE_CHANGED = 'on_connection_state_changed'

M.ON_REQUEST_TOKEN = 'on_request_token'

M.ON_TOKEN_PRIVILEGE_WILL_EXPIRE = 'on_token_privilege_will_expire'

-- 麦克风采集状态变化
M.ON_LOCAL_AUDIO_STATE_CHANGED = 'on_local_audio_state_changed'

-- 音频设备变化回调（提示系统音频设备状态发生改变，比如耳机被拔出）
M.ON_AUDIO_DEVICE_STATE_CHANGED = 'on_audio_device_state_changed'

-- 声网连接质量的回调
M.ON_RTC_STATS = 'on_rtc_stats'

M.ON_ERROR = 'on_error'

return M