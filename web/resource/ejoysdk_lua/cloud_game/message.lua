local json = require "ejoysdk_lua.ejoysdk_json"
local cloud_adapter = require "ejoysdk_lua.cloud_game.cloud_adapter"
local E = require "ejoysdk_lua.ejoysdk"
local JBA = require "ejoysdk_lua.ejoysdk_js_bridge_adapter"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local EC = require "ejoysdk_lua.ejoysdk_constants"
local CSTAT = require "ejoysdk_lua.cloud_game.cloud_stat"
local unpack = table.unpack or unpack
local EM = require "ejoysdk_lua.ejoysdk_module"
local cloud_config = require "ejoysdk_lua.cloud_game.cloud_config"

local TAG = EM.MODULE.CLOUD_GAME .. "cloud_message"

---@class CloudMsg
local M = {}

local MAX_ID = 10000000
local FUNC_ID = 0

M.MSG_NAMES = {
    MSG_RESPONSE = "RESPONE",
    -- 调用通用远端
    MSG_INVOKE_REMOTE = "INVOKE_REMOTE",
    -- 远程调用结果
    MSG_INVOKE_RESULT = "INVOKE_RESULT"
}

local MESSAGE_RULE = {
    -- 最多重试5次
    MAX_RETRY_TIMES = 5
}

-- 远端调用缓存
local cache_remote_calls = {}
-- 远端调用缓存，这个缓存收到回调之后，不会值空，满足注册的方法能多次回调
local save_remote_calls = {}
local send_msg_retry_times = {}

-- 远端调用结果回调
JBA.output2 = function(func_id, callback_params)
    local body = {
        msg_name = M.MSG_NAMES.MSG_INVOKE_RESULT,
        func_id = func_id,
        params = callback_params
    }
    E.LOG.debug(TAG,'jba output, func_id >> ' .. tostring(func_id))
    local result_str = JSON.encode(body)
    M:_send_data(func_id, result_str)
end

---@return CloudMsg
function M.create()
    local tb = {
        req_msg = {},
        req_handle = {},
        session_id = 0
    }
    setmetatable(tb, {__index = M})
    return tb
end

local log = function(s)
    E.LOG.debug(TAG, s)
end

local function gen_fun_id()
    FUNC_ID = (FUNC_ID + 1) % MAX_ID
    local func_id_str = tostring(FUNC_ID)
    return func_id_str
end

