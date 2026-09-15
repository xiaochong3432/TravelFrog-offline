local EVENT = require 'ejoysdk_lua.chat.ejoysdk_voice_event'
local ET = require 'ejoysdk_lua.ejoysdk_topic'
local QL = require "ejoysdk_lua.ejoysdk_qualitylog"
local E = require 'ejoysdk_lua.ejoysdk'
local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
local utils = require 'ejoysdk_lua.ejoysdk_utils'
local chat_cache = require 'ejoysdk_lua.chat.ejoysdk_chat_cache'
local voice_topic = require 'ejoysdk_lua.chat.ejoysdk_voice_topic'
local _chat_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local EM = require "ejoysdk_lua.ejoysdk_module"
--local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local AGORA_JF_UPLOAD_NOW = false

local TAG = EM.MODULE.CHAT .. 'voice'

local fsm = utils.fsm
local STATES = {}
STATES.NOT_JOIN = 'not_join'
STATES.JOINING = 'joining'
STATES.JOINED = 'joined'
STATES.NOT_READY = 'not_ready'
STATES.LEAVING = 'leaving'

local EVENTS = {}
EVENTS.JOIN = 'join'
EVENTS.JOIN_SUCC = 'join_succ'
EVENTS.JOIN_FAIL = 'join_fail'
EVENTS.LEAVE = 'leave'
EVENTS.LEAVE_SUCC = 'leave_succ'
EVENTS.LEAVE_FAIL = 'leave_fail'
EVENTS.INIT = 'init'

-- VOICE_STATUS是用于把实时语音状态同步给聊天服务的, 暂时只需同步这2个状态，joined\not_join
local VOICE_STATUS = {}
VOICE_STATUS.JOINED = 'joined'
VOICE_STATUS.NOT_JOIN = 'not_join'

-- key是player_id，value是true/false
local mute_remote_cache_by_user  = {}
local EJVOICE_MUTE_REMOTE_CACHE = E.LazyKeyStore:New("EJVOICE_Mute_Remote_Cache", true, true, false)

local channel_voice_date_map = {}

local M = {}

M.STATES = STATES
M.VOICE_STATUS = VOICE_STATUS
M.CHANNEL_INFO_DESC_MAX_LENGTH = 200

local voice_vendor = nil
local join_timestamp = 0

M.auto_join_channel = false -- 默认改成不自动进入频道，因为自动进入频道，有很多业务问题
M.auto_leave_channel = true

local channel_params = {}

local cur_channel = nil
local cur_voice_user_id = nil

local mute_local_value = false
local voice_status = VOICE_STATUS.NOT_JOIN

local voice_listener = nil
local state_before_leave = nil
local open_mic_start_time = 0

local function callback(handler_name, ...)
    if voice_listener then
        local handler = voice_listener[handler_name]
        if handler then
            handler(...)
        end
    end
    ET.publish('voice_' .. handler_name, ...)
end

local fsm_callbacks = {}

-- NOT READY 状态
fsm_callbacks['on' .. EVENTS.INIT] = function(self, _from, ...)
    return fsm.SYNC, STATES.NOT_JOIN
end

fsm_callbacks['on' .. EVENTS.JOIN] = function(self, _from, ...)

    if voice_vendor then
        local channel_id, player_id, channel_param = ...
        voice_vendor.join_channel(channel_id, player_id, channel_param)
    end
    return fsm.SYNC, STATES.JOINING
end

fsm_callbacks['on' .. EVENTS.JOIN_SUCC] = function(self, _from, ...)
    return fsm.SYNC, STATES.JOINED, 'join_succ', ...
end

fsm_callbacks['on' .. EVENTS.JOIN_FAIL] = function(self, _from, ...)
    return fsm.SYNC, STATES.NOT_JOIN, 'join_fail', ...
end

fsm_callbacks['on' .. EVENTS.LEAVE_SUCC] = function(self, _from, ...)
    return fsm.SYNC, STATES.NOT_JOIN, 'leave_succ', ...
end

fsm_callbacks['on' .. EVENTS.LEAVE_FAIL] = function(self, _from, ...)
    assert(state_before_leave ~= nil, 'state_before_leave is nil')
    return fsm.SYNC, state_before_leave, 'leave_fail', ...
end

fsm_callbacks['on' .. EVENTS.LEAVE] = function(self, from, ...)
    local channel_id = ...
    if from == STATES.JOINING then
        state_before_leave = from
        --_ejoysdk.log('invoke agora cancel join channel, leave')
        voice_vendor.leave_channel()
        return fsm.SYNC, STATES.LEAVING, 'cancel'
    elseif from == STATES.JOINED then
        if channel_id == cur_channel then
            state_before_leave = from
            --_ejoysdk.log('invoke agora leave channel')
            voice_vendor.leave_channel()
            return fsm.SYNC, STATES.LEAVING, 'leave'
        end
    end
end

fsm_callbacks['onenter' .. STATES.NOT_JOIN] = function(self, _from, ...)
    local type = ...
    --_ejoysdk.log('onenter states not join, type: ' .. tostring(type))
    if type == 'leave_succ' then
        local _, channel_id = ...
        E.LOG.d(TAG, 'tell cp EVENT.ON_LEAVE_CHANNEL_SUCC, channel_id=' .. tostring(channel_id))

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        local agora_vendor = require 'ejoysdk_lua.vendors.agora'

        callback(EVENT.ON_LEAVE_CHANNEL_SUCC, channel_id)

        if open_mic_start_time > 0 then
            -- 离开频道时，上报开麦时长
            local self_player_id = EG.player_info() and EG.player_info().player_id
            local self_player_name = EG.player_info() and EG.player_info().player_name
            local cached_group = chat_cache.get_group(cur_channel) or {}
            local group_type = cached_group.info and cached_group.info.type
            if os.time() > open_mic_start_time then
                local duration = os.time() - open_mic_start_time

                local jf_params = {duration=duration}
                if self_player_id and type(self_player_id) == 'string' and #self_player_id > 0 then
                    jf_params.roleId = self_player_id
                end
                if self_player_name and type(self_player_name) == 'string' and #self_player_name > 0 and not agora_vendor.is_forbid_upload_role_name_from_cc() then
                    jf_params.roleName = self_player_name
                end
                jf_params.type = group_type or ''
                jf_params.result = duration
                jf_params.is_upload_now = AGORA_JF_UPLOAD_NOW

                ESTAT.stat_bizid('duration.user.voice.online', '0', '0', jf_params)
            end

            open_mic_start_time = 0
        end
    elseif type == 'join_fail' then
        local _, code, message = ...
        E.LOG.d(TAG, 'tell cp EVENT.ON_JOIN_CHANNEL_FAIL, code=' .. tostring(code) .. ', message=' .. tostring(message))

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        callback(EVENT.ON_JOIN_CHANNEL_FAIL, code, message)
    --elseif type == 'cancel' then
        -- pass
    end
