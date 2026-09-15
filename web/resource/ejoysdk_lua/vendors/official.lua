-- 海外登录的主入口，其login函数会拉起webview网页
local E = require 'ejoysdk_lua.ejoysdk'
local Vendor = require 'ejoysdk_lua.vendors.vendor'
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local ET = require 'ejoysdk_lua.ejoysdk_topic'
local EV = require 'ejoysdk_lua.ejoysdk_vendors'
local USER = require 'ejoysdk_lua.user_center.ejoysdk_usercenter'
--local EC = require 'ejoysdk_lua.user_center.system_config'
--local ECC = require 'ejoysdk_lua.ejoysdk_config_center'
local UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local V = require "ejoysdk_lua.version"
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local AGST = require 'ejoysdk_lua.vendors.agst_account'
--local EJOYRES = require 'ejoysdk_lua.res.ejoysdk_res'
local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
local AEGIS_DATA = require 'ejoysdk_lua.aegis.aegis_collect_data'
local UP = require "ejoysdk_lua.user_center.usercenter_protocal"
local HISTORY = require 'ejoysdk_lua.account.official_history'
local EM = require "ejoysdk_lua.ejoysdk_module"

local EG = nil

local TAG = EM.MODULE.VENDORS.OFFICIAL
local RES_GAME_LOGIN = "${brand}_usercenter"
local VENDOR_NAME = 'OFFICIAL'
local OFFICIAL = Vendor:Inherit(VENDOR_NAME)
local AGST_OFFICIAL_SIGN = E.LazyKeyStore:New('AGST_OFFICIAL_SIGN')
local LAST_OFFICIAL_LOGIN_VENDOR = E.LazyKeyStore:New('LAST_OFFICIAL_LOGIN_VENDOR', false, false, false)
local LAST_LOGIN_SUCC_VENDOR = E.SPKeyStore:New('com.ejoy.sdk.lua', "LAST_LOGIN_SUCC_VENDOR")
local HTTP = E.HTTP
local pga_can_auto_login = false

local URL_CONFIG = {
    host = 'qookkagames.com',
    url_base = 'https://ww-hk-account.qookkagames.com',
    airline_info = {
        brand = 'qookka',
        node = 'hk'
    },
    API = {
        login = 'm#/start',
        quick_login = 'm#/quick', -- 快速登录
        user_center = 'm#/account',
        real_name = 'm#/realname', -- 实名
        login_intercept = 'm#/intercept', -- 登录拦截，目前用于儿童年龄校验和实名制，后续更多场景H5直接扩展就好
        user_detail_completion = "m#/account/completion?from=sdk",
        recharge_limit_err_tips = 'm#/recharge_limit_tips', -- 限额提示页
        recharge_limit_user_info = '', --限额时显示输入用户年龄等信息的页面
        recharge_limit_update_user_info = 'apiClient/sdkAccount/editUserInfoByToken' --限额时用于更新用户年龄等信息
    },
    -- 仅在列表中的才支持缓存
    --CACHE_API = {
    --    login = '#/start',
    --    quick_login = '#/quick', -- 快速登录
    --}
}

local function update_airline_url()
    local gangplank_config = EGC.get_current_cdn_config()
    if not gangplank_config then
        return
    end

    URL_CONFIG.url_base = gangplank_config['airline_center'] or URL_CONFIG.url_base
    URL_CONFIG.host = E.HTTP.parse(URL_CONFIG.url_base).host
    URL_CONFIG.airline_info = (gangplank_config['ext'] and gangplank_config['ext']['airline_info']) or URL_CONFIG.airline_info
    RES_GAME_LOGIN = string.gsub(RES_GAME_LOGIN, "${brand}", URL_CONFIG.airline_info.brand)
end

function OFFICIAL.get_api_url(api)
    local realapi = URL_CONFIG.API[api]
    local api_url = HTTP.uri_join(URL_CONFIG.url_base, realapi or api)
    return api_url
end

function OFFICIAL.can_pga_autologin()
    return pga_can_auto_login
end

local product_infos = {}
local pay_inited = false
local logining_vendor_name = nil