-- 避免数组出现nil，参数最多个数为8个
local function param_encode(v1, v2, v3, v4, v5, v6, v7, v8, ...)
    assert(#{...} == 0, "参数不能大于8")
    return {
        v1 = v1,
        v2 = v2,
        v3 = v3,
        v4 = v4,
        v5 = v5,
        v6 = v6,
        v7 = v7,
        v8 = v8
    }
end
local function param_decode(tb)
    return tb.v1, tb.v2, tb.v3, tb.v4, tb.v5, tb.v6, tb.v7, tb.v8
end

function M:receive_data(json_str)
    local msg = json.decode(json_str)
    local msg_name = msg["msg_name"]

    E.LOG.debug(TAG, "receive_data msg_name:" .. tostring(msg_name))
    --回应处理
    if msg_name == M.MSG_NAMES.MSG_RESPONSE then
        --请求处理
        local session_id = msg.session_id
        if not self.req_msg[session_id] then
            log("[cloud game] _receive_data  error!!!!! can't find session_id " .. session_id)
            return
        end

        E.LOG.debug(TAG, "receive_data, msg >>")
        E.LOG.debug(TAG, msg)
        if msg.error_code then
            self.req_msg[session_id].error_handle.cb(msg.error_code, msg.error_msg)
        else
            self.req_msg[session_id].cb(param_decode(msg.param))
        end

        -- 置空，一次远程调用完成
        self.req_msg[session_id] = nil
    elseif msg_name == M.MSG_NAMES.MSG_INVOKE_REMOTE then
        local invoke_params = param_decode(msg.param)
        JBA.input2(invoke_params)
    elseif msg_name == M.MSG_NAMES.MSG_INVOKE_RESULT then
        local func_id = msg.func_id
        local callback_params = msg.params
        local cb = cache_remote_calls[func_id] or save_remote_calls[func_id]
        E.LOG.debug(TAG, "receive invoke callback, func_id:" .. tostring(func_id) .. ", time >> " .. tostring(os.time()))
        if cb then
            E.LOG.debug(TAG, "receive invoke callback, begin callback >>")
            E.LOG.debug(TAG, callback_params)
            cb(unpack(callback_params))
        else
            E.LOG.warn(TAG, "receive invoke callback, cb not found")
        end

        -- 置空，一次远程调用完成， save_remote_calls 里面的func不处理
        cache_remote_calls[func_id] = nil

        --local session_id = msg.session_id
        ---- 置空，一次远程调用完成
        --self.req_msg[session_id] = nil
    else
        local handle = self.req_handle[msg_name]
        if not handle then
            log("[cloud game] req_handle not find !!!!! " .. tostring(msg_name))
            return
        end

        local msg_session_id = msg.session_id
        local respone = function(...)
            --处理结束后返回结果
            local resp_msg = {
                msg_name = "RESPONE",
                session_id = msg_session_id,
                param = param_encode(...)
            }
            local tem = json.encode(resp_msg)
            log("[cloud game] rpc response " .. tem)
            self:_send_data(msg_session_id, tem)
        end
        local error_respone = function(error_code, error_msg)
            local resp_msg = {
                msg_name = "RESPONE",
                session_id = msg_session_id,
                error_code = error_code,
                error_msg = error_msg
            }
            local tem = json.encode(resp_msg)
            log("[cloud game] rpc request handle error" .. tostring(tem))
            self:_send_data(msg_session_id, tem)
        end
        local handle_msg = function()
            handle(error_respone, respone, param_decode(msg.param))
        end
        --返回异常
        local ret, error_msg = pcall(handle_msg)
        if not ret then
            error_respone(EC.CLOUD_GAME_ERROR_CODES.UNKNOWN, error_msg)
        end
    end
end

function M:_send_data(session_id, json_str, cb, ext)
    local session_id_str = tostring(session_id)
    send_msg_retry_times[session_id_str] = 0

    local send_callback
    send_callback = function(succ, ...)
        local send_times = send_msg_retry_times[session_id_str]
        if not succ then
            local code, msg, fail_msg_id = ...
            E.LOG.debug(TAG, "_send_data failed, current retry times:" .. tostring(send_times))
            if send_times > MESSAGE_RULE.MAX_RETRY_TIMES then
                E.LOG.warn(TAG, "_send_data reach max retry times, abort!")
                if cb then
                    cb(false, EC.CLOUD_GAME_ERROR_CODES.REACH_MAX_RETRY_TIMES, tostring(msg) .. ", " .. tostring(code))
                end
                -- stat
                local stat_params = {}
                if ext then
                    stat_params.action = ext.msg_name or ""
                    stat_params.send_times = send_times
                    stat_params.code = code
                    stat_params.msg = msg
                end
                CSTAT.stat_event("cloud_msg_send_max_retry_times", stat_params)
            else
                send_times = send_times + 1
                send_msg_retry_times[session_id_str] = send_times
                E.LOG.warn(TAG, "_send_data retry begin")
                cloud_adapter.send_data(json_str, send_callback, fail_msg_id)
            end
        else
            E.LOG.debug(TAG, "_send_data succ")
            if cb then
                cb(true)
            end

            -- stat
            local stat_params = {}
            if ext then
                stat_params.msg_name = ext.msg_name or ""
                stat_params.send_times = send_times
            end
            CSTAT.stat_event("cloud_msg_send_succ", stat_params)
        end
    end

    cloud_adapter.send_data(json_str, send_callback)
end

---@param handle fun(error_response_cb,response_cb,...):void
---error_response_cb(error_code,error_msg)
function M:rpc_register_handle(msg_name, handle)
    if self.req_handle[msg_name] then
        E.LOG.error(TAG, "register_handle duplication msg_name >>" .. msg_name)
        return
    end
    E.LOG.debug(TAG, "register_handle msg_name >>" .. msg_name)
    self.req_handle[msg_name] = handle
end

---使用默认异常处理
function M:rpc_request_default(cb, msg_name, ...)
    self:rpc_request(self:rpc_create_error_handle(), cb, msg_name, ...)
end

--- @param cb fun(error_code,msg) timeout=nil表示不会超时,超时error_code = M.ERROR_CODE.Timeout
function M:rpc_create_error_handle(cb, timeout)
    if not cb then
        return nil
    end
    return {
        cb = cb or function(error_code, error_msg)
                log(
                    "[cloud game] rpc_response_default_error_handle " ..
                        tostring(error_code or "nil") .. tostring(error_msg or "nil")
                )
            end,
        timeout = timeout
    }
end

--- @param error_handle fun(error_code,error_msg)
--- @param cb fun(...)
function M:rpc_request(error_handle, cb, msg_name, ...)
    self.session_id = gen_fun_id()
    local session_id = self.session_id
    local err_callback = function(code, msg)
        if self.req_msg[session_id] then
            if error_handle and error_handle.cb then
                error_handle.cb(code, msg)
            end
            -- 置空回调
            self.req_msg[session_id] = nil
        end
    end

    --超时
    if error_handle and error_handle.timeout then
        E.Timer.once(
            error_handle.timeout,
            function()
                err_callback(EC.CLOUD_GAME_ERROR_CODES.TIME_OUT, "request timeout " .. tostring(msg_name))
            end
        )
    end

    local msg = {
        msg_name = msg_name,
        session_id = session_id,
        param = param_encode(...)
    }

    E.LOG.debug(TAG, ">>> before _send_data")
    E.LOG.debug(TAG, msg)
    self.req_msg[session_id] = msg

    if cloud_config.DEBUG_OPTIONS.TestSendMessageFailed then
        E.LOG.debug(TAG, "TestSendMessageFailed now mock return failed")
        err_callback(EC.CLOUD_GAME_ERROR_CODES.UNKNOWN, "test send failed msg")
        return
    end

    self:_send_data(session_id, json.encode(msg), function(succ, ...)
        if succ then
            E.LOG.debug(TAG, "rpc_request _send_data succ")
        else
            local code, msg2 = ...
            E.LOG.warn(TAG, "rpc_request _send_data failed, code:" .. tostring(code) .. ", msg:" .. tostring(msg2))
            err_callback(code, msg2)
        end
    end, msg)

    msg.error_handle = error_handle
    msg.cb = cb
end

local function generate_func_params(func, save_func)
    local func_id = gen_fun_id()
    local func_params = {}
    func_params["_func_id"] = func_id
    if save_func then
        save_remote_calls[func_id] = func
    else
        cache_remote_calls[func_id] = func
    end
    E.LOG.debug(TAG, "generate_func_params, cache callback, func_id:" .. tostring(func_id) .. ", func:" .. tostring(func))
    return func_params
end

--- save_func = true 表示参数列中的func在收到远程调用之后不清除，满足一些注册方法能多次通知
-- fixme 这里还有一个问题是方法的参数列表中有些func是多次调用的，有些只需要调用一次，对于一次调用的不清楚会导致泄露
function M:invoke_remote(error_handle, module, func, params, save_func)
    local call_params = params or {}

    local func_params = {}
    for i, param in ipairs(call_params) do
        -- its callback, process it
        if type(param) == 'function' then
            func_params[i] = generate_func_params(param, save_func)
        elseif type(param) == 'table' then
            local table_param = {}
            for k, sub_param in pairs(param) do
                if type(sub_param) == 'function' then
                    table_param[k] = generate_func_params(sub_param, save_func)
                else
                    table_param[k] = sub_param
                end
            end
            func_params[i] = table_param
        else
            func_params[i] = param
        end
    end

    local body = {
        module = module,
        ["function"] = func,
        params = func_params
    }

    E.LOG.debug(TAG, "invoke_remote body >>")
    E.LOG.debug(TAG, body)

    self:rpc_request(error_handle, nil, M.MSG_NAMES.MSG_INVOKE_REMOTE, body)
end

return M
