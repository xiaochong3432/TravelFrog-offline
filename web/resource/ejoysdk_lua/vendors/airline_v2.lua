local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local UP = require "ejoysdk_lua.user_center.usercenter_protocal"
local HISTORY = require 'ejoysdk_lua.airline_v2.airline_v2_history'
local ECC = require 'ejoysdk_lua.ejoysdk_config_center'
local CONFIG = require 'ejoysdk_lua.airline_v2.airline_v2_config'
local PROTOCOL = require 'ejoysdk_lua.overseas.protocol'
local AEGIS_DATA = require 'ejoysdk_lua.aegis.aegis_collect_data'
local EM = require "ejoysdk_lua.ejoysdk_module"
--local RES = require 'ejoysdk_lua.res.ejoysdk_res'
local ANT = require 'ejoysdk_lua.vendors.ant'
local TAOBAO = require 'ejoysdk_lua.vendors.taobao'
local PHONE_AUTH = require 'ejoysdk_lua.vendors.ali_datapkg'
local EQL = require "ejoysdk_lua.ejoysdk_qualitylog"

local VENDOR_NAME = "AIRLINE_V2"
local UNISDK_CHANNEL = "ALIGAMES"
local TAG_AIRLINE_V2 = EM.MODULE.VENDORS.AIRLINE_V2

--最后一次登录的数据，用于自动登录
local END_TIME_LOGIN_DATA = nil

local M = Vendor:Inherit(VENDOR_NAME)

-- 前端登录类型
local LOGIN_TYPE_QUICK = 'TYPE_QUICK'
local LOGIN_TYPE_START = 'TYPE_START'

-- 登录回调
local login_cb = nil
local h5_login_auth_info = nil

local URL_CONFIG = {
    h5_url_base = 'https://pre-account-lingxi.aligames.com',
    api_url_base = 'https://magic-account-api.flysdk.cn/client',
    url_query = '?ver=1.0&df=json&cver=' .. E.get_pkg_info().versions.lua_version .. '&os=' .. E.get_pkg_info().os,
    API = {
        auto_login = 'account.loginWithServiceTicket', --自动登录，不显示h5
        refresh_token = 'account.refresh.token', --刷新token
        login = 'm#/start', -- 常规登录，无历史记录
        quick_login = 'm#/quick', -- 快速登录，带历史记录
        account = 'm/account#/', --用户中心
        phone_auth = 'm#/sign/phoneAuth' -- 一键登录
    },
    -- 缓存白名单
    --CACHE_API = {
    --    login = '#/start', -- 常规登录，无历史记录
    --    quick_login = '#/quick', -- 快速登录，带历史记录
    --    phone_auth = '#/sign/phoneAuth' -- 一键登录
    --}
}
-- 登录页里点击一个登录按钮后调用的接口
function M.login(login_type, pass_ext, cb)
    if login_type and type(login_type) == 'string' and #login_type > 0 then

        local vendor_name = string.upper(login_type)

        E.LOG.debug(TAG_AIRLINE_V2, 'login to ' .. vendor_name)
        pass_ext = pass_ext or {}

        local login_switch = {
            ['TAOBAO_AUTH'] = TAOBAO.login,
            ['ANT_AUTH'] = ANT.login,
            ['PHONE_AUTH'] = PHONE_AUTH.login,
        }

        local login_func = login_switch[vendor_name]
        if login_func then
            login_func(pass_ext, function(succ, ...)
                if succ then
                    local token, _user_id = ...
                    PROTOCOL.succ_callback(cb, { token = token })
                    -- stat login method end
                    EQL.commit_action_succ_main("al2_login_method_end", vendor_name)
                else
                    local code, message, outsource = ...
                    PROTOCOL.fail_callback(cb, code, message, (outsource or {}).ext_info)

                    -- stat login method end
                    EQL.commit_action_fail_main("al2_login_method_end", vendor_name, code, message)
                end
            end)

            -- stat login method invoke
            EQL.commit_action_main("al2_login_method_begin", vendor_name)
        end
    else
        -- 旧逻辑
        local nonce = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.randomkey())
        E.LOG.debug(TAG_AIRLINE_V2, 'login to native')
        UNI.login(UNISDK_CHANNEL, { nonce = nonce })

        -- stat login method invoke
        EQL.commit_action_main("al2_login_method_begin", "aligames")
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

