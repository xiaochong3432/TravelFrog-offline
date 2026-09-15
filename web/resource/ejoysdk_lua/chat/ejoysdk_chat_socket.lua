local Class = require "ejoysdk_lua.ejoysdk_class"
local lsocket = _ejoysdk_lsocket
local E = require 'ejoysdk_lua.ejoysdk'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local EM = require "ejoysdk_lua.ejoysdk_module"
local chat_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
local utils = require "ejoysdk_lua.ejoysdk_utils"

local M = Class:Inherit("ChatSocket")

local CONNECT_INTERVAL = 5

local CONNECT_TIMEOUT = 5

local connect_time = 0

local MAX_GET_NATIVE_RESOLVE_TIMES = 15
local PRE_GET_NATIVE_SEC = 0.2
local PRE_RESOLVE_TIMEOUT_SEC = 3

-- 第一次出现400错误的时间戳
local first_appear_400_time = 0
local appear_400_count = 0
local appear_400_max_count = 15
local appear_check_duration = 60 * 4

local TAG = EM.MODULE.CHAT .. "socket"

M.CHAT_STOP = "STOP"
M.CHAT_DISCONNECT = "DISCONNECT"
M.CHAT_CONNECTED = "CONNECTED"
M.CHAT_LOGINED = "LOGINED"

M.EVT_CONNECT_FAILED = "CONNNECT_FAILED"

--
-- server.socket_type
-- server.addr
-- server.port
--
-- handlers.on_message -- require return succ, n or false
-- handlers.on_connect_error
-- handlers.on_disconnect
-- handlers.on_connected
-- handlers.on_error
--

function M:_init(server, handlers)
    chat_log.call_api(chat_log_util.header(), TAG, '_init', chat_log.LOG_LEVEL.HIGH, {}, server, handlers)

    assert(server.socket_type == "TCP")

    self.status = self.STOP
    self.fd = nil
    self.recv_buf = ""
    self.send_buf = ""
    self.server = server
    self.handlers = handlers

    self.connect_interval = 0

    -- 和游戏保持一致，一次生命周期仅使用一次，失败后走旧逻辑避免异常
    self.can_use_resolve = true
end

function M:run()
    self.status = self.CHAT_DISCONNECT
    self:connect()
end

function M:get_server()
    return  utils.deepcopy(self.server or {})
end

function M:close()
    self.status = self.CHAT_STOP
    if not self.fd then
        return
    end
    self.fd:close()
    self.fd = nil
    self.send_buf = ""
    self.handlers.on_disconnect()

    chat_log.info(chat_log_util.header(), TAG, 'chat_on_disconnect', 'chat_socket_connect', {}, {})
end

function M:get_status()
    return self.status
end

function M:check_connect_status_unblock()
    --chat_log.call_api(chat_log_util.header(), TAG, 'check_connect_status_unblock', chat_log.LOG_LEVEL.LOW, {})

    E.LOG.debug(TAG, 'chat_connect: check_connect_status_unblock start')

    local rr, rw = lsocket.select(nil, {self.fd}, 0)
    if not rr or not rw or next(rw) == nil then

        --local _code = tostring(CONSTANTS.RPC_ERROR_CODES.CODE_SOCKET_CONNECT_SOCKET_NOT_READY)
        --local _msg = 'socket_not_ready'
        -- chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = msg} , {})

        connect_time = connect_time + 1
        if connect_time < CONNECT_TIMEOUT then
            E.Timer.once(1, function()

                E.LOG.debug(TAG, 'chat_connect: check_connect_status_unblock retry')

                self:check_connect_status_unblock()
            end)
        else
            local msg = 'connect reach max times'
            if rr == false then -- select return 0, select timeout
                msg = msg .. ', select return 0'
            end
            if rr == nil and type(rw) == 'string' then
                msg = msg .. ', select error: ' .. tostring(rw)
            end

            local code = tostring(CONSTANTS.RPC_ERROR_CODES.CODE_SOCKET_CONNECT_RETRY_REACH_MAX_TIMES)

            E.LOG.debug(TAG, 'chat_connect: check_connect_status_unblock fail, error_msg=' .. tostring(msg))

            self.handlers.on_connect_error(msg , code)

            --chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = msg} , {})
        end
    else
        local ok, err = self.fd:status()
        if not ok then
            local code = tostring(CONSTANTS.RPC_ERROR_CODES.CODE_SOCKET_CONNECT_CHECK_FD_STATUS_NOT_OK)
            local msg = 'check_connect_status_not_ok, err:' .. tostring(err)

            --chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = msg} , {})

            E.LOG.debug(TAG, 'chat_connect: check_connect_status_unblock fail, error_msg=' .. tostring(msg))

            self.handlers.on_connect_error('connect fd status not ok, err: '.. tostring(err), code)
            return false
        else
            E.LOG.debug(TAG, 'chat_connect: check_connect_status_unblock succ')

            self.status = self.CHAT_CONNECTED
            self.handlers.on_connected()

            -- 连接上了，重置一下日志公参
            chat_log_util.resset_header()

            --chat_log.info(chat_log_util.header(), TAG, 'chat_on_connected', 'chat_socket_connect', {}, {})
        end
    end
