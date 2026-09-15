local E = require 'ejoysdk_lua.ejoysdk'
local cache = require 'ejoysdk_lua.chat.ejoysdk_chat_cache'
local UNI = require 'ejoysdk_lua.vendors.unisdk'
local EM = require "ejoysdk_lua.ejoysdk_module"
local voice_event = require 'ejoysdk_lua.chat.ejoysdk_voice_event'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local log_mgr = require "ejoysdk_lua.ejoysdk_log_mgr"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local ECC = require 'ejoysdk_lua.ejoysdk_config_center'

local VENDOR_NAME = 'AGORA'

local SYNC_IS_COMPAT_NEW_API = "SYNC_IS_COMPAT_NEW_API"
local CAST_INIT_ENGINE = "CAST_INIT_ENGINE"
local CAST_JOIN_CHANNEL = "CAST_JOIN_CHANNEL"
local CAST_JOIN_CHANNEL_WITH_TOKEN = "CAST_JOIN_CHANNEL_WITH_TOKEN"
local CAST_LEAVE_CHANNEL = "CAST_LEAVE_CHANNEL"
local CAST_ENABLE_AUDIO_VOLUME_INDICATION = "CAST_ENABLE_AUDIO_VOLUME_INDICATION"
local CAST_MUTE_LOCAL = "CAST_MUTE_LOCAL"
local CAST_MUTE_REMOTE = 'CAST_MUTE_REMOTE'
local CAST_MUTE_REMOTE_ALL = 'CAST_MUTE_REMOTE_ALL'
local CAST_SET_ENABLE_SPEAKER = 'CAST_SET_ENABLE_SPEAKER'
local CAST_SET_PARAMETERS = 'CAST_SET_PARAMETERS'
local CAST_ADJUST_RECORD_VOLUME = "CAST_ADJUST_RECORD_VOLUME"
local CAST_ADJUST_PLAYING_VOLUME = "CAST_ADJUST_PLAYING_VOLUME"
local CAST_SET_DEFAULT_AUDIO_ROUTE_TO_SPEAKER = 'CAST_SET_DEFAULT_AUDIO_ROUTE_TO_SPEAKER'
local CAST_SET_AUDIO_PROFILE = 'CAST_SET_AUDIO_PROFILE'
local CAST_ENABLE_LOCAL_AUDIO = 'CAST_ENABLE_LOCAL_AUDIO'
--local CAST_SET_CHANNEL_PROFILE = 'CAST_SET_CHANNEL_PROFILE'
local CAST_SET_CLIENT_ROLE = 'CAST_SET_CLIENT_ROLE'
local CAST_START_ECHO_TEST = 'CAST_START_ECHO_TEST'
local CAST_STOP_ECHO_TEST = 'CAST_STOP_ECHO_TEST'
local CAST_START_LASTMILE_PROBE_TEST = 'CAST_START_LASTMILE_PROBE_TEST'
local CAST_STOP_LASTMILE_PROBE_TEST = 'CAST_STOP_LASTMILE_PROBE_TEST'

local EVT_USER_JOINED = "EVT_USER_JOINED"
local EVT_USER_OFFLINE = "EVT_USER_OFFLINE"
local EVT_USER_MUTED = "EVT_USER_MUTED"
local EVT_JOIN_CHANNEL_SUCC = "EVT_JOIN_CHANNEL_SUCC"
local EVT_JOIN_CHANNEL_FAIL = "EVT_JOIN_CHANNEL_FAIL"
local EVT_REJOIN_CHANNEL_SUCC = "EVT_REJOIN_CHANNEL_SUCC"
local EVT_LEAVE_CHANNEL_SUCC = 'EVT_LEAVE_CHANNEL_SUCC'
local EVT_LEAVE_CHANNEL_FAIL = 'EVT_LEAVE_CHANNEL_FAIL'
local EVT_ERROR = "EVT_ERROR"
local EVT_CONNECTION_LOST = "EVT_CONNECTION_LOST"
local EVT_CONNECTION_BANNED = "EVT_CONNECTION_BANNED"
local EVT_CONNECTION_INTERRUPT = "EVT_CONNECTION_INTERRUPT"
local EVT_AUDIO_VOLUME_INDICATION = "EVT_AUDIO_VOLUME_INDICATION"
local EVT_LASTMILE_QUALITY = "EVT_LASTMILE_QUALITY"
local EVT_LASTMILE_PROBE_RESULT = "EVT_LASTMILE_PROBE_RESULT"
local EVT_AUDIO_QUALITY = "EVT_AUDIO_QUALITY"
local EVT_CONNECTION_STATE_CHANGED = "EVT_CONNECTION_STATE_CHANGED"
local EVT_REQUEST_TOKEN = "EVT_REQUEST_TOKEN"
local EVT_TOKEN_PRIVILEGE_WILL_EXPIRE = "EVT_TOKEN_PRIVILEGE_WILL_EXPIRE"
local EVT_LOCAL_AUDIO_STATE_CHANGED = "EVT_LOCAL_AUDIO_STATE_CHANGED"
local EVT_AUDIO_DEVICE_STATE_CHANGED = "EVT_AUDIO_DEVICE_STATE_CHANGED"
local EVT_RTC_STATS = "EVT_RTC_STATS"