local function update_userinfo(vendor, user_info)
    if user_info and VENDOR_NAME == user_info.with and vendor and string.len(vendor) > 0 then
        if vendor == 'QR_LOGIN' then
            E.LOG.debug(TAG, 'qr_login not save login history')
            return
        end
        LAST_OFFICIAL_LOGIN_VENDOR:set(vendor)
        LAST_LOGIN_SUCC_VENDOR:set(vendor)
        HISTORY.update(user_info)
    end
end

local function auto_bind_pgs(user_info, login_vendor)
    local PGS_VENDOR = "PGA_LOGIN"
    -- isPga表示这个账号还没绑定过PGS账号(如果为true仅代表有绑定, 但不一定是绑定到当前登录的PGS账号上)
    if PGS_VENDOR == login_vendor or not EV.has_vendor(PGS_VENDOR) then
        return
    end

    -- 如果当前没PGA插件, 或者PGA还没登录, 都不会去绑
    (EV.get('PGA_LOGIN') or {}).get_auth_code(function(succ, ...)
        local LANG = require 'ejoysdk_lua.lang.util'
        if succ then
            -- 仅在PGS插件且已登录的情况下才显示提示
            local login_tips = ''
            local server_domain = E.CONFIG.get_config(E.CONFIG.KEY.SERVER_DOMAIN):lower()
            if '.sialiagames.com.tw' == server_domain then
                login_tips = '青鳥'
            elseif '.orientalgame.com.tw' == server_domain then
                login_tips = '東風'
            elseif '.vntth.com' == server_domain then
                login_tips = 'VNTTH'
            elseif '.qookkagames.com' == server_domain then
                login_tips = 'Qookka'
            elseif '.qoolandgames.com' == server_domain then
                login_tips = 'Qooland'
            end
            if user_info.isPga == true then
                E.Toast.show(string.format(LANG.getString('login_tips', ''), login_tips .. ' '), { use_native = true })
            else
                local data = ...
                if data and data.auth_code and '' ~= data.auth_code then
                    local ECM = require 'ejoysdk_lua.ejoysdk_channel_manager'
                    local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
                    ECM.bind('PGA_LOGIN', function(bind_succ, ...)
                        if bind_succ then
                            E.Toast.show(LANG.getString('pgs_auto_bind', 'Your account has bound to PGS'), { use_native = true })
                        else
                            local err_code = ...
                            E.LOG.debug(TAG, "bind failed, err_code=" .. tostring(err_code or CONSTANTS.OFFICIAL_ERR_CODES.CODE_BIND_FAIL))
                            E.Toast.show(string.format(LANG.getString('login_tips', ''), login_tips .. ' '), { use_native = true })
                        end
                    end)
                end
            end
        else
            E.LOG.debug(TAG, "pgs get auth_code failed")
        end
    end)
end

local init_handler = function()
    --尝试获取pgs能否自动登录
    if EV.has_vendor('PGA_LOGIN') then
        E.LOG.debug(TAG, 'pgs try get auth code')
        local pga_login = EV.get('PGA_LOGIN') or {}
        if pga_login.get_auth_code then
            pga_login.get_auth_code(function(succ, ...)
                if succ then
                    pga_can_auto_login = true
                    E.LOG.debug(TAG, 'pgs get auth code: true')
                else
                    pga_can_auto_login = false
                    E.LOG.debug(TAG, 'pgs get auth code: false')
                end
            end)
        end
    else
        E.LOG.debug(TAG, 'no PGA_LOGIN, pgs should not try get auth code')
    end
end

local auth_handler = function(user_info)
    E.LOG.debug(TAG, 'official auth_handler-----')
    if user_info and VENDOR_NAME == user_info.with and logining_vendor_name and string.len(logining_vendor_name) > 0 then
        -- 账号登录成功后更新登录历史
        update_userinfo(logining_vendor_name, user_info)
    end
end

local acquire_handler = function(user_info)
    E.LOG.debug(TAG, 'official acquire_handler -----')
    if user_info and VENDOR_NAME == user_info.with and logining_vendor_name and string.len(logining_vendor_name) > 0 then
        update_userinfo(logining_vendor_name, user_info)
        auto_bind_pgs(user_info, logining_vendor_name)
        logining_vendor_name = nil
    end