end

function M.update_mute_remote_config(channel_id)
    if not channel_id then
        return
    end

    if not voice_vendor then
        return 
    end

    if mute_remote_cache_by_user and type(mute_remote_cache_by_user) == 'table' then
        for player_id, m_value in pairs(mute_remote_cache_by_user) do
            local p_is_mute = m_value or false
            voice_vendor.mute_remote(player_id, p_is_mute, channel_id)
        end
    end
end

-- JOINED 状态
fsm_callbacks['onenter' .. STATES.JOINED] = function(self, _from, ...)
    local type = ...
    if type == 'join_succ' then
        local _, channel_id, uid = ...
        E.LOG.d(TAG, 'tell cp EVENT.ON_JOIN_CHANNEL_SUCC, channel_id=' .. tostring(channel_id) .. ', uid=' .. tostring(uid))

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        M.update_mute_remote_config(channel_id)

        callback(EVENT.ON_JOIN_CHANNEL_SUCC, channel_id, uid)
    elseif type == 'leave_fail' then
        local _, code, msg = ...
        E.LOG.d(TAG, 'tell cp EVENT.ON_LEAVE_CHANNEL_FAIL, code=' .. tostring(code) .. ', msg=' .. tostring(msg))

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        callback(EVENT.ON_LEAVE_CHANNEL_FAIL, code, msg)
    elseif type == 'rejoin_succ' then
	    local _, channel_id, uid = ...
        E.LOG.d(TAG, 'tell cp EVENT.ON_REJOIN_CHANNEL_SUCC, channel_id=' .. tostring(channel_id) .. ', uid=' .. tostring(uid))

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        callback(EVENT.ON_REOIN_CHANNEL_SUCC, channel_id, uid)
    end
    return fsm.ASYNC
end

-- onstagechange
fsm_callbacks['onstatechange'] = function(self, from, to, ...)
    ET.publish('voice_onstatechange', from, to)
end

local voice_fsm = fsm.create({
    initial = STATES.NOT_READY,
    events = {
        { name = EVENTS.JOIN, from = STATES.NOT_JOIN },
        { name = EVENTS.JOIN_SUCC, from = STATES.JOINING },
        { name = EVENTS.JOIN_FAIL, from = STATES.JOINING },
        { name = EVENTS.LEAVE, from = STATES.JOINING }, -- cancel join
        { name = EVENTS.LEAVE, from = STATES.JOINED },
        { name = EVENTS.LEAVE_SUCC, from = STATES.LEAVING },
        { name = EVENTS.LEAVE_FAIL, from = STATES.LEAVING },
        { name = EVENTS.INIT, from = STATES.NOT_READY }
    },
    callbacks = fsm_callbacks
})

function M.init()
    --chat_log.call_api(chat_log_util.header(), TAG, 'init', chat_log.LOG_LEVEL.LOW, {})

    if mute_remote_cache_by_user and #mute_remote_cache_by_user == 0 then
        local current_player_mute_list = (EJVOICE_MUTE_REMOTE_CACHE and EJVOICE_MUTE_REMOTE_CACHE:get()) or {}
        if EG.player_info() then
            mute_remote_cache_by_user = current_player_mute_list[EG.player_info().player_id] or {}
        end
    end

    E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.INIT')
    voice_fsm:add_event(EVENTS.INIT)
end

function M.uninit()
    --chat_log.call_api(chat_log_util.header(), TAG, 'uninit', chat_log.LOG_LEVEL.LOW, {})

    if voice_fsm.current == STATES.JOINED then
        E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.LEAVE')
        voice_fsm:add_event(EVENTS.LEAVE, cur_channel)
    else
        voice_fsm:reset()
    end
end

function M.get_state()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_state', chat_log.LOG_LEVEL.LOW, {})

    local res = voice_fsm.current

    --chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_status', chat_log.LOG_LEVEL.LOW, {}, res)

    return res
end

function M.get_curr_channel_id()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_curr_channel_id', chat_log.LOG_LEVEL.LOW, {})

    local res = cur_channel

    --chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_curr_channel_id', chat_log.LOG_LEVEL.LOW, {}, res)

    return res
end

function M.get_curr_voice_user_id()
    return cur_voice_user_id
end

function M.get_mute_local_value()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_mute_local_value', chat_log.LOG_LEVEL.LOW, {})

    local res = mute_local_value

    --chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_mute_local_value', chat_log.LOG_LEVEL.LOW, {}, res)

    return res
end

-- 服务端同步用的voice_status
function M.get_voice_status()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_voice_status', chat_log.LOG_LEVEL.LOW, {})

    local res = voice_status

    --chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_voice_status', chat_log.LOG_LEVEL.LOW, {}, res)

    return res
end

function M.voice_channel_user_change(channel_id, removes_map, updates_map)
    removes_map = removes_map or {}
    updates_map = updates_map or {}

    --chat_log.call_api(chat_log_util.header(), TAG, 'voice_channel_user_change', chat_log.LOG_LEVEL.LOW, {}, channel_id, removes_map, updates_map)

    E.LOG.d(TAG, 'voice_channel_user_change start, channel_id=' .. tostring(channel_id) .. ', cur_channel=' .. tostring(cur_channel))

    -- 如果channel_id不是当前连线的channel，就直接return
    if channel_id ~= cur_channel then

        E.LOG.d(TAG, 'voice_channel_user_change, channel_id not same')
        return
    end

    if not EG.player_info() then

        E.LOG.d(TAG, 'voice_channel_user_change, not have player_info')

        return
    end

    -- 检测自己，有没有被踢出
    if EG.player_info().player_id and removes_map[EG.player_info().player_id] then

        E.LOG.d(TAG, 'voice_channel_user_change, self in removes_map, need leave_channel')

        M.leave_channel(channel_id)
        return
    end

    for uid, user in pairs(updates_map) do
        if uid == EG.player_info().player_id then
            M.mute_local_from_server_sync(user.mute)
        else
            M._mute_remote_for_server_sync(uid, user.management_mute or (mute_remote_cache_by_user[uid] or false))
        end
    end

    if voice_vendor and voice_vendor.execute_delay_uid_callbacks then
        voice_vendor.execute_delay_uid_callbacks()
    end
end

-- 更新频道内音频记录信息
--[[
    最后一个用户退出时，voice_channel.data 会为空
    eg:
    "voice_channel": {
        "type": "agora",
        "data": {
            "sid": "513459df124076a5ec579eb20a8d6ca2"
        }
    }
]]
function M.voice_channel_info_update(channel_id, voice_channel)

    local voice_data = voice_channel and voice_channel.data
    if channel_id and voice_data then
        channel_voice_date_map[channel_id] = voice_data
    end