local AGORA_JF_UPLOAD_NOW = false

local agora_listener = nil

local TAG = EM.MODULE.VENDORS.AGORA

-- 从配置中心判断是否禁用上报角色名称
local function is_forbid_upload_role_name_from_cc()
    local cc_config = ECC.get_config(ECC.NAMESPACE.EJOYSDK_BIZ)
    local agora_config = cc_config and cc_config.config and cc_config.config.agora  -- 读取agora的配置
    if agora_config and agora_config.is_forbid_upload_role_name then
        return true
    end
    return false
end

local function callback(handler_name, ...)
    local handler = agora_listener[handler_name]
    if handler then
        handler(...)
    end

    -- 语音遇到错误，打点上报
    if handler_name == 'on_error' then
        local voice = require 'ejoysdk_lua.chat.ejoysdk_voice'
        local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'

        local error_code, error_msg = ...

        local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
        local chat_cache = require 'ejoysdk_lua.chat.ejoysdk_chat_cache'

        local self_player_id = EG.player_info() and EG.player_info().player_id
        local self_player_name = EG.player_info() and EG.player_info().player_name
        local cached_group = chat_cache.get_group(voice.get_curr_channel_id()) or {}
        local group_type = cached_group.info and cached_group.info.type
        local jf_params = {code=tostring(error_code), msg=tostring(error_msg)}
        if self_player_id and type(self_player_id) == 'string' and #self_player_id > 0 then
            jf_params.roleId = self_player_id
        end
        if self_player_name and type(self_player_name) == 'string' and #self_player_name > 0 and not is_forbid_upload_role_name_from_cc() then
            jf_params.roleName = self_player_name
        end
        jf_params.type = group_type or ''
        jf_params.result = false
        jf_params.is_upload_now = AGORA_JF_UPLOAD_NOW

        ESTAT.stat_bizid('error.voice.online', '0', '0', jf_params)
    end
end

local delay_callback_list = {}
local function add_delay_uid_callback(handler_name, body)
    table.insert(delay_callback_list, { handler_name = handler_name, body = body })
end

local M = Vendor:Inherit(VENDOR_NAME)

M.AUDIO_SCENARIO_DEFAULT = 0; -- 默认音频应用场景。
M.AUDIO_SCENARIO_CHATROOM_ENTERTAINMENT = 1; -- 娱乐应用，需要频繁上下麦的场景。
M.AUDIO_SCENARIO_EDUCATION = 2; -- 教育应用，流畅度和稳定性优先。
M.AUDIO_SCENARIO_GAME_STREAMING = 3; -- 游戏直播应用，需要外放游戏音效也直播出去的场景。听得到游戏背景音。
M.AUDIO_SCENARIO_SHOWROOM = 4; -- 秀场应用，音质优先和更好的专业外设支持。
M.AUDIO_SCENARIO_CHATROOM_GAMING = 5; -- 游戏开黑。 听不到游戏背景音。

M.AUDIO_PROFILE_DEFAULT = 0; -- 默认设置。指定 48 KHz 采样率，音乐编码，单声道，编码码率最大值为 52 Kbps。
M.AUDIO_PROFILE_SPEECH_STANDARD = 1; -- 指定 32 KHz 采样率，语音编码, 单声道，编码码率最大值为 18 Kbps。
M.AUDIO_PROFILE_MUSIC_STANDARD = 2; -- 指定 48 KHz 采样率，音乐编码, 单声道，编码码率最大值为 48 Kbps。
M.AUDIO_PROFILE_MUSIC_STANDARD_STEREO = 3; -- 指定 48 KHz采样率，音乐编码, 双声道，编码码率最大值为 56 Kbps。
M.AUDIO_PROFILE_MUSIC_HIGH_QUALITY = 4; -- 指定 48 KHz 采样率，音乐编码, 单声道，编码码率最大值为 128 Kbps。
M.AUDIO_PROFILE_MUSIC_HIGH_QUALITY_STEREO = 5; -- 指定 48 KHz 采样率，音乐编码, 双声道，编码码率最大值为 192 Kbps。

-- (声网文档)9: 当前使用的 Token 过期，用户被迫退出频道。客户端需要重新向自己的业务服务器申请 Token，并使用新的 Token 重新加入频道。
-- 声网文档不正确，测试发现，当reason=9时，其实还在频道里。
M.CONNECTION_CHANGED_TOKEN_EXPIRED = 9

local audio_scenario = M.AUDIO_SCENARIO_DEFAULT
local audio_profile = M.AUDIO_PROFILE_MUSIC_HIGH_QUALITY_STEREO

local is_joining_channel = false
local is_leaveing_channel = false

-- error native没有携带信息，用于重连的记录
local last_join_suc_uid = nil
local last_join_suc_channel = nil

M.is_forbid_upload_role_name_from_cc = is_forbid_upload_role_name_from_cc

