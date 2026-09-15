--[[
    聊天model层实现
    状态从 0-1-2，1,2状态都可能切到状态0
    0.offline
    1.在线，但数据未同步（get_latest_session未成功）
    2.在线且同步
--]] 

local E = require 'ejoysdk_lua.ejoysdk'
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local EH = require "ejoysdk_lua.ejoysdk_holo"
local Class = require "ejoysdk_lua.ejoysdk_class"
local M = Class:Inherit('chat_model_impl')
local EC = require 'ejoysdk_lua.chat.ejoysdk_chat_base'
local ECS = require 'ejoysdk_lua.chat.ejoysdk_chat_server'
local SOCKET = require "ejoysdk_lua.chat.ejoysdk_chat_socket"
local DISPATCHER = require 'ejoysdk_lua.chat.ejoysdk_chat_push_dispatcher'
local msg_util = require "ejoysdk_lua.chat.export.ejoysdk_chat_msg_util"
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local chat_cahe = require 'ejoysdk_lua.chat.ejoysdk_chat_cache'
local player_info = require 'ejoysdk_lua.player.player_info'
local player_scene = require 'ejoysdk_lua.player.player_info_scene'
local player_cache = require 'ejoysdk_lua.player.player_info_cache'
local chat_session_msg_class = require "ejoysdk_lua.chat.export.ejoysdk_chat_session_msg"
local chat_api = require 'ejoysdk_lua.server_api.ejoysdk_chat_api'
local chat_token = require 'ejoysdk_lua.chat.ejoysdk_chat_token_util'
local chat_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local EM = require "ejoysdk_lua.ejoysdk_module"
local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
local old_chat = require "ejoysdk_lua.chat.ejoysdk_chat"
local CALLBACK = require 'ejoysdk_lua.chat.ejoysdk_chat_callback_manager'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local STATES = require 'ejoysdk_lua.chat.ejoysdk_chat_states'

local TAG = EM.MODULE.CHAT .. 'chat_model_impl'

local get_destination

local chat_model_status = {
    offline = 'offline',     -- 未连接
    online0 = "online0",     -- 已登录，未同步数据
    online1 = "online1"      -- 已登录，已数据同步
}

local rpc_process_type = {
    get_chat_token = 'get_chat_token',
    do_login = "do_login",
    get_latest_session = "get_latest_session",
    init_connect = "init_connect"
}

local MAX_ID = 10000000

--- 初始化
-- 模块初始化接口，创建model层需要的数据结构。
-- @param handler 回调module
-- @param init_param.user_type 用户类型，player/account
-- @param init_param.old_chat_handler 出于兼容性保留，后面要拿掉
-- @return nil
function M:_init(handler, init_param)
    self.user_type = init_param.user_type or "player"
    assert(self.user_type == "player" or self.user_type == "account", "user_type_error")
    self.handler = handler
    self.sessions = {}
    self.session_msgs = {}
    self.msg_send_cache = {}
    self.callback = {}
    self.last_task_id = nil
    self.task_id_counter = 0
    self.status = chat_model_status.offline
    self.groups = {}
    self.get_common_scene_state = 0
    self.rpc_process_time = {}
    self.destroy_flag = false
    self.old_chat_handler = init_param.old_chat_handler or {}
    self:_init_user_info()
    self:_register_handler()
    self:_try_to_login()
    self:_try_get_scene_info()
end

function M:_register_handler()
    -- 这个在unregister_handler有移除
    DISPATCHER.register_server_handlers(self:_get_conn_handler())

    local destination = get_destination(self.user_type)
    local chat_v2_handlers = function(header, msg)
        if self.destroy_flag then
            return
        end

        self:HANDLERS(header, msg)
    end
    self.chat_v2_handlers = chat_v2_handlers
    -- 这个在unregister_handler有移除
    DISPATCHER.register_chat_v2_handlers(destination, chat_v2_handlers)

    -- 这个在unregister_handler有移除
    CALLBACK.register_callback(destination, self.old_chat_handler)

    local gangplank_logout_handler = function()
        if self.destroy_flag then
            return
        end

        self:_gangplank_logout_handler()
    end
    self.gangplank_logout_handler = gangplank_logout_handler
    -- 这个在unregister_handler有移除
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)

    local gangplank_exit_handler = function()
        if self.destroy_flag then
            return
        end

        self:_gangplank_exit_handler()
    end
    self.gangplank_exit_handler = gangplank_exit_handler
    -- 这个在unregister_handler有移除
    ET.subscribe(ET.gangplank.EXIT, gangplank_exit_handler)

    local player_offline_handler = function()
        if self.destroy_flag then
            return
        end

        self:_player_offline_handler()
    end
    self.player_offline_handler = player_offline_handler
    -- 这个在unregister_handler有移除
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, player_offline_handler)
end

function M:_unregister_handler()
    local destination = get_destination(self.user_type)
    DISPATCHER.unregister_server_handlers(self:_get_conn_handler())
    DISPATCHER.unregister_chat_v2_handlers(destination)
    CALLBACK.unregister_callback(destination)
    ET.unsubscribe(ET.gangplank.LOGOUT, self.gangplank_logout_handler)
    ET.unsubscribe(ET.gangplank.EXIT, self.gangplank_exit_handler)
    ET.unsubscribe(ET.gangplank.PLAYER_OFFLINE, self.player_offline_handler)
end

function M:destroy()
    E.LOG.d(TAG, '聊天准备-destroy, destroy_flag=' .. tostring(self.destroy_flag))

    ECS.close()

    if not self.destroy_flag then
        self.destroy_flag = true

        self.groups = {}
        self.sessions = {}
        self.session_msgs = {}
        self:_unregister_handler()
    end
end

function M:_gangplank_logout_handler()
    E.LOG.d(TAG, '聊天准备-gangplank_logout')

    chat_token.reset_token_data()

    self:destroy()
end