end

-- 获取频道内音频记录信息
function M.get_channel_voice_info(channel_id)
    if channel_id then
        return channel_voice_date_map[channel_id]
    end
    return nil
end

function M.get_history_channel_voice_infos()
    return utils.deepcopy(channel_voice_date_map)
end

-- 举报频道内音频记录
--[[
    channel_id: string, 频道id
    report_type_id: string, 后台的举报类型; [场景类型]拼接[举报类型id] 如audio_agora, audio是固定的场景类型，agora是场景id
    report_desc: string, 举报描述
    player_id: string, 举报的player_id
    extend_data: table, 拓展的透传参数，可以传{}
    cb: function, cb(true), cb(false, code, message)
]]
function M.report(channel_id, report_type_id, report_desc, player_id, extend_data, cb)
    
    if not channel_id then
        cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER, 'channel_id is nil')
        return
    end

    local voice_data = M.get_channel_voice_info(channel_id)
    if not voice_data then
        E.LOG.warn(TAG, 'current voice_data is not valid')
        voice_data = {}
        -- cb(false, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_NO_CHANNEL, 'current channel_id is not valid')
        -- return
    end

    local contents = {}
    extend_data = extend_data or {}
    -- 进入频道时间 join_time、举报时间report_time、举报经过的间隔report_interval
    extend_data.join_timestamp = join_timestamp
    -- extend_data.report_timestamp = E.time()
    local report_timestamp = E.time()
    extend_data.report_interval = report_timestamp - join_timestamp
    extend_data.join_time = os.date("%Y-%m-%d %H:%M:%S", extend_data.join_timestamp)
    extend_data.report_time = os.date("%Y-%m-%d %H:%M:%S", report_timestamp)
    local voice_user_id = "0"
    local group_info = M.get_voice_group_info(channel_id)
    
    if group_info and group_info.voice_channel_users then
        for _, user in pairs(group_info.voice_channel_users) do
            if user and user.user_id == player_id then
                voice_user_id = user.voice_user_id
                break
            end
        end
    end

    -- E.log(group_info)
    -- E.log(voice_user_id)
    
    contents[1] = { content_type = "audio_raw", audio_raw = { channel_name = channel_id, sid = voice_data.sid, voice_user_id = tostring(voice_user_id) }, extend_data = extend_data }
    -- E.log(contents)
    local suspect_info = { player_id = player_id }

    M.report_to_platform(report_type_id, report_desc, nil, suspect_info, contents, cb)
end

-- 举报频道内音频记录
--[[
    获取后台配置的举报类型
    cb: function, cb(true, report_types), cb(false, code, message)
        report_types: table - array
            id: 举报类型id
            name: 举报类型名
            priority: 优先级
]]
function M.get_report_types(cb)
    local RAPI = require 'ejoysdk_lua.server_api.ejoysdk_report_mailbox'
    RAPI.get_report_types(cb)
end

function M.report_to_platform(report_type_id, report_desc, scene, suspect_info, contents, cb)
    local RAPI = require 'ejoysdk_lua.server_api.ejoysdk_report_mailbox'
    RAPI.report(report_type_id, report_desc, scene, suspect_info, contents, cb)
end

local function update_voice_mute(group_id)
    if not cur_channel then
        return
    end

    if not EG.player_info() then
       return
    end

    local group = chat_cache.get_group(group_id)
    if group and group.voice_channel_users then
        for _, user in pairs(group.voice_channel_users) do
            if user.user_id == EG.player_info().player_id then
                M.mute_local_from_server_sync(user.mute)
            else
                M._mute_remote_for_server_sync(user.user_id, user.management_mute or (mute_remote_cache_by_user[user.user_id] or false))
            end
        end
    end
end

function M.update_voice_mute(group_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'update_voice_mute', chat_log.LOG_LEVEL.LOW, {}, group_id)

    update_voice_mute(group_id)
end

-- 该方法只是发通知到Chat那边，chat发起RPC请求到服务器，把本地的麦克风状态同步到服务器，是同步告知的作用
local function voice_channel_status_update(group_id, _voice_status, _mute_local_value, voice_user_id, channel_info)
    E.LOG.debug(TAG, 'voice_channel_status_update, group_id='.. tostring(group_id) .. ', voice_status=' .. tostring(_voice_status) .. ', _mute_local_value=' .. tostring(_mute_local_value))
    if group_id then
        ET.publish(voice_topic.VOICE_CHANNEL_STATUS_UPDATE, group_id, _voice_status, _mute_local_value, voice_user_id, channel_info)
    end
end

-- 该方法不仅具备同步状态到服务器的作用，服务器还会做权限校验，校验不过callback是fail
local function async_voice_channel_status_update(group_id, _voice_status, _mute_local_value, voice_user_id, channel_info, cb)
    E.LOG.debug(TAG, 'async_voice_channel_status_update, group_id='.. tostring(group_id) .. ', voice_status=' .. tostring(_voice_status) .. ', _mute_local_value=' .. tostring(_mute_local_value))
    if group_id then
        local EC = require 'ejoysdk_lua.chat.ejoysdk_chat'
        -- set_voice_channel_status(group_id, status, mute_local_value, voice_user_id, channel_info, cb)
        EC.set_voice_channel_status(group_id, _voice_status, _mute_local_value, voice_user_id, channel_info, cb)
    end
end

local function inner_renew_token_with_params(renew_channel_id)
    if voice_vendor and voice_vendor.is_support_token_refresh() and renew_channel_id then
        local voice_version = M.get_agora_token_version()
        M.get_voice_token(renew_channel_id, voice_version, function (succ, ...)
            if succ then
                local ret_info = ...
                if ret_info and type(ret_info) == 'table' and ret_info.token and ret_info.uid then
                    voice_vendor.renew_token_with_params({ token = ret_info.token })
                else
                    -- 服务端是旧的，走原逻辑，比如无uid字段
                    local channel_param = channel_params[renew_channel_id]
                    if channel_param then
                        voice_vendor.renew_token_with_params(channel_param)
                    end
                end
            else
                E.LOG.d(TAG, 'renew token: get_voice_token fail')
            end
        end)
    end
end

