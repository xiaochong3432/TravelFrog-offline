local E = require "ejoysdk_lua.ejoysdk"
local EH = require "ejoysdk_lua.ejoysdk_holo"
local ECS = require "ejoysdk_lua.chat.ejoysdk_chat_socket"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local DISPATCHER = require 'ejoysdk_lua.chat.ejoysdk_chat_push_dispatcher'
local PACK = require 'ejoysdk_lua.chat.ejoysdk_chat_data_pack'
local compat = require 'ejoysdk_lua.compat.ejoysdk_compat'
local string_pack, string_unpack, xpcall = compat.string.pack, compat.string.unpack, compat.xpcall
local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
local CALLBACK = require 'ejoysdk_lua.chat.ejoysdk_chat_callback_manager'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local chat_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local rpc_opentracing = require 'ejoysdk_lua.chat.ejoysdk_chat_rpc_opentracing'
local EM = require "ejoysdk_lua.ejoysdk_module"
local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
local utils = require "ejoysdk_lua.ejoysdk_utils"
local chat_jf = require 'ejoysdk_lua.chat.ejoysdk_chat_jf'
local chat_token = require 'ejoysdk_lua.chat.ejoysdk_chat_token_util'

local TAG = EM.MODULE.CHAT .. 'server'

local LAST_SERVER_PORT_STORE = E.LazyKeyStore:New('CHAT_SERVER_LAST_PORT_NUM', false, false, false)

local M = {}

local CHAT_SOCKET = nil

-- 服务端聊天多端口
local DEFAULT_SERVER_PORTS = {
    12345,
    443,
    80,
}

local current_chat_server_port = 0
local current_chat_server_port_arr = DEFAULT_SERVER_PORTS
local current_server_port_idx = 1
local need_add_port_idx = false

local function init_with_server_ports_config()
    local chat_config = EGC.get_current_chat_config()
    local ports = DEFAULT_SERVER_PORTS
    if chat_config and chat_config[EGC.CONFIG_KEY.KEY_CHAT_PORTS] and next(chat_config[EGC.CONFIG_KEY.KEY_CHAT_PORTS]) ~= nil then
        --E.LOG.debug(TAG, "init_server_ports_data has chat config, override local ports")
        ports = chat_config[EGC.CONFIG_KEY.KEY_CHAT_PORTS]
    end

    --E.LOG.debug(TAG, "init_server_ports_data ports >>")
    --E.log(ports)
    return ports
end

local function init_server_port()
    current_chat_server_port_arr = init_with_server_ports_config()

    local last_server_port_str = LAST_SERVER_PORT_STORE:get()
    local last_server_port = 0
    if last_server_port_str and type(last_server_port_str) == 'string' and #last_server_port_str > 0 then
        --E.LOG.debug(TAG, "init_server_port, last_server_port:"..tostring(last_server_port_str))
        last_server_port = tonumber(last_server_port_str)
    end

    local is_port_valid = false
    if last_server_port and last_server_port > 0 then
        for _, port in ipairs(current_chat_server_port_arr) do
            if port == last_server_port then
                is_port_valid = true
            end
        end
    end

    if is_port_valid then
        current_chat_server_port = last_server_port
    else
        current_chat_server_port = current_chat_server_port_arr[current_server_port_idx]
    end
end

local function next_server_port()
    if need_add_port_idx then
        current_server_port_idx = current_server_port_idx + 1
        need_add_port_idx = false
    end
    if current_server_port_idx > #current_chat_server_port_arr then
        current_server_port_idx = 1
    end
    --_ejoysdk.log('next_server_port: ' .. tostring(current_server_port_idx))
    return current_chat_server_port_arr[current_server_port_idx]
end

function M.get_server_port()
    return current_chat_server_port_arr[current_server_port_idx]
end

local function on_server_port_fail()
    need_add_port_idx = true
    LAST_SERVER_PORT_STORE:set('')
end

function M.get_server()
    local server = {
        addr = M.get_server_addr(),
        port = next_server_port(),
        socket_type = "TCP"
    }

    E.LOG.debug(TAG, "chat server url:" .. server.addr)

    return server
end

function M.get_conn_status()
    if CHAT_SOCKET == nil then
        return nil
    else
        return CHAT_SOCKET:get_status() 
    end
end

-- 返回值table, 字段如下
-- result.addr
-- result.port
-- result.socket_type
function M.get_curr_socket_server()
    if CHAT_SOCKET then
        return  CHAT_SOCKET:get_server() or {}
    end

    return {}
end

function M.get_server_addr()
    local product = E.CONFIG.get_config("product"):lower()

    local server_name
    local chat_config = EGC.get_current_chat_config()
    if chat_config and chat_config[EGC.CONFIG_KEY.KEY_HOST] then
        server_name = chat_config[EGC.CONFIG_KEY.KEY_HOST]
    else
        local region = E.CONFIG.get_config("region")
        local splice_rules = E.CONFIG.get_splice_rules()
        local region_rule = splice_rules[E.CONFIG.RULE_KEY.RULE_REGION]
        if region and region_rule == E.CONFIG.URL_REGION_SPLICE_RULE.RULE_DEFAULT then
            region = '-' .. region:lower()
        else
            region = ''
        end

        server_name = product .. region .. "-chat-tcpclient" .. EGC.server_domain_suffix()
    end
    return server_name
