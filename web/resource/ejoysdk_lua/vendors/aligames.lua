local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local uuid = require "ejoysdk_lua.ejoysdk_uuid"
local EV = require 'ejoysdk_lua.ejoysdk_vendors'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local DS_PROXY = require 'ejoysdk_lua.vendors.ds_login_proxy'
local AIRLINE_V2 = require "ejoysdk_lua.vendors.airline_v2"
local EM = require "ejoysdk_lua.ejoysdk_module"
local ACF = require "ejoysdk_lua.vendors.aligames_config"
local WP = require 'ejoysdk_lua.vendors.win_official_pay'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'

local CHANNEL = "ALIGAMES"
local UNISDK_CHANNEL = "ALIGAMES"
local TAG =  EM.MODULE.VENDORS.ALIGAMES

local ASYNC_INVESTIGATION = "ASYNC_INVESTIGATION"
--local ASYNC_EXIT = "ASYNC_EXIT"

--local ASYNC_SET_EXT_DATA = "ASYNC_SET_EXT_DATA"
local ASYNC_CALL_WEB_VIEW = "ASYNC_CALL_WEB_VIEW"

local CAST_GAME_STARTED = "CAST_GAME_STARTED"
local CAST_GAME_EVENT = "CAST_GAME_EVENT"
local CAST_ADD_LOCAL_NOTIFICATION = "CAST_ADD_LOCAL_NOTIFICATION"
local CAST_SHOW_CUSTOMER_SERVICE_WEB = "CAST_SHOW_CUSTOMER_SERVICE_WEB"
local CAST_CLEAR_LOCAL_NOTIFICATION = "CAST_CLEAR_LOCAL_NOTIFICATION"
local CAST_CREATE_ROLE = "CAST_CREATE_ROLE"
local CAST_ROLE_LEVEL_UP = "CAST_ROLE_LEVEL_UP"
local CAST_GIFT_CODE = "CAST_GIFT_CODE"
local CAST_QRCODE_SCAN = "CAST_QRCODE_SCAN" --扫描二维码
local CAST_CUSTOM_SERVICE = "CAST_CUSTOM_SERVICE"
--local CAST_SET_ORIENTATION = "CAST_SET_ORIENTATION"

local SYNC_GET_DEVICE_ID = "SYNC_GET_DEVICE_ID"
local SYNC_GET_PUSH_TOKEN = "SYNC_GET_PUSH_TOKEN"
--local SYNC_GET_API_AVAILABLE = "SYNC_GET_API_AVAILABLE"

local SYNC_UTDID = "SYNC_UTDID"
local SYNC_IS_EMULATOR = "SYNC_IS_EMULATOR"
local SYNC_GET_CHANNELID = "SYNC_GET_CHANNELID"
local SYNC_GET_SUB_CHANNELID = "SYNC_GET_SUB_CHANNELID"
local SYNC_GET_FT_VERSION = 'SYNC_GET_FT_VERSION'

local SYNC_IS_SUPPORT_ALI_AUTH = 'SYNC_IS_SUPPORT_ALI'..'PAY_AUTH'
local SYNC_IS_SUPPORT_IOS_LOGOUT = 'SYNC_IS_SUPPORT_IOS_LOGOUT'

local ASYNC_ALI_AUTH = 'ASYNC_ALI'..'PAY_AUTH'
local ASYNC_ALI_AUTH_V2 = 'ASYNC_ALI'..'PAY_AUTH_V2'
local ASYNC_READ_APK_CHANNEL_EXTRA_INFO = "ASYNC_READ_APK_CHANNEL_EXTRA_INFO"

-- iOS 特有
local ASYNC_RECORD_START = "ASYNC_RECORD_START"
local ASYNC_RECORD_STOP = "ASYNC_RECORD_STOP"

local CAST_ORDER_RETRY = "CAST_ORDER_RETRY"
local CAST_BORADCAST = "CAST_BORADCAST"
local CAST_UPDATE_ALIGAMES_CLIENT_EXTRA_DATA = "CAST_UPDATE_ALIGAMES_CLIENT_EXTRA_DATA"

local CLOSE_EVENT_DATA_USER_CENTER = "aligames_user_center"
local CLOSE_EVENT_DATA_BBS = "aligames_bbs"
local CLOSE_EVENT_DATA_CUSTOM = "aligames_custom"
local CLOSE_EVENT_DATA_CUSTOMER_SERVICE = "aligames_customer_service"

local EVENT_NOTIFY_ACCOUNT_DATA = "EVENT_NOTIFY_ACCOUNT_DATA"

local PAY_FAILED_NOT_REALNAME = -10001
local PAY_FAILED_LIMITED = -10002
-- 缓存本地游戏设置的productcode，方便下次启动时直接读取
local CUR_PRODUCTCODE_SP = E.LazyKeyStore:New('EJOY_CUR_PRODUCTCODE_SP', false, false, false)

local M = Vendor:Inherit(CHANNEL)

M.EVT_SWITCH_USER_SUCC = "EVT_SWITCH_USER_SUCC"
M.EVT_SWITCH_USER_CANCEL = "EVT_SWITCH_USER_CANCEL"
M.EVT_SWITCH_USER_FAIL = "EVT_SWITCH_USER_FAIL"

local auth_listener = nil
local logout_listener = nil
local pay_listener = nil
local switch_listener = nil
local exit_listener = nil
local qrcode_listener = nil
local pay_inited = false
local product_infos = {}
local sysinfo = {}
local role_info = {}
local pay_params = {}
local bbs_url = nil
-- vendor授权信息
local AUTH_INFO = {}
local aligames_ext_params = {}

local aligames_login_data = nil -- 自研游戏登录后的数据，iOS需要使用，以避免cookie问题
-- 统计商品列表重试次数
local products_request_times = 0

M.QRCODE_CONST = {
    STATE_GENFAIL = "gen_fail",
    STATE_GENSUCC = "gen_succ",
    STATE_SCANED  = "scaned",
    STATE_TIMEOUT = "timeout",

    TYPE_LOGIN = "login",
    TYPE_PAY   = "pay"
}

-- 获取当前登录用户的数据，包括token，sid之类的，目前仅iOS支持，安卓cookie很稳定暂不需要。
-- 数据样例见https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/bmerag#PrM7X
function M.get_current_login_user_data()
    return aligames_login_data or {}
end

function M.check_products()
    EG.product_infos_base(CHANNEL, function(succ, infos)
        products_request_times = products_request_times + 1
        if succ then
            E.LOG.debug(TAG,"获取 aligames product info success")

            product_infos = infos
            ET.publish('purchase_inited', CHANNEL)

            E.LOG.debug(TAG, product_infos)

            pay_inited = true

            local stat_params = {}
            stat_params.request_times = products_request_times
            ESTAT.stat_action('products_check', nil, true, stat_params)
        else
            E.LOG.error(TAG,"获取 aligames product info failure")

            if AUTH_INFO ~= nil and next(AUTH_INFO) ~= nil then
                E.LOG.debug(TAG, "it's login state, and need recheck products")
                E.Timer.once(5, M.check_products)

                if products_request_times == 50 then
                    E.LOG.warn(TAG, "check_products reaches so much times, need stat")
                    local stat_params = {}
                    stat_params.request_times = products_request_times
                    ESTAT.stat_action('products_check', nil, false, stat_params)
                end
            else
                E.LOG.debug(TAG, "check_products logout state, not need check products")
            end
        end
    end)
