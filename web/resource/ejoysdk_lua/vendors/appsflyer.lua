local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local EM = require "ejoysdk_lua.ejoysdk_module"
local OVERSEA_APPLOG = require "ejoysdk_lua.vendors.oversea_applog"

--经分SDK
local CHANNEL = "APPSFLYER"

local TAG = EM.MODULE.VENDORS.APPSFLYER

local M = Vendor:Inherit(CHANNEL)
--初始化appsflyer
local CAST_INIT_APPSFLYER = "CAST_INIT_APPSFLYER"
--更新uid
local CAST_UPDATE_UID = "CAST_UPDATE_UID"
--打点事件
local CAST_COMMIT_EVENT = "CAST_COMMIT_EVENT"
-- 生成邀请链接
local ASYNC_GEN_INVITE_LINK = "ASYNC_GEN_INVITE_LINK"

M.enable_ldu = false
-- 调用appsflyer打点
-- 为避免与默认事件冲突，事件名称应该用英文小写，格式： (a-z and 0-9)
function M.commit_event(event_name, params)
    if M.enable_ldu == true then
        E.LOG.debug(TAG, "appsflyer commit_event disabled with LDU setting")
        return
    end

    local event_params = {
        event_name = event_name,
        params = params
    }
    UNI.cast(CHANNEL, CAST_COMMIT_EVENT, event_params)
end

--初始化经分
local function init_appsflyer_sdk()
    local init_param = {
        debuggable = false,
        collect_imei = false,
        currency_code = 'USD',
        appsflyer_disable = false,
        enable_ldu =  (OVERSEA_APPLOG.has_enabled_ldu() == true) or false,
        -- iOS only
        collect_device_name = false,

    }
    UNI.cast(CHANNEL, CAST_INIT_APPSFLYER, init_param)

    -- 增加安装来源的事件上报，referrer表示安装来源,如 instant
    local ejoy_referrer = E.Sysinfo.get_ejoy_referer() or 'none'
    E.LOG.debug(TAG, 'try commit instant event >> ' .. tostring(ejoy_referrer))
    local params = {
        referrer = ejoy_referrer
    }
    M.commit_event("install_referrer", params)
end

-- 更新经分参数
local function update_uid(userId)
    local params = {
        uid = userId
    }
    UNI.cast(CHANNEL, CAST_UPDATE_UID, params)
end

local login_handler = function(user_info)
    local params = {
        uid = user_info.uid,
        pid = user_info.pid,
        account_id = user_info.uid
    }

    -- 补充AF规范打点：https://support.appsflyer.com/hc/en-us/articles/115005544169#verticals-login
    M.commit_event('af_login', params)

    -- update stat account param
    update_uid(user_info.uid)
end

local function gangplank_logout_handler()
    --登出成功，更新经分数据
    -- update stat account param
    update_uid('')
end

local function gangplank_exit_handler()
    update_uid('')
end

function M.init(opt, cb)
    E.LOG.debug(TAG, 'AppsFlyer start init')

    -- 初始化经分sdk
    init_appsflyer_sdk()

    -- 游戏启动打点，账号级的状态，用ET.gangplank.LOGIN、ET.gangplank.LOGOUT、ET.gangplank.EXIT就可以了
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)
    ET.subscribe(ET.gangplank.EXIT, gangplank_exit_handler)

    ET.subscribe(ET.analytics.REGISTER, function(user_info)
        -- AF规范打点：https://support.appsflyer.com/hc/en-us/articles/115005544169#verticals-complete-registration
        M.commit_event('af_complete_registration', {account_id = user_info.uid})
    end)

    ET.subscribe(ET.analytics.PURCHASE_SUCC, function(order_id, product_info)
        local params = {
            af_order_id = order_id
        }
        local player_info = EG.player_info()
        params.role_id = player_info.player_id
        params.role_name = player_info.player_name
        params.server_id = player_info.server_id
        params.server_name = player_info.server_name

        local user_info = EG.user_info()
        params.account_id = user_info.uid

        if product_info then
            if product_info.product_id then
                params.af_content_id = product_info.product_id
            end
            if product_info.show_money then
                params.af_revenue = product_info.show_money
            end
            if product_info.money_type then
                params.af_currency = product_info.money_type
            end
        end

        -- 补充AF规范打点：https://support.appsflyer.com/hc/en-us/articles/115005544169#verticals-purchase
        M.commit_event('af_purchase', params)
    end)

    -- 注册applog events
    OVERSEA_APPLOG.register_applog_events(CHANNEL, M)

    -- callback init success
    cb(true)
end

M.INVITE_LINK = {
    onlink_id = 'onelink_id',
    channel   = 'channel',
    refer_name = 'referrer_name',
    refer_uid  = 'referrer_uid',
    refer_image_url = 'referrer_image_url',
    campaign   = 'campaign',
    custom_params = 'custom_params'
}

function M.gen_invite_link(params, cb)

    local callback = function(succ, ...)
        if succ then
            local body = ...
            cb(true, body.url)
        else
            --local code, body = ...
            cb(false)
        end
    end

    UNI.async_call(CHANNEL, ASYNC_GEN_INVITE_LINK, params, nil, callback)
end

-- appsflyer 包含统计
M:is_implemented({Vendor.ABILITY.STATS})

return M