end

M.DESTINATION = {
    PLAYER = 'chat',
    ACCOUNT = 'acc_chat',
    BADGE = 'badge' --红点
}

local PLAYER_INFO = nil

local MAX_ID = 10000000
local TRACE_ID = 0
local SEND_ID = 0
local PLAYER_ID_HASH = ""

-- TODO : 心跳还要注意锁屏的问题
local heart_beat_running = false -- TODO : 避免断线重连后，多个重复心跳。更好实现是断线时取消时钟，不过 Native 层接口还没做
local heart_beat_interval = 60 -- 心跳发送间隔，单位：秒
local heart_beat_timeout_count = 0
local heart_beat_max_timeout_count = 5 -- 最多允许连续10次心跳超时

local RPC_CBS = {}

local function on_connect_start()
    --chat_log.info(chat_log_util.header(), TAG, 'on_connect_start', 'socket_connect', {}, {})
    DISPATCHER.on_connect_start()
end

local function on_connect_error(error_msg, error_code)
    chat_jf.connect_fail({err_msg = error_msg or 'nil', err_code = error_code or -1})

    --chat_log.info(chat_log_util.header(), TAG, 'on_connect_error', 'socket_connect', {error_msg=error_msg}, {})

    CHAT_SOCKET = nil
    on_server_port_fail()
    DISPATCHER.on_connect_error(error_msg)
end

local function on_connecting()
    --chat_log.info(chat_log_util.header(), TAG, 'on_connecting', 'socket_connect', {}, {})
    DISPATCHER.on_connecting()
end

local function on_connected()
    --chat_log.info(chat_log_util.header(), TAG, 'on_connected', 'socket_connect', {}, {})

    -- data pack重置
    PACK.reset()

    current_chat_server_port = current_chat_server_port_arr[current_server_port_idx]
    local port_str = tostring(current_chat_server_port)
    --E.LOG.debug(TAG, "on_connected update current port:"..port_str)
    LAST_SERVER_PORT_STORE:set(port_str)

    DISPATCHER.on_connected()
end

local function on_disconnect()
    --chat_log.info(chat_log_util.header(), TAG, 'on_disconnect', 'socket_connect', {}, {})

    CHAT_SOCKET = nil
    DISPATCHER.on_disconnect()
end

local function on_error(error_msg, error_code)
    chat_log.info(chat_log_util.header(), TAG, 'on_error', 'socket_connect', {error_msg=error_msg, error_code=error_code}, {})

    CHAT_SOCKET = nil
    on_server_port_fail()
    DISPATCHER.on_error(error_msg, error_code)
end

local function heart_beat()
    if not CHAT_SOCKET or CHAT_SOCKET:get_status() ~= CHAT_SOCKET.CHAT_CONNECTED then
        heart_beat_running = false
        return
    end

    -- fix: cb一定要传, 防止底层不判空，直接调
    -- 新增心跳超时的逻辑，连续超时5次，就主动断开
    M.rpc_chat({ cmd = 'heartbeat' }, function (ret)
        if ret.code ~= 0 then
            if ret.code == CONSTANTS.RPC_ERROR_CODES.CODE_TIMEOUT then
                heart_beat_timeout_count = heart_beat_timeout_count + 1

                chat_log.warn(chat_log_util.header(), TAG, 'heart_beat_timeout', {code=ret.code, msg=ret.msg, timeout_count=heart_beat_timeout_count})

                if heart_beat_timeout_count >= heart_beat_max_timeout_count then

                    if CHAT_SOCKET then
                        CHAT_SOCKET:close()
                    end

                    on_error('heartbeat_timeout', CONSTANTS.RPC_ERROR_CODES.CODE_TIMEOUT)

                    heart_beat_timeout_count = 0
                end
            else
                chat_log.warn(chat_log_util.header(), TAG, 'heart_beat_error', {code=ret.code, msg=ret.msg})
            end
        else
            heart_beat_timeout_count = 0
        end
    end)
    E.Timer.once(heart_beat_interval, function()
        heart_beat()
    end)

    heart_beat_running = true
end

local function parse_plaintext_recv(recv)
    local lines = E.Utils.split_string(recv, '\n')
    if lines then
        local first_line = lines[1]
        local first_line_splits = E.Utils.split_string(first_line, ' ')
        if #first_line_splits > 1 then
            local second_split = first_line_splits[2]
            local res = tonumber(second_split)
            return res or CONSTANTS.CHAT_ERROR_CODES.CODE_SERVER_PLAINTEXT_CODE_FIRST_LINE_MISS
        end
    end
    return CONSTANTS.CHAT_ERROR_CODES.CODE_SERVER_PLAINTEXT_CODE_EMPTY
end

local function cmd_rpc_receive(content_data)
    if content_data and content_data.msg then
        return content_data.msg.cmd or ''
    end

    return ''
end

-- 对特定的RPC，可以调高日志等级
local function log_level_rpc_receive(_content_data)
    return chat_log.LOG_LEVEL.LOW
end

-- 一些很长的rpc_receive是需要自定义打印的
local function should_custom_log_rpc_receive(content_data)
    local cmd = cmd_rpc_receive(content_data)
    local should = false
    if cmd == 'get_latest_session' then
        should = true
    elseif cmd == 'get_session_msg' then
        should = true
    elseif cmd == 'info_msg' then
        should = true
    elseif cmd == 'login' then
        should = true
    end

    return should