end

local login_handler = function()
    -- 已经初始化了pay，不需再次执行
    if pay_inited then
        return
    end

    E.LOG.debug(TAG, "开始获取 aligames product info")

    -- 重置商品列表请求次数
    products_request_times = 0
    M.check_products()
end

local function update_ext_params()
    E.LOG.debug(TAG, "init_handler CAST_UPDATE_ALIGAMES_CLIENT_EXTRA_DATA params >>")
    E.LOG.debug(TAG, aligames_ext_params)
    UNI.cast(UNISDK_CHANNEL, CAST_UPDATE_ALIGAMES_CLIENT_EXTRA_DATA, aligames_ext_params)
end

local init_handler = function()
    E.LOG.debug(TAG, "监听到gangplank初始化成功")
    local UIM = require "ejoysdk_lua.user_info_manager"
    local cloud_game_info = UIM.get_cloud_game_info()
    local cloud_game_run_mode = cloud_game_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_RUN_MODE]
    -- 详细 ex 字段定义参考：https://yuque.antfin-inc.com/mxb7qq/confluence-sdkdev-vg6uys/18108448

    aligames_ext_params.mobileRunMode = cloud_game_run_mode

    local product_code = E.CONFIG.get_config("product"):lower()
    aligames_ext_params.productCode = product_code
    update_ext_params()

    -- save to sp
    E.LOG.debug(TAG, "init save productcode:" .. tostring(product_code))
    CUR_PRODUCTCODE_SP:set(product_code)
end

local productcode_change_handler = function()
    local cur_product = E.CONFIG.get_config("product")
    if cur_product ~= aligames_ext_params.productCode then
        E.LOG.debug(TAG, "update productCode:" .. tostring(cur_product) .. ", previous:" .. tostring(aligames_ext_params.productCode))
        aligames_ext_params.productCode = cur_product

        update_ext_params()

        -- save to sp
        CUR_PRODUCTCODE_SP:set(cur_product)
    end
end

local set_player_info_handler = function(player_info, type)
    role_info = {
        roleId      = player_info.player_id,
        roleName    = player_info.player_name,
        roleLevel   = player_info.level,
        zoneId      = player_info.server_id,
        zoneName    = player_info.server_name,
        opportunityType = type
    }
    E.LOG.debug(TAG, "=================== set_role_info ===========================")
    E.LOG.debug(TAG, role_info)
    UNI.set_player_info(CHANNEL, player_info, type)
end

local IOS_PAY_UN_CERTIFICATION = 'UN_CERTIFICATION'
local IOS_PAY_UNDER_AGE_OVER_LIMIT = 'UNDER_AGE_OVER_LIMIT'

local get_ios_pay_error = function(msg)
    if not msg then
        return nil
    end
    local pattern = 'NSLocalizedDescription=(.-)%[(.-)%]'
    local error_msg, error_code
    msg:gsub(pattern, function(p1, p2)
        error_msg = p1
        error_code = p2
    end)

    return error_code, error_msg
end

local get_android_pay_error = function(msg)
    if not msg then
        return nil
    end

    local pattern = "%((-*%d+)%).*"
    local code = string.match(msg, pattern)
    return code
end

-- 检查是否需要走新的大圣登录流程
function M.need_go_new_ds_login_protocol_ios()
    -- 是iOS且支持钉钉登录且优先级高于灵犀登录，那就走新的流程，否则还是走老流程
    if _ejoysdk.os() == "ios" and DS_PROXY.check_if_support_dingding_login() then
        return true
    end

    return false
end

function M.need_go_new_ds_login_protocol_windows()
    if _ejoysdk.os() == "windows" and DS_PROXY.check_if_support_lingxi_login_v2() then
        return true
    end

    return false
end

-- 是否需要走灵犀2.0的登录页
function M.need_go_lingxi_login_v2_ios()
    if _ejoysdk.os() == "ios" and DS_PROXY.check_if_support_lingxi_login_v2() then
        return true
    end

    return false
end

local function go_lingxi_login_v2_ios()
    AIRLINE_V2.exec_login(function(succ, token, brand, accountOs)
        E.log('airline login callback ------')
        if not accountOs or accountOs == '' then
            accountOs = 'ios'
        end
        if succ then
            E.LOG.debug(TAG, 'airline login success')
            -- airline登录成功，准备开始大圣登录
            local ds_param = {
                channelId = E.get_channel(), -- 渠道号，这里没有lingxi所以需要换个函数
                ex = {
                    loginType = "phone",
                    airline = brand,
                    token = token,
                    accountOs = accountOs
                }
            }
            E.log('ds_param = ')
            E.log(ds_param)
            DS_PROXY.login_to_ds_service(ds_param, function(ds_succ, body)
                if ds_succ then
                    E.LOG.debug(TAG, 'ds login success---')
                    E.log(body)

                    local outsource = {
                        platform = E.get_channel(),
                        with = CHANNEL,
                        ptoken = body.token,
                        pid = '', --info.pid,--这个值没有
                        --guest = false,
                        ext = {}
                    }

                    if auth_listener then
                        E.LOG.debug(TAG, ' star call auth_listener_callback_function')
                        auth_listener(ds_succ, outsource, {})
                    else
                        E.LOG.debug(TAG, ' not has auth_listener_callback_function')
                    end
                else
                    E.LOG.error(TAG, 'ds login failed---')
                    local outsource = {
                        code = body.code,
                        msg = body.message or ''
                    }
                    auth_listener(ds_succ, outsource, {})
                end
            end)
        else
            -- airline 登录失败
            E.LOG.error(TAG, 'airline login failed')
        end
    end)
end


function M.login()
    E.LOG.tips(TAG, 'If you get a login error')
    if _ejoysdk.os and _ejoysdk.os() == "windows" then
        if M.need_go_new_ds_login_protocol_windows() then
            E.log(TAG.." 走新的大圣登录的流程")
            DS_PROXY.set_auth_listener(function(succ, params, ext)
                E.log(TAG..'回调auth_listener_callback_function')
                auth_listener(succ, params, ext)
            end)


            DS_PROXY.login()
        else
            M.get_login_qrcode(function (succ, info)
                if succ then
                    -- 回调二维码生成成功
                    qrcode_listener(M.QRCODE_CONST.STATE_GENSUCC, info, M.QRCODE_CONST.TYPE_LOGIN)
                    -- 轮询登录二维码扫描状态
                    M.poll_qrcode_login_status()
                else
                    --回调二维码生成失败
                    qrcode_listener(M.QRCODE_CONST.STATE_GENFAIL, info, M.QRCODE_CONST.TYPE_LOGIN)
                end
            end)
        end
    else
        -- 这是iOS的钉钉登录
        if M.need_go_new_ds_login_protocol_ios() then
            E.LOG.debug(TAG, " 走新的大圣登录的流程")
            DS_PROXY.set_auth_listener(function(succ, params, ext)
                E.LOG.debug(TAG, '回调auth_listener_callback_function')
                auth_listener(succ, params, ext)
            end)


            DS_PROXY.login()
            return
        end


        if M.need_go_lingxi_login_v2_ios() then
            -- 灵犀2.0的逻辑，看看是不是判断sdkconfig.json里包含airline_v2
            E.log('走airline_V2的登录流程----')
            go_lingxi_login_v2_ios()

            return
        end

        E.LOG.debug(TAG, '走原来的登录流程')

        local nonce = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.randomkey())
        UNI.login(UNISDK_CHANNEL, {nonce = nonce})
    end