local voice_listener_wrapper = {
    [EVENT.ON_JOIN_CHANNEL_SUCC] = function(channel_id, uid, voice_user_id)
        QL.commit_event("sdk.ejoy_voice_join_succ",{})

        cur_channel = channel_id
        cur_voice_user_id = voice_user_id
        voice_status = M.VOICE_STATUS.JOINED
        join_timestamp=E.time()

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        local channel_info
        local channel_param = channel_params[channel_id]
        if channel_param then
            channel_info = channel_param and channel_param.channel_info
        end

        -- 同步到聊天服务器
        update_voice_mute(channel_id)

        E.LOG.d(TAG, 'voice_channel_status_update, mute=' .. tostring(mute_local_value) .. ', on join channel')
        voice_channel_status_update(channel_id, M.VOICE_STATUS.JOINED, mute_local_value, voice_user_id, channel_info)

        -- 更新状态机，内部会给游戏回调
        E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.JOIN_SUCC')
        voice_fsm:add_event(EVENTS.JOIN_SUCC, channel_id, uid)

        local agora_vendor = require 'ejoysdk_lua.vendors.agora'

        -- 进入语音频道的打点
        local self_player_id = EG.player_info() and EG.player_info().player_id
        local self_player_name = EG.player_info() and EG.player_info().player_name
        local cached_group = chat_cache.get_group(channel_id) or {}
        local group_type = cached_group.info and cached_group.info.type

        local jf_params = {}
        if self_player_id and type(self_player_id) == 'string' and #self_player_id > 0 then
            jf_params.roleId = self_player_id
        end
        if self_player_name and type(self_player_name) == 'string' and #self_player_name > 0 and not agora_vendor.is_forbid_upload_role_name_from_cc() then
            jf_params.roleName = self_player_name
        end
        jf_params.type = group_type or ''
        jf_params.is_upload_now = AGORA_JF_UPLOAD_NOW

        ESTAT.stat_bizid('voice.user.online', '0', '0', jf_params)
    end,
    [EVENT.ON_REOIN_CHANNEL_SUCC] = function(channel_id,uid)
        QL.commit_event("sdk.ejoy_voice_rejoin_succ",{})

        join_timestamp=E.time()

        --直接跳转到具体的状态,因为重连触发后当前的状态不稳定
        E.LOG.d(TAG, 'voice_fsm.transition -> STATES.JOINED')
	    -- bugfix: 第3个参数，需要补上rejoin_succ
        voice_fsm:transition(voice_fsm.current, STATES.JOINED, 'rejoin_succ', channel_id,uid)

        -- 这个回调，是声网断连后，自动重连成功，在EVENT.ON_JOIN_CHANNEL_SUCC已经同步过了，就没必要再重复到聊天服务器了
        --update_voice_mute(channel_id)
        --voice_status = M.VOICE_STATUS.JOINED
        --voice_channel_status_update(channel_id, M.VOICE_STATUS.JOINED, mute_local_value)
    end,
    [EVENT.ON_CONNECTION_INTERRUPT] = function()
        -- 断连服务器4s，声网会触发该回调，声网会开启自动重连，重连成功，会通过REOIN_CHANNEL_SUCC告诉客户端，重新加入频道成功。
        QL.commit_event("sdk.ejoy_voice_interrupt",{stime=(E.time()-join_timestamp)})

        -- 声网会自动重连的，所以没必要这个时候就同步到聊天服务器
        --voice_status = M.VOICE_STATUS.NOT_JOIN
        --voice_channel_status_update(cur_channel, M.VOICE_STATUS.NOT_JOIN, mute_local_value)
    end,
    [EVENT.ON_CONNECTION_LOST] = function()
        -- 只要 10 秒和服务器无法连接就会触发该回调。如果 SDK 在断开连接后，20 分钟内还是没能重新加入频道，SDK 会停止尝试重连。
        QL.commit_event("sdk.ejoy_voice_lost",{stime=(E.time()-join_timestamp)})

        -- 声网在20分钟内会自动重连的，所以没必要这个时候就同步到聊天服务器
        --voice_status = M.VOICE_STATUS.NOT_JOIN
        --voice_channel_status_update(cur_channel, M.VOICE_STATUS.NOT_JOIN, mute_local_value)
    end,
    [EVENT.ON_JOIN_CHANNEL_FAIL] = function(code, message)
        QL.commit_event("sdk.ejoy_voice_join_fail",{})
        _ejoysdk.log('lua EVENT ON JOIN CHANNEL FAIL')

        E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.JOIN_FAIL')
        voice_fsm:add_event(EVENTS.JOIN_FAIL, code, message)

        --voice_status = M.VOICE_STATUS.NOT_JOIN
        --voice_channel_status_update(cur_channel, M.VOICE_STATUS.NOT_JOIN, mute_local_value)
    end,
    [EVENT.ON_LEAVE_CHANNEL_SUCC] = function(channel_id)

        QL.commit_event("sdk.ejoy_voice_leave",{stime=(E.time()-join_timestamp)})
        _ejoysdk.log('lua EVENT ON LEAVE CHANNEL SUCC, channel_id =' .. tostring(channel_id))

        cur_channel = nil
        cur_voice_user_id = nil
        voice_status = M.VOICE_STATUS.NOT_JOIN

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        -- 同步到聊天服务器
        voice_channel_status_update(channel_id, M.VOICE_STATUS.NOT_JOIN, mute_local_value, nil)

        E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.LEAVE_SUCC')
        -- 变更状态机，内部会给游戏回调
        voice_fsm:add_event(EVENTS.LEAVE_SUCC, channel_id)
    end,
    [EVENT.ON_LEAVE_CHANNEL_FAIL] = function(code, message)
        _ejoysdk.log('lua EVENT ON LEAVE CHANNEL FAIL')

        E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.LEAVE_FAIL')
        voice_fsm:add_event(EVENTS.LEAVE_FAIL, code, message)
    end,
    [EVENT.ON_CONNECTION_STATE_CHANGED] = function(...)
        local _, reason, last_join_suc_channel = ...
        if last_join_suc_channel and reason then
            -- token过期
            if reason == voice_vendor.CONNECTION_CHANGED_TOKEN_EXPIRED then
                --_ejoysdk.log('lua EVENT ON ON_CONNECTION_STATE_CHANGED, reason =' .. tostring(reason))

                -- 不去改状态了，reasonw=9时，其实还在频道内。声网的文档不正确
                --voice_status = M.VOICE_STATUS.NOT_JOIN
                --voice_fsm:transition(voice_fsm.current,STATES.NOT_JOIN)
                inner_renew_token_with_params(last_join_suc_channel)
                -- 不去重新进入频道了，reasonw=9时，其实还在频道内。声网的文档不正确
                --M.join_channel(last_join_suc_channel)
            end
        end
        callback(EVENT.ON_CONNECTION_STATE_CHANGED, ...)
    end,
    [EVENT.ON_TOKEN_PRIVILEGE_WILL_EXPIRE] = function(...)
        -- 即将过期
        inner_renew_token_with_params(cur_channel)
        callback(EVENT.ON_TOKEN_PRIVILEGE_WILL_EXPIRE, ...)
    end
}