end

local login_handler = function(_user_info)
    E.LOG.debug(TAG, 'gangplank login_handler -----')

    if pay_inited then
        return
    end

    EG.product_infos_base(VENDOR_NAME, function(succ, infos)
        if succ then
            E.LOG.debug(TAG, "获取 OFFICIAL product info success >>")

            product_infos = infos
            ET.publish('purchase_inited', VENDOR_NAME, infos)

            E.LOG.debug(TAG, product_infos)

            pay_inited = true
        else
            local status = infos
            E.LOG.warn(TAG, "获取 OFFICIAL product info failure: " .. tostring(status))
        end
    end)
end

-- 全局错误码处理器，目前主要用于处理海外账号中心token过期，后续SDK实现token自动刷新功能
local function global_errcode_handler(_vendor_name, err_code)
    E.LOG.debug(TAG, 'global_errcode_handler, errCode:' .. (err_code or 'nil'))
    if err_code == USER.USER_CENTER_ERROR_CODES.ERR_TOKEN_EXPIRED
            or err_code == USER.USER_CENTER_ERROR_CODES.ERR_TOKEN_INVALID then
        E.LOG.warn(TAG, 'global_errcode_handler err_code:' .. tostring(err_code) .. ', token is invalid or expired, now need logout')
        EG.logout()
        return true
    end

    return false
end

local function check_login_res()
    ET.unsubscribe(ET.gangplank.GLOBAL_CDN_CONFIG_SUCC, check_login_res)
    update_airline_url()

    -- EJOYRES内部自动更新
    --local cache_switch = is_wv_use_local_res()
    --E.LOG.debug(TAG, "check_login_res cache_switch:" .. tostring(cache_switch))
    --if cache_switch == true then
    --    EJOYRES.res_update_by_key(RES_GAME_LOGIN) -- 提前检查更新
    --end
end

function OFFICIAL.init(opt, cb)
    HISTORY.init()
    ET.subscribe(ET.gangplank.INITED, init_handler)
    ET.subscribe(ET.gangplank.ACQUIRE, acquire_handler)
    ET.subscribe(ET.gangplank.USER_INFO_UPDATE, acquire_handler)
    ET.subscribe(ET.gangplank.AUTH_SUCC, auth_handler)
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.analytics.REGISTER, function(user_info)
        ESTAT.stat_action('register_result', logining_vendor_name, true, { trace_id = user_info.uid })
    end)

    E.LOG.debug(TAG, "official init begin")
    if EGC.get_global_cdn_config() then
        E.LOG.debug(TAG, "official init has cdn config")
        check_login_res()
    else
        E.LOG.debug(TAG, "official init wait for cdn config")
        ET.subscribe(ET.gangplank.GLOBAL_CDN_CONFIG_SUCC, check_login_res)
    end

    cb(true)
end

local function login_manual()
    local api = 'login'
    local host = URL_CONFIG.host
    local url = OFFICIAL.get_api_url(api)
    local official_history = require 'ejoysdk_lua.account.official_history'
    if next(official_history.get_list()) then
        api = 'quick_login'
        url = OFFICIAL.get_api_url(api)
    end

    local airline_brand = URL_CONFIG.airline_info.brand
    local airline_node = URL_CONFIG.airline_info.node

    local login_start = function(preferred, fallback)
        -- 前端需要知道当前的品牌与节点信息，用户品牌展示与接口请求

        local append_params = '?'
        if string.find(url, '?') then
            append_params = '&'
        end

        append_params = append_params .. 'airlineType=' .. airline_brand
        append_params = append_params .. '&' .. 'serverNode=' .. airline_node

        preferred.url = E.Utils.string_insert(preferred.url, append_params, string.find(preferred.url, '#'))
        fallback.url = E.Utils.string_insert(fallback.url, append_params, string.find(fallback.url, '#'))

        E.LOG.debug(TAG, "prefered url: " .. tostring(preferred.url) .. ',fallback url: ' .. tostring(fallback.url))
        local OL = require 'ejoysdk_lua.overseas.login'
        OL.open_login_webview(preferred, fallback)
    end

    local fallback = { url = url, host = host }
    local preferred = UTILS.deepcopy(fallback)
    login_start(preferred, fallback)

    --local cache_api = URL_CONFIG.CACHE_API[api or '']
    --if cache_api then
    --    EJOYRES.get_res(ECC.NAMESPACE.H5_RESOURCE, RES_GAME_LOGIN, function(succ, config)
    --        if succ then
    --            -- 使用缓存
    --            preferred.host = config.local_url
    --            preferred.url = 'file://' .. preferred.host
    --
    --            if _ejoysdk.os() ~= 'ios' then
    --                -- FIXME ios旧版本对本地页锚点支持有问题，native已修复，待版本铺开前先屏蔽锚点
    --                preferred.url = preferred.url .. ( cache_api or '')--..'#/start'
    --            end
    --        end
    --
    --        E.LOG.debug(TAG, "open url: " .. tostring(preferred.url))
    --        login_start(preferred, fallback)
    --    end)
    --else
    --    login_start(preferred, fallback)
    --end