end

local function logout_callback(params)
    logout_listener(params)
    --清空auth_info
    AUTH_INFO = {}

    aligames_login_data = nil -- 退出登录时清理数据
end

function M.logout()
    aligames_login_data = nil -- 退出登录时清理数据

    if E.CONFIG.get_config('os') == 'android' then
        UNI.logout(UNISDK_CHANNEL)
    elseif E.CONFIG.get_config('os') == 'ios' then
        if M.need_go_new_ds_login_protocol_ios() then
            DS_PROXY.logout()
            return
        end


        if M.need_go_lingxi_login_v2_ios() then
            -- 灵犀2.0的逻辑，看看是不是判断sdkconfig.json里包含airline_v2
            E.log('走airline_V2的退出登录流程----logout')
            AIRLINE_V2.exec_logout()
            return
        end


        local value = UNI.sync_call(UNISDK_CHANNEL, SYNC_IS_SUPPORT_IOS_LOGOUT, {})
        if value and value.support then -- 新版本灵犀 SDK 才支持 logout。旧版灵犀 SDK 存在需重发验证码问题
            UNI.logout(UNISDK_CHANNEL)
        else
            logout_callback({})
        end
    else

        if M.need_go_new_ds_login_protocol_windows() then
            DS_PROXY.logout()
        else

            logout_callback({})

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

function M.can_pay()
    return pay_inited
end

function M.vendor_channel()
    return CHANNEL
end

local g_gangplank_pay_callback_table = {}
local function hander_android_pay_timeout_callback(order_id)
    g_gangplank_pay_callback_table[order_id] = true -- 设一个值

    -- 延迟5分钟检查有无回调过来
    local timeout_value = 5 * 60
    -- 留个口子，也可以从轻舟配置下发这个超时时间
    local ECC = require 'ejoysdk_lua.ejoysdk_config_center'
    local BizConfig = ECC.get_config(ECC.NAMESPACE.EJOYSDK_BIZ)
    local BizConfigData = BizConfig and BizConfig.config
    if BizConfigData and BizConfigData.time_config and BizConfigData.time_config.pay_callback_time_out then
        timeout_value = tonumber(BizConfigData.time_config.pay_callback_time_out)
    end

    E.Timer.once(timeout_value, function()
        E.LOG.debug(TAG,'支付的超时回调来啦----')
        E.LOG.debug(TAG, 'order_id = '..tostring(order_id))
        -- 确保是同一次支付调用，如果是新的支付调用来了
        if not g_gangplank_pay_callback_table[order_id] then
            -- 已经回调过的，则不再回调
            E.LOG.debug(TAG,'之前已经回调过该次支付，或者其他原因清理了缓存数据，直接丢弃本次超时回调')
            return
        end

        -- 渠道还没回调过来，则主动发一个超时回调
        local ext_params = {}
        ext_params.ext = {}
        ext_params.ext.code = CONSTANTS.CHANNEL_ERROR_CODE.CHANNEL_PAY_TIMEOUT
        --ext_params.ext.msg = 'channel pay timeout' -- 国内版署不能有英文
        E.LOG.debug(TAG,'回调游戏本次支付超时')

        pay_listener(false, order_id, ext_params)
        g_gangplank_pay_callback_table[order_id] = nil --  删除掉

    end)
end

local function handle_pay_result(succ, _order_id, ext_params)
    E.LOG.debug(TAG, 'aligames lua pay listener, succ: ' .. tostring(succ))
    E.LOG.debug(TAG, 'order_id ==='..tostring(_order_id))
    E.LOG.debug(TAG, ext_params)
    local os = E.Sysinfo.os()
    if os == 'android' and (not g_gangplank_pay_callback_table[_order_id]) then
        -- 九游渠道返回的是渠道订单id，而不是gangplank的订单i，支付取消甚至oder_id是空字符串，所以匹配不上会进来这里
        local utils = require "ejoysdk_lua.ejoysdk_utils"
        if not _order_id or string.len(tostring(_order_id)) == 0 or utils.tablelength(g_gangplank_pay_callback_table) > 0  then
            -- 九游支付取消或失败的情况
            -- 九游支付成功的情况，因为order_id不匹配会进来这里，但是还没给游戏支付回调(缓存里有值)，此时需要回调给游戏，不能return
            E.LOG.debug(TAG, 'g_gangplank_pay_callback_table 里找不到order_id，是因为order_id为空，或者 order_id不是gangplank创建的导致匹配不上. order_id = '.. tostring(_order_id))
            E.LOG.debug(TAG, '此时依然需要给游戏支付回调，且同时清空缓存table，避免5分钟后继续超时回调支付pay_listener')
            g_gangplank_pay_callback_table = {} -- 清空缓存数据
        else
            -- 其他情况order_id是正常的，来到此处则表示已经回调过，则不再回调
            E.LOG.debug(TAG, '之前已经回调过支付callback，本次不再进行回调')
            return
        end

    end


    if not succ then
        ext_params.ext = ext_params.ext or {}
        if os == 'ios' then
            -- for test
            --ext_params.ext.msg = 'Error Domain=IAPServerError Code=0 \"实名制信息错误[UN_CERTIFICATION]\" UserInfo={status=error, error_msg=实名制信息错误, NSLocalizedDescription=先实名制，再支付[UN_CERTIFICATION], certification_info={\n    \"certification_result\" = 00;\n    \"is_force\" = 1;\n}, error_code=REALNAME_ERROR}'
            --ext_params.ext.msg = 'Error Domain=IAPServerError Code=0 \"实名制信息错误[UN_CERTIFICATION]\" UserInfo={status=error, error_msg=实名制信息错误, NSLocalizedDescription=因防沉迷限制，您单笔充值不能超过5元，请降低充值金额后再试[UNDER_AGE_OVER_LIMIT], certification_info={\n    \"certification_result\" = 00;\n    \"is_force\" = 1;\n}, error_code=REALNAME_ERROR}'

            local error_code, error_msg = get_ios_pay_error(ext_params.ext.msg)
            E.LOG.error(TAG, 'pay aligames error_code: ' .. tostring(error_code))
            if error_code == IOS_PAY_UN_CERTIFICATION then
                ext_params.ext.code = PAY_FAILED_NOT_REALNAME
                ext_params.ext.msg = error_msg
                pay_listener(false, _order_id, ext_params)
                return
            elseif error_code == IOS_PAY_UNDER_AGE_OVER_LIMIT then
                ext_params.ext.code = PAY_FAILED_LIMITED
                ext_params.ext.msg = error_msg
                pay_listener(false, _order_id, ext_params)
                return
            end
        elseif os == 'android' then
            local err_msg = ext_params.msg
            local code = get_android_pay_error(err_msg)
            E.LOG.error(TAG, "pay failed, err_msg:"..(err_msg or 'nil')..', code:'..(code or 'nil'))
            if code and #code > 0 then
                ext_params.ext.code = code
                ext_params.ext.msg = err_msg
                E.LOG.warn(TAG, "pay failed ext params >>")
                E.LOG.warn(TAG, ext_params)
                pay_listener(false, _order_id, ext_params)
                if _order_id then -- 判空
                    g_gangplank_pay_callback_table[_order_id] = nil
                end
                E.LOG.debug(TAG,'回调支付失败')
                return
            end
        elseif os == 'windows' then
            -- 成功和失败的参数解析
            E.LOG.debug(TAG, "nothing to do here")
        end
    end


    pay_listener(succ, _order_id, ext_params)
    if os == 'android' then
        if _order_id then -- 判空
            g_gangplank_pay_callback_table[_order_id] = nil
        end
        E.LOG.debug(TAG,'android回调支付')
    end