end

-- 一些很长的rpc_receive是需要自定义打印的
local function custom_log_rpc_receive(content_data)
    local cmd = cmd_rpc_receive(content_data)
    if cmd == 'get_latest_session' then
        local copy_content_data = utils.deepcopy(content_data)
        copy_content_data.msg.sessions = nil
        local log_session_ids
        if content_data.msg and content_data.msg.sessions then
            log_session_ids = chat_log_util.session_ids(content_data.msg.sessions) or {}
        end
        copy_content_data.msg.log_session_ids = log_session_ids
        chat_log.rpc_receive(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, copy_content_data, {})
    elseif cmd == 'get_session_msg' then
        local copy_content_data = utils.deepcopy(content_data)
        copy_content_data.msg.msgs = nil
        local log_msg_infos = {}
        if content_data.msg and content_data.msg.msgs then
            log_msg_infos = chat_log_util.simple_msg_infos(content_data.msg.msgs)
        end
        local log_msg_infos_by_section = chat_log.list_by_section(log_msg_infos, 4)

        for _,section in pairs(log_msg_infos_by_section) do
            copy_content_data.msg.log_msg_section = section
            chat_log.rpc_receive(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, copy_content_data, {})
        end
    elseif cmd == 'info_msg' then
        local copy_content_data = utils.deepcopy(content_data)
        copy_content_data.msg.msgs = nil
        local log_msg_infos = {}
        if content_data.msg and content_data.msg.msgs then
            log_msg_infos = chat_log_util.simple_msg_infos(content_data.msg.msgs)
        end
        local log_msg_infos_by_section = chat_log.list_by_section(log_msg_infos, 4)

        for _,section in pairs(log_msg_infos_by_section) do
            copy_content_data.msg.log_msg_section = section
            chat_log.rpc_receive(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, copy_content_data, {})
        end
    elseif cmd == 'login' then
        local copy_content_data = utils.deepcopy(content_data)
        copy_content_data.msg.groups = nil
        local log_groups = {}
        if content_data.msg and content_data.msg.groups then
            log_groups = chat_log_util.simple_group_infos(content_data.msg.groups)
        end
        local log_groups_by_section = chat_log.list_by_section(log_groups, 3)

        for _,section in pairs(log_groups_by_section) do
            copy_content_data.msg.log_group_section = section
            chat_log.rpc_receive(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, copy_content_data, {})
        end
    end
end

-- 一些很长的rpc_send是需要自定义打印的, 聊天内容因为隐私需要，也不能打印
local function should_custom_log_rpc_send(content_data)
    local cmd = ''
    if content_data.content_body and content_data.content_body.cmd then
        cmd = content_data.content_body.cmd
    end

    local should = false

    if cmd == 'send' then
        should = true
    elseif cmd == 'login' then
        should = true
    end

    return should
end

-- 一些很长的rpc_send是需要自定义打印的
local function custom_log_rpc_send(content_data)

    local cmd = ''
    if content_data.content_body and content_data.content_body.cmd then
        cmd = content_data.content_body.cmd
    end

    if cmd == 'send' then
        local copy_content_data = utils.deepcopy(content_data)
        -- 隐私合规的原因，日志里，不能包含聊天内容
        if copy_content_data.content_body and copy_content_data.content_body.content then
            copy_content_data.content_body.content = nil
        end

        chat_log.rpc_send(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, copy_content_data, {})
    elseif cmd == 'login' then
        chat_log.rpc_send(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.HIGH, content_data, {})
    end
end

-- 只有登录是10s，其他rpc是5s
local function rpc_timeout_config(cmd)
    if cmd and cmd == 'login' then
        return 10
    else
        return 5
    end
end

local function on_message(recv)
    if recv == "" then
        return false
    end
    local ok, pack, n = xpcall(string_unpack, function (x)
        chat_log.warn(chat_log_util.header(),
                TAG,
                'string_unpack_error',
                {
                    lua_error_msg = tostring(x)
                },
                {})

    end,">s4", recv)

    if not ok then
        local error_code = parse_plaintext_recv(recv)
        chat_log.warn(chat_log_util.header(), TAG, 'parse_plaintext_recv_error', {err_code=CONSTANTS.CHAT_ERROR_CODES.CODE_PARSE_PLAINTEXT_RECV, detail_err_code=error_code, err_msg='parse_plaintext_recv_error'})
        --E.LOG.debug(TAG, 'parse_plaintext_recv, error_code=' .. tostring(error_code))
        return false, error_code
    end

    local header, msg
    ok, header, msg = PACK.unpack_data(pack)

    local content_data = {header=header, msg=msg}
    if should_custom_log_rpc_receive(content_data) then
        custom_log_rpc_receive(content_data)
    else
        local log_level = log_level_rpc_receive(content_data)
        chat_log.rpc_receive(chat_log_util.header(), TAG, log_level, content_data, {})
    end

    if not ok then
        -- 包体解密解析失败
        if CHAT_SOCKET then
            CHAT_SOCKET:close()
        end
        local _error_msg = header
        --E.log('pack decrypt fail msg: ' .. tostring(error_msg))
        on_error('pack decrypt fail')
        return false, -1
    end
    local session = header.session
    local cb = RPC_CBS[session]
    utils.reset_deepcopy_only_once_record()
    if cb then
        RPC_CBS[session] = nil
        xpcall(cb, function (x)
            chat_log.warn(chat_log_util.header(),
                    TAG,
                    'rpc_callback_exe_error',
                    {
                        err_code=CONSTANTS.RPC_ERROR_CODES.CODE_CALLBACK_EXE_ERROR,
                        lua_error_msg = tostring(x)
                    },
                    {}
            )

            -- 把异常抛给游戏侧方便他们统计，debug调试
            local notify_succ, notify_error = pcall(CALLBACK.callback, 'chat', CALLBACK.HANDLER_NAME.ON_HANDLERS_ERROR, '', x)  -- x前面的参数是堆栈，为了性能，现在不抓堆栈了
            if not notify_succ then
                chat_log.warn(chat_log_util.header(), TAG, 'chat_notify_cp_error', {notify_error=notify_error}, {})
            end
        end, msg)
    else
        DISPATCHER.handle_message(header, msg)
    end

    return true, n