--配置中心获取数据处理
local function ecc_config_handler()
    E.LOG.debug(TAG_AIRLINE_V2, 'ecc_config_handler call')
end

function M.init(opt, cb)

    E.LOG.debug(TAG_AIRLINE_V2, "init")

    --配置中心注册获取配置
    ECC.subscribe(ECC.NAMESPACE.USERCENTER_CN, ecc_config_handler)

    URL_CONFIG.api_url_base = CONFIG.get_airline_api_host() or URL_CONFIG.api_url_base
    E.LOG.debug(TAG_AIRLINE_V2, "api_url_base: " .. tostring(URL_CONFIG.api_url_base))

    URL_CONFIG.h5_url_base = CONFIG.get_airline_h5_api_host() or URL_CONFIG.h5_url_base
    E.LOG.debug(TAG_AIRLINE_V2, "h5_url_base: " .. tostring(URL_CONFIG.h5_url_base))
    --初始化账号列表
    HISTORY.init()

    ET.subscribe(ET.gangplank.ACQUIRE_FAILED, function(_fail_info)
        -- 谷歌自己也会有自动登录，为了正常弹出账号选择，在登录异常时需要先提前logout
        E.LOG.debug(TAG_AIRLINE_V2, "airline_v2 login fail>>")
        M.logout()
    end)

    cb(true)
end

local function get_api_url(api)
    local realapi = URL_CONFIG.API[api]
    local api_url = E.HTTP.uri_join(URL_CONFIG.h5_url_base, realapi or api)
    return api_url
end

local function update_userinfo(user_info)
    E.LOG.debug(TAG_AIRLINE_V2, "update_userinfo")
    E.LOG.debug(TAG_AIRLINE_V2, user_info)
    HISTORY.update(user_info)
end

local function open_webview(url, api)
    --url = E.Utils.string_insert(url, '?debug=true', string.find(url, '#'))

    local auth_info = HISTORY.get_auth_info()
    local airlineToken = (auth_info or {}).airlineToken
    local accountId = (auth_info or {}).accountId
    local params_ds_token = EG.user_info().ptoken or airlineToken
    local local_start_up_data = {
        pkg_info = E.get_pkg_info(),
        airlineToken = airlineToken,
        accountId = accountId,
        ds_token = params_ds_token,
        aegis_data = AEGIS_DATA.get_encrypt_data(),
        ejoysdk_ver = E.get_sdk_version_name('EJOYSDK')
    }

    E.LOG.debug(TAG_AIRLINE_V2, 'open_webview:' .. (url or 'nil') .. ', ds_token:' .. (params_ds_token or 'nil'))

    local host = {}
    local local_startup_data = {
        transparent = true,
        startupData = local_start_up_data
    }

    local white_host_list = {
        '.ejoy.com', '.aligames.com', '.alibaba.net', '.hepinggames.com', '.lingxigames.com', '.suixiagames.com'
    }
    for _, new_host in pairs(white_host_list) do
        host[new_host] = local_startup_data
    end

    local new_white_hosts = CONFIG.get_white_hosts()
    for _, new_host in pairs(new_white_hosts) do
        host[new_host] = local_startup_data
    end

    local options = {
        compactMode = true,
        use_fragment = true,
        hide_close_btn = true
    }
    local js_callback = nil
    local close_callback = function()
        --没登录成功，则返回登录取消
        if (not h5_login_auth_info or string.len(h5_login_auth_info.airlineToken or '') <= 0 ) then
            --EG.logout(true)
            if (login_cb) then
                login_cb(false)
            end
        end
    end

    E.WebView.open(url, host, options, js_callback, close_callback)
    --local cache_api = URL_CONFIG.CACHE_API[api]
    --local brand = CONFIG.get_airline_brand()
    --if cache_api and brand and '' ~= brand then
    --    local res_name = brand .. '_login'
    --    RES.get_res(ECC.NAMESPACE.H5_RESOURCE, res_name, function(succ, config)
    --        if succ then
    --            -- 使用缓存
    --            host[config.local_url] = local_startup_data
    --
    --            local local_url = 'file://' .. config.local_url
    --            local ejoysdk_version = E.get_sdk_version_name('EJOYSDK')
    --            local version_check = require "ejoysdk_lua.ejoysdk_version_check"
    --            local result = version_check.compare_versions(ejoysdk_version, '2.5.3')
    --            --E.log('ejoysdk_version = '..tostring(ejoysdk_version))
    --            --E.log('result = '..tostring(result))
    --            if _ejoysdk.os() ~= 'ios' or result >= 0 then
    --                --  ios旧版本对本地页锚点支持有问题，native已修复，判断版本号来处理
    --                local_url = local_url .. (cache_api or '')
    --            end
    --            E.WebView.open(local_url, host, options, js_callback, close_callback)
    --        else
    --            E.WebView.open(url, host, options, js_callback, close_callback)
    --        end
    --    end)
    --else
    --    E.WebView.open(url, host, options, js_callback, close_callback)
    --end
