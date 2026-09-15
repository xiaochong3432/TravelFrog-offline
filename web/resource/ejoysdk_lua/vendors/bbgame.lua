local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
--local JSON = require "ejoysdk_lua.ejoysdk_json"
local EM = require "ejoysdk_lua.ejoysdk_module"
local CHANNEL = "BBG"
local UNISDK_CHANNEL = "BBG"

local TAG = EM.MODULE.VENDORS.BBGAME

--BBG打开客服系统
local CAST_SHOW_CUSTOMER = "CAST_SHOW_CUSTOMER"
--BBG打开用户中心
local CAST_SHOW_USER_CENTER = "CAST_SHOW_USER_CENTER"

local M = Vendor:Inherit(CHANNEL)

M.EVT_SWITCH_USER_SUCC = "EVT_SWITCH_USER_SUCC"
M.EVT_SWITCH_USER_CANCEL = "EVT_SWITCH_USER_CANCEL"
M.EVT_SWITCH_USER_FAIL = "EVT_SWITCH_USER_FAIL"

local auth_listener = nil
local logout_listener = nil
local pay_listener = nil
local switch_listener = nil
local exit_listener = nil
local pay_inited = false
local product_infos = {}

local login_handler = function()
    -- 已经初始化了pay，不需再次执行
    if pay_inited then
        return
    end

    E.LOG.debug(TAG, "开始获取 bbgame product info")

    EG.product_infos_base(CHANNEL, function(succ, infos)
        if succ then
            E.LOG.debug(TAG, "获取 bbgame product info success")

            product_infos = infos
            ET.publish('purchase_inited', CHANNEL)

            E.LOG.debug(TAG, product_infos)

            pay_inited = true
        else
            E.LOG.debug(TAG, "获取 bbgame product info failure")
        end
    end)
end

local set_player_info_handler = function(player_info, type)
    UNI.set_player_info(CHANNEL, player_info, type)
end

function M.init(opt, cb)
    pay_listener = opt.pay_listener
    auth_listener = opt.auth_listener
    logout_listener = opt.logout_listener
    switch_listener = opt.switch_listener
    exit_listener = opt.exit_listener

    E.LOG.debug(TAG, 'bbgame start init!!!!')

    if pay_inited then
        -- callback init success
        cb(true)
        return
    end

    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.SET_PLAYER_INFO_WITH_TYPE, set_player_info_handler)

    UNI.register_pay_listener(UNISDK_CHANNEL, function(succ, _order_id, ext_params)
        pay_listener(succ, _order_id, ext_params)
    end)

    UNI.register_login_listener(UNISDK_CHANNEL, function(succ, info, ext_params)
        if succ then
            E.LOG.debug(TAG, ext_params)
            local outsource = {
                platform = UNISDK_CHANNEL,
                ptoken = info.token,
                guest = false,
                ext = {
                    opcode =  ext_params.opcode
                }
            }

            if ext_params and ext_params.is_switch then
                switch_listener(outsource, {})
            else
                auth_listener(true, outsource, {})
            end

        else
            if ext_params and not ext_params.is_switch then
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

    local firebase = require 'ejoysdk_lua.vendors.firebase'
    firebase.set_native_vendor(UNISDK_CHANNEL)

    -- callback init success
    cb(true)
end

function M.login()
    UNI.login(UNISDK_CHANNEL, {})
end

function M.logout()
    E.LOG.debug(TAG, 'call lua bbgame logout')
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
    return pay_inited
end

function M.pay(product_id, _count, order_id, _body)
    local product = product_infos[product_id]
    assert(product, "product_id " .. tostring(product_id) .. " not found")

    local pay_params = {
        cpOrderId = order_id,
        amount = product.money,
        payProductID = product.product_id,
        payProductName = product.product_desc,
        payProductDescribe = product.product_desc,
        payCallbackURL = '', -- 回调地址
        payCallbackParams = '' -- 透传参数
    }
    UNI.pay(UNISDK_CHANNEL, order_id, pay_params)
end

function M.product_list()
    return product_infos
end

function M.exit()
    UNI.exit(UNISDK_CHANNEL)
end

function M.open_customer_service()
    UNI.cast(UNISDK_CHANNEL, CAST_SHOW_CUSTOMER, {})
end

function M.open_user_center()
    UNI.cast(UNISDK_CHANNEL, CAST_SHOW_USER_CENTER, {})
end

-- bbgame 暂不接分享功能，只包含账号 和 支付
M:is_implemented({"ACCOUNT", "PAY"})

return M