end

function M:connect()
    E.LOG.debug(TAG, 'chat_connect: chat_socket connect start')

    -- 开始连接，重置一下日志公参
    chat_log_util.resset_header()

    self.handlers.on_connect_start() -- 开始建连
    --chat_log.info(chat_log_util.header(), TAG, 'chat_on_connect_start', 'chat_socket_connect', {addr=tostring(self.server.addr), port= tostring(self.server.port)}, {})

    -- 1.iOS LuaVM 在主线程，BSD getaddrinfo dns 弱网有卡死 watchdog kill掉的问题，需要异步解析
    -- 2.Android 和 Windows 同步处理没有问题
    -- 3.判断_ejoysdk_lresolve兼容旧Native版本(iOS)
    -- 4.request有timeout时间，默认3s检查是否解析完成；如果解析完成，则在E.Timer.once的0.2s内不断去检测拿到结果（iOS只是float即小于1s）
    local e_lresolve = _ejoysdk_lresolve -- luacheck: ignore
    if _ejoysdk.os() == "ios" and e_lresolve and self.can_use_resolve then
        local resolve = require 'ejoysdk_lua.chat.ejoysdk_resolve'
        local finish_count = 0

        --chat_log.debug(chat_log_util.header(), TAG, 'chat_will_request_host', 'chat_socket_connect', {addr=tostring(self.server.addr), timeout_sec=PRE_RESOLVE_TIMEOUT_SEC}, {})

        E.LOG.debug(TAG, 'chat_connect: resolve request start on iOS')

        resolve.request(self.server.addr, PRE_RESOLVE_TIMEOUT_SEC, function (success, data)
            finish_count = 1
            --chat_log.debug(chat_log_util.header(), TAG, 'chat_request_host_finish', 'chat_socket_connect', {addr=tostring(self.server.addr), succ = tostring(success), data = data}, {})

            if success and type(data) == "table" then

                local target_addr
                if data and #data >= 1 then
                    --chat_log.debug(chat_log_util.header(), TAG, 'chat_get_family_finish', 'chat_socket_connect', {family=tostring(data[1].family), addr=tostring(data[1].addr)}, {})

                    --E.LOG.debug(TAG, "family: " .. tostring(data[1].family) .. " addr: " .. tostring(data[1].addr))
                    target_addr = data[1].addr
                    if not target_addr then
                        self.can_use_resolve = false

                        local code = tostring(CONSTANTS.RPC_ERROR_CODES.CODE_SOCKET_CONNECT_TARGET_ADDR_NIL)
                        local error_msg = 'lresolve: dns resolve target_addr is nil'

                        E.LOG.debug(TAG, 'chat_connect: resolve request fail, error_msg=' .. tostring(error_msg))

                        self.handlers.on_connect_error(error_msg, code)

                        --chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = error_msg} , {})
                        return
                    end
                else
                    local code = tostring(CONSTANTS.RPC_ERROR_CODES.CODE_SOCKET_CONNECT_DNS_RESOLVE_EMPTY)
                    local error_msg = 'lresolve: dns resolve count 0'

                    E.LOG.debug(TAG, 'chat_connect: resolve request fail, error_msg=' .. tostring(error_msg))

                    self.can_use_resolve = false
                    self.handlers.on_connect_error(error_msg, code)

                    --chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = error_msg} , {})
                    return
                end

                -- 直接使用ip建立连接
                local fd,err = lsocket.connect(target_addr, self.server.port)

                if fd == nil then
                    -- connect 失败，基本是网络问题，比如 dns 解析失败
                    local code = tostring(CONSTANTS.RPC_ERROR_CODES.CODE_SOCKET_CONNECT_FD_NIL)
                    local msg = 'fd is nil, err: ' .. tostring(err)

                    E.LOG.debug(TAG, 'chat_connect: resolve request fail, error_msg=' .. tostring(msg))

                    self.handlers.on_connect_error(msg, code)

                    --chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = msg} , {})
                    return
                end

                E.LOG.debug(TAG, 'chat_connect: resolve request succ, on_connecting')

                self.fd = fd

                connect_time = 0

                self.handlers.on_connecting()

                --chat_log.debug(chat_log_util.header(), TAG, 'chat_on_connecting', 'chat_socket_connect', {}, {})

                self:check_connect_status_unblock()
                
            else
                self.can_use_resolve = false
                --E.LOG.debug(TAG, "resolve host err: " .. tostring(data))
                local code = tostring(CONSTANTS.RPC_ERROR_CODES.CODE_SOCKET_CONNECT_RESOLVE_ERR)
                local msg = 'lresolve err: ' .. tostring(data)

                E.LOG.debug(TAG, 'chat_connect: resolve request fail, error_msg=' .. tostring(msg))

                self.handlers.on_connect_error(msg, code)
                --chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = msg} , {})
            end
        end)

        local function get_resolve_result_with_timer(try_times)

            --chat_log.debug(chat_log_util.header(), TAG, 'chat_get_resolve_result_with_timer', 'chat_socket_connect', {try_times=tostring(try_times), finish_count=tostring(finish_count)}, {})

            -- E.LOG.debug(TAG, "resolve times:" .. tostring(try_times))
            if try_times > 0 and finish_count == 0 then
                -- 对应iOS的Timer.once实现，是支持float类型的，但Android是不支持的
                E.Timer.once(PRE_GET_NATIVE_SEC, function()
                    resolve.wait(PRE_GET_NATIVE_SEC)
                    if finish_count == 1 then
                        --chat_log.debug(chat_log_util.header(), TAG, 'chat_resolve_host_finish', 'chat_socket_connect', {}, {})
                        --E.LOG.debug(TAG, "resolve host finish!")

                        E.LOG.debug(TAG, 'chat_connect: resolve host finish')
                    else
                        get_resolve_result_with_timer(try_times - 1)
                    end
                end)
            end
        end

        get_resolve_result_with_timer(MAX_GET_NATIVE_RESOLVE_TIMES)

    else
        E.LOG.debug(TAG, 'chat_connect: lsocket connect on Android')

        local fd,err = lsocket.connect(self.server.addr, self.server.port)

        if fd == nil then
            -- connect 失败，基本是网络问题，比如 dns 解析失败
            local code = tostring(CONSTANTS.CODE_SOCKET_CONNECT_FD_NIL)
            local msg = 'fd is nil, err: ' .. tostring(err)

            E.LOG.debug(TAG, 'chat_connect: lsocket connect fail, error_msg=' .. tostring(msg))

            self.handlers.on_connect_error(msg, code)

            --chat_log.warn(chat_log_util.header(), TAG, 'chat_socket_connect_error', {code = code, msg = msg} , {})
            return
        end

        self.fd = fd

        connect_time = 0

        E.LOG.debug(TAG, 'chat_connect: lsocket connect succ, on_connecting')

        self.handlers.on_connecting()

        --chat_log.debug(chat_log_util.header(), TAG, 'chat_on_connecting', 'chat_socket_connect', {}, {})

        self:check_connect_status_unblock()
    end