local mt = {}
mt.__index = function(self, key)
    return voice_listener and voice_listener[key]
end
setmetatable(voice_listener_wrapper, mt)

function M.set_voice_vendor(vendor)
    -- call_api把vendor传进去会爆栈崩溃，先去掉
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_voice_vendor', chat_log.LOG_LEVEL.LOW, {})

    voice_vendor = vendor
    voice_vendor.set_listener(voice_listener_wrapper)
end

function M.set_listener(listener)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_listener', chat_log.LOG_LEVEL.LOW, {})

    voice_listener = listener
end

function M.remove_listener()
    --chat_log.call_api(chat_log_util.header(), TAG, 'remove_listener', chat_log.LOG_LEVEL.LOW, {})

    voice_listener = nil
end

function M.add_channel_param(channel_id, param)
    --chat_log.call_api(chat_log_util.header(), TAG, 'add_channel_param', chat_log.LOG_LEVEL.LOW, {}, channel_id, param)

    channel_params[channel_id] = param
end

function M.remove_channel_param(channel_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'remove_channel_param', chat_log.LOG_LEVEL.LOW, {}, channel_id)

    channel_params[channel_id] = nil
end

function M.get_channel_param(channel_id)
    if channel_params and channel_params[channel_id] then
        utils.deepcopy(channel_params[channel_id])
    else
        return {}
    end
end

-- 主动请求agora token, 协议：https://aliyuque.antfin.com/ejoy-platform/ejoy-platform/kz58v4gvpalbof8z
function M.get_voice_token(channel_id, versions, cb)
    local ejoysdk_chat = require 'ejoysdk_lua.chat.ejoysdk_chat'
    ejoysdk_chat.get_agora_channel_token(channel_id, versions, cb)
end

function M.get_agora_token_version()
    -- AccessToken版本，后续升级AccessToken2根据native返回版本来升级
    -- 返回支持的token版本, 如当前只支持1 则是{”1“}
    return {"1"}
end

function M.is_support_token_join()
    if voice_vendor then
        return voice_vendor.is_support_token_join()
    end
    return false
end

-- channel_id: string, 频道id
-- channel_info: table, 预留透传参数
--      desc: string, 透传到admin后台的标记描述, 最大长度限制200, 超过会截断
function M.join_channel(channel_id, channel_info)
    --chat_log.call_api(chat_log_util.header(), TAG, 'join_channel', chat_log.LOG_LEVEL.LOW, {}, channel_id)

    if channel_info and channel_info.desc and #channel_info.desc > M.CHANNEL_INFO_DESC_MAX_LENGTH then
        E.LOG.d(TAG, 'channel_info.desc over max length')
        channel_info.desc = string.sub(channel_info.desc, 1, M.CHANNEL_INFO_DESC_MAX_LENGTH)
    end

    -- 只有是未加入，才可以加入
    local current_state = M.get_state()
    E.LOG.d(TAG, 'join_channel current_state=' .. tostring(current_state))

    if voice_fsm:is(STATES.NOT_JOIN) == false then
        callback(EVENT.ON_JOIN_CHANNEL_FAIL, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_STATE_INVALID_JOIN_FAIL, 'only NOT_JOIN state can join')
        return
    end

    E.LOG.d(TAG, 'join_channel >>>')
    E.LOG.d(TAG, {channel_id=channel_id})

    if voice_vendor then
        local gangplank = require 'ejoysdk_lua.ejoysdk_gangplank'
        local player_id = gangplank.player_info().player_id
        if not player_id then
            return
        end

        -- 确保屏蔽数据可以根据角色获取到
        if mute_remote_cache_by_user and #mute_remote_cache_by_user == 0 then
            local current_player_mute_list = (EJVOICE_MUTE_REMOTE_CACHE and EJVOICE_MUTE_REMOTE_CACHE:get()) or {}
            mute_remote_cache_by_user = current_player_mute_list[EG.player_info().player_id] or {}
        end

        -- 旧逻辑：旧native或者旧server
        local function join_channel_with_account()
            local channel_param = channel_params[channel_id]
            if channel_param then
                E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.JOIN')
                channel_param.use_account_join = true
                -- 先清空一下
                channel_param.channel_info = nil
                if channel_info then
                    channel_param.channel_info = channel_info
                end
                voice_fsm:add_event(EVENTS.JOIN, channel_id, player_id, channel_param)
            else
                callback(EVENT.ON_JOIN_CHANNEL_FAIL, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_NO_CHANNEL, 'current channel_id is not valid，maybe current player not in the group')
            end
        end

        if M.is_support_token_join() then
            -- 如果是新版本，就直接从chat服务获取到token，同时携带一个agora_version
            local voice_version = M.get_agora_token_version()
            M.get_voice_token(channel_id, voice_version, function (succ, ...)
                if succ then
                    local ret_info = ...
                    if ret_info and type(ret_info) == 'table' and ret_info.token and ret_info.uid then
                        -- 新服务端 
                        E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.JOIN')
                        -- 更新下缓存信息
                        local channel_param = channel_params[channel_id]
                        if channel_param then
                            channel_param.token = ret_info.token
                            channel_param.channel_info = channel_info
                        end

                        voice_fsm:add_event(EVENTS.JOIN, channel_id, player_id, { token = ret_info.token, voice_user_id = ret_info.uid, channel_info = channel_info})
                    else
                        E.LOG.w(TAG, 'chat server is old')
                        join_channel_with_account()
                    end
                else
                    local code, msg = ...
                    -- 获取token失败
                    callback(EVENT.ON_JOIN_CHANNEL_FAIL, code or CONSTANTS.CHAT_ERROR_CODES.CODE_SERVER_ERROR_ON_GET_VOICE_TOKEN_FAIL, msg or 'get voice_token fail')
                end
            end)
        else
            join_channel_with_account()
        end
    end
end

-- 不一定会保证退出语音频道和回调离开频道成功消息，因为可能之前加入的时候，已经提前离开了。
function M.leave_channel(channel_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'leave_channel', chat_log.LOG_LEVEL.LOW, {}, channel_id)

    local current_state = M.get_state()
    E.LOG.d(TAG, 'leave_channel current_state=' .. tostring(current_state))

    -- 只有是已加入才可以离开
    if voice_fsm:is(STATES.JOINED) == false then
        callback(EVENT.ON_LEAVE_CHANNEL_FAIL, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_STATE_INVALID_LEAVE_FAIL, 'only JOINED state can leave')
        return
    end
    
    E.LOG.d(TAG, 'leave_channel >>>')
    E.LOG.d(TAG, {channel_id = channel_id})

    E.LOG.d(TAG, 'voice_fsm.add_event -> STATES.LEAVE')
    voice_fsm:add_event(EVENTS.LEAVE, channel_id)
