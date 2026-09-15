local E = require "ejoysdk_lua.ejoysdk"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
--local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local CHANNEL = "HW_LOGIN"
local UNISDK_CHANNEL = "HW_LOGIN"

local TAG = EM.MODULE.VENDORS.HW_LOGIN

local M = Vendor:Inherit(CHANNEL)

M.EVT_SWITCH_USER_SUCC = "EVT_SWITCH_USER_SUCC"
M.EVT_SWITCH_USER_CANCEL = "EVT_SWITCH_USER_CANCEL"
M.EVT_SWITCH_USER_FAIL = "EVT_SWITCH_USER_FAIL"

local auth_listener = nil
local logout_listener = nil
local switch_listener = nil
local exit_listener = nil

function M.init(opt, cb)
    auth_listener = opt.auth_listener
    logout_listener = opt.logout_listener
    switch_listener = opt.switch_listener
    exit_listener = opt.exit_listener

    E.LOG.debug(TAG, 'start init!')

    UNI.register_login_listener(UNISDK_CHANNEL, function(succ, info, ext_params)
        if succ then
            E.LOG.debug(TAG, ext_params)
            local outsource = {
                platform = UNISDK_CHANNEL,
                ptoken = info.token,
                guest = false,
                ext = {
                    opcode = ext_params and ext_params.opcode

                }
            }

            if ext_params and ext_params.is_switch then
                switch_listener(outsource, {})
            else
                auth_listener(true, outsource, {})
            end

        else
            if not ext_params or not ext_params.is_switch then
                auth_listener(false, info)
            end
        end
    end)

    UNI.register_logout_listener(UNISDK_CHANNEL, function (ext_params)
        logout_listener(ext_params)
    end)

    UNI.register_exit_cb(UNISDK_CHANNEL, function (succ)
        exit_listener(succ)
    end)

    -- callback init success
    cb(true)
end

-- 是否经过账号中心
function M.use_user_center()
    return true
end

function M.login()
    UNI.login(UNISDK_CHANNEL, {})
end

function M.logout()
    UNI.logout(UNISDK_CHANNEL)
end

function M.merge_info(info, pinfo)
    return M.merge_helper(info, pinfo)
end

function M.simple_token()
    return false
end

function M.check_token(_outsource, _info)
    M.login()
end

function M.can_pay()
    return false
end

function M.exit()
    UNI.exit(UNISDK_CHANNEL)
end

M:is_implemented({"ACCOUNT"})

return M