end

local function gen_failed_ext_params(_code, _msg)
    return {
        code = _code,
        msg = _msg
    }
end

-- 阿里游戏要求 product_id 是整形
function M.pay(product_id, _count, order_id, _body)
    E.LOG.tips(TAG, 'If you get a payment error')
    local product = product_infos[product_id]
    assert(product, "product_id " .. tostring(product_id) .. " not found")
    --local p = E.CONFIG.get_config('product'):lower()
    local money = product.money
    if _ejoysdk.os() == 'ios' then
        money = tonumber(product.money)
        money = money / 100.0
        E.LOG.debug(TAG,'aligames pay, product = ')
        E.LOG.debug(TAG, product)
    end


     pay_params = {
        cpOrderId = order_id,
        amount = money,
        moneyType = product.money_type,
        payProductID = product.product_id,
        payProductName = product.product_desc,
        payProductDescribe = product.product_desc,
        -- product_type没有就默认是消费型  https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/oevt5u#HGxIK
        payProductType = product.product_type or 1,
        payCallbackURL = EG.gangplank_url('/notify/aligames'),
        payCallbackParams = '' -- 透传参数
    }
    E.LOG.debug(TAG, "pay params >>")
    E.LOG.debug(TAG, pay_params)

    local os = _ejoysdk.os and _ejoysdk.os()
    if os == 'ios' then
        local CG = require('ejoysdk_lua.cloud_game.cloud_config')
        local pkgInfo = E.get_pkg_info()
        if pkgInfo.cloud_game_mode and pkgInfo.cloud_game_mode == CG.CLOUD_MODE.MOBILE then
            E.LOG.debug(TAG, 'ios云微端才需要拼接这个后缀')
            pay_params.payProductID = product.product_id .. '.cloud_ejoy'
            local temp_params = {cloudSuffix='.cloud_ejoy'}
            local params_str = JSON.encode(temp_params)
            pay_params.payCallbackParams = params_str
        end
    end

    if os == 'android' then
        hander_android_pay_timeout_callback(order_id)
    end

    if os ~= "windows" then
        UNI.pay(UNISDK_CHANNEL, order_id, pay_params)
    elseif WP:is_support_ability({EV.ABILITY.PAY}) then
        E.LOG.debug(TAG, "pay find support vendor win_official_pay, begin pay >>")
        WP.uni_pay(order_id, pay_params, function(succ, _order_id, ext_params)
            E.LOG.debug(TAG, "pay handle result from win_official_pay, succ:" .. tostring(succ))
            handle_pay_result(succ, _order_id, ext_params)
        end)
    else
        -- callback pay_listener false
        local ext_params = gen_failed_ext_params(CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_PAY_NOT_SUPPORT, "暂不支持支付")
        pay_listener(false, order_id, ext_params)
    end
end

function M.product_list()
    return product_infos
end


function M.investigation(cb)
    UNI.async_call(UNISDK_CHANNEL, ASYNC_INVESTIGATION, {}, nil, cb)
end

function M.game_started(info)
    UNI.cast(UNISDK_CHANNEL, CAST_GAME_STARTED, info)
end

function M.get_device_id()
    return UNI.sync_call(UNISDK_CHANNEL, SYNC_GET_DEVICE_ID, {})
end

function M.add_local_notification(title, content, date, hour, min)
    UNI.cast(UNISDK_CHANNEL, CAST_ADD_LOCAL_NOTIFICATION, {
        title = title,
        content = content,
        date = date,
        hour = hour,
        min = min,
        })
end

function M.clean_local_notification()
    UNI.cast(UNISDK_CHANNEL, CAST_CLEAR_LOCAL_NOTIFICATION, {})
end

--function M.get_boolean_api_available(id)
--    return UNI.sync_call(UNISDK_CHANNEL, SYNC_GET_API_AVAILABLE, {api=id})
--end

--function M.open_forum(cb)
--    local forum_info = {
--        data = {},
--        data_type = "YsdkForum"
--    }
--    UNI.async_call(UNISDK_CHANNEL, ASYNC_SET_EXT_DATA, forum_info, nil, cb)
--end

--function M.open_vplayer(cb)
--    local vplayer_info = {
--        data = {},
--        data_type = "YsdkVplayer"
--    }
--    UNI.async_call(UNISDK_CHANNEL, ASYNC_SET_EXT_DATA, vplayer_info, nil, cb)
--end

--function M.game_exit(cb)
--    UNI.async_call(UNISDK_CHANNEL, ASYNC_EXIT, {}, nil, cb)
--end

function M.exit()
    if E.CONFIG.get_config('os') == 'android' then
        UNI.exit(UNISDK_CHANNEL)
    else
        exit_listener(true)
    end
end

-- 阿里设备标识
function M.utdid()
    local ret = UNI.sync_call(UNISDK_CHANNEL, SYNC_UTDID, {}) or {}
    return ret.value
end

function M.is_emulator()
    local ret = UNI.sync_call(UNISDK_CHANNEL, SYNC_IS_EMULATOR, {}) or {}
    return ret.value
end

function M.channel_id()
    local ret = UNI.sync_call(UNISDK_CHANNEL, SYNC_GET_CHANNELID, {}) or {}
    return ret.value
end

function M.sub_channel_id()
    local ret = UNI.sync_call(UNISDK_CHANNEL, SYNC_GET_SUB_CHANNELID, {}) or {}
    return ret.value
end

function M.get_ft_version()
    local ret = UNI.sync_call(UNISDK_CHANNEL, SYNC_GET_FT_VERSION, {})
    if ret and ret.value then
        E.LOG.debug(TAG, 'get_ft_version success:'.. tostring(ret.value))
        return ret.value
    else
        E.LOG.warn(TAG, 'get_ft_version failed')
        return ''
    end
end

function M.open_customer_service()
    UNI.cast(UNISDK_CHANNEL, CAST_SHOW_CUSTOMER_SERVICE_WEB, {})
end

function M.create_role(info)
    UNI.cast(UNISDK_CHANNEL, CAST_CREATE_ROLE, info)
end

function M.role_level_up(info)
    UNI.cast(UNISDK_CHANNEL, CAST_ROLE_LEVEL_UP, info)
