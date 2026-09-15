local E = require 'ejoysdk_lua.ejoysdk'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local EM = require "ejoysdk_lua.ejoysdk_module"
local VENDOR_NAME = 'PGA_LOGIN'
local TAG = EM.MODULE.VENDORS.PLAYGAMES

local ASYNC_GET_AUTH_CODE = 'ASYNC_GET_AUTH_CODE'

local M = Vendor:Inherit(VENDOR_NAME)

local login_type= VENDOR_NAME
local register_disabled = false -- PGS特殊字段，用于检测首次登录PGS是否已经注册，如有则快速登录
local show_continue_login = false

function M.login(params)
    params = params or {}
    login_type = (params or {}).vendor or VENDOR_NAME
    register_disabled = (params.pass_ext or {}).register_disabled or false
    UNI.login(VENDOR_NAME)
    --UNI.login(VENDOR_NAME, {})
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

function M.logout(params)
    login_type = (params or {}).vendor or VENDOR_NAME
    UNI.logout(VENDOR_NAME)
end

function M.login_fail(_status, _last_login_params, _fail_cb)
    return false
end

function M.get_auth_code(cb,refresh)
    if not refresh or type(refresh) ~= 'boolean' then
        refresh = false
    end
    UNI.async_call(VENDOR_NAME,ASYNC_GET_AUTH_CODE,{refresh = refresh},nil,cb)
end

local options = {}
function M.init(opt, cb)
    -- For login
    local vendor_name = (opt.proxy or {}).vendor_name or VENDOR_NAME
    options[vendor_name]=opt

    local register_login_callback = function (succ, info, _ext_paramas)
        local option = options[login_type]
        if succ then
            show_continue_login = true
            E.LOG.debug(TAG, 'register_login_listener succ, info.token:'..tostring(info.token))
            local outsource = {
                platform = login_type,
                ptoken = JSON.encode({code=info.token,clientid=info.channel_product_code,regDisabled = (register_disabled or false)}),
                guest = false
            }
            local ext = {}
            option.auth_listener(succ,outsource,ext)
        else
            E.LOG.warn(TAG, "register_login_listener failed >>")
            E.LOG.debug(TAG, info)
            option.auth_listener(false,info)
        end
    end
    local register_logout_callback = function(ext_params)
        E.LOG.debug(TAG, "logout_listener >>")
        local option = options[login_type]
        option.logout_listener(ext_params)
    end

    UNI.register_login_listener(VENDOR_NAME, register_login_callback)
    UNI.register_logout_listener(VENDOR_NAME, register_logout_callback)

    -- callback init success
    cb(true)
end

--登录成功过就设置为true
function M.show_continue_login()
    return show_continue_login
end

M:is_implemented({"ACCOUNT"})

return M