function M:_gangplank_exit_handler()
    E.LOG.d(TAG, '聊天准备-gangplank_exit')

    chat_token.reset_token_data()

    self:destroy()
end

function M:_player_offline_handler()
    E.LOG.d(TAG, '聊天准备-player_offline')

    chat_token.reset_token_data()

    self:destroy()
end

function M:_get_conn_handler()
    return {
        on_connect_error = function() self:_on_connect_error() end,
        on_connected = function() self:_on_connected() end,
        on_disconnect = function() self:_on_disconnect() end,
        on_error = function() self:_on_error() end
    }
end

-- 尝试聊天登录
function M:_try_to_login()
    if not EG.user_info().uid or #(EG.user_info().uid) == 0 then
        E.LOG.e(TAG, 'account not login try login')
        return
    end

    if not EH.get_player_token() or #(EH.get_player_token()) == 0 then
        E.LOG.e(TAG, 'player_token not exist try login')
        return
    end

    if chat_token.is_chat_token_valid() then
        self:_do_connect_when_needed()
        self:_do_login()
    else
        self:_get_chat_token()
    end
end

--[[
    尝试获取scene_info，聊天会用到chat、default场景，scene_info会影响到player_info的获取
    聊天内部很多replace_player_info方法会获取player_info

    0:表示默认状态
    1:表示正在获取中
    2:表示获取成功
    -1:表示获取失败
--]]
function M:_try_get_scene_info()
    if self.get_common_scene_state == 2 or self.get_common_scene_state == 1 then
        return
    end

    self.get_common_scene_state = 1
    E.Timer.once(10, function()
        -- 10s后如果还是进行中，就强制置为失败
        if self.get_common_scene_state == 1 then
            self.get_common_scene_state = -1
        end
    end)

    local scene_ids = {player_scene.OFFICIAL_SCENE.CHAT,
                       player_scene.OFFICIAL_SCENE.DEFAULT}
    player_scene.get_scene_infos(scene_ids, function(succ, ...)
        if succ then
            self.get_common_scene_state = 2
        else
            self.get_common_scene_state = -1
        end
    end)
end

function M:_on_connect_error()
    if self.destroy_flag then
        return
    end
    
    self.rpc_process_time[rpc_process_type.init_connect] = nil

    E.LOG.d(TAG, '聊天准备-连接错误')
    self:_on_offline()
end

function M:_on_disconnect()
    if self.destroy_flag then
        return
    end

    self.rpc_process_time[rpc_process_type.init_connect] = nil

    E.LOG.d(TAG, '聊天准备-连接断开')
    self:_on_offline()
end

function M:_on_error()
    if self.destroy_flag then
        return
    end

    self.rpc_process_time[rpc_process_type.init_connect] = nil

    E.LOG.d(TAG, '聊天准备-遇到错误')
    self:_on_offline()
end

function M:_on_offline()
    self:_update_status(chat_model_status.offline)
end

function M:_on_connected()
    if self.destroy_flag then
        return
    end

    self.rpc_process_time[rpc_process_type.init_connect] = nil
    
    E.LOG.d(TAG, '聊天准备-连接成功')
    -- 连接创建好，可以尝试登录了。
    self:_do_login()
end

function M:_update_status(status_value)

    if status_value == chat_model_status.online0 then
        E.LOG.d(TAG, '聊天准备-聊天已登录')
    elseif status_value == chat_model_status.online1 then
        E.LOG.d(TAG, '聊天准备-聊天已同步')
    else
        E.LOG.w(TAG, '聊天准备-已下线')
    end

    if self.status == 'offline' and E.Utils.start_with(status_value, 'online') then
        self.handler:info_chat_state('online')
    elseif status_value == 'offline' then
        self.handler:info_chat_state('offline')
    end

    self.status = status_value
end

function M:_do_connect_when_needed()
    if next(self.rpc_process_time) then
        E.LOG.d(TAG, 'rpc_process_time >>')
        E.LOG.d(TAG, self.rpc_process_time)
        return
    end

    -- 要判空，否则ECS.init会报错
    if not EG.player_info() or #(EG.player_info().player_id) == 0 then
        return
    end

    -- nil 是只有连接不存在时，正在尝试也不是nil
    if ECS.get_conn_status() then
        return
    end

    self.rpc_process_time[rpc_process_type.init_connect] = os.time()
    E.LOG.d(TAG, '聊天准备-新建连接...')
    ECS.init(EG.player_info(), false)
end

function M:_get_chat_token()
    if next(self.rpc_process_time) then
        E.LOG.d(TAG, 'rpc_process_time >>')
        E.LOG.d(TAG, self.rpc_process_time)
        return
    end

    E.LOG.d(TAG, '聊天准备-获取token...')
    self.rpc_process_time[rpc_process_type.get_chat_token] = os.time()
    chat_api.get_chat_token(function(...)
        self:_get_chat_token_cb(...)
    end)
end

function M:_get_chat_token_cb(succ, ...)
    E.LOG.d(TAG, '聊天准备-获取token结束, succ=' .. tostring(succ))
    self.rpc_process_time[rpc_process_type.get_chat_token] = nil
    if succ then
        local data = ...
        chat_token.update_token_data(data)
    end
end


function M:clear_rpc_process_time()
    self.rpc_process_time = {}
end

function M:_do_login()
    if next(self.rpc_process_time) then
        E.LOG.d(TAG, 'rpc_process_time >>')
        E.LOG.d(TAG, self.rpc_process_time)
        return
    end

    if chat_token.is_chat_token_valid() and ECS.get_conn_status() == SOCKET.CHAT_CONNECTED then
        E.LOG.d(TAG, '聊天准备-登录中...')

        self.rpc_process_time[rpc_process_type.do_login] = os.time()
        local destination = get_destination(self.user_type)
        ECS.login(destination, function(ret)
            self:_do_login_cb(ret)
        end)
    end
end