end

function OFFICIAL.get_last_login()
    return LAST_OFFICIAL_LOGIN_VENDOR:get()
end

function OFFICIAL.login()
    E.LOG.tips(TAG, 'If you get a login error')
    update_airline_url()

    logining_vendor_name = nil
    local last_vendor = OFFICIAL.get_last_login()
    E.LOG.debug(TAG, 'last_vendor is ' .. tostring(last_vendor))
    local OL = require 'ejoysdk_lua.overseas.login'
    local OH = require 'ejoysdk_lua.account.official_history'
    --local ST = require 'ejoysdk_lua.vendors.st_account'
    local vendor = EV.get(last_vendor)
    local vendor_can_auto_login = true --默认可以自动登录
    if vendor and vendor.can_auto_login then
        -- 重新读取是否能自动登录
        vendor_can_auto_login = vendor.can_auto_login() -- vendor 本身可以自动登录
    end

    if last_vendor and string.len(last_vendor) > 0 and vendor_can_auto_login then
        -- 尝试匹配ST自动登录
        E.LOG.debug(TAG, '开始进行last_vendor的自动登录流程---')
        local last_user_info = OH.get_last_login_account()
        if ('ST_LOGIN' ~= last_vendor) == true and (last_user_info or {}).login_type == last_vendor then
            -- 如果本身就是ST自动登录就直接登就好

            -- 需要历史记录与最后的登录类型一致才认为登录的账号是一致的
            last_user_info.st = last_user_info.ptoken
            last_user_info.login_from = 'local'
            E.LOG.debug(TAG, '尝试使用ST登录')
            OL.login('ST_LOGIN', last_user_info, function(resp)
                if resp and resp.succ and resp.body and resp.body.token then
                    E.LOG.debug(TAG, 'ST登录成功')
                    OL.notify_login(resp.succ, resp.body.token)
                else
                    E.LOG.warn(TAG, 'ST登录失败')
                    login_manual()
                end
            end)
        else
            -- 自动上次的登录
            E.LOG.debug(TAG, 'last_user_info is')
            E.LOG.debug(TAG, last_user_info)
            OL.login(last_vendor, nil, function(resp)
                if resp and resp.succ and resp.body and resp.body.token then
                    OL.notify_login(resp.succ, resp.body.token)
                else
                    login_manual()
                end
            end)
        end
    else
        OL.try_auto_login(function(ret)
            if not ret then
                login_manual()
                --OL.open_login_webview(URL_CONFIG.host,get_api_url('login'))
            end
        end)
    end
end

local function open_webview(api, js_cb, close_cb)
    update_airline_url()
    local gangplank_user_info = EG.user_info()
    local usercenter_user_info = USER.user_info()

    E.WebView.open(
            OFFICIAL.get_api_url(api),
            {
                [URL_CONFIG.host] = {
                    startupData = {
                        area = E.CONFIG.get_config('district'),
                        language = E.CONFIG.get_config('lang'):lower(),
                        publish_area = E.CONFIG.get_config(E.CONFIG.KEY.PUBLISH_AREA) or '',
                        pkg_info = E.get_pkg_info(),
                        ejoy_token = gangplank_user_info.token,
                        uc_token = usercenter_user_info.token,
                        aegis_data = AEGIS_DATA.get_encrypt_data()
                    },
                    transparent = true
                },
            },
            { compactMode = true, use_fragment = true, hide_close_btn = false},
            function(_values)
                if js_cb then
                    js_cb(_values.args)
                end
            end,
            function(_values)
                if close_cb then
                    close_cb(_values.args)
                end
            end)