function M.set_parameters(params)
    log_mgr.call_api({}, TAG, 'set_parameters', log_mgr.LOG_LEVEL.LOW, {}, params)

    UNI.cast(VENDOR_NAME, CAST_SET_PARAMETERS, {
        params = params
    })
end

local function initialize_engine()
    E.LOG.debug(TAG, 'agora initialize engine')
    UNI.cast(VENDOR_NAME, CAST_INIT_ENGINE, {})
end

function M.init(_opt, cb)
    --log_mgr.call_api({}, TAG, 'init', log_mgr.LOG_LEVEL.LOW, {}, opt, cb)

    initialize_engine()
    local ejoysdk_voice = require 'ejoysdk_lua.chat.ejoysdk_voice'
    ejoysdk_voice.set_voice_vendor(M)

    -- callback init success
    cb(true)
end

local is_support_cache = {}
-- 是否支持sdk已接入的新的声网api，内部使用仅用来区分需要版本兼容的接口
function M.is_compat_agora_api(api_name)
    if is_support_cache[api_name] ~= nil then
        return is_support_cache[api_name]
    end

    local ret = UNI.sync_call(VENDOR_NAME, SYNC_IS_COMPAT_NEW_API, { name = api_name })
    if ret then
        local result = ret.value or false
        is_support_cache[api_name] = result
        return result
    end

    is_support_cache[api_name] = false

    return false
end

function M.is_support_token_join()
    return M.is_compat_agora_api(CAST_JOIN_CHANNEL_WITH_TOKEN) or false
end

-- 对应agora use_join_token, 传递 opt.use_account_join 则对应joinChannelByUserAccount
-- 对外接口部分uid是player_id, voice_user_id是用于声网的id
function M.join_channel(channel_id, uid, opt)
    log_mgr.call_api({}, TAG, 'join_channel', log_mgr.LOG_LEVEL.LOW, {}, channel_id, uid, opt)

    local agora_token = opt.token
    is_joining_channel = true
    M.set_parameters('{\"che.audio.keep.audiosession\":true}')
    M.set_parameters('{\"rtc.sync_user_account_callback\":true}')
    M.set_default_to_speaker(true)
    UNI.cast(VENDOR_NAME, CAST_SET_AUDIO_PROFILE, {
        profile = audio_profile,
        scenario = audio_scenario
    })
    
    -- 默认是优先使用CAST_JOIN_CHANNEL_WITH_TOKEN，旧版本不支持则走回CAST_JOIN_CHANNEL  
    local is_support_token_join = M.is_support_token_join()
    local use_account_join = opt and opt.use_account_join or false
    -- Native端是旧逻辑 或者 服务端是旧逻辑，走原有的 CAST_JOIN_CHANNEL
    if not is_support_token_join or use_account_join then
        E.LOG.d(TAG, 'join_channel with old api: joinChannelByUserAccount, is_support_token_join:' .. tostring(is_support_token_join) .. ', use_account_join:' .. tostring(use_account_join))
        UNI.cast(VENDOR_NAME, CAST_JOIN_CHANNEL, {
            token = agora_token,
            voice_channel = channel_id,
            uid = uid
        })
    else
        local voice_user_id = opt and opt.voice_user_id
        M.update_id_maps(channel_id, uid, voice_user_id)
        UNI.cast(VENDOR_NAME, CAST_JOIN_CHANNEL_WITH_TOKEN, {
            token = agora_token,
            voice_channel = channel_id,
            uid = uid,
            voice_user_id = voice_user_id
        })
    end

    last_join_suc_uid = uid
    last_join_suc_channel = channel_id
end

function M.leave_channel()
    log_mgr.call_api({}, TAG, 'leave_channel', log_mgr.LOG_LEVEL.LOW, {})

    is_leaveing_channel = true

    UNI.cast(VENDOR_NAME, CAST_LEAVE_CHANNEL, {})
end

function M.set_listener(listener)
    log_mgr.call_api({}, TAG, 'set_listener', log_mgr.LOG_LEVEL.LOW, {}, listener)

    agora_listener = listener
end

function M.enable_volume_indication(interval, smooth)
    log_mgr.call_api({}, TAG, 'enable_volume_indication', log_mgr.LOG_LEVEL.LOW, {}, interval, smooth)

    UNI.cast(VENDOR_NAME, CAST_ENABLE_AUDIO_VOLUME_INDICATION, {
        interval = interval,
        smooth = smooth
    })
end

function M.set_enable_speaker(enable)
    log_mgr.call_api({}, TAG, 'set_enable_speaker', log_mgr.LOG_LEVEL.LOW, {}, enable)

    UNI.cast(VENDOR_NAME, CAST_SET_ENABLE_SPEAKER, {
        enable = enable
    })
end

function M.enable_local_audio(enable)
    log_mgr.call_api({}, TAG, 'enable_local_audio', log_mgr.LOG_LEVEL.LOW, {}, enable)

    UNI.cast(VENDOR_NAME, CAST_ENABLE_LOCAL_AUDIO, {
        enable = enable
    })
end