end

function M:tick()
    if self.status == self.CHAT_DISCONNECT and os.time() - self.connect_interval < CONNECT_INTERVAL then
        self:connect() -- 这个函数不会执行到，因为and前后的逻辑不会同时成立
    end
    if self.status ~= self.CHAT_CONNECTED then
        return
    end

    self:read()
    self:send_remain()
end

function M:read()
    if self.status ~= self.CHAT_CONNECTED then
        return
    end
    while true do
        local succ, opt = self.handlers.on_message(self.recv_buf)
        if succ then
            local n = opt
            self.recv_buf = self.recv_buf:sub(n)

            -- 解析成功，需要把400错误，重置回去
            self:reset_400_count()
        else
            local error_code = opt
            local rr = lsocket.select({ self.fd}, 0)
            if not rr or next(rr) == nil then
                return
            end
            local p, err = self.fd:recv()
            if not p then
                self:socket_error(err, error_code)
                return
            end
            self.recv_buf = self.recv_buf .. p
        end
    end
end

function M:write(pack)
    self.send_buf = self.send_buf .. pack
    self:send_remain()
end

function M:send_remain()
    if self.send_buf == "" then
        return
    end

    -- send 之前确保 select
    local rr, rw = lsocket.select(nil, {self.fd}, 0)
    if not rr or not rw or next(rw) == nil then
        return
    end

    local bytes, err = self.fd:send(self.send_buf)
    if not bytes then
        self:socket_error(err)
        return
    else
        self.send_buf = self.send_buf:sub(bytes + 1)
    end