end

function OFFICIAL.open_user_center()
    open_webview('user_center')
end

-- 完善资料页
function OFFICIAL.open_userinfo_completion(cb)
    local result = false
    open_webview('user_detail_completion', function(_args)
        if cb and _args.type == 'update_user_info' then
            result = _args.result or false
            --cb(_args.result or false)
        end
    end, function()
        if cb then
            cb(result)
        end
    end)
end

-- 支付限额年龄信息更新
--local function open_pay_limitation_page(cb)
--    local result = {}
--    -- TODO 前端还没实现，留着
--    open_webview('recharge_limit_user_info',function(_args)
--        if cb and _args.type == 'update_age_info' then
--            result = _args.result or {}
--        end
--    end,function()
--        if cb then
--            cb(result)
--        end
--    end)
--end

-- 支付限额错误提示
local function open_pay_limitation_err_page(cb)
    open_webview('recharge_limit_err_tips', nil, function()
        if cb then
            cb()
        end
    end)
end

function OFFICIAL.merge_info(info, pinfo)
    return OFFICIAL.merge_helper(info, pinfo)
end

function OFFICIAL.simple_token()
    return false
end

function OFFICIAL.check_token(_outsource, _info)
    OFFICIAL.login()
end

function OFFICIAL.logout()
    E.WebView.close()
    -- 登出成功
    OFFICIAL.opt.logout_listener({})
end

-- 是否经过账号中心
function OFFICIAL.use_user_center()
    return true
end

OFFICIAL:is_implemented({ 'ACCOUNT'})

-------------------- 混合 ---------------------
local function proxy_auth_listener(vendor_name, auth_listener, proxy)
    return function(succ, ...)
        E.LOG.debug(TAG, 'proxy_auth_listener proxy login type: ' .. tostring(proxy.proxy_login_type) .. ', vendor_name:' .. (vendor_name or 'nil'))
        if succ then
            local outsource, ext = ...
            outsource = outsource or {}
            outsource.with = VENDOR_NAME

            auth_listener(true, outsource, ext)

            proxy.login_fail_intercept_times = 0
        else
            auth_listener(false, ...)
        end
    end
end

local function proxy_logout_listener(_vendor_name, logout_listener, proxy)
    return function(ext_params)
        if proxy.bind_logout_listener then
            E.LOG.debug(TAG, "proxy_logout_listener call bind_logout_listener")
            proxy.bind_logout_listener(ext_params)
            proxy.bind_logout_listener = nil
        else
            E.LOG.debug(TAG, "proxy_logout_listener call logout_listener")
            logout_listener(ext_params)
        end
    end
end