-- 静音/取消静音。该方法用于允许/禁止往网络发送本地音频流。
-- 当设置为 True 时, 该方法不禁用麦克风，因此不影响正在进行的录制。
function M.mute_local(mute)
    log_mgr.call_api({}, TAG, 'mute_local', log_mgr.LOG_LEVEL.LOW, {}, mute)

    UNI.cast(VENDOR_NAME, CAST_MUTE_LOCAL, {mute = mute})
end

function M.mute_remote(uid, mute, channel_id)
    log_mgr.call_api({}, TAG, 'mute_remote', log_mgr.LOG_LEVEL.LOW, {}, uid, mute)

    local voice_user_id
    if channel_id and uid then
        voice_user_id = M.get_cache_voice_user_id_with(channel_id, uid)
    end

    UNI.cast(VENDOR_NAME, CAST_MUTE_REMOTE, {
        mute = mute,
        uid = uid,
        voice_user_id = voice_user_id
    })
end

function M.mute_remote_all(mute)
    log_mgr.call_api({}, TAG, 'mute_remote_all', log_mgr.LOG_LEVEL.LOW, {}, mute)

    UNI.cast(VENDOR_NAME, CAST_MUTE_REMOTE_ALL, {
        mute = mute
    })
end

function M.adjust_record_volume(volume)
    log_mgr.call_api({}, TAG, 'adjust_record_volume', log_mgr.LOG_LEVEL.LOW, {}, volume)

    UNI.cast(VENDOR_NAME, CAST_ADJUST_RECORD_VOLUME, {volume = volume})
end

function M.adjust_playing_volume(volume)
    log_mgr.call_api({}, TAG, 'adjust_playing_volume', log_mgr.LOG_LEVEL.LOW, {}, volume)

    UNI.cast(VENDOR_NAME, CAST_ADJUST_PLAYING_VOLUME, {volume = volume})
end

function M.set_default_to_speaker(default_to_speaker)
    log_mgr.call_api({}, TAG, 'set_default_to_speaker', log_mgr.LOG_LEVEL.LOW, {}, default_to_speaker)

    UNI.cast(VENDOR_NAME, CAST_SET_DEFAULT_AUDIO_ROUTE_TO_SPEAKER,
            {default_to_speaker = default_to_speaker})
end

function M.set_profile_scenario(profile, scenario)
    log_mgr.call_api({}, TAG, 'set_profile_scenario', log_mgr.LOG_LEVEL.LOW, {}, profile, scenario)

    E.LOG.d(TAG, 'set_profile_scenario, profile=' .. tostring(profile) .. ', scenario=' .. tostring(scenario))

    audio_profile = profile
    audio_scenario = scenario
end

function M.set_client_role(role)
    log_mgr.call_api({}, TAG, 'set_client_role', log_mgr.LOG_LEVEL.LOW, {}, role)

    UNI.cast(VENDOR_NAME, CAST_SET_CLIENT_ROLE, {role = role})
end

function M.start_echo_test(interval_in_seconds)
    log_mgr.call_api({}, TAG, 'start_echo_test', log_mgr.LOG_LEVEL.LOW, {}, interval_in_seconds)

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'start_echo_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, CAST_START_ECHO_TEST, {interval_in_seconds = interval_in_seconds})
end

function M.stop_echo_test()
    log_mgr.call_api({}, TAG, 'stop_echo_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'stop_echo_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, CAST_STOP_ECHO_TEST, {})
end

function M.start_lastmile_probe_test(config)
    log_mgr.call_api({}, TAG, 'start_lastmile_probe_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'start_lastmile_probe_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, CAST_START_LASTMILE_PROBE_TEST, config or {})
end

function M.stop_lastmile_probe_test()
    log_mgr.call_api({}, TAG, 'stop_lastmile_probe_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'stop_lastmile_probe_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, CAST_STOP_LASTMILE_PROBE_TEST, {})
end

function M.enable_loopback_recording(enable, device_name)
    log_mgr.call_api({}, TAG, 'enable_loopback_recording', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'enable_loopback_recording不支持移动端')
        return
    end

    if device_name and type(device_name) == 'string' and #device_name > 0 then
        UNI.cast(VENDOR_NAME, 'CAST_ENABLE_LOOPBACK_RECORDING', {enable=enable, device_name=device_name})
    else
        UNI.cast(VENDOR_NAME, 'CAST_ENABLE_LOOPBACK_RECORDING', {enable=enable})
    end
end

function M.set_device(type, device_id)
    log_mgr.call_api({}, TAG, 'set_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'set_device不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_SET_DEVICE', {type=type, device_id=device_id})
end

function M.get_default_device(type)
    log_mgr.call_api({}, TAG, 'get_default_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_default_device不支持移动端')
        return {}
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'CAST_GET_DEFAULT_DEVICE', {type=type})
    if ret then
        return ret.value or {}
    else
        return {}
    end
end

function M.get_device(type, index)
    log_mgr.call_api({}, TAG, 'get_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_device不支持移动端')
        return {}
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_GET_DEVICE', {type=type, index=index})
    if ret then
        return ret.value or {}
    else
        return {}
    end
end

