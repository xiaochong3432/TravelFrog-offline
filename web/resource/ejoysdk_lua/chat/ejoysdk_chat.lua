local E = require 'ejoysdk_lua.ejoysdk'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local utils = require "ejoysdk_lua.ejoysdk_utils"
local server = require 'ejoysdk_lua.chat.ejoysdk_chat_server'
local STATES = require 'ejoysdk_lua.chat.ejoysdk_chat_states'
local chat_base = require 'ejoysdk_lua.chat.ejoysdk_chat_base'
local chat_friend = require 'ejoysdk_lua.chat.ejoysdk_chat_friend'
local DISPATCHER = require 'ejoysdk_lua.chat.ejoysdk_chat_push_dispatcher'
local CALLBACK = require 'ejoysdk_lua.chat.ejoysdk_chat_callback_manager'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local voice = require 'ejoysdk_lua.chat.ejoysdk_voice'
local voice_topic = require 'ejoysdk_lua.chat.ejoysdk_voice_topic'
local chat_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local chat_jf = require 'ejoysdk_lua.chat.ejoysdk_chat_jf'
local EM = require "ejoysdk_lua.ejoysdk_module"
local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
local player_log_util = require 'ejoysdk_lua.player.player_log_util'

local TAG = EM.MODULE.CHAT .. 'chat'

local M = {}
M.re_send_id = {}

local state = STATES.NO_PLAYER_TOKEN
local is_logining = false
local is_login_succ = false

local get_chat_token_process = false

local GET_PLAYER_INFO_FAIL_CODE = -400001;
local GET_PLAYER_INFO_FAIL_MESSAGE = 'get player info fail'

local AGORA_JF_UPLOAD_NOW = false

-- 取消旧逻辑：1小时内，最多重试3次的限制

do
    ET.subscribe(ET.chat.UPDATE_STATE, function(new_state, login_result_params)
        if new_state == STATES.LOGIN_SUCC or new_state == STATES.LOGIN_FAIL then
            if login_result_params and login_result_params.destination == server.DESTINATION.PLAYER then
                --E.LOG.debug(TAG, 'UPDATE_STATE, its for player, update state:'..new_state)
                state = new_state
            end
        else
            --E.LOG.debug(TAG, 'UPDATE_STATE, update state:'..new_state)
            state = new_state
        end
    end)
end

function M.get_status()
    chat_log.call_api(chat_log_util.header(), TAG, 'get_status', chat_log.LOG_LEVEL.LOW, {})

    local res = state

    chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_status', chat_log.LOG_LEVEL.LOW, {}, res)
    return res
end

function M.is_login_succ()
    chat_log.call_api(chat_log_util.header(), TAG, 'is_login_succ', chat_log.LOG_LEVEL.LOW, {})

    local res = is_login_succ

    chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'is_login_succ', chat_log.LOG_LEVEL.LOW, {}, res)
    return res
end

function M.get_last_error_msg()
    chat_log.call_api(chat_log_util.header(), TAG, 'get_last_error_msg', chat_log.LOG_LEVEL.LOW, {})

    local res = chat_base.get_last_error_msg()

    chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_last_error_msg', chat_log.LOG_LEVEL.LOW, {}, res)

    return res
end

local SERVER_INIT_HANDLERS = {}
M.SERVER_INIT_HANDLERS = SERVER_INIT_HANDLERS

-- chat_base在重建连接时，会调这个方法
function SERVER_INIT_HANDLERS.on_server_init_start()
    --E.LOG.debug(TAG, 'exec on_server_init_start')
    --E.LOG.debug(TAG,'update is_login_succ, value=false, time=on_server_init_start')
    is_login_succ = false
end

-- chat_base在获取chat_token时，会调这个方法
function SERVER_INIT_HANDLERS.get_chat_token_start()
    E.LOG.debug(TAG, 'exec get_chat_token_start')
    get_chat_token_process = true
end

-- chat_base在chat_token完成时，会调这个方法
function SERVER_INIT_HANDLERS.get_chat_token_end()
    E.LOG.debug(TAG, 'exec get_chat_token_end')
    get_chat_token_process = false
end

local RPC_CALL_HANDLERS = {}
M.RPC_CALL_HANDLERS = RPC_CALL_HANDLERS

function RPC_CALL_HANDLERS.on_check_rpc_call_start()
    --E.LOG.debug(TAG, 'exec on_check_rpc_call_start')
    if is_login_succ then
        --E.LOG.debug(TAG, 'exec on_check_rpc_call res=succ')
       return true
    end

    --E.LOG.debug(TAG, 'exec on_check_rpc_call res=fail')
    return false
end

function M.init(game_handlers, auto_login, retry_times)
    chat_log.call_api(chat_log_util.header(), TAG, 'init', chat_log.LOG_LEVEL.HIGH, {}, game_handlers, auto_login, retry_times)

    CALLBACK.register_callback(server.DESTINATION.PLAYER, game_handlers)

    M.real_init(auto_login, retry_times)
end

function M.real_init(auto_login, retry_times)
    --注册聊天推送监听器
    DISPATCHER.register_chat_handlers(server.DESTINATION.PLAYER, M.HANDLERS)
    DISPATCHER.register_server_handlers(M.SERVER_HANDLERS)

    --初始化实时消息下发模块
    local REALTIME_MSG = require 'ejoysdk_lua.chat.ejoysdk_realtime_msg'
    REALTIME_MSG.init()

    -- 初始化 chat_baes
    chat_base.init(auto_login, retry_times)
    chat_base.register_server_init_handlers(server.DESTINATION.PLAYER, SERVER_INIT_HANDLERS)

    server.register_rpc_call_handlers(server.DESTINATION.PLAYER, RPC_CALL_HANDLERS)

    ET.subscribe(voice_topic.VOICE_CHANNEL_STATUS_UPDATE, M.set_voice_channel_status)
end

function M.tick()
    --chat_log.call_api(chat_log_util.header(), TAG, 'tick', chat_log.LOG_LEVEL.LOW, {})

    chat_base.tick()
end

function M.close()
    chat_log.call_api(chat_log_util.header(), TAG, 'close', chat_log.LOG_LEVEL.LOW, {})
    -- 游戏主动关闭后，为了让游戏调用retry_connect时，delay_time恢复成从0s递增，所以需要在这里重置一下retry_connect_index
    chat_base.reset_retry_connect_index()

    ET.publish(ET.chat.UPDATE_STATE, STATES.USER_CLOSE)

    --E.LOG.debug(TAG,'update is_login_succ, value=false,time=close')
    is_login_succ = false

    M.re_send_id = {}
    chat_base.close()
end

M.TYPE_PERSONAL = chat_base.TYPE_PERSONAL
M.TYPE_GROUP = chat_base.TYPE_GROUP
M.TYPE_SYSTEM = chat_base.TYPE_SYSTEM
M.SYSTEM_CHAT_GROUP = chat_base.SYSTEM_CHAT_GROUP
M.SYSTEM_FRIEND = chat_base.SYSTEM_FRIEND
M.SYSTEM_GAME = chat_base.SYSTEM_GAME

local start_with = E.Utils.start_with
local split_string = E.Utils.split_string

function M.get_session_type(session_id)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_session_type', chat_log.LOG_LEVEL.LOW, {}, session_id)

    return chat_base.get_session_type(session_id)