end

function M.open_test_url(url)
    open_webview(url)
end

-- 是否能自动登录
function M.can_auto_login()
    E.LOG.debug(TAG_AIRLINE_V2, 'can_auto_login start')
    local res = false
    local end_login_data = HISTORY.get_auth_info()
    if end_login_data then
        E.LOG.debug(TAG_AIRLINE_V2, end_login_data)
    else
        E.LOG.debug(TAG_AIRLINE_V2, "end_login_data is nil")
    end

    if _ejoysdk.os() == "windows" and end_login_data and end_login_data.loginType == 'qrcode' then
        -- PC扫码登录不用进行自动登录
        E.LOG.debug(TAG_AIRLINE_V2, 'windows qrcode login type, can not auto login')
    elseif end_login_data and end_login_data.serviceTicket then
        END_TIME_LOGIN_DATA = end_login_data
        res = true
    end
    E.LOG.debug(TAG_AIRLINE_V2, 'can_auto_login end, res=' .. tostring(res))
    return res
end

function M.st_login(auth_info, cb, loading_visable)
    if loading_visable then
        E.Loading.show()
    end
    E.LOG.debug(TAG_AIRLINE_V2, 'st_login start')
    local api_url = E.HTTP.uri_join(URL_CONFIG.api_url_base, URL_CONFIG.API.auto_login)
    api_url = api_url .. URL_CONFIG.url_query
    E.LOG.debug(TAG_AIRLINE_V2, api_url)
    local st = auth_info.serviceTicket

    EQL.commit_action_main("al2_st_login_begin")
    UP.post_to(api_url, URL_CONFIG.API.auto_login, { ['serviceTicket'] = st }, function(succ, ...)
        E.LOG.debug(TAG_AIRLINE_V2, 'auto_login request finish')
        if loading_visable then
            E.Loading.dismiss()
        end
        if succ then
            local body = ...
            --st_login update_userinfo
            body.accountOs = auth_info.accountOs -- 取历史账号里的accountOs，服务器不返回这个字段
            update_userinfo(body)
            local airlineTokenTimeout = body['airlineTokenTimeout']
            -- Token过期前1小时刷新
            local timeout = airlineTokenTimeout / 1000 - E.time() - 60 * 60
            if timeout <= 0 then
                timeout = 1
            end
            E.Timer.once(timeout, M.refresh_token)
            cb(true, ...)

            local brand = CONFIG.get_airline_brand()
            EQL.commit_action_succ_main("al2_st_login_end", brand)
        else
            local code, msg = ...
            E.LOG.warn(TAG_AIRLINE_V2, 'code=' .. tostring(code) .. ', msg=' .. (msg or 'nil'))
            cb(false, code, msg)

            EQL.commit_action_fail_main("al2_st_login_end", nil, code, msg)
        end
    end)
end

function M.auto_login()
    E.LOG.debug(TAG_AIRLINE_V2, 'auto_login start')
    local cb = function(succ, ...)
        E.LOG.debug(TAG_AIRLINE_V2, 'auto_login callback')
        if succ then
            local body = ...
            E.LOG.debug(TAG_AIRLINE_V2, body)
            local brand = CONFIG.get_airline_brand()
            local token = body['airlineToken']
            login_cb(true, token, brand)
        else
            local code, msg = ...
            E.LOG.debug(TAG_AIRLINE_V2, 'code=' .. tostring(code) .. ', msg=' .. (msg or 'nil'))

            --自动登录失败拉起h5
            M.show_login_h5()
        end
    end

    if not END_TIME_LOGIN_DATA then
        local code = 74000001 -- SDK错误码
        local msg = 'END_TIME_LOGIN_DATA is empty, somethins wrong!'
        cb(false, code, msg)

        EQL.commit_action_fail_main("al2_st_login_end", nil, code, msg)
        return
    end

    M.st_login(END_TIME_LOGIN_DATA, cb, true)
    E.LOG.debug(TAG_AIRLINE_V2, 'auto_login end')