end

function M.gift_code(info)
    UNI.cast(UNISDK_CHANNEL, CAST_GIFT_CODE, info)
end

function M.call_web_view(info, cb)
    return UNI.async_call(UNISDK_CHANNEL, ASYNC_CALL_WEB_VIEW, info, nil, cb)
end

if E.CONFIG.get_config('os') == 'android' then
    function M.get_push_token()
        return UNI.sync_call(UNISDK_CHANNEL, SYNC_GET_PUSH_TOKEN, {})
    end

    function M.game_event(id, remark)
        UNI.cast(UNISDK_CHANNEL, CAST_GAME_EVENT, {
            event_id = id,
            remark = remark or "",
            })
    end
else
    function M.record_start(cb)
        UNI.async_call(UNISDK_CHANNEL, ASYNC_RECORD_START, {}, nil, cb)
    end

    function M.record_stop(cb)
        UNI.async_call(UNISDK_CHANNEL, ASYNC_RECORD_STOP, {}, nil, cb)
    end

    function M.order_retry()
        UNI.cast(UNISDK_CHANNEL, CAST_ORDER_RETRY, {})
    end

    function M.boradcast()
        UNI.cast(UNISDK_CHANNEL, CAST_BORADCAST, {})
    end

    function M.game_event(id, remark)
        local remark_str = remark and JSON.encode(remark) or "{}"
        UNI.cast(UNISDK_CHANNEL, CAST_GAME_EVENT, {
            event_id = id,
            remark = remark_str,
        })
    end
end