local function make_vendor_proxy(vendor_name, vendor)
    vendor = vendor or EV.get(vendor_name)
    if vendor then
        local proxy = vendor:Inherit(vendor_name .. '_PROXY')
        E.LOG.debug(TAG, '------make ' .. vendor_name .. ' official proxy-------')
        proxy.vendor_name = vendor_name
        proxy.init = function(opt, cb)
            proxy.proxy_old_auth_listener = opt.auth_listener
            opt.auth_listener = proxy_auth_listener(vendor_name, opt.auth_listener, proxy)
            opt.logout_listener = proxy_logout_listener(vendor_name, opt.logout_listener, proxy)
            opt.proxy = proxy
            vendor.init(opt, cb)
        end
        proxy.login_fail_intercept_times = 0
        proxy.login_fail = function(status, last_login_params, fail_cb)
            last_login_params = last_login_params or {}
            local stat_params = {
                outsource = last_login_params.outsource or {},
                info = last_login_params.info or {}
            }
            ESTAT.stat_action('login_result', vendor_name, false, stat_params)
            if proxy.login_fail_intercept_times > 1 then
                proxy.login_fail_intercept_times = 0
                return false
            end
            if vendor.login_fail then
                local result = vendor.login_fail(status, last_login_params, fail_cb)
                if result then
                    proxy.login_fail_intercept_times = proxy.login_fail_intercept_times + 1
                    E.LOG.debug(TAG, 'proxy.login_fail_intercept_times: ' .. tostring(proxy.login_fail_intercept_times))
                end
                return result
            else
                return false
            end
        end
        proxy.logout = function()
            E.LOG.debug(TAG, 'make_vendor_proxy receive logout, vendor_name:' .. tostring(vendor_name))
            -- first need usercenter logout
            USER.logout()
            -- then call vendor logout
            ESTAT.stat_action('logout', vendor_name)
            vendor.logout() -- 原来的vendor，如fb的

            --E.WebView.close() -- 游客转正后需要登出关闭webview
        end
        proxy.login = function(ext)
            proxy.proxy_login_type = 'login'
            ESTAT.stat_action('login', vendor_name)
            logining_vendor_name = vendor_name
            ext = ext or {}
            ext.vendor = vendor_name
            vendor.login(ext)
        end
        proxy.bind = function(bind_listener)
            proxy.proxy_login_type = 'bind'
            proxy.proxy_bind_listener = bind_listener
            ESTAT.stat_action('bind', vendor_name)
            vendor.login({ vendor = vendor_name })
        end
        proxy.bind_logout = function(cb)
            -- 绑定前先做注销操作，让玩家有重新选择绑定账号的机会
            proxy.bind_logout_listener = cb
            vendor.logout({ vendor = vendor_name })
        end
        proxy.use_user_center = function()
            -- official 下面的vendor都经过账号中心
            return true
        end

        proxy.is_support_ability = function(_self, abilities)
            for _, ability in ipairs(abilities) do
                local l = Vendor.get_methods(ability)
                for _, v in ipairs(l) do
                    local result = rawget(vendor, v)
                    if not result then
                        return false
                    end
                end
            end
            return true
        end

        return proxy
    end
    return nil
end

local pay_proxies_channel_ids = {
    OFFICIALPAY = '998236'
}

local function get_request_id()
    math.randomseed(os.time())
    local random_mills = math.random(1, 1000)
    local sys_clock = os.time() * 1000
    local random_time_in_mills = sys_clock + random_mills
    E.LOG.debug(TAG, 'get_request_id :' .. tostring(random_time_in_mills) .. ', sys_clock:' .. tostring(sys_clock) .. ', random_mills:' .. tostring(random_mills))
    return random_time_in_mills
end

local function update_pay_limitation(pay_limit_age_cb, rules, cb)
    local update_age = function(input_info)
        if (not input_info or not input_info.area or not input_info.birthday) then
            cb(false, 5004001, '年龄输入错误')
            return
        end
        local gangplank = require 'ejoysdk_lua.ejoysdk_gangplank'
        -- 发送http请求更新，此处的请求有点特殊，协议是用户中心的，但接口是前端的，前端会直接透到用户中心
        -- 协议 https://yuque.antfin.com/ejoy-platform/ejoy-platform/ck13ul
        local url = OFFICIAL.get_api_url('recharge_limit_update_user_info')
        local user_info = gangplank.user_info()
        local user_center_info = USER.user_info()
        local params = {
            opType = 3,
            gameId = E.get_pkg_info().game_id or '',
            token = user_info.ptoken or '', -- 账号中心token
            ejoyId = user_center_info.ejoyId or '',
            openId = user_center_info.openId or '',
            receiveEjoyEmailType = 2,
            area = input_info.area or '',
            birthday = input_info.birthday or ''
        }
        UP.post_to(url, '', params, cb)
    end

    if (pay_limit_age_cb) then
        -- 外部有实现
        pay_limit_age_cb(rules, update_age)
        --elseif(open_pay_limitation_page)then
        --    -- 显示默认的错误页
        --    open_pay_limitation_page(update_age)
    else
        cb(false, -1, '无年龄输入实现')
    end
end

