local E = require "ejoysdk_lua.ejoysdk"
local ESP = require "ejoysdk_lua.qrcode.ejoysdk_scan_pkg"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local QR = require 'ejoysdk_lua.qrcode.ejoysdk_qrcode'
local VENDOR_NAME = "EJOY_SCAN"
local TAG_EJOY_SCAN = 'TAG_EJOY_SCAN'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local EG = require 'ejoysdk_lua.ejoysdk_gangplank'

local M = Vendor:Inherit(VENDOR_NAME)

-- 前端登录类型
local LOGIN_TYPE_START = 'TYPE_START'

local function open_webview(url, close_cb)

    local local_start_up_data = {
        pkg_info = E.get_pkg_info(),
        ejoysdk_ver = E.get_sdk_version_name('EJOYSDK')
    }

    E.LOG.debug(TAG_EJOY_SCAN, 'open_webview:'..(url or 'nil'))

    local host = {
        ['.aligames.com'] = {
            transparent = true,
            startupData = local_start_up_data
        },
        ['.ejoy.com'] = {
            transparent = true,
            startupData = local_start_up_data
        },
        ['.alibaba.net'] = {
            transparent = true,
            startupData = local_start_up_data
        },
        ['.hepinggames.com'] = {
            transparent = true,
            startupData = local_start_up_data
        },
        ['.suixiagames.com'] = {
            transparent = true,
            startupData = local_start_up_data
        },
        ['.lingxigames.com'] = {
            transparent = true,
            startupData = local_start_up_data
        }
    }

    E.WebView.open(url, host, {
        compactMode= true,
        use_fragment = true,
        hide_close_btn = true
    }, nil, function(_values)

        -- 关闭的时候也停止轮询，前端会call一次，避免浏览器过快、未知情况关闭引起不必要的轮询请求
        QR.cancel_query_status()

        if close_cb then
            close_cb(_values.args)
        end
    end)
end

-- h5登录完成的回调
-- type: 常规登录
--[[ 
    ["type"] => "TYPE_START"
    ["data"] => table: 0x7f2c675a7f80{
    ["pinfo"] => table: 0x7f2c675e3580{
      ["with"] => "ALIGAMES"
      ["with_account"] => "cdf6031dac467a0f9943f2fd1c6fd2de"
      ["pid"] => "cdf6031dac467a0f9943f2fd1c6fd2de"
      ["platform"] => "998233"
    }
    ["uid"] => "cdf6031dac467a0f9943f2fd1c6fd2de"
    ["loginType"] => "qrcode"
    ["token"] => "AhCHZVXi8+nutcqKaZ46l5XjHYPslSBjZGY2MDMxZGFjNDY3YTBmOTk0M2YyZmQxYzZmZDJkZYea+jINxPoexO/lpBXA7cI="
}
]]

function M.h5_callback_login_finish(login_result, _cb)
    E.LOG.debug(TAG_EJOY_SCAN, 'h5_callback_login_finish start')
    E.log(login_result)
    if login_result == nil then
        E.log('h5 callback fail, login_result is nil')
        M.opt.auth_listener(false, {code = CONSTANTS.AIRLINE_ACCOUNT_ERROR_CODES.CODE_OAUTH_FAILED, msg = 'h5 callback result is nil'})
        return
    end
    local params = login_result
    local type = params.type
    local auth_info = params.data or {}
    if type == LOGIN_TYPE_START then
        if auth_info.loginType == 'qrcode' then -- 暂不限制；_ejoysdk.os() == "android" and 
            ESTAT.stat_action("finish_ejscan_login")

            local pinfo = auth_info.pinfo or {}
            -- ptoken没有传递过来，本身依赖lua轮询二维码后更新（SCAN_LOGIN事件）
            pinfo.ptoken = tostring(EG.user_info().ptoken)
            M.opt.auth_listener(true, pinfo, {})

            -- 扫码登录仅更新当前auth_info，不保存到登陆历史列表里，避免其跑到自动登录或者快速登录（登陆历史列表）的流程里
            -- 也不需要刷新token，因为token跟手机号登陆的不一样；也不用login_cb回去走大圣登陆流程了，此时流程已结束
            E.LOG.debug(TAG_EJOY_SCAN, 'scan qrcode login type, only need update auth_info, do not need save to login history')
        else
            M.opt.auth_listener(false, {code = CONSTANTS.AIRLINE_ACCOUNT_ERROR_CODES.CODE_OAUTH_FAILED, msg = 'not support os, token: ' .. tostring(auth_info.token)})
        end
    else
        M.opt.auth_listener(false, {code = CONSTANTS.AIRLINE_ACCOUNT_ERROR_CODES.CODE_OAUTH_FAILED, msg = 'not support login_type, token: ' .. tostring(auth_info.token)})
    end

    E.LOG.debug(TAG_EJOY_SCAN, 'h5_callback_login_finish end')
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

function M.login()
    local url = ESP.get_url('SCAN')
    open_webview(url)
    ESTAT.stat_action("start_ejscan_login")
end

function M.logout()
    if M.opt and M.opt.logout_listener then
        M.opt.logout_listener({})
    end
end

function M.init(opt, cb)
    M.opt = opt
    E.LOG.debug(TAG_EJOY_SCAN, "init")
    if cb then
        cb(true)
    end
end

M:is_implemented({"ACCOUNT"})

return M