end

function M.is_voice_channel(channel_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'is_voice_channel', chat_log.LOG_LEVEL.LOW, {}, channel_id)

    local ret = false
    for id, _ in pairs(channel_params) do
        if id == channel_id then
            ret = true
            break
        end
    end

    --chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'is_voice_channel', chat_log.LOG_LEVEL.LOW, {}, ret)

    return ret
end

-- 常规配置

function M.set_enable_speaker(enable)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_enable_speaker', chat_log.LOG_LEVEL.LOW, {}, enable)

    if voice_vendor then
        voice_vendor.set_enable_speaker(enable)
    end
end

-- 来源于服务端的同步操作，关闭的本地音频流
function M.mute_local_from_server_sync(mute)
    -- SDK内会循环调用此方法，这里不打日志了
    if voice_vendor then
        mute_local_value = mute

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        voice_vendor.mute_local(mute)
    end
end

local function mute_local_with_atom_privilege(mute, cb)
    local finish_handle = function()
        -- voice_vendor.mute_local(mute) , 等广播回来再开启
        mute_local_value = mute

        local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
        chat_log_util.resset_header()

        local agora_vendor = require 'ejoysdk_lua.vendors.agora'

        utils.safe_call_cb(cb, true)
        --chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'mute_local', chat_log.LOG_LEVEL.LOW, {}, cb, true)

        if not mute then
            open_mic_start_time = os.time()

            -- 上麦的打点
            local self_player_id = EG.player_info() and EG.player_info().player_id
            local self_player_name = EG.player_info() and EG.player_info().player_name
            local cached_group = chat_cache.get_group(cur_channel) or {}
            local group_type = cached_group.info and cached_group.info.type

            local jf_params = {}
            if self_player_id and type(self_player_id) == 'string' and #self_player_id > 0 then
                jf_params.roleId = self_player_id
            end
            if self_player_name and type(self_player_name) == 'string' and #self_player_name > 0 and not agora_vendor.is_forbid_upload_role_name_from_cc() then
                jf_params.roleName = self_player_name
            end
            jf_params.type = group_type or ''
            jf_params.is_upload_now = AGORA_JF_UPLOAD_NOW

            ESTAT.stat_bizid('mic.user.online', '0', '0', jf_params)

            ESTAT.stat_bizid('click.mic.online', '0', '0', jf_params)
        else
            if open_mic_start_time > 0 then
                -- 下麦时，上报开麦时长
                local self_player_id = EG.player_info() and EG.player_info().player_id
                local self_player_name = EG.player_info() and EG.player_info().player_name
                local cached_group = chat_cache.get_group(cur_channel) or {}
                local group_type = cached_group.info and cached_group.info.type
                if os.time() > open_mic_start_time then
                    local duration = os.time() - open_mic_start_time

                    local jf_params = {duration=duration}
                    if self_player_id and type(self_player_id) == 'string' and #self_player_id > 0 then
                        jf_params.roleId = self_player_id
                    end
                    if self_player_name and type(self_player_name) == 'string' and #self_player_name > 0 and not agora_vendor.is_forbid_upload_role_name_from_cc() then
                        jf_params.roleName = self_player_name
                    end
                    jf_params.type = group_type or ''
                    jf_params.result = duration
                    jf_params.is_upload_now = AGORA_JF_UPLOAD_NOW

                    ESTAT.stat_bizid('duration.user.voice.online', '0', '0', jf_params)
                end

                open_mic_start_time = 0
            end
        end
    end

    -- 关麦不用先判断权限，直接本地先关麦，然后同步给服务器。这样可以规避聊天断连导致无法关麦的问题
    if mute then
        if voice_vendor then
            voice_vendor.mute_local(mute)
        end
        finish_handle()
        voice_channel_status_update(cur_channel, voice_status, mute_local_value, cur_voice_user_id)
        return
    end

    -- 该接口调用是权限校验的用意, 参数mute是用户所期望的开麦or关麦
    async_voice_channel_status_update(cur_channel, voice_status, mute, cur_voice_user_id, nil, function (succ, ...)
        if not succ then
            -- 权限校验不通过
            local code, msg = ...

            --chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'mute_local', chat_log.LOG_LEVEL.LOW, {}, cb, false, code, msg)
            utils.safe_call_cb(cb, false, code, msg)
            return
        end

        -- 能走到这，可以放心设置mute_local，权限校验，服务器在async_voice_channel_status_update已经校验了。
        finish_handle()
    end)
end

-- 用户手动操作，关闭本地音频流，请调用本接口
function M.mute_local(mute, cb)
    --chat_log.call_api(chat_log_util.header(), TAG, 'mute_local', chat_log.LOG_LEVEL.LOW, {}, mute, cb)

    if not voice_vendor then
        --chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'mute_local', chat_log.LOG_LEVEL.LOW, {}, cb, false, CONSTANTS.CODE_VOICE_VENDOR_MISS, 'voice vendor not found')
        utils.safe_call_cb(cb, false, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_VENDOR_MISS, 'voice vendor not found')
        return
    end

    mute_local_with_atom_privilege(mute, cb)
end

function M.get_mute_remote_config_by_user()
    if mute_remote_cache_by_user then
        return utils.deepcopy(mute_remote_cache_by_user)
    else
        return {}
    end
end

function M.mute_remote(player_id, mute, cb)
    -- SDK内会循环调用此方法，这里不打日志了

    if not voice_vendor then
        utils.safe_call_cb(cb, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_VENDOR_MISS, 'vendor miss')
        return
    end

    if not player_id then
        utils.safe_call_cb(cb, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_PARAMS_INVALID, 'target_player_id miss')
        return
    end

    if not cur_channel or not fsm.current == STATES.JOINED then
        utils.safe_call_cb(cb, CONSTANTS.CHAT_ERROR_CODES.CODE_VOICE_CHANNEL_STATES_INVALID, 'channel states must is joined')
        return
    end

    mute = mute or false

    if mute then
        mute_remote_cache_by_user[player_id] = mute
    else
        mute_remote_cache_by_user[player_id] = nil
    end

    voice_vendor.mute_remote(player_id, mute, cur_channel)

    if EJVOICE_MUTE_REMOTE_CACHE then
        local current_player_mute_list = EJVOICE_MUTE_REMOTE_CACHE:get() or {}
        current_player_mute_list[EG.player_info().player_id] = mute_remote_cache_by_user
        EJVOICE_MUTE_REMOTE_CACHE:set(current_player_mute_list)
        EJVOICE_MUTE_REMOTE_CACHE:save()
    end

    local agora_vendor = require 'ejoysdk_lua.vendors.agora'

    -- (解除)屏蔽某人的打点
    local self_player_id = EG.player_info() and EG.player_info().player_id
    local self_player_name = EG.player_info() and EG.player_info().player_name
    local cached_group = chat_cache.get_group(M.get_curr_channel_id()) or {}
    local group_type = cached_group.info and cached_group.info.type
    local jf_params = {mutetype=mute, target_player_id=player_id}
    if self_player_id and type(self_player_id) == 'string' and #self_player_id > 0 then
        jf_params.roleId = self_player_id
    end
    if self_player_name and type(self_player_name) == 'string' and #self_player_name > 0 and not agora_vendor.is_forbid_upload_role_name_from_cc() then
        jf_params.roleName = self_player_name
    end
    jf_params.type = group_type or ''
    jf_params.result = mute
    jf_params.is_upload_now = AGORA_JF_UPLOAD_NOW

    ESTAT.stat_bizid('muteperson.mic.online', '0', '0', jf_params)