local function create_official_order(order_id, channel_id, params, cb, override)
    local gangplank_config = EGC.get_current_cdn_config()
    local payment_center_url = gangplank_config.payment_center .. '/client/pay.order.create' .. '?ver=1.0&df=json&gt=ng&cver=1.0.0' .. '&os=' .. E.Sysinfo.os()

    E.LOG.debug(TAG, 'payment_center_url: ' .. tostring(payment_center_url))
    E.LOG.debug(TAG, 'create official order, order id: ' .. tostring(order_id) .. ', >>')
    E.LOG.debug(TAG, params)
    local last_login_vendor = EG.get_last_login()
    local order_info = UTILS.deepcopy(params.cb)

    order_info.area = E.CONFIG.get_config('district')
    order_info.gameRegion = gangplank_config.region
    order_info.token = EG.user_info().ptoken
    order_info.orderSrc = E.Sysinfo.os()
    order_info.thirdPartyType = (EG.user_info() or {}).platform or ''-- 三方渠道类型，与登录相关

    local post_params = {
        id = get_request_id(), -- 使用和灵犀相同的 id 生成
        client = {
            ve = V.LUA_VERSION,
            gameId = E.get_pkg_info().game_id,
            os = E.Sysinfo.os(),
            channelId = channel_id,
            si = 'si',
            pkgInfo = E.get_pkg_info()
        },
        data = order_info
    }

    E.LOG.debug(TAG, 'log official post params >>')
    E.LOG.debug(TAG, post_params)

    local fail_cb = function(resp, common_cb)
        local state = resp.body.state
        local ERR_CODE_NEED_AGE = 5004001
        local ERR_CODE_PAY_LIMITATION = 5004002
        local rule = {}
        if (state.code == ERR_CODE_NEED_AGE or state.code == ERR_CODE_PAY_LIMITATION) and resp.body.data then
            rule = resp.body.data
            state.msg = JSON.encode(rule)
        end

        if (state.code == ERR_CODE_NEED_AGE) then
            update_pay_limitation(override.pay_limit_age_cb, rule, function(succ, ...)
                if (succ) then
                    --更新成功，重新请求
                    create_official_order(order_id, channel_id, params, cb, override)
                else
                    common_cb()
                    local code, msg = ...
                    E.LOG.debug(TAG, "failed to update user info, code: " .. tostring(code) .. ",msg=" .. tostring(msg))
                end
            end)
        elseif (state.code == ERR_CODE_PAY_LIMITATION and not override.pay_limit_custom_err) then
            open_pay_limitation_err_page(common_cb)
        else
            common_cb()
        end
    end

    E.LOG.debug(TAG, 'create official order')
    E.HTTP.post(payment_center_url, { trace = true, acceptable = HTTP.CT_JSON }, HTTP.CT_JSON, post_params, function(resp)
        --E.LOG.debug(TAG, resp)
        if resp.status == 200 then
            local state = resp.body.state
            if state.code == 2000000 then
                cb(true, resp.body.data)
            else
                fail_cb(resp, function()
                    cb(false, state.code, state.msg)
                    global_errcode_handler(last_login_vendor, state.code)
                end)
            end
        else
            cb(false, resp.status, '')
        end
    end)
end

local function make_pay_vendor_proxy(vendor_name, vendor)
    vendor = vendor or EV.get(vendor_name)
    if vendor then
        local proxy = vendor:Inherit(vendor_name .. '_PAY_PROXY')
        E.LOG.debug(TAG, '------make ' .. vendor_name .. ' official proxy-------')
        proxy.init = function(opt, cb)
            proxy.proxy_pay_listener = opt.pay_listener
            vendor.init(opt, cb)
        end
        proxy.pay = function(product_id, count, order_id, body, override)
            if vendor and vendor.skip_official_order and vendor.skip_official_order() then
                vendor.pay(product_id, count)
            else
                create_official_order(order_id, pay_proxies_channel_ids[vendor_name], body, function(succ, ...)
                    if succ then
                        local local_params = {
                            gp_order_id=order_id,
                            product_info=product_infos[product_id]
                        }

                        local data = ...
                        data.channelEx = data.channelEx or {}
                        -- 注意：data.channelEx不要去改，支付SDK会验签的，改了会验签失败，导致不能支付。
                        vendor.pay(product_id, count, data.accountOrderId, data.channelEx, local_params)
                    else
                        local code, msg = ...
                        local ext = { code = code, msg = msg, platform = vendor_name }
                        proxy.proxy_pay_listener(false, order_id, ext)
                    end
                end, override)
            end
        end
        proxy.product_list = function()
            return product_infos
        end
        proxy.vendor_channel = function()
            return VENDOR_NAME
        end
        proxy.can_pay = vendor.can_pay
        return proxy
    end
    return nil