function M.init(opt, cb)
    pay_listener = opt.pay_listener
    auth_listener = opt.auth_listener
    logout_listener = opt.logout_listener
    switch_listener = opt.switch_listener
    exit_listener = opt.exit_listener
    qrcode_listener = opt.qrcode_listener

    if _ejoysdk.sysinfo then
        sysinfo = _ejoysdk.sysinfo()
    end

    ET.subscribe(ET.gangplank.INITED, init_handler)
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.SET_PLAYER_INFO_WITH_TYPE, set_player_info_handler)
    ET.subscribe(ET.config.CONFIG_CHANGED, productcode_change_handler)

    UNI.register_pay_listener(UNISDK_CHANNEL, handle_pay_result)

    UNI.register_login_listener(UNISDK_CHANNEL, function(succ, info, ext_params)
        if succ then
            -- 大圣 SDK 从 3.8.3.9 版本开始，在 token 快过期之前，自动刷新 token，并回调一次登录成功
            -- 游戏需要自行处理两次回调的情况
            -- 互娱 SDK 不能拦截，因为游戏可能在已经 acquire 成功后，又 acquire 一次

            E.LOG.debug(TAG, 'aligames login success')
            E.LOG.debug(TAG, ext_params)

            AUTH_INFO = {
                platform = tostring(M.channel_id()),
                ptoken = info.token,
                guest = false,
                with = UNISDK_CHANNEL,
                with_account = nil,
                ext = {
                    opcode =  ext_params.opcode
                }
            }

            if ext_params and  ext_params.cloudGameExt then
                local cloudGameExt = ext_params.cloudGameExt
                if cloudGameExt.cloudGameLogin then
                    E.LOG.debug(TAG, 'channel cloud game login stat')
                    local UIM = require "ejoysdk_lua.user_info_manager"
                    UIM.set_channel_cloud_game_tag(true)
                    ESTAT.stat_action('channel_cloud_game_login', nil, true, cloudGameExt)
                else
                    E.LOG.debug(TAG, 'has cloudGameExt but cloudGameLogin is false')
                end
            end

            if ext_params and ext_params.is_switch then
                switch_listener(AUTH_INFO, {})
            else
                auth_listener(true, AUTH_INFO, {})
            end
        else
            AUTH_INFO = {}

            if info and info.msg then
                local code = string.match(info.msg, "错误码=(-*%d+)")
                if(code and #code > 0) then
                    info.ds_code = code
                else
                    if (info.code and #(tostring(info.code))> 0) then
                        info.ds_code = info.code
                    end
                end
                code = string.match(info.msg, "%((-*%d+)%)")
                if(code and #code > 0) then
                    info.ds_server_code = code
                else
                    if (info.code and #(tostring(info.code)) > 0) then
                        info.ds_server_code = code
                    end
                end
            end
            E.LOG.error(TAG, 'aligames login fail info')
            E.LOG.error(TAG, info)
            auth_listener(false, info)
            --local err_code = 0
            --local err_msg = nil
            --if info then
            --    if (info.code and #(tostring(info.code)) > 0) then
            --        err_code = info.code
            --    elseif (info.ds_code and #(tostring(info.ds_code)) > 0) then
            --        err_code = info.ds_code
            --    elseif (info.ds_server_code and #(tostring(info.ds_server_code)) > 0) then
            --        err_code = info.ds_server_code
            --    end
            --
            --    err_msg = info.msg
            --end
        end
    end)

    UNI.register_logout_listener(UNISDK_CHANNEL, function (ext_params)
        logout_callback(ext_params)
    end)

    UNI.register_exit_cb(UNISDK_CHANNEL, function (succ)
        exit_listener(succ)
    end)


    UNI.register_event_cb(UNISDK_CHANNEL, function(type, data)
        if type == EVENT_NOTIFY_ACCOUNT_DATA then
            aligames_login_data = data
        end
    end)

    if M.need_go_new_ds_login_protocol_windows() then
        local PC = require "ejoysdk_lua.vendors.ds_pc"
        -- init最后回调true了，这里不需要回调，回调多次会导致gangplank init回调多次
        PC.init(opt)
    end
    
    -- 初始化windows的支付组件
    WP.uni_init()

    -- callback init success
    cb(true)
end

-- =========================== QRCODE =====================

local ALI_API = {
    RSP_CODE_SUCC    = 2000000, --已扫描
    RSP_CODE_UNSCAN  = 2000001, --未扫描
    RSP_CODE_TIMEOUT = 4001110  --二维码过期
}

-- 获取授权信息
function M.get_auth_info()
    return AUTH_INFO
end

-- 刷新二维码
-- @param type login/pay
function M.qrcode_refresh(type)
    if type == M.QRCODE_CONST.TYPE_LOGIN then
        M.login()
    elseif type == M.QRCODE_CONST.TYPE_PAY then
        M.qrcode_pay()
    end
end

-- 阿里游戏官方渠道 HTTP 请求
local function ALIGAMES_HTTP_POST(url, data, succ_cb, fail_cb)
    local sdkconfig = E.CONFIG.get_config("unisdk_meta")
    local req_id = string.gsub(uuid(), "-", "")
    local body = {
        id = req_id,
        client = {
            os = "windows",
            gameId = sdkconfig.game_id,
            ex = {
                fr  = "windows",
                mac = sysinfo.mac
            }
        },
        data = data
    }

    E.HTTP.post(url, {}, E.HTTP.CT_JSON, body, function (resp)
        if resp.status == 200 then
            -- 阿里游戏官方SDK接口返回数据
            local resp_data = JSON.decode(resp.body)
            local code =resp_data.state.code
            if code == ALI_API.RSP_CODE_SUCC then
                succ_cb(resp_data.data)
            else
                local error_info = {
                    error_code = code,
                    error_msg  = resp_data.state.msg,
                    error_type = 'biz' -- 业务响应错误
                }
                fail_cb(error_info)
            end
        else
            local error_info = {
                error_code = resp.status,
                error_msg  = resp.body,
                error_type = 'network' -- 网络响应错误
            }
            fail_cb(error_info)
        end
    end)
end

-- 轮询登录二维码扫描状态
function M.poll_qrcode_login_status()
    local url = "https://qrcode.flysdk.cn/pc/qrcode.login.poll?ver=1.0&df=json"
    local body = {
        pcLoginUuid = M.qrcode_login_uuid
    }
    ALIGAMES_HTTP_POST(url, body, function (data)
        --扫码登录成功
        qrcode_listener(M.QRCODE_CONST.STATE_SCANED, data, M.QRCODE_CONST.TYPE_LOGIN)
        AUTH_INFO = {
            platform = UNISDK_CHANNEL,
            ptoken = data.token,
            guest = false,
            with = UNISDK_CHANNEL,
            with_account = nil,
            ext = {
                platform =  data.platform
            }
        }
        auth_listener(true, AUTH_INFO, {})

        -- Token过期前1小时刷新
        local timeout = data.timeout - 60 * 60
        if timeout <= 0 then
            timeout = 1
        end
        E.Timer.once(timeout, M.refresh_token)

    end, function(error_info)
        local error_code = error_info.error_code
        local error_type = error_info.error_type

        if error_code == ALI_API.RSP_CODE_UNSCAN or error_type == "network" then
            --用户还未扫码, 或者网络请求错误，需继续轮询
            E.Timer.once(1, M.poll_qrcode_login_status)
        elseif error_code == ALI_API.RSP_CODE_TIMEOUT then
            --二维码已过期
            qrcode_listener(M.QRCODE_CONST.STATE_TIMEOUT, error_info, M.QRCODE_CONST.TYPE_LOGIN)
        else
            --其他错误, 回调登录失败
            local cbinfo = {
                code = error_code,
                msg  = error_info.error_msg,
                type = error_type
            }
            auth_listener(false, cbinfo)
        end
    end)
end

-- 获取登录二维码内容(PC端调用)
function M.get_login_qrcode(cb)

    local url = 'https://qrcode.flysdk.cn/pc/qrcode.login.get?ver=1.0&df=json'

    ALIGAMES_HTTP_POST(url, {}, function (data)
        --登录二维码获取成功
        M.qrcode_login_uuid = data.pcLoginUuid

        local info = {
            qrcode_txt = data.qrcodeScheme,
            qrcode_timeout = data.timeout
        }
        cb(true, info)

    end, function (error_info)
        E.LOG.warn(TAG, error_info or {})
        cb(false, error_info)
    end)
end

function M.refresh_token()
    local url = 'https://qrcode.flysdk.cn/pc/qrcode.token.exchange?ver=1.0&df=json'
    local data = {
        token = AUTH_INFO.ptoken
    }
    E.LOG.debug(TAG, '刷新 Aligames Token')
    ALIGAMES_HTTP_POST(url, data, function (resp_data)
        E.LOG.debug(TAG, 'token 刷新成功：'.. tostring(resp_data.token))
        AUTH_INFO.ptoken = resp_data.token
        local timeout = resp_data.timeout - 60 * 60
        if timeout <= 0 then
            timeout = 1
        end
        E.Timer.once(timeout, M.refresh_token)

    end, function (error_info)
        if error_info.error_type == 'network' then
            E.Timer.once(5, M.refresh_token)
        else
            E.LOG.debug(TAG, "token 刷新失败")
            E.LOG.debug(TAG, error_info)
        end
    end)
end

function M.qrcode_pay()
    --PC扫码支付
    M.get_pay_qrcode(pay_params, function (succ, info)

        if succ then
            qrcode_listener(M.QRCODE_CONST.STATE_GENSUCC, info, M.QRCODE_CONST.TYPE_PAY)
            M.qrcode_pay_uuid = info.qrcode_uuid
            M.poll_qrcode_pay_status()
        else
            qrcode_listener(M.QRCODE_CONST.STATE_GENSUCC, info, M.QRCODE_CONST.TYPE_PAY)
        end

    end)
end

-- 获取支付二维码
function M.get_pay_qrcode(order_param, cb)

    local url = 'https://qrcode.flysdk.cn/pc/qrcode.pay.get?ver=1.0&df=json'
    local data = {
        token = AUTH_INFO.ptoken,
        orderInfo = order_param,
        roleInfo = role_info
    }

    ALIGAMES_HTTP_POST(url, data, function (resp_data)
        --获取支付二维码成功
        local filename = "qrcode_pay.bmp"
        local succ, msg = _ejoysdk.qrcode_gen_bmp(resp_data.qrcodeScheme, filename, 1)
        if succ then
            local info = {
                qrcode_img = msg,
                qrcode_txt = resp_data.qrcodeScheme,
                qrcode_timeout = resp_data.timeout,
                qrcode_uuid = resp_data.pcPayUuid
            }
            cb(true, info)
        else
            local info = {
                error_msg  = msg,
                error_code = M.QRCODE_CONST.STATE_GENFAIL
            }
            cb(false, info)
        end

    end, function (error_info)
        E.LOG.warn(TAG, error_info or {})
        cb(false, error_info)
    end)

end

function M.poll_qrcode_pay_status()

    local url = 'https://qrcode.flysdk.cn/pc/qrcode.pay.poll?ver=1.0&df=json'

    local params = {
        pcPayUuid = M.qrcode_pay_uuid
    }

    ALIGAMES_HTTP_POST(url, params, function (data)
        --扫码登录成功
        E.LOG.debug(TAG, "已扫描支付二维码")
        qrcode_listener(M.QRCODE_CONST.STATE_SCANED, data, M.QRCODE_CONST.TYPE_PAY)

    end, function(error_info)
        local error_code = error_info.error_code
        local error_type = error_info.error_type

        if error_code == ALI_API.RSP_CODE_UNSCAN or error_type == "network" then
            --网络请求错误，需继续轮询
            E.Timer.once(1, M.poll_qrcode_pay_status)
        elseif error_code == ALI_API.RSP_CODE_TIMEOUT then
            --二维码已过期，
            qrcode_listener(M.QRCODE_CONST.STATE_TIMEOUT, error_info, M.QRCODE_CONST.TYPE_PAY)
        else
            --其他错误, 回调失败
            pay_listener(false, pay_params.cpOrderId,  error_info)
        end
    end)

end

-- 打开移动端扫码界面（Android/iOS端调用, 必须在登录成功后才能调用）
function M.qrcode_scan()
    UNI.cast(UNISDK_CHANNEL, CAST_QRCODE_SCAN, {})
end


--function M.set_app_orientation(temp_orientation)
--    UNI.cast(UNISDK_CHANNEL, CAST_SET_ORIENTATION, { orientation=temp_orientation })
--end

-- 打开客服
-- 新接口
function M.show_custom_service(params, cb)
    M.custom_service(params)
    if cb then
        cb(true)
    end
end

function M.ali_auth(auth_info, cb)
    local ali_auth_ver = ASYNC_ALI_AUTH
    if E.Sysinfo.os() == 'android' then
        ali_auth_ver = ASYNC_ALI_AUTH_V2
    end

    E.LOG.debug(TAG, 'ali_auth with native ali version:'..ali_auth_ver)

    UNI.async_call(UNISDK_CHANNEL, ali_auth_ver, {auth_info= auth_info}, nil, function(succ, ...)
        E.LOG.debug(TAG, 'lua ali_pay_simple_auth cb result: ' .. tostring(succ))
        if succ then
            local auth_result = ...
            E.log(auth_result)
            if E.Sysinfo.os() == 'ios' then -- iOS 精简版参数和 Android 格式不一样
                auth_result = auth_result or {}
                local resultStatus = auth_result.resultStatus
                local result = auth_result.result or {}
                local new_auth_result = 'resultStatus={' .. tostring(resultStatus) .. '};memo={};'
                new_auth_result = new_auth_result .. 'result={'
                for key, value in pairs(result) do
                    new_auth_result = new_auth_result .. tostring(key) .. '=' .. '"' .. tostring(value) .. '"' .. '&'
                end
                new_auth_result = new_auth_result:sub(1, #new_auth_result - 1) -- 移除最后一个 &
                new_auth_result = new_auth_result .. '}'
                E.LOG.debug(TAG, 'new auth result: ' .. tostring(new_auth_result))
                cb(true, new_auth_result)
            else
                local body = ...
                if body and body.result then
                    E.LOG.debug(TAG, 'ali_auth result:' .. tostring(body.result))
                    cb(true, body.result)
                else
                    E.LOG.error(TAG, 'ali_auth failed, result is empty!')
                    E.LOG.error(TAG, body)
                    cb(false)
                end
            end
        else
            cb(false)
        end
    end)
end

function M.read_apk_channel_extra_info(key, cb)
    if E.Sysinfo.os() == 'android' then
        UNI.async_call(UNISDK_CHANNEL, ASYNC_READ_APK_CHANNEL_EXTRA_INFO, {channel_extra_info_key = key}, nil,function(succ, ...)
            if succ then
                local body = ...
                if body and body.result then
                    E.LOG.debug(TAG, 'read_apk_channel_extra_info key=' .. tostring(key) .. ', result=' .. tostring(body.result))
                    cb(true, body.result)
                else
                    E.LOG.warn(TAG, 'read_apk_channel_extra_info failed, no result')
                    E.LOG.warn(TAG, body)
                    cb(false)
                end
            else
                E.LOG.warn(TAG, 'read_apk_channel_extra_info failed')
                cb(false)
            end
        end)
    else
        E.LOG.warn(TAG, 'read_apk_channel_extra_info, not implemented!')
    end

end

local function open_webview(url, screen_orientation, closeEventData, options)
    local params_ds_token = EG.user_info().ptoken or AUTH_INFO.ptoken
    local local_start_up_data = {
        pkg_info = E.get_pkg_info(),
        ds_token = params_ds_token,
        ejoysdk_ver = E.get_sdk_version_name('EJOYSDK')
    }


    E.LOG.debug(TAG, 'open_webview:'..(url or 'nil')..', ds_token:'..(params_ds_token or 'nil'))

    local wv_options = {
        compactMode= true,
        closeEventData = closeEventData,
        screen_orientation = screen_orientation
    }

    if options then
        for wo_k, wo_v in pairs(options) do
            wv_options[wo_k] = wo_v
        end
    end

    E.WebView.open(url, {
        ['.aligames.com'] = {
            startupData = local_start_up_data
        },
        ['.lingxigames.com'] = {
            startupData = local_start_up_data
        },
        ['.ejoy.com'] = {
            startupData = local_start_up_data
        },
        ['30.103.91.243'] = {
            startupData = local_start_up_data
        }
    }, wv_options)
end

-- 是否能显示灵犀用户中心页面
function M.can_show_user_center()
    if ACF.is_lingxi_baipai() then
        _ejoysdk.log(TAG .. "can_show_user_center false, baipai not support show user_center")
        return false
    end

    local os = E.Sysinfo.os()
    if os == "android" then
        -- 扫码包不支持用户中心
        if E.is_scan_pkg() then
            return false
        end
        -- android 有多个渠道，才需要根据一渠来判断是否是灵犀渠道
        local pkg_info = E.get_pkg_info()
        return pkg_info.ds_channel_id == ACF.CONSTANTS.LX_CHANNEL_ID
    elseif os == "ios" then
        -- 扫码包不支持用户中心
        if E.is_scan_pkg() then
            return false
        end
        return true
    elseif os == "windows" then
        local DS_PC = require 'ejoysdk_lua.vendors.ds_pc'
        if DS_PC.is_official_channel_id() then
            return true -- 官方渠道支持用户中心，外渠不支持
        end

        -- windows 的 webview 目前没有传递登录态
        return false
    else
        return false
    end
end

function M.set_lx_guest_bind_state()
    local os = E.Sysinfo.os()
    if os == 'android' then
        local bind_store = E.SPKeyStore:New('cn.uc.gamesdk.pref', 'cn.uc.gamesdk.guestBindInfo')
        local value = {
            type = 3,
            account = EG.user_info().account
        }
        bind_store:set(JSON.encode(value))
    elseif os == 'ios' then
        local bind_store = E.SPKeyStore:New('cn.uc.gamesdk.pref', 'G9SDKAccountGuestBindInfoKey')
        bind_store:set('G9SDKAccountGuestBindHasPhone')
    end
end

local function listen_webview_event(close_event_data)
    --js 事件监听
    local function webview_js_callback(_value)
        local args = _value.args
        if args.type == 'logout' or args.type == 'bind_succ' then
            E.LOG.debug(TAG, "webview_js_callback receive logout event! do logout")
            M.set_lx_guest_bind_state()
            EG.logout()
        end
    end

    -- webview 关闭事件监听
    local function webview_close_callback(_value)
        E.LOG.debug(TAG, "listen_webview_close_event, receive close event")

        if _value and _value.args == close_event_data then
            E.LOG.debug(TAG, "listen_webview_close_event, event>>".. tostring(_value.args))
            ET.unsubscribe('webview_close', webview_close_callback)
            ET.unsubscribe('webview_jsargs', webview_js_callback)
        end
    end

    ET.subscribe('webview_close', webview_close_callback)
    ET.subscribe('webview_jsargs', webview_js_callback)
end

local function is_empty(str)
    return not str or '' == str or type(str)~='string'
end

function M.show_user_center(screen_orientation)
    --支持灵犀和水下两种用户中心页面，按品牌区分
    local pkg_info = E.get_pkg_info()
    local brand = pkg_info['airline']
    if is_empty(brand) then
        E.LOG.debug(TAG, '开始访问灵犀用户中心页面')
        open_webview("https://account-lingxi.aligames.com/m/#/linxi", screen_orientation, CLOSE_EVENT_DATA_USER_CENTER)
        listen_webview_event(CLOSE_EVENT_DATA_USER_CENTER)
    else
        --打开水下品牌用户中心页面
        AIRLINE_V2.show_user_center()
    end
end
M.open_user_center = M.show_user_center

--[[判断str是否以substr结尾。是返回true，否返回false，失败返回失败信息]]
local endswith = function(str, substr)
    if str == nil or substr == nil then
        return nil, "the string or the sub-string parameter is nil"
    end
    local str_tmp = string.reverse(str)
    local substr_tmp = string.reverse(substr)
    if string.find(str_tmp, substr_tmp) ~= 1 then
        return false
    else
        return true
    end
end

local function append_url_path(url, path)
    if not path or path == '' then
        E.LOG.warn(TAG, 'appendUrlPath path is nil')
        return url
    end

    local query_index = string.find(url, '?', 1, true)
    local url_base = url
    local url_query = nil
    if query_index and query_index > 1 then
        url_base = string.sub(url, 1, query_index - 1)
        url_query = string.sub(url, query_index)
    end

    if endswith(url_base, "/") then
        local url_len = string.len(url_base)
        url_base = string.sub(url_base, 1, url_len - 1)
    end

    local url_with_path = url_base .. path

    local result = url_with_path
    if url_query then
        result = url_with_path..url_query
    end

    E.LOG.debug(TAG, 'append_url_path result:'..result)
    return result
end

function M.append_url_path_for_test(url, path)
    return append_url_path(url, path)
end

-- @param screen_orientation: 屏幕方向，portrait:竖屏，landscape: 横屏
-- @param path: url path，游戏可以自行传入，打开论坛的任意页面
-- @param options: 支持传递打开bbs页面的webview option
function M.show_bbs(screen_orientation, path, options)
    E.LOG.debug(TAG, '开始访问论坛页面')

    local function open_bbs_webview(url)
        if path then
            E.LOG.debug(TAG, 'show bbs with path:' .. path)
            url = append_url_path(url, path)
        else
            E.LOG.debug(TAG, 'show bbs without path')
        end

        E.LOG.debug(TAG, 'show_bbs, open_bbs_webview url:'..(url or 'nil'))
        url = url .. '#client=' .. E.Sysinfo.os()
        open_webview(url, screen_orientation, CLOSE_EVENT_DATA_BBS, options)
        listen_webview_event(CLOSE_EVENT_DATA_BBS)
    end

    if not bbs_url then
        local product_id =  E.CONFIG.get_config('product')
        local bbs_get_url_service = '/api/get_bbs_url'
        -- FIXME: 这里没有考虑到全球服情况的 BBS 地址
        local bbs_api_url = 'https://'..product_id..'-bbs.ejoy.com'..bbs_get_url_service

        E.HTTP.get(bbs_api_url, {acceptable = E.HTTP.CT_JSON}, function(resp)
            E.LOG.debug(TAG, 'show_bbs, get bbs url resp>>')
            --E.log(resp)
            local default_bbs_url = 'https://'..product_id..'-bbs.ejoy.com'
            local url = default_bbs_url
            if resp.body and resp.body.code == 0 and resp.body.bbs_url and resp.body.bbs_url ~= "" then
                url = resp.body.bbs_url
                bbs_url = url
                E.LOG.debug(TAG, 'show_bbs, get bbs url success, url:'.. tostring(bbs_url))
            else
                if resp.body and resp.body.code then
                    E.LOG.error(TAG, 'show_bbs, get bbs url failed, code:'.. tostring(resp.body.code) ..', msg:'..(resp.body.message or 'nil'))
                else
                    E.LOG.error(TAG, 'show_bbs, get bbs url failed, response body return nil')
                end
            end

            open_bbs_webview(url)
        end)
    else
        E.LOG.debug(TAG, 'show_bbs, has cached bbs_url:' .. tostring(bbs_url))
        open_bbs_webview(bbs_url)
    end
end

-- 打开一个带大圣登录态的webview
function M.show_url(url, screen_orientation, close_event_data)
    if not url or url == '' then
        E.LOG.warn(TAG, 'show_url url is empty!')
    end
    E.LOG.debug(TAG, '开始访问自定义页面, url:'..url)

    local my_close_event_data = close_event_data or CLOSE_EVENT_DATA_CUSTOM
    open_webview(url, screen_orientation, my_close_event_data)
    listen_webview_event(my_close_event_data)
end

-- 如果客服变更，需要改这一层的接口
-- 需要注意的是旧线上游戏历史原因使用的入口是这个；而非直接从show_custom_service进来；新游戏可以从show_custom_service作为入口
-- 旧接口，需要保留
function M.custom_service(params)
    -- 统一webview实现，依赖配置中心下发配置，对应namespace: usercenter_cn
    -- 读取配置中心下发配置，包含客服url和是否使用大圣webview的开关
    -- 预发：https://general-pre.aligames.com/lx_customer_relay_page
    -- 线上：https://general.aligames.com/lx_customer_relay_page

    local cs_url = "https://general.aligames.com/lx_customer_relay_page" -- default

    local use_ds
    local CC = require 'ejoysdk_lua.ejoysdk_config_center'
    local custom_service_config = CC.get_config(CC.NAMESPACE.USERCENTER_CN)
    if custom_service_config and custom_service_config.config then
        local customer_service_infos = custom_service_config.config.customer_service
        if customer_service_infos then
            cs_url = customer_service_infos.url or cs_url
            use_ds = customer_service_infos.use_ds or false
        end
    end

    -- eg: https://general.aligames.com/lx_customer_relay_page?gameid=100000
    if cs_url and not use_ds then
        -- 走新的ejoysdk webview逻辑
        params = params or {}
        -- orientation可以为空，传all或sensor横屏打开在iOS ejoysdk 2.3.x 下轻微刘海屏适配问题（白边）；orientation为空下iOS适配会横屏充满
        -- 旧ds webview 也不支持打开后的旋转
        local orientation = params.orientation
        -- 兼容旧sdk大圣接口的拼接参数
        for k, v in pairs(params) do
            if type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean") then
                cs_url = E.Utils.url_append_params(cs_url, k, tostring(v))
            end
        end

        open_webview(cs_url, orientation, CLOSE_EVENT_DATA_CUSTOMER_SERVICE)
        listen_webview_event(CLOSE_EVENT_DATA_CUSTOMER_SERVICE)
    else
        -- windows 没有大圣webview的客服入口，需要屏蔽
        if E.Sysinfo.os() == 'windows' then
            E.LOG.warn(TAG, 'windows is not support custom_service')
            return
        end

        -- 旧的大圣webview逻辑
        UNI.cast(UNISDK_CHANNEL, CAST_CUSTOM_SERVICE, params or {})
    end
end

function M.is_for_lingxi()
    return ACF.is_for_lingxi()
end

function M.is_support_ali_auth()
    local ret = UNI.sync_call(UNISDK_CHANNEL, SYNC_IS_SUPPORT_ALI_AUTH, {}) or {}
    return ret.value or false
end

function M.get_lingxi_brand()
    local lx_brand = ACF.get_lingxi_brand()
    E.LOG.debug(TAG, "get_lingxi_brand:" .. tostring(lx_brand))
    return lx_brand
end

-- aligames 无分享，只包含账号 和 支付
M:is_implemented({"ACCOUNT", "PAY", "CUSTOM_SERVICE"})

return M