end

function M:reset_400_count()
    first_appear_400_time = 0
    appear_400_count = 0
end

function M:socket_error(err, err_code)
    self.status = self.CHAT_STOP
    if not self.fd then
        return
    end
    self.fd:close()
    self.fd = nil
    self.send_buf = ""
    self.connect_interval = os.time()
    --标识读/写数据出错

    -- 偶尔遇到网络波动，错误码400，是很正常的，不能认定一定是token失效导致。
    -- 所以需要设定一个阈值，达到这个阈值，才把400错误码，抛给游戏，引导游戏做重新登录游戏
    if err_code == 400 then
        local need_tell_outer = false

        if first_appear_400_time == 0 then
            first_appear_400_time = os.time()
            appear_400_count = 0
        else
            if os.time() - first_appear_400_time <= appear_check_duration then
                if appear_400_count >= appear_400_max_count then
                    first_appear_400_time = 0
                    appear_400_count = 0
                    need_tell_outer = true

                    local holo = require 'ejoysdk_lua.ejoysdk_holo'
                    local token = holo.get_player_token()
                    local expire_time = (holo.get_player_token_body() or {}).expire_time or 0

                    local param = {
                        ['first_appear_400_time']=first_appear_400_time,
                        ['token']=token or 'null',
                        ['expire_time']=expire_time,
                        ['is_priority_high']=true
                    }

                    ESTAT.stat_error_with_limit(TAG, 'ejoy_chat_socket_400_error_reach_max', 'ejoy_chat_socket_400_error_reach_max', 'chat_err_scoket_error', param)
                else
                    --E.LOG.debug('ejoysdk_chat_socket', '出现400次数, 第' .. tostring(appear_400_count) .. '次')
                    appear_400_count = appear_400_count + 1
                end
            else
                first_appear_400_time = os.time()
                appear_400_count = 0
            end
        end

        -- 需要告诉游戏，则将错误码400，转成CODE_SOCKET_TOKEN_ERROR
        if need_tell_outer then
            err_code = CONSTANTS.CHAT_ERROR_CODES.CODE_SOCKET_TOKEN_ERROR
        end
    end

    self.handlers.on_error('socket error, err: ' .. tostring(err), (err_code or -1))

    chat_log.error(chat_log_util.header(), TAG, (err_code or -1), 'chat_socket_on_error', {err_code=(err_code or -1), err_msg=tostring(err)}, {})
end

return M