function M.get_count(type)
    log_mgr.call_api({}, TAG, 'get_count', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_count不支持移动端')
        return 0
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_GET_COUNT', {type=type})

    if ret then
        return ret.value or 0
    else
        return 0
    end
end

function M.set_application_volume(type, volume)
    log_mgr.call_api({}, TAG, 'set_application_volume', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'set_application_volume不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_SET_APPLICATION_VOLUME', {type=type, volume=volume})
end

function M.get_application_volume(type)
    log_mgr.call_api({}, TAG, 'get_application_volume', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_application_volume不支持移动端')
        return 0
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_GET_APPLICATION_VOLUME', {type=type})
    if ret then
        return ret.value or 0
    else
        return 0
    end
end

function M.set_application_mute(type, mute)
    log_mgr.call_api({}, TAG, 'set_application_mute', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'set_application_mute不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_SET_APPLICATION_MUTE', {type=type, mute=mute})
end

function M.is_application_mute(type)
    log_mgr.call_api({}, TAG, 'is_application_mute', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'is_application_mute不支持移动端')
        return false
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_IS_APPLICATION_MUTE', {type=type})
    if ret then
        return ret.value or false
    else
        return false
    end
end

function M.enumerate_playback_devices()
    log_mgr.call_api({}, TAG, 'enumerate_playback_devices', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'enumerate_playback_devices不支持移动端')
        return {}
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_ENUMERATE_PLAYBACK_DEVICES', {})
    if ret then
        return ret.value or {}
    else
        return {}
    end
end

function M.enumerate_recording_devices()
    log_mgr.call_api({}, TAG, 'enumerate_recording_devices', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'enumerate_recording_devices不支持移动端')
        return {}
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_ENUMERATE_RECORDING_DEVICES', {})
    if ret then
        return ret.value or {}
    else
        return {}
    end
end

function M.follow_system_playback_device(enable)
    log_mgr.call_api({}, TAG, 'follow_system_playback_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'follow_system_playback_device不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_FOLLOW_SYSTEM_PLAYBACK_DEVICE', {enable=enable})
end

function M.follow_system_recording_device(enable)
    log_mgr.call_api({}, TAG, 'follow_system_recording_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'follow_system_recording_device不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_FOLLOW_SYSTEM_RECORDING_DEVICE', {enable=enable})
end

function M.set_playback_device(device_id)
    log_mgr.call_api({}, TAG, 'set_playback_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'set_playback_device不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_SET_PLAYBACK_DEVICE', {device_id=device_id})
end

function M.get_playback_device()
    log_mgr.call_api({}, TAG, 'get_playback_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_playback_device不支持移动端')
        return ''
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'CAST_GET_PLAYBACK_DEVICE', {})
    if ret then
        return ret.value or ''
    else
        return ''
    end
end

function M.get_playback_device_info()
    log_mgr.call_api({}, TAG, 'get_playback_device_info', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_playback_device_info不支持移动端')
        return {}
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'CAST_GET_PLAYBACK_DEVICE_INFO', {})
    if ret then
        return ret.value or {}
    else
        return {}
    end
end

function M.set_recording_device(device_id)
    log_mgr.call_api({}, TAG, 'set_recording_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'set_recording_device不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_SET_RECORDING_DEVICE', {device_id=device_id})
end

function M.get_recording_device()
    log_mgr.call_api({}, TAG, 'get_recording_device', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_recording_device不支持移动端')
        return ''
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'CAST_GET_RECORDING_DEVICE', {})
    if ret then
        return ret.value or ''
    else
        return ''
    end
end

function M.is_start_echo_test_process()
    log_mgr.call_api({}, TAG, 'is_start_echo_test_process', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'is_start_echo_test_process不支持移动端')
        return  false
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_IS_START_ECHO_TEST_PROCESS', {})
    if ret then
        return ret.value or false
    else
        return false
    end
end

function M.is_start_lastmile_probe_test_process()
    log_mgr.call_api({}, TAG, 'is_start_lastmile_probe_test_process', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'is_start_lastmile_probe_test_process不支持移动端')
        return  false
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_IS_START_LASTMILE_PROBE_TEST_PROCESS', {})
    if ret then
        return ret.value or false
    else
        return false
    end
end

function M.is_start_playback_device_test_process()
    log_mgr.call_api({}, TAG, 'is_start_playback_device_test_process', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'is_start_playback_device_test_process不支持移动端')
        return  false
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_IS_START_PLAYBACK_DEVICE_TEST_PROCESS', {})
    if ret then
        return ret.value or false
    else
        return false
    end
end

function M.is_start_recording_device_test_process()
    log_mgr.call_api({}, TAG, 'is_start_recording_device_test_process', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'is_start_recording_device_test_process不支持移动端')
        return  false
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_IS_START_RECORDING_DEVICE_TEST_PROCESS', {})
    if ret then
        return ret.value or false
    else
        return false
    end
end

function M.is_start_audio_device_loopback_test_process()
    log_mgr.call_api({}, TAG, 'is_start_audio_device_loopback_test_process', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'is_start_audio_device_loopback_test_process不支持移动端')
        return  false
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'SYNC_IS_START_AUDIO_DEVICE_LOOPBACK_TEST_PROCESS', {})
    if ret then
        return ret.value or false
    else
        return false
    end
end

function M.get_recording_device_info()
    log_mgr.call_api({}, TAG, 'get_recording_device_info', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'get_recording_device_info不支持移动端')
        return {}
    end

    local ret = UNI.sync_call(VENDOR_NAME, 'CAST_GET_RECORDING_DEVICE_INFO', {})
    if ret then
        return ret.value or {}
    else
        return {}
    end
end

function M.set_recording_device_volume(volume)
    log_mgr.call_api({}, TAG, 'set_recording_device_volume', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'set_recording_device_volume不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_SET_RECORDING_DEVICE_VOLUME', {volume=volume})
end

function M.start_playback_device_test(test_audio_file_path)
    log_mgr.call_api({}, TAG, 'start_playback_device_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'start_playback_device_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_START_PLAYBACK_DEVICE_TEST', {test_audio_file_path=test_audio_file_path})
end

function M.stop_playback_device_test()
    log_mgr.call_api({}, TAG, 'stop_playback_device_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'stop_playback_device_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_STOP_PLAYBACK_DEVICE_TEST', {})
end

function M.start_recording_device_test(interval)
    log_mgr.call_api({}, TAG, 'start_recording_device_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'start_recording_device_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_START_RECORDING_DEVICE_TEST', {interval=interval})
end

function M.stop_recording_device_test()
    log_mgr.call_api({}, TAG, 'stop_recording_device_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'stop_recording_device_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_STOP_RECORDING_DEVICE_TEST', {})
end

function M.start_audio_device_loopback_test(interval)
    log_mgr.call_api({}, TAG, 'start_audio_device_loopback_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'start_audio_device_loopback_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_START_AUDIO_DEVICE_LOOPBACK_TEST', {interval=interval})
end

function M.stop_audio_device_loopback_test()
    log_mgr.call_api({}, TAG, 'stop_audio_device_loopback_test', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'stop_audio_device_loopback_test不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_STOP_AUDIO_DEVICE_LOOPBACK_TEST', {})
end

function M.renew_token(token)
    log_mgr.call_api({}, TAG, 'renew_token', log_mgr.LOG_LEVEL.LOW, {})

    -- 暂时只有PC端支持该接口
    if _ejoysdk.os() ~= "windows" then
        E.LOG.d(TAG, 'renew_token不支持移动端')
        return
    end

    UNI.cast(VENDOR_NAME, 'CAST_RENEW_TOKEN', {token=token})
end

function M.renew_token_with_params(params)
    M.renew_token(params.token)
end

local is_support_renewtoken
-- renewtoken等移动端未有实现，暂先开启windows
function M.is_support_token_refresh()

    if is_support_renewtoken == nil then
        if _ejoysdk.os() == "windows" then
            is_support_renewtoken = true
        else
            is_support_renewtoken = false
        end
    end

    return is_support_renewtoken
end

local voice_user_id_maps = {}
local player_id_maps = {}
function M.update_id_maps(t_channel_id, t_player_id, t_voice_user_id)
    if not t_channel_id or #t_channel_id == 0 then
        return
    end

    if not t_player_id or #t_player_id == 0 then
        return
    end

    if not t_voice_user_id then
        return
    end

    if not voice_user_id_maps[t_channel_id] then
        voice_user_id_maps[t_channel_id] = {}
    end

    voice_user_id_maps[t_channel_id][t_player_id] = t_voice_user_id
    player_id_maps[t_voice_user_id] = t_player_id
end

function M.get_cache_voice_user_id_with(t_channel_id, t_player_id)

    if voice_user_id_maps[t_channel_id] and voice_user_id_maps[t_channel_id][t_player_id] then
        return voice_user_id_maps[t_channel_id][t_player_id]
    end

    local target_voice_user_id
    local group_info = cache.get_group(t_channel_id)
    
    if group_info and group_info.voice_channel_users then

        if voice_user_id_maps[t_channel_id] == nil then
            voice_user_id_maps[t_channel_id] = {}
        end

        for _, user in pairs(group_info.voice_channel_users) do
            if user.user_id then
                voice_user_id_maps[t_channel_id][user.user_id] = user.voice_user_id
            end

            if user and user.user_id == t_player_id then
                target_voice_user_id = user.voice_user_id
            end            
        end
    end

    return target_voice_user_id
end

function M.get_cache_player_id(t_voice_user_id)

    t_voice_user_id = tostring(t_voice_user_id)

    if player_id_maps[t_voice_user_id] then
        return player_id_maps[t_voice_user_id]
    end

    local target_id
    if last_join_suc_channel then
        local group_info = cache.get_group(last_join_suc_channel)
        if group_info and group_info.voice_channel_users then
            -- E.log(group_info.voice_channel_users)
            for _, user in pairs(group_info.voice_channel_users) do
                if user.voice_user_id then
                    player_id_maps[user.voice_user_id] = user.user_id
                end
    
                if user and user.voice_user_id == t_voice_user_id then
                    target_id = user.user_id
                end            
            end
        end
    end

    return target_id
end

function M.set_last_join_suc_channel(new_channel)
    last_join_suc_channel = new_channel
end

local function replace_voice_user_id_to_player_id(body)
    -- 需要换回player_id对外
    local found_uid = true
    if body and body.voice_user_id and body.uid and body.uid == "" then
        found_uid = false
        local re_uid = M.get_cache_player_id(body.voice_user_id)
        if re_uid then
            body.uid = re_uid
            found_uid = true
        end
    end

    return found_uid
end

-- 延迟的callback需要放在这里
function M.execute_delay_uid_callbacks()
    if delay_callback_list and next(delay_callback_list) ~= nil then
        local new_list = {}
        for _, callback_info in ipairs(delay_callback_list) do
            if replace_voice_user_id_to_player_id(callback_info.body) then
                local body = callback_info.body
                E.LOG.d(TAG, 'delay_uid_callbacks handler_name=' .. tostring(callback_info.handler_name))
                if callback_info.handler_name == voice_event.ON_USER_JOINED then
                    callback(voice_event.ON_USER_JOINED, body.uid)
                elseif callback_info.handler_name == voice_event.ON_USER_MUTED then
                    callback(voice_event.ON_USER_MUTED, body.uid, body.muted)
                end
            else
                table.insert(new_list, callback_info)
            end
        end
        delay_callback_list = new_list
    end
end

local HANDLERS = {}

HANDLERS[EVT_USER_JOINED] = function(body)
    local found_uid = replace_voice_user_id_to_player_id(body)
    
    if found_uid then
        callback(voice_event.ON_USER_JOINED, body.uid)
    else
        -- 需要确保delay_body_callback的时候抛出的key值是一致的
        add_delay_uid_callback(voice_event.ON_USER_JOINED, body)
    end
end

HANDLERS[EVT_USER_OFFLINE] = function(body)
    replace_voice_user_id_to_player_id(body)
    if last_join_suc_channel and body and body.uid then
        --E.LOG.debug(TAG, 'EVT_USER_OFFLINE, last_join_suc_channel=' .. last_join_suc_channel .. ', uid=' .. body.uid)
        cache.voice_channel_user_change_update_group(last_join_suc_channel, {[body.uid]=true}, nil)
    end
    callback(voice_event.ON_USER_LEAVE, body.uid, body.reason)
end

HANDLERS[EVT_USER_MUTED] = function(body)
    local found_uid = replace_voice_user_id_to_player_id(body)
    if found_uid then
        callback(voice_event.ON_USER_MUTED, body.uid, body.muted)
    else
        add_delay_uid_callback(voice_event.ON_USER_MUTED, body)
    end
end

HANDLERS[EVT_JOIN_CHANNEL_SUCC] = function(body)
    replace_voice_user_id_to_player_id(body)
    is_joining_channel = false
    --_ejoysdk.log('agora on join channel succ: ' .. body.channel or '')
    --E.log(body)
    last_join_suc_uid = body.uid
    last_join_suc_channel = body.channel
    callback(voice_event.ON_JOIN_CHANNEL_SUCC, body.channel, body.uid, body.voice_user_id)
end

-- android特有的实现，不会引起error17的错误
HANDLERS[EVT_JOIN_CHANNEL_FAIL] = function(body)
    is_joining_channel = false
    --_ejoysdk.log('agora on join channel fail')
    callback(voice_event.ON_JOIN_CHANNEL_FAIL, body.code, body.message)
end

HANDLERS[EVT_LEAVE_CHANNEL_SUCC] = function()
    last_join_suc_uid = nil
    local value = last_join_suc_channel
    last_join_suc_channel = nil
    callback(voice_event.ON_LEAVE_CHANNEL_SUCC, value) -- 如果是加入前的退出，不做返回
    -- 离开后清理频道延迟的回调
    delay_callback_list = {}
end

HANDLERS[EVT_LEAVE_CHANNEL_FAIL] = function(body)
    is_leaveing_channel = false
    callback(voice_event.ON_LEAVE_CHANNEL_FAIL, body.code, body.message)
end

HANDLERS[EVT_REJOIN_CHANNEL_SUCC] = function(body)
    replace_voice_user_id_to_player_id(body)
    last_join_suc_uid = body.uid
    last_join_suc_channel = body.channel
    callback(voice_event.ON_REOIN_CHANNEL_SUCC, body.channel, body.uid)
end

HANDLERS[EVT_ERROR] = function(body)
    local error_code = body.code or -10000
    local error_msg = body.message or ''

    E.LOG.e(TAG, 'EVT_ERROR, error_code=' .. tostring(error_code) .. ', error_msg=' .. error_msg)

    -- 声网的错误码：https://docs.agora.io/cn/Interactive%20Broadcast/error_rtc?platform=Android
    if is_joining_channel then
        if error_code == 18 then -- leave channel 报错回调，声网 SDK 会回调 18
            return
        elseif error_code == 17 then -- code = 17 表示 join channel 失败已经在频道中了，就不需要改变状态了
            is_joining_channel = false
            E.LOG.debug(TAG, 'agora already in channel')
            if last_join_suc_channel and last_join_suc_uid then
                callback(voice_event.ON_JOIN_CHANNEL_SUCC, last_join_suc_channel, last_join_suc_uid)
            else
                callback(voice_event.ON_JOIN_CHANNEL_FAIL, error_code, error_msg .. ' (last channel status error, call leave channel first)')
            end

            return
        end
        is_joining_channel = false
        callback(voice_event.ON_JOIN_CHANNEL_FAIL, error_code, error_msg)
    elseif is_leaveing_channel then
        if error_code == 18 then -- 错误码18，表示已离开，或者不在频道，为了状态机的正确性，故返回离开频道成功
            is_leaveing_channel = false
            callback(voice_event.ON_LEAVE_CHANNEL_SUCC, nil)
            return
        end

        is_leaveing_channel = false
        callback(voice_event.ON_LEAVE_CHANNEL_FAIL, error_code, error_msg)
    else
        callback(voice_event.ON_ERROR, error_code, error_msg)
    end
end

HANDLERS[EVT_CONNECTION_INTERRUPT] = function()
    callback(voice_event.ON_CONNECTION_INTERRUPT)
end

HANDLERS[EVT_CONNECTION_BANNED] = function()
    callback(voice_event.ON_CONNECTION_BANNED)
end

HANDLERS[EVT_CONNECTION_LOST] = function()
    callback(voice_event.ON_CONNECTION_LOST)
end

HANDLERS[EVT_AUDIO_VOLUME_INDICATION] = function(body)
    if body and body.speakers then
        for _, user_info in pairs(body.speakers) do
            -- 0 是自己的声音
            if user_info and user_info.uid ~= "0" then
                replace_voice_user_id_to_player_id(user_info)
            end
        end
    end
    callback(voice_event.ON_VOLUME_INDICATION, body.speakers, body.total_volume)
end

HANDLERS[EVT_LASTMILE_QUALITY] = function(body)
    callback(voice_event.ON_LASTMILE_QUALITY, body.quality)
end

HANDLERS[EVT_LASTMILE_PROBE_RESULT] = function(body)
    callback(voice_event.ON_LASTMILE_PROBE_RESULT, body)
end

HANDLERS[EVT_AUDIO_QUALITY] = function(body)
    replace_voice_user_id_to_player_id(body)
    callback(voice_event.ON_AUDIO_QUALITY, body)
end

HANDLERS[EVT_CONNECTION_STATE_CHANGED] = function(body)
    callback(voice_event.ON_CONNECTION_STATE_CHANGED, body.state, body.reason, last_join_suc_channel)
end

HANDLERS[EVT_REQUEST_TOKEN] = function()
    callback(voice_event.ON_REQUEST_TOKEN)
end

HANDLERS[EVT_TOKEN_PRIVILEGE_WILL_EXPIRE] = function(body)
    callback(voice_event.ON_TOKEN_PRIVILEGE_WILL_EXPIRE, body.token)
end

HANDLERS[EVT_LOCAL_AUDIO_STATE_CHANGED] = function(body)
    -- 麦克风采集关闭或重新开启后，会收到回调 onLocalAudioStateChanged， 并报告state=LOCAL_AUDIO_STREAM_STATE_STOPPED(0) 或 state=LOCAL_AUDIO_STREAM_STATE_RECORDING(1)。
    -- state枚举值：https://docportal.shengwang.cn/cn/live-streaming-premium-legacy/API%20Reference/cpp/namespaceagora_1_1rtc.html#a19311f858629420654fcc0da9d043332
    -- error枚举值：https://docportal.shengwang.cn/cn/live-streaming-premium-legacy/API%20Reference/cpp/namespaceagora_1_1rtc.html#a3929991eea3a522dcbf6ac078810045e
    callback(voice_event.ON_LOCAL_AUDIO_STATE_CHANGED, body.state, body.error)
end

HANDLERS[EVT_AUDIO_DEVICE_STATE_CHANGED] = function(body)
   callback(voice_event.ON_AUDIO_DEVICE_STATE_CHANGED, body.device_id, body.device_type, body.device_state)
end

HANDLERS[EVT_RTC_STATS] = function(body)
    callback(voice_event.ON_RTC_STATS, body)
end

if E.Sysinfo.os() == 'windows' then
    _ejoysdk.register_cb(
            'AGORA',
            function(_cbid, js_str, _chunk)
                local value = JSON.safe_decode(js_str)
                if not agora_listener then
                    return
                end
                if not value or not value.type then
                    return
                end

                local handler = HANDLERS[value.type]
                if handler then
                    handler(value.body)
                end
            end
    )
else
    UNI.register_event_cb('AGORA', function(type, body)
        log_mgr.debug({}, TAG, 'receive_agora_event', 'chat_receive_agora_event', {type=type, body=body}, {})

        if not agora_listener then
            return
        end
        local handler = HANDLERS[type]
        if handler then
            handler(body)
        end
    end)
end

return M