end

local destination_rpc_call_handlers_cache = {}
function M.unregister_rpc_call_handlers(destination)
    --E.LOG.debug(TAG, 'unregister_rpc_call_handlers, destination:'..(destination or 'nil'))
    destination_rpc_call_handlers_cache[destination] = nil
end

function M.register_rpc_call_handlers(destination, rpc_call_handlers)
    M.unregister_rpc_call_handlers(destination)
    --E.LOG.debug(TAG, 'register_rpc_call_handlers, destination:'..(destination or 'nil'))
    destination_rpc_call_handlers_cache[destination] = rpc_call_handlers
end

local function init_server(player_info, token_changed)
    local safe_token_changed = token_changed or false

    math.randomseed(os.time())
    TRACE_ID = math.random(MAX_ID)
    SEND_ID = math.random(MAX_ID)

    PLAYER_INFO = player_info

    local key = _ejoysdk_crypt.hashkey(tostring(player_info.player_id))
    PLAYER_ID_HASH = _ejoysdk_crypt.hexencode(key)

    -- 初始化data pack
    PACK.init()

    init_server_port()

    M.run_socket()

    -- 如果token发生变化，scoket要重置400的错误计数，因为400的错误，大概率是token校验不过导致的。既然token都变化了，所以计数当然要重置回去
    if CHAT_SOCKET and safe_token_changed then
        CHAT_SOCKET:reset_400_count()
    end
end

function M.init(player_info, token_changed)
    E.LOG.debug(TAG, 'chat_connect: chat_server init start')

    xpcall(init_server, function (x)

        E.LOG.debug(TAG, 'chat_connect: chat_server init has lua_error')

        local msg = 'init_server_error'
        on_connect_error(msg)

        -- 7010006
        chat_log.warn(chat_log_util.header(),
                TAG,
                'init_server_fail',
                {
                    err_code=CONSTANTS.CHAT_ERROR_CODES.CODE_INIT_SERVER_FAIL,
                    err_msg = msg,
                    lua_error_msg = tostring(x)  -- lua虚拟机抛出来的错误信息
                },
                {}
        )

    end, player_info, token_changed)
end

function M.close()
    if CHAT_SOCKET then
        CHAT_SOCKET:close()
    end
end

function M.run_socket(_connect_handlers)
    if CHAT_SOCKET then
        CHAT_SOCKET:close()
        CHAT_SOCKET = nil
    end
    CHAT_SOCKET = ECS:New(M.get_server(), {
        on_connect_start = on_connect_start,
        on_connect_error = on_connect_error,
        on_connected = on_connected,
        on_disconnect = on_disconnect,
        on_error = on_error,
        on_message = on_message,
        on_connecting = on_connecting
    })
    CHAT_SOCKET:run()
end

function M.tick()
    if CHAT_SOCKET then
        CHAT_SOCKET:tick()
    end
end

local function trace_id()
    TRACE_ID = (TRACE_ID + 1) % MAX_ID
    return TRACE_ID
end

local function send_id()
    SEND_ID = (SEND_ID + 1) % MAX_ID
    local counter = string.format("%.8d", SEND_ID)
    return tostring(os.time()) .. PLAYER_ID_HASH .. counter
end
M.send_id = send_id