end

local proxies = {
    FB = function()
        return make_vendor_proxy('FB')
    end,

    -- iOS GameCenter登录，
    APPLE = function()
        return make_vendor_proxy('APPLE')
    end,

    -- Apple ID登录，
    APPLE_LOGIN = function()
        return make_vendor_proxy('APPLE_LOGIN')
    end,

    GOOGLE = function()
        return make_vendor_proxy('GOOGLE')
    end,

    GOOGLE_PLAY = function()
        return make_vendor_proxy('GOOGLE_PLAY', EV.get('GOOGLE'))
    end,

    -- 游客登录
    AGST = function()
        return make_vendor_proxy(AGST.VENDOR_NAME)
    end,

    -- 自有账号的主体登录逻辑，如Qookka，
    AIRLINE = function()
        return make_vendor_proxy('AIRLINE')
    end,

    -- Twitter登录
    TWITTER_LOGIN = function()
        return make_vendor_proxy('TWITTER_LOGIN')
    end,

    -- BBGameSDK登录，for SGZ2017账号迁移
    BBG_LOGIN = function()
        return make_vendor_proxy("BBG_LOGIN")
    end,

    -- 华为登录
    HW_LOGIN = function()
        return make_vendor_proxy("HW_LOGIN")
    end,

    -- LINE登录
    LINE = function()
        return make_vendor_proxy("LINE")
    end,

    -- CITA_引继码
    CITA_LOGIN = function()
        return make_vendor_proxy("CITA_LOGIN")
    end,

    ST_LOGIN = function()
        return make_vendor_proxy("ST_LOGIN")
    end,

    PGA_LOGIN = function()
        return make_vendor_proxy("PGA_LOGIN")
    end,

    QR_LOGIN = function()
        return make_vendor_proxy("QR_LOGIN")
    end,

    DMM_LOGIN = function()
        return make_vendor_proxy("DMM_LOGIN")
    end,

    -- 聚合页面类型的登录逻辑，触发登录即弹窗聚合登录页面，由用户自行选择具体登录方式。
    -- 聚合哪些登录方式由包体的sdkconfig.json、账号中心后台配置，两者决定。
    OFFICIAL = function()
        return make_vendor_proxy('OFFICIAL', OFFICIAL)
    end
}

local pay_proxies = {
    OFFICIALPAY = function()
        return make_pay_vendor_proxy('OFFICIALPAY')
    end
}

function OFFICIAL.get_pay_notify_url(vendor_name)
    local pay_channel_id = pay_proxies_channel_ids[vendor_name]
    return EGC.get_current_cdn_config().payment_center .. '/cs/' .. pay_channel_id
end

function OFFICIAL.get_umbrella_vendors(vendors)
    EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    local out = {}
    for name, _ in pairs(vendors) do
        if proxies[name] then
            out[name] = proxies[name]()
        end
        if pay_proxies[name] then
            out[name] = pay_proxies[name]()
        end
    end
    return out
end

-- 标记转正
function OFFICIAL.mark_agst_official()
    AGST_OFFICIAL_SIGN:set(true)
end

-- 清除转正
function OFFICIAL.clear_agst_official_sign()
    AGST_OFFICIAL_SIGN:delete()
end

-- 判断是否已经转正
function OFFICIAL.has_marked_agst_official()
    return AGST_OFFICIAL_SIGN:get() or false
end

function OFFICIAL.reset_last_official_login()
    LAST_OFFICIAL_LOGIN_VENDOR:set('')
end
return OFFICIAL