function M:_do_login_cb(ret)
    E.LOG.d(TAG, '聊天准备-登录结束, succ=' .. tostring(ret.code == 0))
    self.rpc_process_time[rpc_process_type.do_login] = nil
    if ret.code == 0 then
        self:_update_status(chat_model_status.online0)
        self:_process_group_on_login(ret)

        local destination = get_destination(self.user_type)
        local login_result_params = {
            destination = destination
        }
        ET.publish(ET.chat.UPDATE_STATE, STATES.LOGIN_SUCC, login_result_params)
    end
end

function M:_merge_group(groups)
    local adds = {}
    local updates = {}
    for _, v in ipairs(groups) do
        local group_id = v.group_id
        if self.groups[group_id] == nil then
            adds[group_id] = v
        else
            updates[group_id] = v
        end
        self.groups[group_id] = v
    end
    return {adds= adds, updates=updates, removes={}}
end

-- 初始化 自己的信息, 后续很多地方会用到 self.user_id
function M:_init_user_info()
    if "player" ~= self.user_type and "account" ~= self.user_type then
        ESTAT.stat_error_with_limit(TAG, 'chat_err_init_user_info_error', 'init_user_info_error', 'chat_err', {msg='user_type invalid'})
        return
    end

    if self.user_type == "player" then
        if EG.player_info() and EG.player_info().player_id then
            self.user_id = EG.player_info().player_id
        else
            E.LOG.e(TAG, 'player_id not exist')
        end
    elseif self.user_type == "account" then
        if EG.user_info() and EG.user_info().uid then
            local account_id = EG.user_info().uid
            self.user_id = "acc_" .. account_id
        else
            E.LOG.e(TAG, 'uid not exist')
        end
    end

    if self.user_id and #(self.user_id) > 0 then
        local key = _ejoysdk_crypt.hashkey(tostring(self.user_id))
        self.USER_ID_HASH = _ejoysdk_crypt.hexencode(key)

        local ids = {}
        player_info.classify_ids(ids, self.user_id)
        player_info.batch_get_infos(ids, {scene='chat'}, function (succ, ...)
            if not succ then
                chat_log.warn(chat_log_util.header(), TAG, 'get_my_user_info_fail', {}, {})
            end
        end)
    end
end

function M:add_callback(task_id, func)
    -- 不能覆盖
    if task_id == nil or task_id ~= self.last_task_id then
        -- log error here
        return false
    end
    self.callback[task_id] = func
    return true
end

function M:get_latest_session()
    if next(self.rpc_process_time) then
        E.LOG.d(TAG, 'rpc_process_time >>')
        E.LOG.d(TAG, self.rpc_process_time)
        return
    end

    E.LOG.d(TAG, '聊天准备-同步会话...')

    local destination = get_destination(self.user_type)
    self.rpc_process_time[rpc_process_type.get_latest_session] = os.time()
    ECS.get_latest_session(destination, function(ret)
        if ret.code == 0 and ret.sessions then
            EC.replace_latest_sessions_user_info_before_cb(ret.sessions, function(replaced_sessions)
                ret.sessions = replaced_sessions
                self:_get_latest_session_cb(ret)
            end, function ()
                self:_get_latest_session_cb({code=CONSTANTS.CHAT_ERROR_CODES.CODE_FILL_PLAYER_INFO_FAIL, message="get_player_info_failed"})
            end)
        else
            self:_get_latest_session_cb(ret)
        end
    end)
end

function M:_get_latest_session_cb(ret)
    E.LOG.d(TAG, '聊天准备-同步会话结束, succ=' .. tostring(ret.code == 0))
    self.rpc_process_time[rpc_process_type.get_latest_session] = nil
    if ret.code == 0 and ret.sessions then
        self:_update_status(chat_model_status.online1)
        local merge_session_ret = self:_merge_session(ret.sessions)
        local adds = merge_session_ret.adds
        local updates = merge_session_ret.updates
        self:_info_chat_session_change(adds, updates, {})
    end
end

function M:tick()
    if self.destroy_flag then
        E.LOG.e(TAG, 'chat_model has destroy, please new instance')
        return
    end

    -- 应该由ejoysdk来调。在抽离连接层的时候做
    ECS.tick()
    if next(self.rpc_process_time) then
        E.LOG.d(TAG, 'rpc_process_time >>')
        E.LOG.d(TAG, self.rpc_process_time)
        return
    end
    if self.status == chat_model_status.offline then
        -- 断连
        self:_try_to_login()
    elseif self.status == chat_model_status.online0 then
        -- 已登录，未同步，需要同步一下
        self:get_latest_session()
    end
end

function M:get_session_msg(iter_data, search_direction, max_msg_count)
    local task_id = self:get_task_id()

    local destination = get_destination(self.user_type)
    local params = {}
    params.session_id = iter_data.session_id
    params.search_direction = search_direction
    params.max_msg_count = max_msg_count
    params.ts = iter_data.ts
    params.msg_id = iter_data.msg_id
    params.cmd = "get_session_msg"
    ECS.rpc_call(destination, params, function(ret)
        self:_get_session_msg_cb(task_id, params.session_id, ret)
    end)

    return task_id
end

function M:_get_session_msg_cb(task_id, session_id, ret)
    if ret.code == 0 and ret.msgs and next(ret.msgs) ~= nil then
        local msgs = ret.msgs

        EC.replace_msgs_user_info_before_cb(msgs, function(replace_msg)
            table.sort(replace_msg, msg_util.smaller)
            self:update_session_msgs(session_id, replace_msg)

            E_UTILS.reset_deepcopy_only_once_record()
            self:_info_chat_rpc_result(task_id, "get_session_msg", ret)
        end, function()
            table.sort(msgs, msg_util.smaller)
            self:update_session_msgs(session_id, msgs)

            E_UTILS.reset_deepcopy_only_once_record()
            self:_info_chat_rpc_result(task_id, "get_session_msg", ret)
        end)
    end
end