end

-- 私有方法，项目组不要调用
function M._mute_remote_for_server_sync(player_id, mute)
    -- SDK内会循环调用此方法，这里不打日志了

    if not voice_vendor then
        return
    end

    if not player_id then
        return
    end

    mute = mute or false
    voice_vendor.mute_remote(player_id, mute, cur_channel)
end

function M.mute_remote_all(mute)
    --chat_log.call_api(chat_log_util.header(), TAG, 'mute_remote_all', chat_log.LOG_LEVEL.LOW, {}, mute)

    if voice_vendor then
        voice_vendor.mute_remote_all(mute)
    end
end

function M.enable_volume_indication(interval)
    --chat_log.call_api(chat_log_util.header(), TAG, 'enable_volume_indication', chat_log.LOG_LEVEL.LOW, {}, interval)

    if voice_vendor then
        voice_vendor.enable_volume_indication(interval)
    end
end

function M.set_parameters(params)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_parameters', chat_log.LOG_LEVEL.LOW, {}, params)

    if voice_vendor then
        voice_vendor.set_parameters(params)
    end
end

function M.adjust_record_volume(volume)
    --chat_log.call_api(chat_log_util.header(), TAG, 'adjust_record_volume', chat_log.LOG_LEVEL.LOW, {}, volume)

    if voice_vendor then
        voice_vendor.adjust_record_volume(volume)
    end
end

function M.adjust_playing_volume(volume)
    --chat_log.call_api(chat_log_util.header(), TAG, 'adjust_playing_volume', chat_log.LOG_LEVEL.LOW, {}, volume)

    if voice_vendor then
        voice_vendor.adjust_playing_volume(volume)
    end
end

function M.enable_local_audio(enable)
    --chat_log.call_api(chat_log_util.header(), TAG, 'enable_local_audio', chat_log.LOG_LEVEL.LOW, {}, enable)

    if voice_vendor then
        voice_vendor.enable_local_audio(enable)
    end
end

