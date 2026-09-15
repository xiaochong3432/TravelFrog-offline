-- 目前仅iOS才有lresolve实现
-- 聊天模块解析dns，尽量避免频繁调用
local _E = require "ejoysdk_lua.ejoysdk"
local e_lresolve = _ejoysdk_lresolve -- luacheck: ignore
local utils = require "ejoysdk_lua.ejoysdk_utils"
local EM = require "ejoysdk_lua.ejoysdk_module"
local chat_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'
local compat = require 'ejoysdk_lua.compat.ejoysdk_compat'
local xpcall = compat.xpcall

local TAG = EM.MODULE.CHAT .. 'resolve'

local M = {}

local MAX_LIMIT_RESOLVE_COUNT = 20

if e_lresolve ~= nil then

    e_lresolve.init()

    local default_timeout = 10 -- 10sec

    local callback_map = {}
    function M.request(hostname, timeout, cb)

        if hostname and cb then
            local count = utils.tablelength(callback_map)
            if count > MAX_LIMIT_RESOLVE_COUNT then
                cb(false, "resolve request max limit at onetime")

                chat_log.warn(chat_log_util.header(), TAG, 'resolve_request_max_limit', {}, {})
                return 
            end

            local servname = nil
            timeout = timeout or default_timeout
            local ok, req_obj = xpcall(e_lresolve.request, function (x)

                cb(false, "resolve request failed")
                chat_log.warn(chat_log_util.header(),
                        TAG,
                        'resolve_request_failed',
                        {lua_error_msg = tostring(x)},
                        {})

            end, hostname, servname)
            if ok then 
                callback_map[req_obj] = {
                    cb = cb,
                    hostname = hostname,
                    timeout = timeout,
                    time = 0,
                }
            end
        end

    end

    function M.wait(delta_time)
        delta_time = delta_time or 0
        for req_obj, info in pairs(callback_map) do
            local cb = info.cb
            local time = info.time
            local timeout = info.timeout
            info.time = time + delta_time

            local ok, ret, result = xpcall(e_lresolve.request_wait, function (x)
                chat_log.warn(chat_log_util.header(),
                        TAG,
                        'resolve_request_wait_failed',
                        {lua_error_msg=tostring(x)},
                        {})
            end, req_obj)

            if ok then
                local success = type(result) == "table" and true or false
                cb(success, result)
                callback_map[req_obj] = nil
            else

                if info.time >= timeout then
                    xpcall(e_lresolve.request_cancel, function (x)
                        chat_log.warn(chat_log_util.header(),
                                TAG,
                                'resolve_request_cancel_failed',
                                {lua_error_msg=tostring(x)},
                                {})
                    end, req_obj)

                    cb(false, "resolve request timeout limit:" .. tostring(timeout) .. " ret:".. tostring(ret))
                    callback_map[req_obj] = nil
                end
            end
        end
    end

    function M.cancel_all()
        for req_obj, _ in pairs(callback_map) do
            xpcall(e_lresolve.request_cancel, function (x)
                chat_log.warn(chat_log_util.header(),
                        TAG,
                        'resolve_cancel_all_failed',
                        {lua_error_msg=tostring(x)},
                        {})
            end, req_obj)
            callback_map[req_obj] = nil
        end
        chat_log.debug(chat_log_util.header(), TAG, 'cancel_all', 'cancel_all', {}, {})
        callback_map = {}
    end

else 
    -- 其他保留空实现
    function M.request(_hostname, _timeout, _cb)

    end

    function M.wait(_delta_time)

    end

    function M.cancel_all()
        
    end
end

return M