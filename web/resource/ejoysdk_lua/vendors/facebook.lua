local E = require 'ejoysdk_lua.ejoysdk'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
--local EG = require "ejoysdk_lua.ejoysdk_gangplank"
--local ER = require 'ejoysdk_lua.ejoysdk_resource'

local Vendor = require "ejoysdk_lua.vendors.vendor"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local OVERSEA_APPLOG = require "ejoysdk_lua.vendors.oversea_applog"

local VENDOR_NAME = 'FB'

local TAG = EM.MODULE.VENDORS.FACEBOOK

local M = Vendor:Inherit(VENDOR_NAME)

--初始化消息
local CAST_INIT_WITH_CONFIG = "CAST_INIT_WITH_CONFIG"
local CAST_COMMIT_EVENT = "CAST_COMMIT_EVENT"

local SYNC_IS_CHROME_TABS_SUPPORT = "SYNC_IS_CHROME_TABS_SUPPORT"

-- 登录 accessToken
local FACEBOOK_CURRENT_USER = E.LazyKeyStore:New('FACEBOOK_CURRENT_USER', false, true, false)

local auth_listener = nil
local logout_listener = nil

local function login_handler()
    --TODO
end

function M.is_access_token_invalid(server_status, ...)
    local USER = require 'ejoysdk_lua.user_center.ejoysdk_usercenter'
    return server_status == 406 or server_status == USER.USER_CENTER_ERROR_CODES.ERR_SERVER_THIRD_PART
end

function M.login_fail(status, _last_login_params, _login_fail_callback)

    if M.is_access_token_invalid(status) and E.Sysinfo.os() == 'ios' then -- Facebook Android SDK 自带自动登录功能
        FACEBOOK_CURRENT_USER:set(nil)
        UNI.login(VENDOR_NAME, {})
        return true
    end
    return false
end

function M.is_support()
    local support = E.Sysinfo.is_app_install('com.facebook.katana') or false
    if not support then
        local ret = UNI.sync_call(VENDOR_NAME, SYNC_IS_CHROME_TABS_SUPPORT, {}, nil)
        support = (ret and ret['support']) or false
    end
    return support
end

function M.login()
    local os = E.Sysinfo.os()
    if os == 'windows' then
        auth_listener(false,{code=CONSTANTS.OFFICIAL_ERR_CODES.CODE_LOGIN_NOT_SUPPORT,msg='Not Support'})
        return
    end

    if E.Sysinfo.os() == 'android' then
        if M.is_support() then
            -- 已经安装或者支持Chrome Custom Tabs, 正常登录
            UNI.login(VENDOR_NAME, {})
        else
            auth_listener(false, {code=-121,msg='不支持'})
        end
    else
        local current_user = FACEBOOK_CURRENT_USER:get()
        if current_user and current_user.token then
            E.LOG.debug(TAG, 'get facebook current user')
            E.LOG.debug(TAG, current_user)
            local outsource = {
                platform = VENDOR_NAME,
                ptoken = current_user.token,
                uid = current_user.uid,
                guest = false
            }
            local ext = {}
            auth_listener(true, outsource, ext)
        else
            E.LOG.debug(TAG, 'no facebook current user')
            UNI.login(VENDOR_NAME, {})
        end
    end
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

function M.logout()
    FACEBOOK_CURRENT_USER:set(nil)
    UNI.logout(VENDOR_NAME)
end

function M.init(opt, cb)
    -- For login
    auth_listener = opt.auth_listener
    logout_listener = opt.logout_listener

    --初始化facebook参数在这里配置
    local config = opt.config or {}
    config.enable_ldu = (OVERSEA_APPLOG.has_enabled_ldu() == true) or false
    UNI.cast(VENDOR_NAME, CAST_INIT_WITH_CONFIG, config)

    UNI.register_login_listener(VENDOR_NAME, function (succ, info, _ext_paramas)
        if succ then
            E.LOG.debug(TAG, 'register_login_listener succ, info.token:'.. tostring(info.token))
            FACEBOOK_CURRENT_USER:set(info)
            local outsource = {
                platform = VENDOR_NAME,
                ptoken = info.token,
                uid = info.uid,
                guest = false
            }
            local ext = {}
            auth_listener(succ, outsource, ext)
        else
            auth_listener(false, info)
        end
    end)
    UNI.register_logout_listener(VENDOR_NAME, function(ext_params)
        logout_listener(ext_params)
    end)

    ET.subscribe(ET.gangplank.LOGIN, login_handler)

    -- 注册applog events
    OVERSEA_APPLOG.register_applog_events(VENDOR_NAME, M)

    -- callback init success
    cb(true)
end

M.enable_ldu = false
-- 调用Facebook打点
-- 注意：Facebook事件名称不能带符号
function M.commit_event(event_name, params)
    if M.enable_ldu == true then
        E.LOG.debug(TAG, "facebook commit_event disabled with LDU setting")
        return
    end

    E.LOG.debug(TAG, "facebook commit_event:" .. tostring(event_name))
    params = params or {}
    params.event_name = event_name
    UNI.cast(VENDOR_NAME, CAST_COMMIT_EVENT, params)
end

M:is_implemented({"ACCOUNT", Vendor.ABILITY.STATS})

return M