end

function M.quick_login(auth_info, cb)
    E.LOG.debug(TAG_AIRLINE_V2, 'quick_login start')
    local st_cb = function(succ, ...)
        E.LOG.debug(TAG_AIRLINE_V2, 'quick_login callback')
        if succ then
            local body = ...
            E.LOG.debug(TAG_AIRLINE_V2, body)
            local token = body['airlineToken']
            local brand = CONFIG.get_airline_brand()
            login_cb(true, token, brand)
            PROTOCOL.succ_callback(cb, {})
        else
            local code, msg = ...
            E.LOG.warn(TAG_AIRLINE_V2, 'code=' .. tostring(code) .. ', msg=' .. (msg or 'nil'))
            --快速登录失败通知h5
            PROTOCOL.fail_callback(cb, code, msg)
        end
    end

    M.st_login(auth_info, st_cb, false)
    E.LOG.debug(TAG_AIRLINE_V2, 'quick_login end')
end

-- 显示登录web,由go-channel触发
function M.exec_login(cb)
    E.LOG.debug(TAG_AIRLINE_V2, 'login start')

    -- airline_v2 登录调用打点
    EQL.commit_action_main("al2_login_invoke")

    --logining_vendor_name = VENDOR_NAME
    if M.can_auto_login() then
        M.auto_login()
    else
        M.show_login_h5()
    end
    --存储native回调
    login_cb = function(...)
        if(cb)then cb(...) end
        login_cb = nil
        h5_login_auth_info = nil;
    end
end

--退出账号，由go-channel触发
function M.exec_logout(cb)
    E.LOG.debug(TAG_AIRLINE_V2, 'logout start')
    HISTORY.delete_auth_info()
    if cb then
        cb(true, {})
    end
end

function M.logout(cb)
    M.exec_logout(cb)
end

function M.has_history_account()
    local list = HISTORY.get_list()
    E.LOG.debug(TAG_AIRLINE_V2, "airline history")
    E.LOG.debug(TAG_AIRLINE_V2, list)
    if list and next(list) ~= nil then
        return true
    end
    return false
end

-- 显示聚合登录H5
function M.show_login_h5()
    if M.has_history_account() then
        M.show_quick_login_h5()
    else
        M.show_start_login_h5()
    end
end

-- 一键登录
function M.support_phone_auth()
    local login_items = M.get_login_items();
    for _, item in ipairs(login_items) do
        if item and item.type and string.upper(item.type) == PHONE_AUTH.AUTH_VENDOR_NAME then
            local airline_v2_config = ECC.get_config(ECC.NAMESPACE.USERCENTER_CN)
            if airline_v2_config and
                    airline_v2_config.config and
                    airline_v2_config.config.loginItems then
                for _, loginItem in ipairs(airline_v2_config.config.loginItems) do
                    if loginItem and loginItem.type and string.upper(loginItem.type) == 'PHONE_AUTH' then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function M.show_start_login_h5()
    local api = 'login'
    if M.support_phone_auth() then
        api = 'phone_auth'
    end

    local url = get_api_url(api)
    open_webview(url, api)

    EQL.commit_action_main("al2_show_h5_login", api)
end

-- 显示快速登录的H5
function M.show_quick_login_h5()
    local api = 'quick_login'
    local url = get_api_url(api)
    open_webview(url, api)

    EQL.commit_action_main("al2_show_h5_login", api)
end