--- 获得会话id
--- @param user_id string 目标用户id
function M:get_to_user_session_id(user_id)
    local user_id1, user_id2 = self.user_id, user_id
    if user_id1 > user_id2 then
        user_id1, user_id2 = user_id2, user_id1
    end

    return string.format("%s:%s", user_id1, user_id2)
end


--- 发送消息
-- 发送富文本接口。不提供文本接口，推荐使用富文本。
-- @param session_id 会话id
-- @param data 发送数据
-- @param data.text 发送原始富文本
-- @param data.extend_data 拓展数据，平台不进行检测
-- @param data.plain_text 消息的纯文本化展示。
-- 不传会通过去掉html标签获得消息纯文本展示，如果希望自己控制，可以传入此参数。
-- 可用于系统推送等场景。
-- @return task_id 用于callback
function M:send_rich_text(session_id, data, at_list)
    local content = {
        type = "rich_text",
        plain_text = data.plain_text,
        data = {
            text = data.text,
            extend_data = data.extend_data
        }
    }

    return self:send("send_rich_text", session_id, content, at_list) 
end

function M:send(task_name, session_id, content, at_list)
    local task_id = self:get_task_id()

    local destination = get_destination(self.user_type)
    local params = {}
    params.session_id = session_id
    params.send_id = ECS.send_id()
    params.content = content
    params.cmd = 'send'
    if at_list and type(at_list) == 'table' and next(at_list) ~= nil then
        params.at_list = at_list or {}
    end
    local mock_msg = self:_create_mock_msg(params)

    self.msg_send_cache[params.send_id] = params

    ECS.rpc_call(destination, params, function(ret)
        self:_send_cb(task_id, task_name, mock_msg, ret)
    end)
    self:update_session_msgs(session_id, {mock_msg})

    return task_id
end

function M:_send_cb(task_id, task_name, mock_msg, ret)
    self:_info_chat_rpc_result(task_id, task_name, ret)
    -- 失败后，改变消息为失败状态
    if ret.code == 0 then
        self.msg_send_cache[mock_msg.send_id] = nil
    else
        if mock_msg then
            mock_msg.reader_status = msg_util.msg_status().failed
            self:update_session_msgs(mock_msg.session_id, {mock_msg})
        end
    end
end

function M:resend(_send_id)
    local params = self.msg_send_cache[_send_id] or {}
    return self:send("resend", params.session_id, params.content, params.at_list)
end

function M:create_to_user_session(to_id)
    local task_id = self:get_task_id()

    local session_id = self:get_to_user_session_id(to_id)
    self:_create_mock_session_by_session_id(session_id, function (succ, ...)
        if succ then
            local session = ...

            self:_create_to_user_session_cb(true, task_id, session)

            local merge_session_ret = self:_merge_session({session})
            local adds = merge_session_ret.adds
            local updates = merge_session_ret.updates
            self:_info_chat_session_change(adds, updates, {})
        else
            self:_create_to_user_session_cb(false, task_id, {code=-1, msg='create to user session fail'})
        end
    end)

    return task_id
end

function M:_create_to_user_session_cb(_succ, task_id, ret)
    self:_info_chat_rpc_result(task_id, "create_to_user_session", ret)
end

function M:set_msg_received(session_id, received_ts)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)
    local req = {session_id=session_id, received_ts=received_ts}

    local params = {}
    params.session_id = session_id
    params.received_ts = received_ts
    params.cmd = 'set_msg_received'

    ECS.rpc_call(destination, params, function(ret)
        self:_set_msg_received_cb(task_id, ret, req)
    end)

    return task_id
end

function M:_set_msg_received_cb(task_id, ret, req)
    local session_id = req.session_id
    local received_ts = req.received_ts
    self:_info_chat_rpc_result(task_id, "set_msg_received", ret)
    if ret.code ~= 0 then
        return
    end
    local msg_status_constant = msg_util.msg_status()
    local session_msg = self.session_msgs[session_id]
    if session_msg ~= nil then
        -- 找到第一个已读消息
        local idx = session_msg:_find_idx_from_back(function(msg)
            return msg.reader_status == msg_status_constant.user_received
        end)
        local msgs = session_msg:get_msg_by_range(idx + 1, nil)
        local unread_before = self:_get_session_unread_count(msgs)
        local change_msgs = {}
        -- 遍历未读的消息，如果已读时间戳会将消息变为已读。
        -- 给予变化通知
        for _, msg in ipairs(msgs) do
            if msg.reader_status == msg_status_constant.server_received and msg.src_id ~= self.user_id then
                if received_ts == nil or received_ts >= msg.ts then
                    msg.reader_status = msg_status_constant.user_received
                    table.insert(change_msgs, msg)
                end
            end
        end
        local unread_after = self:_get_session_unread_count(msgs)
        if next(change_msgs) ~= nil then
            local session_type = EC.get_session_type(session_id).type
            self:_info_chat_msgs(session_type, session_id, change_msgs)
            local old_session_data = self.sessions[session_id]
            if old_session_data ~=nil and old_session_data.session_info.unread > 0 then
                -- 为了以防万一，比如撤回了老消息，让unread减1没处理
                -- 如果设置整个会话已读。未读强制设成0
                if received_ts == nil then
                    self:_set_session_unread(session_id, 0)
                else
                    self:_add_session_unread(session_id, unread_after - unread_before)
                end
                local updates = {[session_id] = old_session_data}
                self:_info_chat_session_change({}, updates, {})
            end
        end
    end
end

function M:create_group(members, invite_msg, info)
    assert(info ~= nil, 'info is nil')
    assert(info.name ~= nil, 'info.name is nil')

    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    members = members or {}
    if #members == 0 then
        -- 不添加的话，lua 转 json 会是一个 object，但服务端的 members 字段只认 array
        table.insert(members, self.user_id)
    end

    local params = {}
    params.members = members
    params.invite_msg = invite_msg
    params.info = info
    params.cmd = "create_group"

    ECS.rpc_call(destination, params, function (ret)
        self:_create_group_cb(task_id, ret)
    end)

    return task_id
