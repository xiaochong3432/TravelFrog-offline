local E = require 'ejoysdk_lua.ejoysdk'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
--local EG = require "ejoysdk_lua.ejoysdk_gangplank"
--local ER = require 'ejoysdk_lua.ejoysdk_resource'

local Vendor = require "ejoysdk_lua.vendors.vendor"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local EM = require "ejoysdk_lua.ejoysdk_module"
local JSON = require 'ejoysdk_lua.ejoysdk_json'

local VENDOR_NAME = 'APPLE_LOGIN'

local TAG = EM.MODULE.VENDORS.APPLE_LOGIN

local M = Vendor:Inherit(VENDOR_NAME)

--初始化消息
--local CAST_INIT_WITH_CONFIG = "CAST_INIT_WITH_CONFIG"

-- 登录 accessToken
local APPLE_CURRENT_USER = E.LazyKeyStore:New('APPLE_CURRENT_USER', false, true, false)

-- 有效期24小时
local ptoken_expiry_duration = 24 * 3600

-- 提前120秒过期
local ptoken_safe_diff = 120

local auth_listener = nil
local logout_listener = nil

local k_login_auto_flag = false -- 是否自动登录的标志位

local function login_handler()
    --暂不需要做啥
end

function M.login_fail(_status, _last_login_params, _login_fail_callback)
    if E.Sysinfo.os() == 'ios' then
        APPLE_CURRENT_USER:set(nil)

        if k_login_auto_flag then
            E.log("Apple 登录token自动登录失败，进行重试+++")
            k_login_auto_flag = false
            UNI.login(VENDOR_NAME, {})

            return true
        end

    end
    return false
end

-- 执行苹果登录的授权
local function exe_apple_login_auth()
    k_login_auto_flag = false
    E.LOG.debug(TAG, 'no Apple_Login current user')
    UNI.login(VENDOR_NAME, {})
end


function M.login()

    if E.Sysinfo.os() ~= 'ios' then

        E.LOG.debug(TAG, 'sign with Apple only support for iOS')
        auth_listener(false,{code=CONSTANTS.OFFICIAL_ERR_CODES.CODE_LOGIN_NOT_SUPPORT,msg='Not Support'})

        return
    end

    local current_user = APPLE_CURRENT_USER:get()

    if not current_user or not current_user.ptoken then
        E.LOG.debug(TAG, 'ptoken miss')
        exe_apple_login_auth()
        return
    end

    local ptoken = JSON.safe_decode(current_user.ptoken)
    if not ptoken or not ptoken.userId then
        E.LOG.debug(TAG, 'ptoken userId miss')
        exe_apple_login_auth()
        return
    end


    if not current_user.ptoken_fetch_time or ((E.time() - current_user.ptoken_fetch_time) >= (ptoken_expiry_duration - ptoken_safe_diff)) then
        E.LOG.debug(TAG, 'ptoken_fetch_time invalid, ptoken_fetch_time=' .. tostring(current_user.ptoken_fetch_time))
        exe_apple_login_auth()
        return
    end

    k_login_auto_flag = true
    E.LOG.debug(TAG, 'get Apple_Login current user, auto login--------')
    E.log(current_user)
    local outsource = {
        platform = VENDOR_NAME,
        ptoken = current_user.ptoken,
        uid = current_user.uid,
        guest = false
    }
    local ext = {}
    auth_listener(true, outsource, ext)
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
    APPLE_CURRENT_USER:set(nil)
    UNI.logout(VENDOR_NAME)
end

function M.init(opt, cb)
    -- For login
    auth_listener = opt.auth_listener
    logout_listener = opt.logout_listener

    --UNI.cast(VENDOR_NAME, CAST_INIT_WITH_CONFIG, opt.config or {})

    UNI.register_login_listener(VENDOR_NAME, function (succ, info, ext_paramas)
        if succ then
            E.LOG.debug('Apple_Login', 'register_login_listener succ')

            local jsonTable = {
                userId = ext_paramas.userId,
                identityToken = ext_paramas.identityToken,
                authorizationCode = ext_paramas.authorizationCode,
                fullName = ext_paramas.fullName,
                email = ext_paramas.email,
                realNameStatus = ext_paramas.realNameStatus,
                bundleID = ext_paramas.bundleID,
            }

            -- 把数据转成jsonstr再传给服务器
            local jsonStr = JSON.encode(jsonTable)

            info.ptoken = jsonStr -- 保存下用来做自动登录
            info.ptoken_fetch_time = E.time()
            APPLE_CURRENT_USER:set(info)

            -- 把所有值都塞到ptoken里
            local outsource = {
                platform = VENDOR_NAME,
                ptoken = jsonStr, --info.token,
                uid = info.uid,
                guest = false,
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

    -- callback init success
    cb(true)
end

--表示仅需要账号登录功能
M:is_implemented({"ACCOUNT"})

return M