-- h5登录完成的回调
-- type: 常规登录还是快速登录，快速登录走st_login
function M.h5_callback_login_finish(login_result, cb)
    E.LOG.debug(TAG_AIRLINE_V2, 'h5_callback_login_finish start')
    E.LOG.debug(TAG_AIRLINE_V2, login_result)
    if login_result == nil then
        E.LOG.warn(TAG_AIRLINE_V2, 'h5 callback fail, login_result is nil')
        return
    end
    local params = login_result
    local type = params.type
    local auth_info = params.data

    h5_login_auth_info = auth_info
    if type == LOGIN_TYPE_START then
        if _ejoysdk.os() == "windows" and auth_info.loginType == 'qrcode' then
            -- PC扫码登录仅更新当前auth_info，不保存到登陆历史列表里，避免其跑到自动登录或者快速登录（登陆历史列表）的流程里
            -- 也不需要刷新token，因为token跟手机号登陆的不一样；也不用login_cb回去走大圣登陆流程了，此时流程已结束
            E.LOG.debug(TAG_AIRLINE_V2, 'windows qrcode login type,only need update auth_info, do not need save to login history')
            HISTORY.update_auth_info(auth_info)
            E.LOG.debug(TAG_AIRLINE_V2, 'windows qrcode login,no need to refresh_token and ds login process, return now.')
        else
            --登录成功，保存账号信息
            update_userinfo(auth_info)

            local token = auth_info.airlineToken
            local airlineTokenTimeout = auth_info.airlineTokenTimeout
            -- Token过期前1小时刷新
            local timeout = airlineTokenTimeout / 1000 - E.time() - 60 * 60
            if timeout <= 0 then
                timeout = 1
            end
            E.Timer.once(timeout, M.refresh_token)

            -- 登录完成，通知go-channel
            if login_cb then
                local brand = CONFIG.get_airline_brand()
                -- 这里需要增加一个accountOs字段给PC使用
                local accountOs = auth_info.accountOs
                login_cb(true, token, brand, accountOs)

                EQL.commit_action_succ_main("al2_h5_login_end", brand)
            else
                E.LOG.error(TAG_AIRLINE_V2, "h5 callback to native, native cb is nil")
            end
        end

    elseif type == LOGIN_TYPE_QUICK then
        -- 快速登录，走st_login
        M.quick_login(auth_info, cb)
    else
        h5_login_auth_info = nil
    end
end

function M.show_user_center()
    local auth_info = HISTORY.get_auth_info()
    if auth_info and auth_info.loginType == 'qrcode' then
        E.LOG.debug(TAG_AIRLINE_V2, '手机扫码登录的用户暂时不支持访问用户中心！！！！')
        return
    end
    E.LOG.debug(TAG_AIRLINE_V2, '开始访问水下品牌用户中心页面')
    local url = get_api_url('account')
    open_webview(url)
end
M.open_user_center = M.show_user_center

-- 从配置中心的本地缓存里，获取配置
function M.get_config_from_center(cb)

    E.LOG.debug(TAG_AIRLINE_V2, 'get_config_from_center start')

    local data = ECC.get_config(ECC.NAMESPACE.USERCENTER_CN)

    E.LOG.debug(TAG_AIRLINE_V2, 'back to h5, get_config_from_center, data=' .. JSON.encode(data))

    if cb then
        PROTOCOL.succ_callback(cb, data)
    end
end

-- H5通过此方法，获取登录项(一期只支持账密 和 手机号)
function M.get_login_items(cb)
    E.LOG.debug(TAG_AIRLINE_V2, 'get_login_items start')
    local airline_v2_config = ECC.get_config(ECC.NAMESPACE.USERCENTER_CN)
    local loginItems = {}

    if airline_v2_config then
        E.LOG.debug(TAG_AIRLINE_V2, airline_v2_config)
        local configItems = airline_v2_config.config.loginItems
        local switch = {
            ['TAOBAO_AUTH'] = TAOBAO.isTaobaoInstalled,
            ['ANT_AUTH'] = ANT.isAntInstalled,
            ['PHONE_AUTH'] = function()
                return PHONE_AUTH.get_current_carrier_name() ~= nil
            end
        }
        local switch_default = function()
            return true
        end

        for _, item in ipairs(configItems) do
            if item and item.type then
                -- 特殊处理
                local process = switch[string.upper(item.type or '')] or switch_default
                if process() == true then
                    table.insert(loginItems, item)
                end
            end
        end
    else
        table.insert(loginItems, { ['type'] = 'mobile' })
    end

    E.LOG.debug(TAG_AIRLINE_V2, 'back to h5, get_login_items, succ, body=' .. tostring(JSON.encode(loginItems)))

    PROTOCOL.succ_callback(cb, loginItems)
    return loginItems