end

function M:_create_group_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "create_group", ret)
end

function M:add_group_member(adds, invite_msg, group_id)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.adds = adds
    params.invite_msg = invite_msg
    params.group_id = group_id
    params.cmd = 'add_group_member'

    ECS.rpc_call(destination, params, function (ret)
        self:_add_group_member_cb(task_id, ret)
    end)

    return task_id
end

function M:_add_group_member_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "add_group_member", ret)
end

function M:reply_add_group_member(reply_msg, is_agree, group_id)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.reply_msg = reply_msg
    params.is_agree = is_agree
    params.group_id = group_id
    params.cmd = 'reply_add_group_member'

    ECS.rpc_call(destination, params, function (ret)
        self:_reply_add_group_member_cb(task_id, ret)
    end)

    return task_id
end

function M:_reply_add_group_member_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "reply_add_group_member", ret)
end

function M:remove_group_member(removes, remove_msg, group_id)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.removes = removes
    params.message = remove_msg
    params.group_id = group_id
    params.cmd = 'remove_group_member'
    ECS.rpc_call(destination, params, function (ret)
        self:_remove_group_member_cb(task_id, ret)
    end)

    return task_id
end

function M:_remove_group_member_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "remove_group_member", ret)
end

-- 更新群组属性接口, 目前客户端只可以修改名字 info.name
function M:update_group(info, group_id)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.info = info
    params.group_id = group_id
    params.cmd = 'update_group'
    ECS.rpc_call(destination, params, function (ret)
        self:_update_group_cb(task_id, ret)
    end)

    return task_id
end

function M:_update_group_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "update_group", ret)
end

function M:delete_group(group_id)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.group_id = group_id
    params.cmd = 'delete_group'
    ECS.rpc_call(destination, params, function (ret)
        self:_delete_group_cb(task_id, ret)
    end)

    return task_id
end

function M:_delete_group_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "delete_group", ret)
end

function M:exit_group(group_id)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.group_id = group_id
    params.cmd = 'exit_group'
    ECS.rpc_call(destination, params, function (ret)
        self:_exit_group_cb(task_id, ret)
    end)

    return task_id
end

function M:_exit_group_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "exit_group", ret)
end

function M:get_group_be_invited_history()
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.cmd = 'get_group_be_invited_history'
    ECS.rpc_call(destination, params, function (ret)
        self:_get_group_be_invited_history_cb(task_id, ret)
    end)

    return task_id
end

function M:_get_group_be_invited_history_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "get_group_be_invited_history", ret)
end

function M:report_msg(report_type_id, report_desc, session_id, msg_id)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.cmd = 'report_msg'
    params.report_type_id = report_type_id
    params.report_desc = report_desc
    params.session_id = session_id
    params.msg_id = msg_id
    ECS.rpc_call(destination, params, function (ret)
        self:_report_msg_cb(task_id, ret)
    end)

    return task_id
end

function M:_report_msg_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "report_msg", ret)
end

function M:get_chat_config()
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    params.cmd = 'get_chat_config'
    ECS.rpc_call(destination, params, function (ret)
        self:_get_chat_config_cb(task_id, ret)
    end)

    return task_id
end

function M:_get_chat_config_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "get_chat_config", ret)
end

function M:set_chat_config(chat_config)
    local task_id = self:get_task_id()
    local destination = get_destination(self.user_type)

    local params = {}
    local safe_chat_config = chat_config
    local safe_push_config = chat_config.push
    if safe_push_config ~= nil then
        local group_types = safe_push_config.push_on_group_types
        -- 空table默认处理成array
        if group_types and next(group_types) == nil then
            local JSON = require "ejoysdk_lua.ejoysdk_json"
            group_types = JSON.newArray()
            safe_push_config.push_on_group_types = group_types
            safe_chat_config.push = safe_push_config

            -- 标记如果是cjson的数组需要encode成array
            params.ejoysdk_pack_data_options = { encode_empty_array = true }
        end
    end
    params.config = safe_chat_config
    params.cmd = 'set_chat_config'

    ECS.rpc_call(destination, params, function (ret)
        self:_set_chat_config_cb(task_id, ret)
    end)

    return task_id
end

function M:_set_chat_config_cb(task_id, ret)
    self:_info_chat_rpc_result(task_id, "set_chat_config", ret)
end