end

function M.personal_session_id(with_player_id)
    chat_log.call_api(chat_log_util.header(), TAG, 'personal_session_id', chat_log.LOG_LEVEL.LOW, {}, with_player_id)

    local res = chat_base.personal_session_id(with_player_id)

    chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'personal_session_id', chat_log.LOG_LEVEL.LOW, {}, res)

    return res
end

-- at_list: table类型, eg. { uid1, uid2 }
function M.send_text_msg(text, session_id, cb, at_list)
    chat_log.call_api(chat_log_util.header(), TAG, 'send_text_msg', chat_log.LOG_LEVEL.HIGH, {}, text, session_id, cb, at_list)

    local send_id = server.send_id()
    M.re_send_id[send_id] = { text = text, session_id = session_id , at_list = at_list}

    chat_base.send_text_msg(server.DESTINATION.PLAYER, send_id, text, session_id, function(succ, ...)
        if succ then
            M.re_send_id[send_id] = nil
        else
            local code, msg = ...
            chat_jf.send_msg_fail(server.DESTINATION.PLAYER, {method = 'send_text_msg', code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'send_text_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end, at_list)
end

function M.resend_text_msg(send_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'resend_text_msg', chat_log.LOG_LEVEL.HIGH, {}, send_id, cb)

    local data = M.re_send_id[send_id]

    chat_base.resend_text_msg(server.DESTINATION.PLAYER, data, send_id, function(succ, ...)
        if succ then
            M.re_send_id[send_id] = nil
        else
            local code, msg = ...
            chat_jf.send_msg_fail(server.DESTINATION.PLAYER, {method = 'resend_text_msg', code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'resend_text_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end)
end

function M.send_custom(custom, session_id, cb, at_list)
    chat_log.call_api(chat_log_util.header(), TAG, 'send_custom', chat_log.LOG_LEVEL.HIGH, {}, custom, session_id, cb, at_list)

    chat_base.send_custom(server.DESTINATION.PLAYER, custom, session_id, function (succ, ...)

        if not succ then
            local code, msg = ...
            chat_jf.send_msg_fail(server.DESTINATION.PLAYER, {method = 'send_custom', code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'send_custom', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end, at_list)
end

-- at_list: table类型, eg. { uid1, uid2 }
function M.send_rich_text_msg(text, extend_data, session_id, cb, at_list)
    chat_log.call_api(chat_log_util.header(), TAG, 'send_rich_text_msg', chat_log.LOG_LEVEL.HIGH, {}, text, extend_data, session_id, cb, at_list)

    local send_id = server.send_id()
    M.re_send_id[send_id] = { text = text, extend_data = extend_data, session_id = session_id , at_list = at_list}

    chat_base.send_rich_text_msg(server.DESTINATION.PLAYER, send_id, text, extend_data, session_id, function(succ, ...)
        if succ then
            M.re_send_id[send_id] = nil
        else
            local code, msg = ...
            chat_jf.send_msg_fail(server.DESTINATION.PLAYER, {method = 'send_rich_text_msg', code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'send_rich_text_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end, at_list)
end

-- 富文本的重发方法
function M.resend_rich_text_msg(send_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'resend_rich_text_msg', chat_log.LOG_LEVEL.HIGH, {}, send_id, cb)

    local data = M.re_send_id[send_id]

    chat_base.resend_rich_text_msg(server.DESTINATION.PLAYER, data, send_id, function(succ, ...)
        if succ then
            M.re_send_id[send_id] = nil
        else
            local code, msg = ...
            chat_jf.send_msg_fail(server.DESTINATION.PLAYER, {method = 'resend_rich_text_msg', code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'resend_rich_text_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end)
end

-- 发送资源消息
-- res_type: string类型，暂时只支持'audio'
-- res_id: string类型，资源上传到平台后，会有res_id
-- at_list: table类型, eg. { uid1, uid2 }
function M.send_resource_msg(text, res_type, res_id, extend_data, session_id, at_list, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'send_resource_msg', chat_log.LOG_LEVEL.HIGH, {}, text, res_type, res_id, extend_data, session_id, at_list, cb)

    local send_id = server.send_id()
    M.re_send_id[send_id] = { text = text, res_type = res_type, res_id = res_id, extend_data = extend_data, session_id = session_id , at_list = at_list}

    chat_base.send_resource_msg(server.DESTINATION.PLAYER, text, res_type, res_id, extend_data, session_id, at_list, send_id, function(succ, ...)
        if succ then
            M.re_send_id[send_id] = nil
        else
            local code, msg = ...
            chat_jf.send_msg_fail(server.DESTINATION.PLAYER, {method = 'send_resource_msg', code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'send_resource_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end)
end

-- 重发资源消息
function M.resend_resource_msg(send_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'resend_resource_msg', chat_log.LOG_LEVEL.HIGH, {}, send_id, cb)

    local data = M.re_send_id[send_id]

    chat_base.resend_resource_msg(server.DESTINATION.PLAYER, data, send_id, function(succ, ...)
        if succ then
            M.re_send_id[send_id] = nil
        else
            local code, msg = ...
            chat_jf.send_msg_fail(server.DESTINATION.PLAYER, {method = 'resend_resource_msg', code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'resend_resource_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end)
end

-- 获取最近N条被@的消息
function M.get_player_latest_at_msgs(cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_latest_at_msgs', chat_log.LOG_LEVEL.HIGH, {}, cb)

    chat_base.get_player_latest_at_msgs(server.DESTINATION.PLAYER, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_latest_at_msgs', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

-- 获取群组经纪人信息, 经纪人相当于群组的代理，可以通过
-- query: table类型
-- query['group_broker_id']: 经纪人id
-- query['sub_group_info.info.type']: 群组类型group_type，例如世界频道的world
-- query={}, query什么都不传，是查询所有经纪人信息
function M.get_user_group_broker_info(query, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_user_group_broker_info', chat_log.LOG_LEVEL.HIGH, {}, query, cb)

    chat_base.get_user_group_broker_info(server.DESTINATION.PLAYER, query, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_user_group_broker_info', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

-- 切换群组分线
function M.switch_group_id(group_broker_id, group_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'switch_group_id', chat_log.LOG_LEVEL.HIGH, {}, group_broker_id, group_id, cb)

    chat_base.switch_group_id(server.DESTINATION.PLAYER, group_broker_id, group_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'switch_group_id', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.set_msg_received(session_id, msg_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'set_msg_received', chat_log.LOG_LEVEL.LOW, {}, session_id, msg_id, cb)

    chat_base.set_msg_received(server.DESTINATION.PLAYER, session_id, msg_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'set_msg_received', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

function M.set_msg_received_with_ts(session_id, ts, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'set_msg_received_with_ts', chat_log.LOG_LEVEL.LOW, {}, session_id, ts, cb)

    chat_base.set_msg_received_with_ts(server.DESTINATION.PLAYER, session_id, ts, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'set_msg_received_with_ts', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

function M.delete_msg(session_id, msg_ids, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'delete_msg', chat_log.LOG_LEVEL.HIGH, {}, session_id, msg_ids, cb)

    chat_base.delete_msg(server.DESTINATION.PLAYER, session_id, msg_ids, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'delete_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

--[[
    清空会话的ts时间之前的所有聊天记录
    session_id: 会话id
    ts: 时间戳，单位秒
    注意：ts可以不传，表示的含义是清空某会话当前时间之前的所有聊天记录
--]]
function M.clean_session_msg(session_id, ts, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'clean_session_msg', chat_log.LOG_LEVEL.LOW, {}, session_id, ts, cb)

    chat_base.clean_session_msg(server.DESTINATION.PLAYER, session_id, ts, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'clean_session_msg', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 消息已读接口 暂时不正式使用，待有需求再开发
--local function set_msg_readed(session_id, msg_id)
--end

function M.get_latest_session(cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_latest_session', chat_log.LOG_LEVEL.HIGH, {}, cb)

    chat_base.get_latest_session(server.DESTINATION.PLAYER, function (succ, ...)
        if not succ then
            local code, msg = ...
            chat_jf.get_latest_session_fail(server.DESTINATION.PLAYER, {api_version = 1, code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end

        if succ then
            local sessions = ...
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_latest_session', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, chat_log_util.session_ids(sessions))
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_latest_session', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
        end
    end)
end

--[[
    V2接口，相比V1接口，是对sessions做了分组
    result_sessions.personal
    result_sessions.group
    result_sessions.system
    result_sessions.other
--]]
function M.get_latest_session_v2(cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_latest_session_v2', chat_log.LOG_LEVEL.HIGH, {}, cb)

    chat_base.get_latest_session_v2(server.DESTINATION.PLAYER, function (succ, ...)
        if not succ then
            local code, msg = ...
            chat_jf.get_latest_session_fail(server.DESTINATION.PLAYER, {api_version = 2, code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end

        if succ then
            local log_ret = {}

            local result_sessions = ...
            if result_sessions then
                if result_sessions.personal then
                    log_ret.personal = chat_log_util.session_ids(result_sessions.personal)
                end

                if result_sessions.group then
                    log_ret.group = chat_log_util.session_ids(result_sessions.group)
                end

                if result_sessions.system then
                    log_ret.system = chat_log_util.session_ids(result_sessions.system)
                end

                if result_sessions.other then
                    log_ret.other = chat_log_util.session_ids(result_sessions.other)
                end
            end

            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_latest_session_v2', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, log_ret)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_latest_session_v2', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
        end

    end)
end

-- 返回值是map，key是group_type，value是array
function M.get_my_groups(cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_my_groups', chat_log.LOG_LEVEL.HIGH, {}, cb)

    if not M.is_login_succ() then
        if cb then
            cb(false, CONSTANTS.CHAT_ERROR_CODES.CODE_NOT_LOGIN, 'not login chat')
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_my_groups', chat_log.LOG_LEVEL.HIGH, {}, cb, false, CONSTANTS.CHAT_ERROR_CODES.CODE_NOT_LOGIN, 'not login chat')
        return
    end

    chat_base.get_my_groups(server.DESTINATION.PLAYER, function (succ, ...)
        if not succ then
            local code, msg = ...
             chat_jf.get_group_fail(server.DESTINATION.PLAYER, {code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end

        if succ then
            local log_groups = {}

            local groups_by_type = ...
            for _,groups in pairs(groups_by_type) do
                for _,group in pairs(groups) do
                    table.insert(log_groups, chat_log_util.simple_group_info(group))
                end
            end

            local log_group_sections = chat_log.list_by_section(log_groups, 3)

            for _,v in pairs(log_group_sections) do
                chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_my_groups', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, v)
            end
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_my_groups', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
        end
    end)
end

function M.get_group(group_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_group', chat_log.LOG_LEVEL.LOW, {}, group_id, cb)

    chat_base.get_group(server.DESTINATION.PLAYER, group_id, function (succ, ...)

        if cb then
            cb(succ, ...)
        end

        if succ then
            local group = ...
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_group', chat_log.LOG_LEVEL.LOW, {}, cb, succ, chat_log_util.simple_group_info(group))
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_group', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

--[[
    opt.direction: 1表示向后翻页，-1表示向前翻页
    opt.max_msg_count: 单次拉取的最大消息数
    opt.ts: 锚点时间戳，单位秒
    opt.msg_id: 锚点消息id, 注：首次拉取后，知道了消息id，强烈推送用消息id做锚点，会比ts做锚点，更能精准拉取
--]]
function M.get_msg(session_id, opt, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_msg', chat_log.LOG_LEVEL.HIGH, {}, session_id, opt, cb)

    chat_base.get_msg(server.DESTINATION.PLAYER, session_id, opt, function (succ, ...)
        if not succ then
            local code, msg = ...
            chat_jf.get_msg_fail(server.DESTINATION.PLAYER, {code = code, msg = msg})
        end

        if cb then
            cb(succ, ...)
        end

        if succ then
            local msgs = ...
            local log_msgs = chat_log_util.simple_msg_infos(msgs)
            local log_msg_sections = chat_log.list_by_section(log_msgs, 5)
            for _,v in pairs(log_msg_sections) do
                chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, v)
            end
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_msg', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
        end
    end)
end

function M.get_msg_by_id(session_id, msg_ids, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_msg_by_id', chat_log.LOG_LEVEL.HIGH, {}, session_id, msg_ids, cb)
    chat_base.get_msg_by_id(server.DESTINATION.PLAYER, session_id, msg_ids, function(succ, ...)
        if not succ then
            local code, msg = ...
            chat_jf.get_msg_fail(server.DESTINATION.PLAYER, {code = code, msg = msg, type = 'get_msg_by_id'})
        end

        if cb then
            cb(succ, ...)
        end

        if succ then
            local msgs = ...
            local log_msgs = chat_log_util.simple_msg_infos(msgs)
            local log_msg_sections = chat_log.list_by_section(log_msgs, 5)
            for _,v in pairs(log_msg_sections) do
                chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_msg_by_id', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, v)
            end
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_msg_by_id', chat_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
        end
    end)
end

function M.create_group(members, invite_msg, group_name, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'create_group', chat_log.LOG_LEVEL.HIGH, {}, members, invite_msg, group_name, cb)

    chat_base.create_group(members, invite_msg, group_name, function (...)

        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'create_group', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.add_group_member(adds, invite_msg, group_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'add_group_member', chat_log.LOG_LEVEL.HIGH, {}, adds, invite_msg, group_id, cb)

    chat_base.add_group_member(adds, invite_msg, group_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'add_group_member', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

-- 参数说明：
--      inviter_user_id，邀请用户ID，不传默认邀请人为群组owner
--      ext，扩展参数，预留参数，传nil或者空table
function M.reply_add_group_member(reply_msg, is_agree, group_id, inviter_user_id, ext, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'reply_add_group_member', chat_log.LOG_LEVEL.HIGH, {}, reply_msg, is_agree, group_id, cb)

    if type(inviter_user_id) == 'function' then
        -- 说明是老版接口
        cb = inviter_user_id
        inviter_user_id = nil
    end
    local _ext = ext or {}

    chat_base.reply_add_group_member(reply_msg, is_agree, group_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'reply_add_group_member', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end, inviter_user_id)
end

function M.remove_group_member(removes, remove_msg, group_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'remove_group_member', chat_log.LOG_LEVEL.HIGH, {}, removes, remove_msg, group_id, cb)

    chat_base.remove_group_member(removes, remove_msg, group_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'remove_group_member', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

-- 更新群组属性接口, 目前客户端只可以修改名字 info.name
function M.update_group(info, group_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'update_group', chat_log.LOG_LEVEL.HIGH, {}, info, group_id, cb)

    chat_base.update_group(info, group_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'update_group', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.delete_group(group_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'delete_group', chat_log.LOG_LEVEL.HIGH, {}, group_id, cb)

    chat_base.delete_group(group_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'delete_group', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.exit_group(group_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'exit_group', chat_log.LOG_LEVEL.HIGH, {}, group_id, cb)

    chat_base.exit_group(group_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'exit_group', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.get_group_be_invited_history(cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_group_be_invited_history', chat_log.LOG_LEVEL.HIGH, {}, cb)

    chat_base.get_group_be_invited_history(function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_group_be_invited_history', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

-- group_id: string类型
-- status: string类型, value=joined\not_join，有便利常量，详见ejoysdk_voice.lua的VOICE_STATUS
function M.set_voice_channel_status(group_id, status, mute_local_value, voice_user_id, channel_info, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'set_voice_channel_status', chat_log.LOG_LEVEL.LOW, {}, group_id, status, mute_local_value, cb)

    chat_base.set_voice_channel_status(group_id, status, mute_local_value, voice_user_id, channel_info, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'set_voice_channel_status', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 设置语音频道的模式
-- 该接口对服务端版本有依赖，只在chat_server版本 >= x.x.x.x 才可以调该接口
-- mode：频道模式, string类型, "free" or "administrator_only"
function M.set_voice_channel_mode(group_id, mode, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'set_voice_channel_mode', chat_log.LOG_LEVEL.LOW, {}, group_id, mode, cb)

    chat_base.set_voice_channel_mode(group_id, mode, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'set_voice_channel_mode', chat_log.LOG_LEVEL.LOW, {}, cb, ...)

        local succ = ...
        if succ then
            local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
            local chat_cache = require 'ejoysdk_lua.chat.ejoysdk_chat_cache'
            local agora_vendor = require 'ejoysdk_lua.vendors.agora'

            -- 设置全体禁言/解除禁言的打点
            local self_player_id = EG.player_info() and EG.player_info().player_id
            local self_player_name = EG.player_info() and EG.player_info().player_name
            local cached_group = chat_cache.get_group(voice.get_curr_channel_id()) or {}
            local group_type = cached_group.info and cached_group.info.type

            local jf_params = {changetype=mode}
            if self_player_id and type(self_player_id) == 'string' and #self_player_id > 0 then
                jf_params.roleId = self_player_id
            end
            if self_player_name and type(self_player_name) == 'string' and #self_player_name > 0 and not agora_vendor.is_forbid_upload_role_name_from_cc() then
                jf_params.roleName = self_player_name
            end
            jf_params.type = group_type or ''
            jf_params.result = mode
            jf_params.is_upload_now = AGORA_JF_UPLOAD_NOW

            ESTAT.stat_bizid('change.mic.online', '0', '0', jf_params)
        end
    end)
end

--[[
    管理用户语音频道的状态，管理员可用此接口禁言用户。
    group_id: string类型
    operations: table类型, eg. {{user_id='131234', mute=true},
                            {user_id='312322', mute=false}}
        operations有数量限制: 1<= count <=50
        item.mute=true\false，禁言 或者 取消禁言
--]]
M.manage_voice_channel_status = chat_base.manage_voice_channel_status

-- 该方法未指定scene_id，获取的是default场景字段的角色信息(批量)
function M.get_player_infos(player_ids, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_infos', chat_log.LOG_LEVEL.LOW, {}, player_ids, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_infos(player_ids, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_infos = ...
            local log_players = player_log_util.simple_player_infos(player_infos)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_players)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法未指定scene_id，获取的是default场景的角色信息(单个)
function M.get_player_info(player_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_info', chat_log.LOG_LEVEL.LOW, {}, player_id, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_info(player_id, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_info = ...
            local log_player = player_log_util.simple_player_info(player_info)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_player)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是default场景字段的角色信息(批量)
function M.get_player_infos_default_scene(player_ids, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_infos_default_scene', chat_log.LOG_LEVEL.LOW, {}, player_ids, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_infos_default_scene(player_ids, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_infos = ...
            local log_players = player_log_util.simple_player_infos(player_infos)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_default_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_players)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_default_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是default场景字段的角色信息(单个)
function M.get_player_info_default_scene(player_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_info_default_scene', chat_log.LOG_LEVEL.LOW, {}, player_id, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_info_default_scene(player_id, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_info = ...
            local log_player = player_log_util.simple_player_info(player_info)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_default_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_player)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_default_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是chat场景字段的角色信息(批量)
function M.get_player_infos_chat_scene(player_ids, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_infos_chat_scene', chat_log.LOG_LEVEL.LOW, {}, player_ids, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_infos_chat_scene(player_ids, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_infos = ...
            local log_players = player_log_util.simple_player_infos(player_infos)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_chat_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_players)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_chat_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是chat场景字段的角色信息(单个)
function M.get_player_info_chat_scene(player_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_info_chat_scene', chat_log.LOG_LEVEL.LOW, {}, player_id, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_info_chat_scene(player_id, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_info = ...
            local log_player = player_log_util.simple_player_info(player_info)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_chat_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_player)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_chat_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是bbs场景字段的角色信息(批量)
function M.get_player_infos_bbs_scene(player_ids, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_infos_bbs_scene', chat_log.LOG_LEVEL.LOW, {}, player_ids, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_infos_bbs_scene(player_ids, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_infos = ...
            local log_players = player_log_util.simple_player_infos(player_infos)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_bbs_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_players)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_bbs_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是bbs场景字段的角色信息(单个)
function M.get_player_info_bbs_scene(player_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_info_bbs_scene', chat_log.LOG_LEVEL.LOW, {}, player_id, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_info_bbs_scene(player_id, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_info = ...
            local log_player = player_log_util.simple_player_info(player_info)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_bbs_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_player)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_bbs_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是friend场景字段的角色信息(批量)
function M.get_player_infos_friend_scene(player_ids, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_infos_friend_scene', chat_log.LOG_LEVEL.LOW, {}, player_ids, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_infos_friend_scene(player_ids, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_infos = ...
            local log_players = player_log_util.simple_player_infos(player_infos)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_friend_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_players)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_infos_friend_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

-- 该方法获取的是friend场景字段的角色信息(单个)
function M.get_player_info_friend_scene(player_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_player_info_friend_scene', chat_log.LOG_LEVEL.LOW, {},player_id, cb)

    -- 内部其实是http，不需要校验登录
    chat_base.get_player_info_friend_scene(player_id, function (succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            local player_info = ...
            local log_player = player_log_util.simple_player_info(player_info)
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_friend_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, log_player)
        else
            chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_player_info_friend_scene', chat_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
        end
    end)
end

function M.ignore(ignore_data, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'ignore', chat_log.LOG_LEVEL.HIGH, {}, ignore_data, cb)

    chat_base.ignore(ignore_data, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'ignore', chat_log.LOG_LEVEL.HIGH, {}, cb,...)
    end)
end

function M.ignore_session(session_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'ignore_session', chat_log.LOG_LEVEL.HIGH, {}, session_id, cb)

    chat_base.ignore_session(session_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'ignore_session', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.ignore_group_types(group_type, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'ignore_group_types', chat_log.LOG_LEVEL.HIGH, {}, group_type, cb)

    chat_base.ignore_group_types(group_type, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'ignore_group_types', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.unignore(unignore_data, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'unignore', chat_log.LOG_LEVEL.HIGH, {}, unignore_data, cb)

    chat_base.unignore(unignore_data, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'unignore', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.unignore_session(session_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'unignore_session', chat_log.LOG_LEVEL.HIGH, {}, session_id, cb)

    chat_base.unignore_session(session_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'unignore_session', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.unignore_group_types(group_type, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'unignore_group_types', chat_log.LOG_LEVEL.HIGH, {}, group_type, cb)

    chat_base.unignore_group_types(group_type, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'unignore_group_types', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.report_msg(report_type_id, report_desc, session_id, msg_id, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'report_msg', chat_log.LOG_LEVEL.LOW, {}, report_type_id, report_desc, session_id, msg_id, cb)

    chat_base.report_msg(report_type_id, report_desc, session_id, msg_id, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'report_msg', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

function M.get_ignore_data()
    chat_log.call_api(chat_log_util.header(), TAG, 'get_ignore_data', chat_log.LOG_LEVEL.LOW, {})

    -- 只是获取缓存，不需要校验登录
    local res = chat_base.get_ignore_data()

    chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'get_ignore_data', chat_log.LOG_LEVEL.LOW, {}, res)
    return res
end

function M.is_ignore_session(session_id)
    chat_log.call_api(chat_log_util.header(), TAG, 'is_ignore_session', chat_log.LOG_LEVEL.LOW, {}, session_id)

    -- 只是缓存判断，不需要校验登录
    local res = chat_base.is_ignore_session(session_id)

    chat_log.call_api_sync_return(chat_log_util.header(), TAG, 'is_ignore_session', chat_log.LOG_LEVEL.LOW, {}, res)

    return res
end

function M.set_global_search_cb(cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'set_global_search_cb', chat_log.LOG_LEVEL.LOW, {}, cb)

    -- 只是设置callback, 不用校验登录状态
    chat_base.set_global_search_cb(cb)
end

function M.global_player_search(search_data, opt, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'global_player_search', chat_log.LOG_LEVEL.LOW, {}, search_data, opt, cb)

    -- 内部其实是http，不是rpc，不用校验登录状态
    chat_base.global_player_search(search_data, opt, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'global_player_search', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

function M.player_search(search_data, opt, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'player_search', chat_log.LOG_LEVEL.LOW, {}, search_data, opt, cb)

    -- 内部其实是http，不是rpc，不用校验登录状态
    chat_base.player_search(search_data, opt, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'player_search', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

function M.get_friend_with_latest_session(cb)
    M.get_friend_with_latest_session_v2('friend', {}, cb)
end

function M.get_friend_with_latest_session_v2(rtype, ext, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_friend_with_latest_session_v2', chat_log.LOG_LEVEL.HIGH, {}, cb)

    -- 会先做http请求，最后调rpc，所以还是需要登录校验的
    chat_base.get_friend_with_latest_session_v2(server.DESTINATION.PLAYER, rtype, ext, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_friend_with_latest_session_v2', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.get_agora_channel_token(group_id, versions, cb)
   chat_base.get_agora_channel_token(group_id, versions, cb)
end

-- 获取账号角色的配置信息
-- 对应配置关联了哪些聊天的全局配置是需要推送的，包括私聊、群聊、系统、客服等
-- https://yuque.antfin.com/ejoy-platform/user_guide/ypgkkl
function M.get_chat_config(cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'get_chat_config', chat_log.LOG_LEVEL.LOW, {}, cb)

    chat_base.get_chat_config(server.DESTINATION.PLAYER, function (...)
        if cb then
            cb(...)
        end
        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'get_chat_config', chat_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

function M.set_chat_config(chat_config, cb)
    chat_log.call_api(chat_log_util.header(), TAG, 'set_chat_config', chat_log.LOG_LEVEL.HIGH, {}, chat_config, cb)

    chat_base.set_chat_config(server.DESTINATION.PLAYER, chat_config, function (...)
        if cb then
            cb(...)
        end

        chat_log.call_api_async_callback(chat_log_util.header(), TAG, 'set_chat_config', chat_log.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

local function callback(handler_name, ...)
    chat_base.callback_destination(server.DESTINATION.PLAYER, handler_name, ...)
end

local function callback_channel(channel, channel_handler_name, ...)
    chat_base.callback_channel(server.DESTINATION.PLAYER, channel, channel_handler_name, ...)
end

local function real_login()
    chat_log.call_api(chat_log_util.header(), TAG, 'login', chat_log.LOG_LEVEL.HIGH, {})

    if get_chat_token_process then
        local stat_key = 'ejoy_chat_server_rpc_call' .. '_' .. 'repeat_login_on_get_chat_token'
        ESTAT.stat_error_with_limit('ejoysdk_chat', stat_key, 'ejoy_chat_server_rpc_call', 'chat_err_repeat_login_on_get_chat_token', {})
        -- -- SDK正在调用get_chat_token
        callback(CALLBACK.HANDLER_NAME.ON_LOGIN, false, CONSTANTS.CHAT_ERROR_CODES.CODE_REPEAT_LOGIN_ON_GET_CHAT_TOKEN, 'repeat login when get chat token')
        return
    end

    if is_login_succ then
        local stat_key = 'ejoy_chat_server_rpc_call' .. '_' .. 'repeat_login_on_succ'
        ESTAT.stat_error_with_limit('ejoysdk_chat', stat_key, 'ejoy_chat_server_rpc_call', 'chat_err_repeat_login_on_succ', {})
        -- 已经登录成功，就别重复调用了
        callback(CALLBACK.HANDLER_NAME.ON_LOGIN, false, CONSTANTS.CHAT_ERROR_CODES.CODE_REPEAT_LOGIN_ON_LOGIN_SUCC, 'repeat login when login succ')

        chat_log.info(chat_log_util.header(), TAG, 'repeat_login_on_login_succ', 'chat_login', {})
        return
    end

    -- 部分项目组在on_connect_lost里调了chat.login()，所以这里由原来的chat_base.init_server() 改成chat_base.retry_connect()更稳妥。因为init_server()就是首次该连接调的方法。
    chat_base.retry_connect()
end

-- 登录失败，尝试重新登录
local function re_login_on_fail()

    E.LOG.debug(TAG, 'chat_connect: re_login_on_fail start')

    --chat_log.info(chat_log_util.header(), TAG, 'start', 're_login_on_fail', {})

    --E.LOG.debug(TAG, 'exec re_login_on_fail')

    local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    local ejoy_token = EG.user_info().token

    local holo = require 'ejoysdk_lua.ejoysdk_holo'
    local token = holo.get_player_token()
    local expire_time = (holo.get_player_token_body() or {}).expire_time or 0

    -- 游戏内注销登录，就不用做重新登录了
    if not ejoy_token or #ejoy_token == 0 or not token or #token == 0 or expire_time < E.time() then
        --E.LOG.debug(TAG, 'ejoy_token失效 或者 moment_token失效，中止自动重新登录')
        --chat_log.info(chat_log_util.header(), TAG, 'token_error', 're_login_on_fail', {})

        -- 需要更新状态
        ET.publish(ET.chat.UPDATE_STATE, STATES.NO_PLAYER_TOKEN)

        return
    end

    -- 以前这里会判断1小时最多重连3次，现在取消这个限制了
    chat_base.retry_connect()
end

local function on_login(ret)
    local log_ret_code
    if ret and ret.code then
        log_ret_code = ret.code
    end
    --chat_log.info(chat_log_util.header(), TAG, 'callback_start', 'on_login_callback', {ret_code = log_ret_code})

    local login_result_params = {
        destination = server.DESTINATION.PLAYER
    }

    local _orig_ret = utils.deepcopy(ret)

    if ret.code == 0 then
        --E.LOG.debug(TAG,'chat server on_login succ')

        E.LOG.debug(TAG, 'chat_connect: check_groups_with_login_result start')

        chat_base.check_groups_with_login_result(server.DESTINATION.PLAYER, ret, function(succ, ...)
            if succ then
                E.LOG.debug(TAG, 'chat_connect: check_groups_with_login_result succ')

                --E.LOG.debug(TAG,'update is_login_succ, value=true, time=check_groups_succ')
                is_login_succ = true

                ET.publish(ET.chat.UPDATE_STATE, STATES.LOGIN_SUCC, login_result_params)

                -- 登录成功，打点groups, 跟踪S3反馈的问题：查看不到游戏内群组问题
                if ret then
                    -- groups不存在 或者 groups的长度为0
                    if not ret.groups or (ret.groups and #ret.groups == 0) then
                        chat_jf.login_result_group_empty({ret_code=log_ret_code})
                    end
                end

                -- 连接成功，把重连时间间隔重置一下，不停服更新导致的重连，才会立即重连
                -- 这里已经跟服务端确认。服务端抖动，或者网络抖动导致的，一会连接成功，一会连接失败，不会对服务器产生更坏的影响，服务器有限流。
                chat_base.reset_retry_connect_index()

                E.LOG.debug(TAG, 'chat_connect: callback on_login succ =====================end')

                callback(CALLBACK.HANDLER_NAME.ON_LOGIN, true, {
                    groups = ret.groups,
                    ignore_data= ret.ignore_data
                })

                if voice.get_curr_channel_id() then
                    --E.LOG.debug(TAG, '聊天登录后, 将实时语音状态同步给聊天服务, voice_status=' .. voice.get_voice_status() .. ', mute_local_value=' .. tostring(voice.get_mute_local_value()))
                    M.set_voice_channel_status(voice.get_curr_channel_id(), voice.get_voice_status(), voice.get_mute_local_value(), voice.get_curr_voice_user_id())
                --else
                    --E.LOG.debug(TAG, '聊天登录后, 没有连实时语音, 无需同步')
                end

                chat_jf.login_succ({})

                --chat_log.info(chat_log_util.header(), TAG, 'chat_login_succ', 'on_login_callback', {})

            else
                E.LOG.debug(TAG, 'chat_connect: check_groups_with_login_result fail')

                --E.LOG.debug(TAG,'update is_login_succ, value=false, time=check_groups_fail')
                is_login_succ = false

                ET.publish(ET.chat.UPDATE_STATE, STATES.LOGIN_FAIL, login_result_params)
                callback(CALLBACK.HANDLER_NAME.ON_LOGIN, false, GET_PLAYER_INFO_FAIL_CODE, GET_PLAYER_INFO_FAIL_MESSAGE)

                chat_jf.login_fail(chat_jf.ACTION.LOGIN_FAIL_CAUSE_BY_CHECK_GROUPS, {ret_code = log_ret_code})

                -- chat_log.debug(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, 'login_fail_on_check_groups', 'on_login_callback', {})
                --chat_log.warn(chat_log_util.header(), TAG, 'chat_login_fail', {code = CONSTANTS.CHAT_ERROR_CODES.CODE_LOGIN_FAIL_ON_CHECK_GROUPS, ret = orig_ret})

                -- 登录失败，尝试重新登录
                re_login_on_fail()
            end
        end)

        -- 登录成功后，获取通用的scene，通用的scene是指那4个官方的场景
        chat_base.get_common_scene()
    else
        --E.LOG.debug(TAG,'update is_login_succ, value=false, time=on_login_fail')
        is_login_succ = false

        --E.LOG.warn(TAG,'chat server on_login fail')
        ET.publish(ET.chat.UPDATE_STATE, STATES.LOGIN_FAIL, login_result_params)
        callback(CALLBACK.HANDLER_NAME.ON_LOGIN, false, ret.code, ret.message or '')

        chat_jf.login_fail(chat_jf.ACTION.LOGIN_FAIL_CAUSE_BY_RPC, {ret_code = log_ret_code})

        -- chat_log.debug(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, 'login_fail_on_ret_code', 'on_login_callback', {ret = orig_ret})

        -- tag, msg, params, _opt
        --chat_log.warn(chat_log_util.header(), TAG, 'chat_login_fail', {code = ret.code, ret = orig_ret})

        -- 登录失败，尝试重新登录
        re_login_on_fail()
    end
end

function M.login()
    -- 这个方法是手动登录的入口方法。增加自动登录的判断，如果是自动登录，就return掉
    if chat_base.auto_login() then
        return
    end
    real_login()
end

function M.logout()
    chat_log.call_api(chat_log_util.header(), TAG, 'logout', chat_log.LOG_LEVEL.HIGH, {})

    --E.LOG.debug(TAG,'update is_login_succ, value=false, time=logout')
    is_login_succ = false
    chat_base.logout()
end

local SERVER_HANDLERS = {}

M.SERVER_HANDLERS = SERVER_HANDLERS

function SERVER_HANDLERS.on_connect_start()
    -- do nothing
end

function SERVER_HANDLERS.on_connect_error(_error_msg)
    --E.LOG.debug(TAG,'update is_login_succ, value=false, time=on_connect_error')
    is_login_succ = false
end

function SERVER_HANDLERS.on_connecting()
    -- do nothing
end

function SERVER_HANDLERS.on_connected()
    --E.LOG.debug(TAG, 'on_connected start login')
    if is_logining then 
        E.LOG.debug(TAG, 'is_logining and return')
        return
    end

    is_logining = true
    chat_base.login(server.DESTINATION.PLAYER, function (...)
        is_logining = false
        on_login(...)
    end)
end

function SERVER_HANDLERS.on_disconnect()
    --E.LOG.debug(TAG,'update is_login_succ, value=false, time=on_disconnect')
    is_login_succ = false
end

function SERVER_HANDLERS.on_connect_lost()
    --E.LOG.debug(TAG,'update is_login_succ, value=false, time=on_connect_lost')
    is_login_succ = false
end

function SERVER_HANDLERS.on_error(_error_msg)
    --E.LOG.debug(TAG,'update is_login_succ, value=false, time=on_error')
    is_login_succ = false
end

local INFO_MSG = {}
M.INFO_MSG = INFO_MSG

function INFO_MSG.chat_msg(msgs)
    callback(CALLBACK.HANDLER_NAME.INFO_CHAT_MSG, msgs)
end

function INFO_MSG.personal_msg(msgs)
    callback(CALLBACK.HANDLER_NAME.INFO_PERSONAL_MSG, msgs)
end

function INFO_MSG.group_msg(msgs)
    callback(CALLBACK.HANDLER_NAME.INFO_GROUP_MSG, msgs)
end

function INFO_MSG.chat_group(msgs)
    chat_base.fill_chat_group_invite_msgs(msgs,function(succ, ...)
        if succ then
            local invite_msgs = ...
            callback(CALLBACK.HANDLER_NAME.INFO_GROUP_INVITED, invite_msgs)
        end
    end)
end

function INFO_MSG.system_chat(msgs)
    callback(CALLBACK.HANDLER_NAME.INFO_SYSTEM_CHAT, msgs)
end

function INFO_MSG.friend(msgs)
    local result = chat_base.process_friend_msgs(msgs)

    if #result.friend_del_msgs > 0 then
        callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_DEL, result.friend_del_msgs)
    end
    if #result.friend_add_msgs > 0 then
        callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_ADD, result.friend_add_msgs)
    end
    if #result.friend_apply_msgs > 0 then
        callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_APPLY, result.friend_apply_msgs)
    end
    if #result.friend_info_change_msgs > 0 then
        callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_INFO_CHANGE, result.friend_info_change_msgs)
    end
end

function INFO_MSG.system(msgs)
    callback(CALLBACK.HANDLER_NAME.INFO_SYSTEM_MSG, msgs)
end

function INFO_MSG.gangplank(msgs)
    callback(CALLBACK.HANDLER_NAME.INFO_GANGPLANK_MSG, msgs)
end

function INFO_MSG.group(groups)
    for _, group in pairs(groups) do
        callback(CALLBACK.HANDLER_NAME.INFO_UPDATE_GROUP, group)
    end
end

local CHAT_HANDLERS = {}
local FRIEND_HANDLERS = {}
local FAVOR_HANDLERS = {}
local SEARCH_HANDLERS = {}
local FOLLOW_HANDLERS = {}
local MAIL_HANDLERS = {}
M.HANDLERS = function(header, msg)
    local method = header.method
    if method then
        if start_with(method, 'friend') then
            local strs = split_string(method, '/')
            local size = #strs
            if size == 4 then
                local handle_type = strs[2] -- channel player
                --local version = strs[3] -- v1.0
                local api = strs[4] -- friend_apply friend_delete
                if type(FRIEND_HANDLERS[api])== 'function' then
                    FRIEND_HANDLERS[api](msg)
                elseif type(FRIEND_HANDLERS[api])== 'table' then
                    if FRIEND_HANDLERS[api][handle_type] then
                        FRIEND_HANDLERS[api][handle_type](msg)
                    end
                end
            end
        elseif start_with(method, 'search') then
            local strs = split_string(method, '/')
            local api = strs[2]
            SEARCH_HANDLERS[api](msg)
        elseif start_with(method, 'favor') then
            local strs = split_string(method, '/')
            local size = #strs
            if size == 4 then
                local handle_type = strs[2] -- channel player
                --local version = strs[3] -- v1.0
                local api = strs[4] -- favor_change
                if type(FAVOR_HANDLERS[api])== 'function' then
                    FAVOR_HANDLERS[api](msg)
                elseif type(FAVOR_HANDLERS[api])== 'table' then
                    if FAVOR_HANDLERS[api][handle_type] then
                        FAVOR_HANDLERS[api][handle_type](msg)
                    end
                end
            end
        elseif start_with(method, 'follow') then
            local strs = split_string(method, '/')
            local size = #strs
            if size == 4 then
                local handle_type = strs[2] -- channel player
                --local version = strs[3] -- v1.0
                local api = strs[4] -- follow_change_info
                if type(FOLLOW_HANDLERS[api])== 'function' then
                    FOLLOW_HANDLERS[api](msg)
                elseif type(FOLLOW_HANDLERS[api])== 'table' then
                    if FOLLOW_HANDLERS[api][handle_type] then
                        FOLLOW_HANDLERS[api][handle_type](msg)
                    end
                end
            end
        elseif method == 'mail_update_push' then
            --奖励邮件推送消息
            MAIL_HANDLERS['mail_update_push'](msg)
        end
    else
        if CHAT_HANDLERS[msg.cmd] then
            CHAT_HANDLERS[msg.cmd](msg)
        else
            CHAT_HANDLERS['on_unhandle'](msg)
        end
    end
end

------------------ CHAT INFO ------------------

function CHAT_HANDLERS.on_unhandle(msg)
    --E.LOG.debug(TAG,'SDK聊天下发 未处理消息: ' .. (msg.cmd or 'empty cmd'))
end

function CHAT_HANDLERS.info_msg(ret)
    -- 这里不用打日志了，所有rpc都会打印的
    -- chat_log.debug(chat_log_util.header(), TAG, 'receive_info_msg', 'receive_info_msg', {ret = ret}, {})

    --E.LOG.debug(TAG,'SDK聊天下发 新消息通知')
    --E.log(ret)

    local msgs = ret.msgs
    chat_base.process_info_msg(msgs, function(result)
        if result.chat_group and #result.chat_group > 0 then
            INFO_MSG['chat_group'](result.chat_group)
        end

        if result.system_chat and #result.system_chat > 0 then
            INFO_MSG['system_chat'](result.system_chat)
        end

        if result.friend and #result.friend > 0 then
            INFO_MSG['friend'](result.friend)
        end

        if result.system and #result.system > 0 then
            INFO_MSG['system'](result.system)
        end

        if result.chat_msg and #result.chat_msg > 0 then
            INFO_MSG['chat_msg'](result.chat_msg)
        end

        if result.personal_msg and #result.personal_msg > 0 then
            INFO_MSG['personal_msg'](result.personal_msg)
        end

        if result.group_msg and #result.group_msg > 0 then
            INFO_MSG['group_msg'](result.group_msg);
        end

        if result.gangplank and #result.gangplank > 0 then
            INFO_MSG['gangplank'](result.gangplank)
        end

        if result.group and #result.group > 0 then
            INFO_MSG['group'](result.group)
        end
    end)
end

function CHAT_HANDLERS.info_offline(msg)
    -- 被顶号后，为了让游戏调用retry_connect时，delay_time恢复成从0s递增，所以需要在这里重置一下retry_connect_index
    chat_base.reset_retry_connect_index()

    ET.publish(ET.chat.UPDATE_STATE, STATES.SERVER_OFFLINE)
    
    -- 这里不用打日志了，所有rpc都会打印的
    --E.LOG.debug(TAG,'update is_login_succ, value=false, time=info_offline')
    is_login_succ = false

    --E.LOG.debug(TAG,'SDK聊天下发 下线通知')
    chat_base.close()
    --E.log(msg)
    callback(CALLBACK.HANDLER_NAME.INFO_OFFLINE, msg.type, msg.msg or '')
end

-- 1. 主动创建群组
-- 2. 被邀请进群组
function CHAT_HANDLERS.info_create_group(msg)
    chat_base.process_create_group_msg(server.DESTINATION.PLAYER, msg, function(replace_group)
        callback(CALLBACK.HANDLER_NAME.INFO_CREATE_GROUP, replace_group)
    end)
end

function CHAT_HANDLERS.info_add_invited_member(msg)
    --E.LOG.debug(TAG,'SDK聊天下发 加入群组邀请')
    chat_base.replace_array_player_before_cb(msg.add_invited_member_infos, function(replace_array)
        callback(CALLBACK.HANDLER_NAME.INFO_ADD_INVITED_MEMBER, msg.group_id, {
            add_invited_member_infos = replace_array
        })
    end)
end

-- 新成员加入时
function CHAT_HANDLERS.info_add_group_member(msg)
    --E.LOG.debug(TAG,'SDK聊天下发 成功加入群组')
    chat_base.replace_array_player_before_cb(msg.add_member_infos , function(replace_array)
        callback(CALLBACK.HANDLER_NAME.INFO_ADD_GROUP_MEMBER, msg.group_id, {
            add_member_infos = replace_array
        })
    end)
end

function CHAT_HANDLERS.info_delete_group(msg)
    chat_base.process_delete_group(server.DESTINATION.PLAYER, msg)
    -- reason: 1. delete_group 2. be_removed
    callback(CALLBACK.HANDLER_NAME.INFO_DELETE_GROUP, msg.group_id, {
        reason = msg.reason,
        message = msg.message or ''
    })
end

function CHAT_HANDLERS.info_update_group(msg)
    --E.LOG.debug(TAG,'SDK聊天下发 群信息 发生改变')

    chat_base.process_update_group(msg, function(replace_group)
        callback(CALLBACK.HANDLER_NAME.INFO_UPDATE_GROUP, replace_group)
    end)
end

function CHAT_HANDLERS.info_voice_channel_user_change(msg)
    --E.LOG.debug(TAG,'SDK聊天下发 实时语音频道用户状态 发生改变')

    chat_base.process_voice_channel_user_change(msg, function(...)
        local change_info = msg or {}
        callback(CALLBACK.HANDLER_NAME.INFO_VOICE_CHANNEL_USER_CHANGE, change_info)
    end)
end

-- 当有人退出群组时，下发消息
-- 1. 被群主踢出 by_owner
-- 2. 主动退出 exit
-- 3. 有人拒绝邀请进入群组 refues_invite
function CHAT_HANDLERS.info_remove_group_member(msg)
    local _remove_type = msg.remove_type
    --E.LOG.debug(TAG,'SDK聊天下发 有用户退出群组, type: ' .. remove_type)

    chat_base.process_remove_group_member(msg, function(...)
        callback(CALLBACK.HANDLER_NAME.INFO_REMOVE_GROUP_MEMBER, msg.group_id, {
            removes = msg.removes,
            remove_type = msg.remove_type,
            message = msg.message or ''
        })
    end)
end

function CHAT_HANDLERS.info_update_session(msg)
    callback(CALLBACK.HANDLER_NAME.INFO_UPDATE_SESSION, msg)
end

------------------ Friend INFO ------------------
FRIEND_HANDLERS.friend_add = {
    channel = function(data)
        local channel = data.user_list[1].channel
        chat_base.process_channel_friend_add(channel, data, function(succ, ...)
            if succ then
                local mix_user_list = ...
                callback_channel(channel, CALLBACK.HANDLER_NAME.CHANNEL_FRIEND_ADD, mix_user_list)
            end
        end)
    end,
    player = function(data)
        chat_base.process_player_friend_add(data, function(succ, ...)
            if succ then
                local add_msgs = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_ADD, add_msgs)
            end
        end)
    end
}

FRIEND_HANDLERS.friend_del = {
    channel = function(data)
        local channel = data.user_list[1].channel
        chat_base.process_channel_friend_del(channel, data, function(succ, ...)
            if succ then
                local mix_user_list = ...
                callback_channel(channel, CALLBACK.HANDLER_NAME.CHANNEL_FRIEND_DEL, mix_user_list)
            end
        end)
    end,
    player = function(data)
        chat_base.process_player_friend_del(data, function(succ, ...)
            if succ then
                local delete_msgs = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_DEL, delete_msgs)
            end
        end)
    end
}

FRIEND_HANDLERS.friend_channel_info_change = function(data)
    local channel = data.user_list[1].channel
    chat_base.process_friend_channel_info_change(channel, data, function(succ, ...)
        if succ then
            local mix_user_list = ...
            callback_channel(channel, CALLBACK.HANDLER_NAME.CHANNEL_FRIEND_INFO_CHANGE, mix_user_list)
        end
    end)
end

FRIEND_HANDLERS.friend_info_change = {
    player = function(data)
        chat_base.process_friend_player_info_change(data, function(succ, ...)
            if succ then
                local info_change_msgs = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_INFO_CHANGE, info_change_msgs)
            end
        end)
    end
}

FRIEND_HANDLERS.friend_apply = {
    player = function(data)
        chat_base.process_friend_player_apply(data, function(succ, ...)
            if succ then
                local apply_msgs = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_APPLY, apply_msgs)
            end
        end)
    end
}

FRIEND_HANDLERS.friend_apply_refuse = {
    player = function(data)
        chat_friend.process_friend_player_apply_refuse(data, function(succ, ...)
            if succ then
                local apply_refuse_msg = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_APPLY_REFUSE, apply_refuse_msg)
            end
        end)
    end
}

FRIEND_HANDLERS.friend_apply_delete = {
    player = function(data)
        chat_friend.process_friend_player_apply_delete(data, function(succ, ...)
            if succ then
                local apply_delete_msg = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FRIEND_APPLY_DELETE, apply_delete_msg)
            end
        end)
    end
}

------------------ Follow INFO ------------------
FOLLOW_HANDLERS.follow_add = {
    player = function(data)
        chat_base.process_player_follow_add(data, function(succ, ...)
            if succ then
                local follow_msg = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FOLLOW_ADD, follow_msg)
            end
        end)
    end
}

FOLLOW_HANDLERS.follow_be_add = {
    player = function(data)
        chat_base.process_player_follow_be_add(data, function(succ, ...)
            if succ then
                local follow_msg = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FOLLOW_BE_ADD, follow_msg)
            end
        end)
    end
}

FOLLOW_HANDLERS.follow_del = {
    player = function(data)
        chat_base.process_player_follow_del(data, function(succ, ...)
            if succ then
                local follow_msg = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FOLLOW_DEL, follow_msg)
            end
        end)
    end
}

FOLLOW_HANDLERS.follow_be_del = {
    player = function(data)
        chat_base.process_player_follow_be_del(data, function(succ, ...)
            if succ then
                local follow_msg = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FOLLOW_BE_DEL, follow_msg)
            end
        end)
    end
}

FOLLOW_HANDLERS.follow_info_change = {
    player = function(data)
        chat_base.process_player_follow_info_change(data, function(succ, ...)
            if succ then
                local follow_msg = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FOLLOW_INFO_CHANGE, follow_msg)
            end
        end)
    end
}
------------------ Favor INFO ------------------
FAVOR_HANDLERS.favor_change = {
    player = function(data)
        chat_base.process_favor_change(data, function(succ, ...)
            if succ then
                local favor_change_msgs = ...
                callback(CALLBACK.HANDLER_NAME.INFO_FAVOR_CHANGE, favor_change_msgs)
            end
        end)
    end
}
SEARCH_HANDLERS.global_search_resp = function(data)
    chat_base.handle_global_search_resp(data)
end

------------------ MAIL INFO ------------------
MAIL_HANDLERS.mail_update_push = function(msgs)
    callback(CALLBACK.HANDLER_NAME.INFO_MAIL_UPDATE_PUSH, msgs)
end

function M.retry_connect()
    chat_base.retry_connect()
end

return M