end

-- 获取登录历史
function M.get_login_history(cb)
    E.LOG.debug(TAG_AIRLINE_V2, 'get_login_history start')

    local history = HISTORY.get_list()

    E.LOG.debug(TAG_AIRLINE_V2, 'back to h5, history, succ, history=' .. tostring(JSON.encode(history)))

    PROTOCOL.succ_callback(cb, history)

    return history
end

--删除账号
function M.delete_history(uid)
    E.LOG.debug(TAG_AIRLINE_V2, 'delete account ' .. tostring(uid))
    HISTORY.delete(uid)
end

function M.refresh_token()
    local auth_info = HISTORY.get_auth_info()
    if auth_info == nil then
        E.LOG.debug(TAG_AIRLINE_V2, "token refresh fail, auth_info is nil")
        return
    end
    local api_url = E.HTTP.uri_join(URL_CONFIG.api_url_base, URL_CONFIG.API.refresh_token)
    api_url = api_url .. URL_CONFIG.url_query
    E.LOG.debug(TAG_AIRLINE_V2, "refresh token url " .. tostring(api_url))
    UP.post_to(api_url, URL_CONFIG.API.refresh_token, { token = auth_info.airlineToken }, function(succ, ...)
        if succ then
            local body = ...
            E.LOG.debug(TAG_AIRLINE_V2, "refresh token succ")
            auth_info.airlineToken = body.airlineToken
            auth_info.airlineTokenTimeout = body.airlineTokenTimeout
            HISTORY.update_auth_info(auth_info)
            local timeout = auth_info.airlineTokenTimeout / 1000 - E.time() - 60 * 60
            if timeout <= 0 then
                timeout = 1
            end
            E.Timer.once(timeout, M.refresh_token)
        else
            local code, msg = ...
            E.LOG.warn(TAG_AIRLINE_V2, 'token refresh fail, code=' .. tostring(code) .. ', msg=' .. tostring(msg))
        end
    end)
end

local debug_web_url = ''
function M.debug_set_web_url(new_url)
    debug_web_url = new_url
    E.LOG.debug(TAG_AIRLINE_V2, ' set_web_url, new_url=' .. tostring(new_url))
end

local new_host_table = {}
function M.debug_add_web_host(new_host)
    new_host_table[new_host] = true
    E.LOG.debug(TAG_AIRLINE_V2, ' add_web_host, new_host=' .. tostring(new_host))
end

function M.debug_clear_new_host_table()
    new_host_table = {}
    E.LOG.debug(TAG_AIRLINE_V2, ' clear_new_host_table')
end

local function debug_open_webview(url)
    local auth_info = HISTORY.get_auth_info()
    local airlineToken = (auth_info or {}).airlineToken
    local accountId = (auth_info or {}).accountId
    local params_ds_token = EG.user_info().ptoken or airlineToken
    local local_start_up_data = {
        pkg_info = E.get_pkg_info(),
        airlineToken = airlineToken,
        accountId = accountId,
        ds_token = params_ds_token,
        aegis_data = AEGIS_DATA.get_encrypt_data(),
        ejoysdk_ver = E.get_sdk_version_name('EJOYSDK')
    }

    E.LOG.debug(TAG_AIRLINE_V2, 'open_webview:' .. (url or 'nil') .. ', ds_token:' .. (params_ds_token or 'nil'))

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

    -- 从配置中心取
    local new_white_hosts = CONFIG.get_white_hosts()
    for _, new_host in pairs(new_white_hosts) do
        host[new_host] = { startupData = local_start_up_data }
    end

    -- 从debug添加的记录里取
    for new_host, _ in pairs(new_host_table) do
        host[new_host] = {
            startupData = local_start_up_data
        }
    end

    E.WebView.open(url, host, {
        compactMode = true,
        use_fragment = true,
        hide_close_btn = true
    })
end

function M.debug_show_h5()
    if #debug_web_url > 0 then
        debug_open_webview(debug_web_url)
    end
end

M:is_implemented({ "ACCOUNT" })

return M