function M.get_voice_group_info(group_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_voice_group_info', chat_log.LOG_LEVEL.LOW, {}, group_id)

    local res = chat_cache.get_group(group_id)

    --local log_group = chat_log_util.simple_group_info(res)
    --chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_voice_group_info', chat_log.LOG_LEVEL.LOW, {}, log_group)

    return res
end

-- 仅PC可调用
function M.start_echo_test(interval_in_seconds)
    --chat_log.call_api(chat_log_util.header(), TAG, 'start_echo_test', chat_log.LOG_LEVEL.LOW, {}, interval_in_seconds)

    if voice_vendor then
        voice_vendor.start_echo_test(interval_in_seconds)
    end
end

-- 仅PC可调用
function M.stop_echo_test()
    --chat_log.call_api(chat_log_util.header(), TAG, 'stop_echo_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.stop_echo_test()
    end
end

-- 仅PC可调用
-- 是否探测上行网络 config.probe_uplink = true/false
-- 是否探测下行网络 config.probe_downlink = true/false
-- 用户期望的最高发送码率 config.expected_uplink_bitrate = 范围为 [100000, 5000000]
-- 用户期望的最高接收码率 config.expected_downlink_bitrate = 范围为 [100000, 5000000]
function M.start_lastmile_probe_test(config)
    --chat_log.call_api(chat_log_util.header(), TAG, 'start_lastmile_probe_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.start_lastmile_probe_test(config)
    end
end

-- 仅PC可调用
function M.stop_lastmile_probe_test()
    --chat_log.call_api(chat_log_util.header(), TAG, 'stop_lastmile_probe_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.stop_lastmile_probe_test()
    end
end

-- SDK内部接口，外部勿调用
-- 仅PC可调用
function M.renew_token(token)
    --chat_log.call_api(chat_log_util.header(), TAG, 'renew_token', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.renew_token(token)
    end
end

-- 仅PC可调用
-- 获取设备的数量，type string类型: playback播放设备类型/recording输入设备类型
function M.get_count(type)
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_count', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_count(type)
    end

    return 0
end

-- 仅PC可调用
-- 获取app音量(播放)，type string类型: playback播放设备类型(只支持playback)
function M.get_application_volume(type)
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_application_volume', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_application_volume(type)
    end

    return 0
end

-- 仅PC可调用
-- app是否静音(播放)，type string类型: playback播放设备类型(只支持playback)
function M.is_application_mute(type)
    --chat_log.call_api(chat_log_util.header(), TAG, 'is_application_mute', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.is_application_mute(type)
    end

    return false
end

-- 仅PC可调用
-- 获取当前所有播放设备
function M.enumerate_playback_devices()
    --chat_log.call_api(chat_log_util.header(), TAG, 'enumerate_playback_devices', chat_log.LOG_LEVEL.LOW, {})
    if voice_vendor then
        return voice_vendor.enumerate_playback_devices()
    end

    return {}
end

-- 仅PC可调用
-- 获取当前所有输入设备
function M.enumerate_recording_devices()
    --chat_log.call_api(chat_log_util.header(), TAG, 'enumerate_recording_devices', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.enumerate_recording_devices()
    end

    return {}
end


function M.set_profile_scenario(profile, scenario)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_profile_scenario', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.set_profile_scenario(profile, scenario)
    end
end

-- 仅PC可调用
-- 开启(关闭)声卡录制
function M.enable_loopback_recording(enable, device_name)
    --chat_log.call_api(chat_log_util.header(), TAG, 'enable_loopback_recording', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.enable_loopback_recording(enable, device_name)
    end
end

-- 仅PC可调用
-- 指定播放(输入)设备 type string类型: playback播放设备类型/recording输入设备类型
function M.set_device(type, device_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.set_device(type, device_id)
    end
end

-- 仅PC可调用
-- 获取默认的播放(输入)设备 type string类型: playback播放设备类型/recording输入设备类型
function M.get_default_device(type)
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_default_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_default_device(type)
    end

    return {}
end

-- 仅PC可调用
-- 根据索引获取的播放(输入)设备的信息(id+name)
-- type string类型: playback播放设备类型/recording输入设备类型
-- index [0, 播放(输入)设备的数量)，数量可通过get_count接口获取
function M.get_device(type, index)
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_device(type, index)
    end

    return {}
end

-- 仅PC可调用
-- 设置app的音量(播放)
-- type string类型: playback播放设备类型(仅支持playback)
-- volume int类型，[0, 255]
function M.set_application_volume(type, volume)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_application_volume', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.set_application_volume(type, volume)
    end
end

-- 仅PC可调用
-- 设置app的静音(播放)
-- type string类型: playback 播放设备类型(仅支持playback)
-- mute bool类型，true静音 false不静音
function M.set_application_mute(type, mute)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_application_mute', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.set_application_mute(type, mute)
    end
end

-- 仅PC可调用
-- 跟随系统播放设备
-- enable bool类型，true跟随 false不跟随
function M.follow_system_playback_device(enable)
    --chat_log.call_api(chat_log_util.header(), TAG, 'follow_system_playback_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.follow_system_playback_device(enable)
    end
end

-- 仅PC可调用
-- 跟随系统输入设备
-- enable bool类型，true跟随 false不跟随
function M.follow_system_recording_device(enable)
    --chat_log.call_api(chat_log_util.header(), TAG, 'follow_system_recording_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.follow_system_recording_device(enable)
    end
end

-- 仅PC可调用
-- 指定播放设备
-- device_id string类型，设备id
function M.set_playback_device(device_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_playback_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.set_playback_device(device_id)
    end
end

-- 仅PC可调用
-- 获取当前播放设备id
function M.get_playback_device()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_playback_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_playback_device()
    end

    return ''
end

-- 仅PC可调用
-- 获取当前播放设备信息(id+name)
function M.get_playback_device_info()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_playback_device_info', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_playback_device_info()
    end

    return {}
end

-- 仅PC可调用
-- 指定输入设备
-- device_id string类型，设备id
function M.set_recording_device(device_id)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_recording_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.set_recording_device(device_id)
    end
end

-- 仅PC可调用
-- 获取当前输入设备id
function M.get_recording_device()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_recording_device', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_recording_device()
    end

    return ''
end

-- 仅PC可调用
-- 获取当前输入设备信息(id+name)
function M.get_recording_device_info()
    --chat_log.call_api(chat_log_util.header(), TAG, 'get_recording_device_info', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        return voice_vendor.get_recording_device_info()
    end

    return {}
end

-- 仅PC可调用
-- 设置输入设备的音量
-- volume int类型，范围[0, 255]
-- 更推荐使用 adjust_record_volume 接口
function M.set_recording_device_volume(volume)
    --chat_log.call_api(chat_log_util.header(), TAG, 'set_recording_device_volume', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.set_recording_device_volume(volume)
    end
end

-- 仅PC可调用
-- 开始播放设备的测试
function M.start_playback_device_test(test_audio_file_path)
    --chat_log.call_api(chat_log_util.header(), TAG, 'start_playback_device_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.start_playback_device_test(test_audio_file_path)
    end
end

-- 仅PC可调用
-- 结束播放设备的测试
function M.stop_playback_device_test()
    --chat_log.call_api(chat_log_util.header(), TAG, 'stop_playback_device_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.stop_playback_device_test()
    end
end

-- 仅PC可调用
-- 开始输入设备的测试
function M.start_recording_device_test(interval)
    --chat_log.call_api(chat_log_util.header(), TAG, 'start_recording_device_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.start_recording_device_test(interval)
    end
end

-- 仅PC可调用
-- 结束输入设备的测试
function M.stop_recording_device_test()
    --chat_log.call_api(chat_log_util.header(), TAG, 'stop_recording_device_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.stop_recording_device_test()
    end
end

-- 仅PC可调用
-- 开始音频设备声卡测试
function M.start_audio_device_loopback_test(interval)
    --chat_log.call_api(chat_log_util.header(), TAG, 'start_audio_device_loopback_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.start_audio_device_loopback_test(interval)
    end
end

-- 仅PC可调用
-- 结束音频设备声卡测试
function M.stop_audio_device_loopback_test()
    --chat_log.call_api(chat_log_util.header(), TAG, 'stop_audio_device_loopback_test', chat_log.LOG_LEVEL.LOW, {})

    if voice_vendor then
        voice_vendor.stop_audio_device_loopback_test()
    end
end

-- 仅PC可调用
-- 是否正在start_echo_test
function M.is_start_echo_test_process()
    --chat_log.call_api(chat_log_util.header(), TAG, 'is_start_echo_test_process', chat_log.LOG_LEVEL.LOW, {})
    if voice_vendor then
        return voice_vendor.is_start_echo_test_process()
    end
end

-- 仅PC可调用
-- 是否正在start_lastmile_probe_test
function M.is_start_lastmile_probe_test_process()
    --chat_log.call_api(chat_log_util.header(), TAG, 'is_start_lastmile_probe_test_process', chat_log.LOG_LEVEL.LOW, {})
    if voice_vendor then
        return voice_vendor.is_start_lastmile_probe_test_process()
    end
end

-- 仅PC可调用
-- 是否正在start_playback_device_test
function M.is_start_playback_device_test_process()
    --chat_log.call_api(chat_log_util.header(), TAG, 'is_start_playback_device_test_process', chat_log.LOG_LEVEL.LOW, {})
    if voice_vendor then
        return voice_vendor.is_start_playback_device_test_process()
    end
end

-- 仅PC可调用
-- 是否正在start_recording_device_test
function M.is_start_recording_device_test_process()
    --chat_log.call_api(chat_log_util.header(), TAG, 'is_start_recording_device_test_process', chat_log.LOG_LEVEL.LOW, {})
    if voice_vendor then
        return voice_vendor.is_start_recording_device_test_process()
    end
end

-- 仅PC可调用
-- 是否正在start_audio_device_loopback_test
function M.is_start_audio_device_loopback_test_process()
    --chat_log.call_api(chat_log_util.header(), TAG, 'is_start_audio_device_loopback_test_process', chat_log.LOG_LEVEL.LOW, {})
    if voice_vendor then
        return voice_vendor.is_start_audio_device_loopback_test_process()
    end
end

return M