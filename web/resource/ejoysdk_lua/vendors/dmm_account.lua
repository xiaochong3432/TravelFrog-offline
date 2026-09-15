local E = require 'ejoysdk_lua.ejoysdk'
local Vendor = require 'ejoysdk_lua.vendors.vendor'
local EM = require "ejoysdk_lua.ejoysdk_module"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
local UTILS = require 'ejoysdk_lua.ejoysdk_utils'

local CAST_INIT = "CAST_INIT"
local VENDOR_NAME = 'DMM_LOGIN'
--local DMM_LOGIN = 'dmm_login' -- 三方的登录名
local DMM = Vendor:Inherit(VENDOR_NAME)

local TAG = EM.MODULE.VENDORS.DMM_ACC
local dmm_appid = ""
local logout_invoke = false -- DMM在登录失败时主动logout自己

local login_callback = function(succ, info, _ext_paramas)
    if succ then
        E.LOG.debug(TAG, 'register_login_listener succ, info.token:' .. tostring(info.token or '') .. ' ,userid:' .. tostring(info.pid or 'nil'))

        local pt = {}
        if _ejoysdk.os() == 'windows' then
            pt.type = 'token'
            pt.appid = dmm_appid
            pt.onetimeToken = info.token
            pt.viewerId = info.pid
        else
            pt.type = 'callback'
            pt.token = info.token
        end

        local outsource = {
            platform = VENDOR_NAME,
            ptoken = JSON.encode(pt),
            uid = info.pid, --unisdk.lua里把user_id转为pid了
            guest = false
        }
        local ext = {}
        DMM.opt.auth_listener(succ, outsource, ext)
    else
        E.LOG.warn(TAG, "register_login_listener failed >>")
        E.LOG.debug(TAG, info)
        DMM.opt.auth_listener(false, info)
    end
end

function DMM.init(opt, cb)
    DMM.opt = opt

    local sdk_info = UNI.get_sdk_info(VENDOR_NAME)
    if sdk_info and sdk_info.meta and type(sdk_info.meta.appid) == 'string' and #(sdk_info.meta.appid) > 0 then
        dmm_appid = sdk_info.meta.appid
    end

    local logout_callback = function(ext_params)
        E.LOG.debug(TAG, "logout_listener >>")
        if not logout_invoke then
            -- 主动触发不返回给游戏
            DMM.opt.logout_listener(ext_params)
        end
    end

    UNI.register_login_listener(VENDOR_NAME, login_callback)
    UNI.register_logout_listener(VENDOR_NAME, logout_callback)
    ET.subscribe(ET.gangplank.ACQUIRE_FAILED, function(_fail_info)
        -- DMM自己也会有自动登录，为了正常弹出账号选择，在登录异常时需要先提前logout
        E.LOG.debug(TAG, "dmm login fail>>")
        DMM.logout({ manual = true })
    end)

    if sdk_info and sdk_info.meta then
        local meta_data = UTILS.deepcopy(sdk_info.meta)
        if type(meta_data.gameserver_url) ~= 'string' or #(meta_data.gameserver_url) <= 0  then
            -- 优先sdkconfig配置,没配才从cdn获取
            local global_config = EGC.get_current_cdn_config()
            --cdn会在channel init前回来
            if global_config and global_config['account_center'] then
                meta_data.gameserver_url = global_config['account_center'] .. '/dmm/login'
            end
        end
        UNI.cast(VENDOR_NAME, CAST_INIT, meta_data)
    end

    -- callback init success
    cb(true)
end

local function auto_login(viewer_id, onetime_token)
    if type(viewer_id) == 'string' and #viewer_id > 0
            and type(onetime_token) == 'string' and #onetime_token > 0 then
        local userinfo = {
            pid = viewer_id,
            token = onetime_token
        }

        login_callback(true, userinfo)
        return true
    end
    login_callback(false)
    return false
end

function DMM.login(ext)
    E.LOG.debug(TAG, 'call dmm login')
    logout_invoke = false
    local pass_ext = (ext or {}).pass_ext or {}
    if not pass_ext.autologin then
        if _ejoysdk.os() ~= 'windows' then
            UNI.login(VENDOR_NAME, {})
        else
            -- windows走DMM客户端拉起，不走普通登录
            DMM.opt.auth_listener(false, { code = CONSTANTS.OFFICIAL_ERR_CODES.CODE_LOGIN_NOT_SUPPORT, msg = 'Not Support' })
        end
    else
        auto_login(pass_ext.uid, pass_ext.token)
    end
end

-- 是否配置支持DMM
function DMM.is_support()
    return UNI.get_sdk_info(VENDOR_NAME) ~= nil
end

-- 检查解析符合dmm的参数
function DMM.check_args(args)
    if (type(args) == 'table'
            and type(args.viewer_id) == 'string' and type(args.onetime_token) == 'string'
            and #(args.viewer_id) > 0 and #(args.onetime_token) > 0) then
        return { uid = args.viewer_id, token = args.onetime_token }
    end
    return nil
end

function DMM.can_auto_login()
    if _ejoysdk.os() == 'windows' then
        -- windows 为外部传入登录，不允许走传统的自动登录
        return false
    end
    return true
end

function DMM.check_token(_outsource, _info)
    DMM.login()
end

function DMM.logout(params)
    params = params or {}
    logout_invoke = params.manual or false
    UNI.logout(VENDOR_NAME)
end

function DMM.merge_info(info, pinfo)
    return DMM.merge_helper(info, pinfo)
end

function DMM.simple_token()
    return false
end

DMM:is_implemented({ 'ACCOUNT' })

return DMM