local function get_extra_header()

    local extra_header_list = {}

    if chat_token.curr_login_version == chat_token.LOGIN_V2 then
        -- E.LOG.debug(TAG, '聊天登录协议V2:协议格式')
        -- 聊天登录V2协议
        local server_version = 1
        table.insert(extra_header_list, string_pack('B', server_version))
        table.insert(extra_header_list, string_pack('B', #(PLAYER_INFO.player_id)))
        table.insert(extra_header_list, PLAYER_INFO.player_id)

        table.insert(extra_header_list, string_pack('B', #(chat_token.get_chat_token() or '')))
        table.insert(extra_header_list, chat_token.get_chat_token() or '')
    else
        -- E.LOG.debug(TAG, '聊天登录协议V1:协议格式')
        -- 聊天登录V1协议
        local server_version = 0
        table.insert(extra_header_list, string_pack('B', server_version))
        local expire_time = 0
        if EH.get_player_token_body() then
            expire_time = EH.get_player_token_body().expire_time
        else
            E.LOG.debug(TAG, 'ejoy_chat_server_get_extra_header, ' .. 'token_is_nil')
            ESTAT.stat_fatal_error("ejoy_chat_server_get_extra_header", 'chat_err_token_is_nil')
        end
        table.insert(extra_header_list, string_pack('>I4', expire_time))
        table.insert(extra_header_list, string_pack('B', #PLAYER_INFO.player_id))
        table.insert(extra_header_list, PLAYER_INFO.player_id)
        table.concat(extra_header_list)
    end

    local rpc_header = table.concat(extra_header_list)
    return rpc_header
end

-- 历史问题，RPC的调用错误码是-1，区分不出具体的错误，所以msg需要抽出来，做成常量，不做随意的变更
local RPC_ERROR_MSG = {
    SOCKET_NOT_INIT = 'socket not init',
    TOKEN_MISS = 'token miss',
    SOCKET_NOT_CONNECTED = 'socket not connected',
    CALL_RPC_ON_NOT_LOGIN = 'call rpc on not login',
    TIME_OUT = 'time out'
}

function M.rpc_call(destination, params, cb)
    if not CHAT_SOCKET then
        chat_log.warn(chat_log_util.header(), TAG, 'chat_rpc_call_fail_socket_not_init', {code = -1, msg = 'socket_not_init'} , {})
        --E.LOG.debug(TAG, 'ejoy_chat_server_rpc_call, ' .. 'socket_not_init')
        ESTAT.stat_fatal_error("ejoy_chat_server_rpc_call", 'chat_err_socket_not_init')

        if cb then
            cb({
                code = -1,
                message = RPC_ERROR_MSG.SOCKET_NOT_INIT
            })
        end
        return
    end

    -- 没登录，就别发送rpc了
    if not EH.get_player_token_body() then

        chat_log.warn(chat_log_util.header(), TAG, 'chat_rpc_call_fail_token_is_nil', {code = -1, msg = 'token_is_nil'} , {})

        --E.LOG.debug(TAG, 'ejoy_chat_server_rpc_call, ' .. 'token_is_nil')
        ESTAT.stat_fatal_error("ejoy_chat_server_rpc_call", 'chat_err_token_is_nil')

        if cb then
            cb({
                code = -1,
                message = RPC_ERROR_MSG.TOKEN_MISS
            })
        end
        return
    end

    if CHAT_SOCKET:get_status() ~= CHAT_SOCKET.CHAT_CONNECTED then

        chat_log.warn(chat_log_util.header(), TAG, 'chat_rpc_call_fail_socket_not_connected', {code = -1, msg = 'socket_not_connected'} , {})

        --E.LOG.debug(TAG, 'ejoy_chat_server_rpc_call, ' .. 'socket_not_connected')
        ESTAT.stat_fatal_error("ejoy_chat_server_rpc_call", 'chat_err_socket_not_connected')

        if cb then
            cb({
                code = -1,
                message = RPC_ERROR_MSG.SOCKET_NOT_CONNECTED
            })
        end
        return
    end

    if params.cmd ~= 'login' then
        local handlers = destination_rpc_call_handlers_cache[destination]
        if handlers and handlers['on_check_rpc_call_start'] then
            if not handlers.on_check_rpc_call_start() then
                -- 说明条件不具备，当前不能调这个rpc
                --E.LOG.debug(TAG, 'ejoy_chat_server_rpc_call, not_login, destination=' .. destination .. ', cmd=' .. params.cmd)

                chat_log.warn(chat_log_util.header(), TAG, 'chat_rpc_call_fail_check_rpc_call_start', {code = CONSTANTS.CHAT_ERROR_CODES.CODE_NOT_LOGIN, msg = 'check_rpc_call_start'} , {})


                local stat_key = destination .. '_' .. (params.cmd or '')
                ESTAT.stat_error_with_limit('ejoysdk_chat_server', stat_key, 'ejoy_chat_server_rpc_call', 'chat_err_rpc_before_login', nil)

                if cb then
                    cb({
                        code = CONSTANTS.CHAT_ERROR_CODES.CODE_NOT_LOGIN,
                        message = RPC_ERROR_MSG.CALL_RPC_ON_NOT_LOGIN
                    })
                end

                return
            end
        end
    end

    -- 有几个比较特殊的协议，需要空数组的jsonencode，但luajon和luacjson处理空table的方式不同，需要传递给json库处理
    local ejoysdk_pack_data_options = params.ejoysdk_pack_data_options
    -- body里面的去掉
    params.ejoysdk_pack_data_options = nil

    local next_trace_id = trace_id()
    local session = next_trace_id

    -- 开启opentracing
    if not params._opentracing then
        params._opentracing = {span_buz=params.cmd}
    end
    local opentracing = params._opentracing
    local net_span
    if opentracing then
        net_span = rpc_opentracing.RPC.start_rpc_span('RPC', params.cmd, params)
    end

    if cb then
        local cb_wraper = function(...)
            -- 结束opentracing
            if opentracing and net_span then
                local info=...
                rpc_opentracing.RPC.stop_rpc_span(opentracing, net_span, info)
            end

            cb(...)
        end
        RPC_CBS[tostring(session)] = cb_wraper

        -- RPC新增超时逻辑, 登录10s， 其他5s
        local timeout_second = rpc_timeout_config(params.cmd)
        E.Timer.once(timeout_second, function()
            if RPC_CBS[tostring(session)] then
                utils.reset_deepcopy_only_once_record()
                local cached_cb_wraper = RPC_CBS[tostring(session)]
                RPC_CBS[tostring(session)] = nil
                cached_cb_wraper({code= CONSTANTS.RPC_ERROR_CODES.CODE_TIMEOUT, msg= RPC_ERROR_MSG.TIME_OUT})
            end
        end)
    end

    local header = {
        codec = 'json',
        destination = destination,
        trace = next_trace_id,
        session = session
    }

    if opentracing and net_span then
        rpc_opentracing.RPC.inject_tracing_header(net_span, header)
    end

    local rpc_header = get_extra_header()

    local content_data = {
        [PACK.DATA_PARTS.RPC_HEADER] = rpc_header,
        [PACK.DATA_PARTS.CONTENT_HEADER] = header,
        [PACK.DATA_PARTS.CONTENT_BODY] = params
    }

    -- rpc发送，打日志
    local log_content_data = {
        [PACK.DATA_PARTS.CONTENT_HEADER] = header,
        [PACK.DATA_PARTS.CONTENT_BODY] = params
    }

    if should_custom_log_rpc_send(log_content_data) then
        custom_log_rpc_send(log_content_data)
    else
        chat_log.rpc_send(chat_log_util.header(), TAG, chat_log.LOG_LEVEL.LOW, log_content_data, {})
    end

    local pack = PACK.pack_data(content_data, ejoysdk_pack_data_options)
    -- E.LOG.debug(TAG, 'rpc_call write pack, destination:'..(destination or 'nil'))
    CHAT_SOCKET:write(pack)

end

-- 角色聊天通道
function M.rpc_chat(params, cb)
    M.rpc_call(M.DESTINATION.PLAYER, params, cb)
end

-- 账号聊天通道
function M.rpc_account_chat(params, cb)
    M.rpc_call(M.DESTINATION.ACCOUNT, params, cb)
end

function M.login(destination, cb)
    local token
    if chat_token.curr_login_version == chat_token.LOGIN_V2 then
        token = chat_token.get_chat_token()
        E.LOG.debug(TAG, 'chat_connect: login use v2')

        --E.LOG.debug(TAG, '聊天登录协议V2:使用chat_token入参')
    else
        token = EH.get_player_token()
        --E.LOG.debug(TAG, '聊天登录协议V1:使用moment_token入参')

        E.LOG.debug(TAG, 'chat_connect: login use v1')
    end

    local params = {}
    params.cmd = 'login'
    params.token = token
    if PACK.is_support_deflate() then
        --E.LOG.debug(TAG, "login check support deflate, and add accept_encoding")
        params["accept_encoding"] = {PACK.ENCODING_TYPES.DEFLATE}
    end
    local game_id = E.get_game_id()
    if game_id then
        local log_data = {}
        log_data.os = E.Sysinfo.os()
        log_data.appId = game_id
        params.log_data = log_data
    end

    M.rpc_call(destination, params, function(ret)
        if ret.code == 0 then
            E.LOG.debug(TAG, 'chat_connect: rpc login succ')

            if not heart_beat_running then
                E.Timer.once(heart_beat_interval, function()
                    heart_beat() -- 登录成功，开始发送心跳
                end)
            end
        else
            E.LOG.debug(TAG, 'chat_connect: rpc login fail, code=' .. tostring(ret.code))
            --E.LOG.debug(TAG, 'ejoy_chat_server_rpc_call, ' .. 'login_fail')
            ESTAT.stat_fatal_error("ejoy_chat_server_rpc_call", 'chat_err_login_fail')
        end
        if cb then
            cb(ret)
        end
    end)
end

function M.send_msg(destination, msg, session_id, msg_send_id, cb, at_list)
    local params = {}
    params.session_id = session_id
    params.send_id = msg_send_id
    local content = {}
    content.type = "text"
    content.data = msg
    params.content = content
    params.cmd = "send"
    if at_list and type(at_list) == 'table' and next(at_list) ~= nil then
        params.at_list = at_list or {}
    end
    --E.LOG.debug('chat_at#', 'send_msg')
    --E.log(params)
    M.rpc_call(destination, params, cb)
end

function M.send_custom(destination, custom, session_id, cb, at_list)
    local params = {}
    params.session_id = session_id
    params.send_id = send_id()
    local content = {}
    content.type = 'client_custom'
    content.data = custom
    params.content = content
    params.cmd = 'send'
    if at_list and type(at_list) == 'table' and next(at_list) ~= nil then
        params.at_list = at_list or {}
    end
    M.rpc_call(destination, params, cb)
end

function M.send_rich_text_msg(destination, text, extend_data, session_id, msg_send_id, cb, at_list)
    local params = {}
    params.session_id = session_id
    params.send_id = msg_send_id
    local content = {}
    content.type = 'rich_text'
    content.data = {text = text, extend_data = extend_data or {}}
    params.content = content
    params.cmd = 'send'
    if at_list and type(at_list) == 'table' and next(at_list) ~= nil then
        params.at_list = at_list or {}
    end

    M.rpc_call(destination, params, cb)
end

function M.send_resource_msg(destination, text, res_type, res_id, extend_data, session_id, at_list, msg_send_id, cb)
    local params = {}
    params.session_id = session_id
    params.send_id = msg_send_id
    local content = {}
    content.type = 'res'
    content.data = {text=text, res_type=res_type, res_id=res_id, extend_data = extend_data or {}}
    params.content = content
    params.cmd = 'send'
    if at_list and type(at_list) == 'table' and next(at_list) ~= nil then
        params.at_list = at_list or {}
    end

    M.rpc_call(destination, params, cb)
end

function M.send(destination, session_id, content, at_list, cb)
    local params = {}
    params.session_id = session_id
    params.send_id = send_id()
    params.content = content
    params.cmd = 'send'
    if at_list and type(at_list) == 'table' and next(at_list) ~= nil then
        params.at_list = at_list or {}
    end
    M.rpc_call(destination, params, function (ret)
        ret.send_id = params.send_id
        if cb then
            cb(ret)
        end
    end)

    return params.send_id
end

function M.get_player_latest_at_msgs(destination, cb)
    local params = {}
    params.cmd = 'get_player_latest_at_msgs'
    M.rpc_call(destination, params, cb)
end

function M.get_user_group_broker_info(destination, query, cb)
    local params = {}
    params.cmd = 'get_user_group_broker_info'
    params.query = query or {}
    M.rpc_call(destination, params, cb)
end

-- 群组经纪人切换群组（切换分线
-- 切换群组即从群组经纪人下面的一个群组离开，进入到另外一个群组
function M.switch_group_id(destination, group_broker_id, group_id, cb)
    local params = {}
    params.cmd = 'switch_group_id'
    params.group_broker_id = group_broker_id
    params.group_id = group_id
    M.rpc_call(destination, params, cb)
end

function M.get_msg(destination, session_id, direction, max_msg_count, ts, cb, msg_id)
    local params = {}
    params.session_id = session_id
    params.search_direction = direction or -1
    params.max_msg_count = max_msg_count or 50
    params.ts = ts
    if msg_id then
        params.msg_id = msg_id
    end
    params.cmd = "get_session_msg"
    --E.LOG.debug(TAG, 'get_msg begin, destination:'..(destination or 'nil')..', cmd:get_session_msg')
    M.rpc_call(destination, params, cb)
end

function M.get_msg_by_id(destination, session_id, msg_ids, cb)
    local params = {}
    params.session_id = session_id
    params.msg_ids = msg_ids or {}
    params.cmd = "get_session_msg"
    M.rpc_call(destination, params, cb)
end

function M.set_msg_received(destination, session_id, msg_id, cb)
    local params = {}
    params.session_id = session_id
    params.msg_id = msg_id
    params.cmd = 'set_msg_received'
    M.rpc_call(destination, params, cb)
end

function M.delete_msg(destination, session_id, msg_ids, cb)
    local params = {}
    params.session_id = session_id
    params.msg_ids = msg_ids or {}
    params.cmd = 'delete_msg'
    M.rpc_call(destination, params, cb)
end

function M.clean_session_msg(destination, session_id, ts, cb)
    local params = {}
    params.session_id = session_id
    if ts then
        params.ts = ts
    end
    params.cmd = 'clean_session_msg'
    M.rpc_call(destination, params, cb)
end

function M.get_chat_config(destination, cb)
    local params = {}
    params.cmd = 'get_chat_config'
    M.rpc_call(destination, params, cb)
end

function M.set_chat_config(destination, chat_config, cb)
    local params = {}
    
    local safe_chat_config = chat_config
    local safe_push_config = chat_config.push
    if safe_push_config ~= nil then
        local group_types = safe_push_config.push_on_group_types
        -- 空table默认处理成array
        if group_types and next(group_types) == nil then 
            group_types = JSON.newArray()
            safe_push_config.push_on_group_types = group_types
            safe_chat_config.push = safe_push_config
            
            params.ejoysdk_pack_data_options = { encode_empty_array = true }
        end
    end
    
    params.config = safe_chat_config
    params.cmd = 'set_chat_config'
    M.rpc_call(destination, params, cb)
end

function M.set_msg_received_with_ts(destination, session_id, ts, cb)
    local params = {}
    params.session_id = session_id
    if ts then
        params.received_ts = ts
    end
    params.cmd = 'set_msg_received'
    M.rpc_call(destination, params, cb)
end

-- 已读接口暂时不正式使用，待需求开发
--local function set_msg_readed(session_id, msg_id)
--    local params = {}
--    params.session_id = session_id
--    params.msg_id = msg_id
--    params.cmd = 'set_msg_readed'
--    M.rpc_chat(params)
--end

function M.get_latest_session(destination, cb)
    local params = {}
    params.cmd = 'get_latest_session'
    M.rpc_call(destination, params, cb)
end

function M.create_group(members, invite_msg, group_name, cb)
    local params = {}
    if #members == 0 then
        -- 不添加的话，lua 转 json 会是一个 object，但服务端的 members 字段只认 array
        table.insert(members, PLAYER_INFO.player_id)
    end

    params.members = members
    params.invite_msg = invite_msg
    local info = {}
    info.name = group_name
    params.info = info
    params.cmd = "create_group"
    M.rpc_chat(params, cb)
end

function M.add_group_member(adds, invite_msg, group_id, cb)
    local params = {}
    params.adds = adds
    params.invite_msg = invite_msg
    params.group_id = group_id
    params.cmd = 'add_group_member'
    M.rpc_chat(params, cb)
end

function M.reply_add_group_member(reply_msg, is_agree, group_id, cb, inviter_user_id)
    local params = {}
    params.reply_msg = reply_msg
    params.is_agree = is_agree
    params.group_id = group_id

    if inviter_user_id then
        params.inviter_user_id = inviter_user_id
    end

    params.cmd = 'reply_add_group_member'
    M.rpc_chat(params, cb)
end

function M.remove_group_member(removes, remove_msg, group_id, cb)
    local params = {}
    params.removes = removes
    params.message = remove_msg
    params.group_id = group_id
    params.cmd = 'remove_group_member'
    M.rpc_chat(params, cb)
end

-- 更新群组属性接口, 目前客户端只可以修改名字 info.name
function M.update_group(info, group_id, cb)
    local params = {}
    params.info = info
    params.group_id = group_id
    params.cmd = 'update_group'
    M.rpc_chat(params, cb)
end

function M.delete_group(group_id, cb)
    local params = {}
    params.group_id = group_id
    params.cmd = 'delete_group'
    M.rpc_chat(params, cb)
end

function M.exit_group(group_id, cb)
    local params = {}
    params.group_id = group_id
    params.cmd = 'exit_group'
    M.rpc_chat(params, cb)
end

function M.get_group_be_invited_history(cb)
    local params = {}
    params.cmd = 'get_group_be_invited_history'
    M.rpc_chat(params, cb)
end

function M.set_voice_channel_status(group_id, status, mute_local_value, voice_user_id, channel_info, cb)
    local params = {}
    params.cmd = 'set_voice_channel_status'
    params.group_id = group_id
    params.channel_status = status
    params.mute = mute_local_value
    if channel_info then
        params.channel_info = channel_info
    end
    if voice_user_id then
        params.voice_user_id = tostring(voice_user_id)
    end
    

    M.rpc_chat(params, cb)
end

function M.set_voice_channel_mode(group_id, mode, cb)
    local params = {}
    params.cmd = 'set_voice_channel_mode'
    params.group_id = group_id
    params.mode = mode
    M.rpc_chat(params, cb)
end

function M.manage_voice_channel_status(group_id, operations, cb)
    local params = {}
    params.cmd = 'manage_voice_channel_status'
    params.group_id = group_id
    params.operations = operations or {}
    M.rpc_chat(params, cb)
end

function M.get_agora_channel_token(group_id, versions, cb)
    local params = {}
    if versions then
        params.agora_version = versions
    end
    params.cmd = 'get_agora_channel_token'
    params.group_id = group_id
    M.rpc_chat(params, cb)
end

function M.get_player_info(player_id, cb)
    local params = {}
    params.cmd = 'get_player_info'
    params.player_id = player_id
    M.rpc_chat(params, cb)
end

function M.get_player_infos(player_ids, cb)
    local params = {}
    params.cmd = 'get_player_infos'
    params.player_ids = player_ids
    M.rpc_chat(params, cb)
end

function M.ignore(ignore_data, cb)
    local params = {}
    params.cmd = 'ignore'
    if not ignore_data.sessions or #ignore_data.sessions == 0 then
        ignore_data.sessions = JSON.newArray()
        params.ejoysdk_pack_data_options = { encode_empty_array = true }
    end
    if not ignore_data.group_types or #ignore_data.group_types == 0 then
        ignore_data.group_types = JSON.newArray()
        params.ejoysdk_pack_data_options = { encode_empty_array = true }
    end
    params.data = ignore_data
    M.rpc_chat(params, cb)
end

function M.unignore(unignore_data, cb)
    local params = {}
    params.cmd = 'unignore'

    if not unignore_data.sessions then
        unignore_data.sessions = JSON.newArray()
        params.ejoysdk_pack_data_options = { encode_empty_array = true }
    end

    if not unignore_data.group_types then
        unignore_data.group_types = JSON.newArray()
        params.ejoysdk_pack_data_options = { encode_empty_array = true }
    end
    
    params.data = unignore_data
    M.rpc_chat(params, cb)
end

function M.report_msg(report_type_id, report_desc, session_id, msg_id, cb)
    local params = {}
    params.cmd = 'report_msg'
    params.report_type_id = report_type_id
    params.report_desc = report_desc
    params.session_id = session_id
    params.msg_id = msg_id
    M.rpc_chat(params, cb)
end

function M.test_chat_server_port()
    init_server_port()
    --E.LOG.debug(TAG, "== test_chat_server_port init ==")
    --E.LOG.debug(TAG, "test_chat_server_port after init_server_port ports >>")
    --E.log(current_chat_server_port_arr)
    --E.LOG.debug(TAG, "test_chat_server_port current_chat_server_port:" .. current_chat_server_port)

    on_server_port_fail()
    next_server_port()
    on_connected()

    local _last_port_cache = LAST_SERVER_PORT_STORE:get()
    --E.LOG.debug(TAG, "== test_chat_server_port fail and connected ==")
    --E.LOG.debug(TAG, "test_chat_server_port current_chat_server_port:" .. current_chat_server_port)
    --E.LOG.debug(TAG, "test_chat_server_port last_port_cache:" .. tostring(last_port_cache))
end

-- 没有对外，单测使用
function M.test_set_need_add_port_idx(_is_need)
    need_add_port_idx = _is_need
end

return M