function M:update_session_msgs(session_id, msgs)
    local session_type = EC.get_session_type(session_id).type
    if next(msgs) == nil then
        -- 如果拉到了空消息，只需要通知消息更新。
        self:_info_chat_msgs(session_type, session_id, msgs)
        return
    end

    -- 验证这一点，以防万一
    for idx = 2, #msgs do
       local v = msgs[idx]
       assert(session_id == v.session_id, "update_session_msgs but session_id not the same")
    end
    local session_adds = {}
    local session_updates = {}

    local function exe_handler()
        -- 1. 通知会话更新
        if next(session_adds) ~= nil or next(session_updates) ~= nil then
            self:_info_chat_session_change(session_adds, session_updates, {})
        end
        -- 2. 通知消息更新
        self:_info_chat_msgs(session_type, session_id, msgs)
        -- 3. 存储会话消息
        self.session_msgs[session_id] = self.session_msgs[session_id] or chat_session_msg_class:New()
        local session_msg = self.session_msgs[session_id]
        session_msg:merge_msgs(msgs)
        local session_msg_count = session_msg:count()
        local max_msg_count = 50
        if session_msg_count > max_msg_count then
            -- 只保留最近的消息。避免内存无限暴涨。
            -- 超出多少条，就删除多少条。
            session_msg:delete_msg_by_range(1, max_msg_count - session_msg_count)
        end
    end

    if self.sessions[session_id] == nil then
        -- 这里要创建好和 get_latest_session 一致的数据结构
        self:_create_mock_session_by_msgs(msgs, function (_succ, mock_session)
            -- todo: succ为false， mock_session里的用户信息是获取失败的
            self.sessions[session_id] = mock_session
            session_adds[session_id] = mock_session

            exe_handler()
        end)
    else
        local orig_last_msg = self.sessions[session_id].last_msgs[1]
        -- 看看是否发生了变化
        -- 1. get_session_msg 是降序排列，所以第一个最大
        -- 2. 本地构造的消息，一次只有一个
        -- 3. 直接比较消息是否更老就好。
        local new_last_msg = msgs[1]

        if not orig_last_msg or msg_util.smaller(orig_last_msg, new_last_msg) or orig_last_msg.send_id == new_last_msg.send_id then
            self.sessions[session_id].last_msgs = {msgs[#msgs]}
            session_updates[session_id] = self.sessions[session_id]
        end

        exe_handler()
    end
end

--[[
    session结构的示例：https://yuque.antfin.com/ejoy-platform/ejoy-platform/bswpaa#bByms
--]]
function M:_create_mock_session_by_msgs(msgs, cb)
    local ret = {}

    table.sort(msgs, msg_util.smaller)
    local last_msg = msgs[#msgs]
    ret.last_msgs = {last_msg}

    local session_info = {}
    session_info.id = msgs[1].session_id
    session_info.unread = self:_get_session_unread_count(msgs)
    session_info.is_ignore = EC.is_ignore_session(msgs[1].session_id) or false
    ret.session_info = session_info

    local session_type = EC.get_session_type(session_info.id)
    if session_type.type == EC.TYPE_GROUP then
        ret.session_info.info = self.groups[session_info.id]
    end

    --[[
        session_type.type == EC.TYPE_PERSONAL的情况
        调replace_latest_sessions_user_info_before_cb之后，会补充 ret.session_info._info
    --]]
    EC.replace_latest_sessions_user_info_before_cb({ret}, function (sessions)
        cb(true, sessions[1])
    end, function()
        cb(false, ret)
    end)
end

function M:_create_mock_session_by_session_id(session_id, cb)

    local ret = {}

    ret.last_msgs = {}

    local session_info = {}
    session_info.id = session_id
    session_info.unread = 0
    session_info.is_ignore = EC.is_ignore_session(session_id) or false
    ret.session_info = session_info

    local session_type = EC.get_session_type(session_info.id)
    if session_type.type == EC.TYPE_GROUP then
        ret.session_info.info = self.groups[session_info.id]
    end

    --[[
        session_type.type == EC.TYPE_PERSONAL的情况
        调replace_latest_sessions_user_info_before_cb之后，会补充 ret.session_info._info
    --]]
    EC.replace_latest_sessions_user_info_before_cb({ret}, function (sessions)
        cb(true, sessions[1])
    end, function()
        cb(false, ret)
    end)
end

function M:_create_session_by_group(group)
    local ret = {}

    local session_info = {}
    session_info.unread = 0
    session_info.id = group.group_id
    session_info.info = group
    session_info.is_ignore = chat_cahe.is_ignore_session(group.group_id) or false

    ret.session_info = session_info
    ret.last_msgs = {}

    local session_type = EC.get_session_type(session_info.id)
    if session_type.type == EC.TYPE_GROUP then
        ret.session_info.info = self.groups[session_info.id] or {}
    else
        ESTAT.stat_error_with_limit(TAG, 'chat_err_create_session_by_group_fail', 'chat_err_create_session_by_group_fail', 'chat_err', {msg='session_type info type data invalid'})
    end

    return ret
end

function M:_create_mock_msg(data)
    assert(data.session_id, 'create_mock_msg fail, session_id is nil')
    assert(data.content, 'create_mock_msg fail, content is nil')
    assert(data.send_id, 'create_mock_msg fail, send_id is nil')

    local ret = {}
    ret.is_ignore = EC.is_ignore_session(data.session_id) or false
    local session_type_info = EC.get_session_type(data.session_id) or {}
    if session_type_info.type == EC.TYPE_PERSONAL then
        ret.to_id = session_type_info.from
        ret.src_id = session_type_info.my_chat_user_id
    elseif session_type_info.type == EC.TYPE_GROUP then
        ret.to_id = data.session_id
        ret.src_id = self.user_id
    else
        assert(false, '其他场景，还没测试，待补充')
    end

    ret.content_id = nil -- content_id就是msg_id
    ret.msg_id = nil
    ret.send_id = data.send_id
    ret.ts = os.time()
    ret.src_type = 'user'
    ret.src_info = {}
    ret.session_id = data.session_id
    ret.reader_status = msg_util.msg_status().sending
    ret.content = data.content
    ret.delete_msg_members = {}
    ret.at_list = {}

    if self.user_type == "player" then
        ret.src_info = player_cache.get_player_info_with_ignore_expire_time(EG.player_info().player_id, 'chat')
    elseif self.user_type == "account" then
        ret.src_info = player_cache.get_account_info_with_ignore_expire_time(EG.user_info().uid)
    end

    return ret
end

-- 把msgs2 合并到 msgs1
function M:_merge_msgs(msgs1, msgs2)
    for _, msg_in2 in pairs(msgs2) do
        table.insert(msgs1, msg_in2)
    end
    table.sort(msgs1, msg_util.smaller)
    return msgs1
end

function M:_merge_session(sessions2)
    local adds = {}
    local updates = {}
    for _, v in ipairs(sessions2) do
        local session_id = v.session_info.id
        if self.sessions[session_id] == nil then
            adds[session_id] = v
        else
            updates[session_id] = v
        end

        self.sessions[session_id] = v
    end
    return {adds= adds, updates=updates}
end

-- start of handlers function
function M:HANDLERS(header, body)
    E_UTILS.reset_deepcopy_only_once_record()

    local cmd = "_" .. (body.cmd or '')
    if body.cmd then
        chat_log.debug(
                chat_log_util.header(),
                TAG,
                'HANDLERS',
                'HANDLERS',
                {cmd=body.cmd},
                {}
        )

        local func = M[cmd]
        if func ~= nil and type(func) == 'function' then
            func(self, header, body)
        else
            self:_default_handler(header, body, cmd)
        end
    elseif header.method then
        old_chat.HANDLERS(header, body)
    else
        chat_log.warn(
                chat_log_util.header(),
                TAG,
                'HANDLERS_unknown_type',
                {},
                {}
        )
    end
end

function M:_default_handler(_header, _body, cmd)
    chat_log.warn(
            chat_log_util.header(),
            TAG,
            'exec_default_handler',
            {cmd=cmd},
            {}
    )
end

function M:_info_msg(_header, body)
    if not body then
        return
    end

    if not body.msgs then
        return
    end

    if next(body.msgs) == nil then
        return
    end

    local session_id = body.msgs[1].session_id
    -- 收到服务器回调时，增加 unread count
    -- 以 get_latest_session 获取的 unread 作为基准
    -- 考虑如下的情况：
    -- 1. recall 之前的未读老消息。不会造成 unread 变化。（bug）
    -- 2. 新消息通知。会造成 unread 变化。

    EC._msgs_player_to_cache(body.msgs)

    EC.replace_msgs_user_info_before_cb(body.msgs, function(replace_msg)
        local unread = self:_get_session_unread_count(replace_msg)
        self:_add_session_unread(session_id, unread)
        self:update_session_msgs(session_id, replace_msg)
    end, function()
        local unread = self:_get_session_unread_count(body.msgs)
        self:_add_session_unread(session_id, unread)
        self:update_session_msgs(session_id, body.msgs)
    end)
end

--[[
    info_create_group的body数据: https://yuque.antfin.com/ejoy-platform/ejoy-platform/bswpaa#SOPoY
    group的session数据: https://yuque.antfin.com/ejoy-platform/ejoy-platform/bswpaa#IyA38
--]]
function M:_info_create_group(_header, body)
    self:_process_groups_on_change({body.group})
end

--[[
    info_update_group的body数据：https://yuque.antfin.com/ejoy-platform/ejoy-platform/bswpaa#rmdOI
--]]
function M:_info_update_group(_header, body)
    self:_process_groups_on_change({body.group})
end

--[[
    _info_delete_group的body结构
    table: 0x74e09dcec0 {
       ["reason"] => "delete_group"
       ["group_id"] => "group_test_srpc_qiu_chat_model"
       ["cmd"] => "info_delete_group"
    }
--]]
function M:_info_delete_group(_header, body)
    local group_id = body.group_id
    local orig_group = self.groups[group_id]
    self.groups[group_id] = nil

    local removes = {[group_id]=orig_group}
    self:_info_group_changes({}, {}, {[group_id]=orig_group})

    self:_sync_session_for_group({}, {}, removes)
end

--[[
    _info_add_group_member的body：https://yuque.antfin.com/ejoy-platform/ejoy-platform/bswpaa#SOPoY
--]]
function M:_info_add_group_member(_header, body)
    self:_process_group_on_add_member_infos(body.group_id, body.add_member_infos)
end

--[[
    _info_remove_group_member的body的结构如下：
    table: 0x74e09c2240{
       ["remove_type"] => "by_server"
       ["cmd"] => "info_remove_group_member"
       ["group_id"] => "group_test_srpc_qiu_chat_model"
       ["removes"] => table: 0x74e09c2280{
          [1] => "EE2FBB36CF4C56E95FA1FA6EC0C9BFF1"
       }
       ["message"] => ""
    }
--]]
function M:_info_remove_group_member(_header, body)
    self:_process_group_on_remove_member_infos(body.group_id, body.removes)
end

-- todo: 待确认
function M:_info_add_invited_member(_header, _body)
end

function M:_info_chat_session_change(adds, updates, removes)

    local adds_session_id = {}
    for k,_ in pairs(adds) do
        table.insert(adds_session_id, k)
    end
    local updates_session_id = {}
    for k,_ in pairs(updates) do
        table.insert(updates_session_id, k)
    end
    local removes_session_id = {}
    for k,_ in pairs(removes) do
        table.insert(removes_session_id, k)
    end

    chat_log.debug(
            chat_log_util.header(),
            TAG,
            '_info_chat_session_change',
            '_info_chat_session_change',
            {
                adds=adds_session_id,
                updates=updates_session_id,
                removes=removes_session_id
            },
            {}
    )

    self.handler:info_chat_session_change(E_UTILS.deepcopy_only_once(adds),
        E_UTILS.deepcopy_only_once(updates),
        E_UTILS.deepcopy_only_once(removes)
    )
end

function M:_info_chat_msgs(session_type, session_id, msgs)

    local log_msgs = {}
    for _, v in pairs(msgs) do
        table.insert(log_msgs,
                {
                    msg_id = v.msg_id,
                    send_id = v.send_id,
                    session_id = v.session_id
                }
        )
    end

    chat_log.debug(
            chat_log_util.header(),
            TAG,
            '_info_chat_msgs',
            '_info_chat_msgs',
            {
                session_type=session_type,
                session_id=session_id,
                msgs=log_msgs
            },
            {}
    )

    self.handler:info_chat_msgs(session_type, session_id, E_UTILS.deepcopy_only_once(msgs))
end

function M:_info_group_changes(adds, updates, removes)

    local adds_group_id = {}
    for k,_ in pairs(adds) do
        table.insert(adds_group_id, k)
    end
    local updates_group_id = {}
    for k,_ in pairs(updates) do
        table.insert(updates_group_id, k)
    end
    local removes_group_id = {}
    for k,_ in pairs(removes) do
        table.insert(removes_group_id, k)
    end

    chat_log.debug(
            chat_log_util.header(),
            TAG,
            '_info_group_changes',
            '_info_group_changes',
            {
                adds=adds_group_id,
                updates=updates_group_id,
                removes=removes_group_id
            },
            {}
    )

    self.handler:info_group_changes(E_UTILS.deepcopy_only_once(adds),
        E_UTILS.deepcopy_only_once(updates),
        E_UTILS.deepcopy_only_once(removes)
    )
end

function M:_info_chat_rpc_result(task_id, task_name, rpc_result)

    chat_log.debug(
            chat_log_util.header(),
            TAG,
            '_info_chat_rpc_result',
            '_info_chat_rpc_result',
            {
                task_id=task_id,
                task_name=task_name,
                code=rpc_result.code,
                msg=rpc_result.msg
            },
            {}
    )

    local to_user_rpc_result = E_UTILS.deepcopy_only_once(rpc_result)
    local callback = self.callback[task_id]
    if type(callback) == "function" then
        callback(task_id, task_name, to_user_rpc_result)
    end
    self.callback[task_id] = nil
    self.handler:info_chat_rpc_result(task_id, task_name, to_user_rpc_result)
end

function M:get_task_id()
    self.task_id_counter = (self.task_id_counter + 1) % MAX_ID
    local counter = string.format("%.8d", self.task_id_counter)
    local task_id = tostring(os.time()) .. self.USER_ID_HASH .. counter
    self.last_task_id = task_id
    return task_id
end

function get_destination(user_type) 
    if user_type == "account" then
        return "acc_chat"
    else
        return "chat"
    end
end

-- start of group process tool
function M:_process_group_on_login(ret)
    if not ret.groups or next(ret.groups) == nil then
        return
    end

    EC.replace_groups_user_info(ret.groups, function (replace_groups)
        local merge_res = self:_merge_group(replace_groups)
        local has_change = next(merge_res.adds) ~= nil or next(merge_res.updates) ~= nil or next(merge_res.removes) ~= nil
        if has_change then
            self:_info_group_changes(merge_res.adds, merge_res.updates, merge_res.removes)
        end
    end)
end

function M:_process_groups_on_change(groups)
    EC.replace_groups_user_info(groups, function (replace_groups)
        local merge_res = self:_merge_group(replace_groups)
        local has_change = next(merge_res.adds) ~= nil or next(merge_res.updates) ~= nil or next(merge_res.removes) ~= nil
        if has_change then
            self:_info_group_changes(merge_res.adds, merge_res.updates, merge_res.removes)
            self:_sync_session_for_group(merge_res.adds, merge_res.updates, merge_res.removes)
        end
    end)
end

function M:_process_group_on_add_member_infos(group_id, add_member_infos)
    EC.replace_array_player_before_cb(add_member_infos , function(replace_array)
        local orig_group = self.groups[group_id]
        orig_group.member_infos = orig_group.member_infos or {}

        local member_infos_map = {}
        for _, v in pairs(orig_group.member_infos) do
            member_infos_map[v.user_id] = true
        end

        -- 做去重
        for _,v in pairs(replace_array) do
            if not member_infos_map[v.user_id] then
                table.insert(orig_group.member_infos, v)
            end
        end

        local updates = {[group_id]=orig_group}

        self:_info_group_changes({}, updates, {})

        self:_sync_session_for_group({}, updates, {})
    end)
end

function M:_process_group_on_remove_member_infos(group_id, remove_member_infos)
    if not group_id or #group_id == 0 then
        return
    end

    if not remove_member_infos or #remove_member_infos == 0 then
        return
    end

    local removes_map = {}
    for _,v in pairs(remove_member_infos) do
        removes_map[v] = true
    end

    local orig_group = self.groups[group_id]
    orig_group.member_infos = orig_group.member_infos or {}
    local remove_member_info_idx = {}
    for k, v in pairs(orig_group.member_infos) do
        if removes_map[v.user_id] then
            table.insert(remove_member_info_idx, k)
        end
    end

    -- 降序排序
    table.sort(remove_member_info_idx, function(a,b)return (a> b) end)
    for _,idx in pairs(remove_member_info_idx) do
        table.remove(orig_group.member_infos, idx)
    end

    local updates = {[group_id] = orig_group}

    self:_info_group_changes({}, updates, {})

    self:_sync_session_for_group({}, updates, {})
end

function M:_sync_session_for_group(adds_g, updates_g, removes_g)

    local adds, updates, removes = {}, {}, {}

    for group_id, group in pairs(adds_g) do
        if not self.sessions[group_id] then
            local session = self:_create_session_by_group(group)
            self.sessions[group_id] = session
            adds[group_id] = session
        else
            local session = self.sessions[group_id]
            session.session_info.info = group
            updates[group_id] = session
        end
    end

    for group_id, group in pairs(updates_g) do
        if not self.sessions[group_id] then
            local session = self:_create_session_by_group(group)
            self.sessions[group_id] = session
            adds[group_id] = session
        else
            local session = self.sessions[group_id]
            session.session_info.info = group
            updates[group_id] = session
        end
    end

    for group_id, _ in pairs(removes_g) do
        if self.sessions[group_id] then
            local session = self.sessions[group_id]
            self.sessions[group_id] = nil
            removes[group_id] = session
        end
    end

    self:_info_chat_session_change(adds, updates, removes)
end

-- 每次更新消息前，对比unread的差值。
function M:_get_session_unread_count(msgs)
    local msg_status_constant = msg_util.msg_status()
    local unread = 0
    for _, msg in pairs(msgs) do
        if msg.reader_status == msg_status_constant.server_received and msg.src_id ~= self.user_id then
            unread = unread + 1
        end
    end

    return unread
end

function M:_add_session_unread(session_id, unread)
    local session = self.sessions[session_id]
    if session ~= nil then
        local new_unread = math.max(session.session_info.unread + unread, 0)
        self:_set_session_unread(session_id, new_unread)
    end
end

function M:_set_session_unread(session_id, unread)
    local session = self.sessions[session_id]
    if session ~= nil then
        session.session_info.unread = unread
    end
end

return M
