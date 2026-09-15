-- 苹果的gamecenter登录

local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local ER = require "ejoysdk_lua.ejoysdk_resource"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local EM = require "ejoysdk_lua.ejoysdk_module"
local unpack = unpack or table.unpack

local CHANNEL = "APPLE"
local TAG = EM.MODULE.VENDORS.APPLE

local M = Vendor:Inherit(CHANNEL)
M.LoginTopic = 'GameCenterLogin'

local IAP_ORDER_ID = E.LazyKeyStore:New('IAP_ORDER_ID', false, false)

local PURCHASE_EVENT = 'PURCHASE_EVENT'
-- local P_FAILED = 0
local P_CANCEL = 1
local P_ERROR = 2
local P_PURCHASING = 3
local P_DEFERRED = 4
local P_COMPLETED = 5

local GAMECENTER_EVENT = 'GAMECENTER_EVENT'
local GAMECENTER_EVENT_TYPE_SUCCESS = 0;
local GAMECENTER_EVENT_TYPE_UNAVAIABLE = 1;
local GAMECENTER_EVENT_TYPE_USER_CANCEL = 2;
local GAMECENTER_EVENT_TYPE_USER_LOGOUT = 3;
local GAMECENTER_EVENT_TYPE_APPLE_DECLINE = 4;

local game_center_info = nil
local on_login = false
local purchase_inited = false
local player_info_inited = false
local product_infos = {}
local pending_order = nil

local multi_regions_enabled = nil -- true，使用用户中心支付; false，使用 gangplank 支付

local function try_callback()
    if not game_center_info then
        return
    end

    if not on_login then
        return
    end

    on_login = false
    if game_center_info.succ then
        local outsource = {
            platform = CHANNEL,
            ptoken = game_center_info.token,
            pid = game_center_info.player_id,
            guest = false,
            with = nil,
            with_account = nil
        }

        local info = {
            display_name = game_center_info.displayName,
            alias = game_center_info.alias,
        }
        M.opt.auth_listener(true, outsource, info)
    else
        if game_center_info.value and type(game_center_info.value) == 'string' then
            -- 如果是string就转成table，兼容一下
            local temp_msg = game_center_info.value
            game_center_info.value = {
                code=-1,
                msg=temp_msg
            }
        end
        M.opt.auth_listener(false, game_center_info.value) -- 把native给的错误信息传出去
    end
end


_ejoysdk.register_cb(GAMECENTER_EVENT, function(cbid, value)
    E.LOG.debug(TAG, 'vendors apple cbid: ' .. tostring(cbid))
    E.LOG.debug(TAG, {
        tag = 'gamecenter tag',
        value = value
    })
    if cbid == GAMECENTER_EVENT_TYPE_SUCCESS then
        value.token = M.make_token(value)
        value.succ = true
        game_center_info = value

        try_callback()
        return
    end


    if cbid == GAMECENTER_EVENT_TYPE_USER_LOGOUT then
        ET.publish(M.LoginTopic, ER.game_center.USER_LOGOUT)
    elseif cbid == GAMECENTER_EVENT_TYPE_USER_CANCEL then
        ET.publish(M.LoginTopic, ER.game_center.USER_CANCEL)
    elseif cbid == GAMECENTER_EVENT_TYPE_APPLE_DECLINE then
        ET.publish(M.LoginTopic, ER.game_center.APPLE_DECLINE)
    elseif cbid == GAMECENTER_EVENT_TYPE_UNAVAIABLE then
        ET.publish(M.LoginTopic, ER.game_center.UNAVAIABLE)
    end

    game_center_info = {succ = false, value = value}
    try_callback()
end)


local function set_inited(infos)
    product_infos = infos
    purchase_inited = true
    ET.publish('purchase_inited', CHANNEL)

    if pending_order then
        M.notify_server(unpack(pending_order))
    end
end

local login_handler = function()
    local EVS = require 'ejoysdk_lua.ejoysdk_vendors'
    if EVS.has_vendor('OFFICIALPAY') then
        return
    end
    if purchase_inited then
        return
    end
    _ejoysdk.iap_init()

    EG.product_infos_base(CHANNEL, function(succ, infos)
        if succ then
            local ids = {}
            for k, _ in pairs(infos) do
                ids[#ids + 1] = k
            end
            local infos_by_apple = _ejoysdk.iap_product_infos(ids)
            E.LOG.debug(TAG, 'info by apple')
            if infos_by_apple then
                E.LOG.debug(TAG, infos)
                set_inited(infos)
            else
                E.LOG.debug(TAG, 'info by apple is nil')
            end
        else
            E.LOG.debug(TAG, "log apple product info fail")
        end
    end)
end

local set_player_info_handler = function()
    player_info_inited = true
    if pending_order then
        M.notify_server(unpack(pending_order))
    end
end

function M.init(opt, cb)
    if purchase_inited then
        return
    end

    M.opt = opt

    multi_regions_enabled = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
    -- 使用 OFFICIAL 的商品列表
    if not multi_regions_enabled then
        ET.subscribe(ET.gangplank.LOGIN, login_handler)
    end
    ET.subscribe('set_player_info', set_player_info_handler)

    -- callback init success
    cb(true)
end

function M.login()
    on_login = true
    _ejoysdk.gamecenter_enable()
end

function M.logout()
    M.opt.logout_listener({})
end


function M.simple_token()
    return false
end

function M.merge_info(a, b)
    return M.merge_helper(a, b)
end

-- 有可能传进来的 token 和当前的不一致
-- 仍然直接运行登录流程， 真不一致了，会被gangplank拦下来
function M.check_token(_outsource, _info)
    M.login()
end

function M.product_list()
    return product_infos
end

-- 支付前主动调用一次
function M.can_pay()
    if not purchase_inited then
        return false
    end

    if IAP_ORDER_ID:get() then
        return false
    end

    local can, _err = _ejoysdk.iap_can_buy_product()
    return can
end

function M.pay(product_id, count, order_id, _body)
    -- 苹果我们只允许买一件
    assert(count == 1, "count error")

    if not M.can_pay()  then
        ET.publish('purchased', false, ER.order.CANT_PURCHASE)
        return
    end

    IAP_ORDER_ID:set(order_id)
    _ejoysdk.iap_purchase_product(product_id, order_id)
end

function M.notify_server(product_id, transactionId, receipt)
    if not purchase_inited or not player_info_inited then
        E.LOG.debug(TAG, 'notify server, not init, add pending product id:' .. tostring(product_id) .. ' ,transaction id:' .. tostring(transactionId))
        pending_order = {
            product_id,
            transactionId,
            receipt,
        }
        return
    end

    pending_order = nil -- 跑到这里说明pending_order已经使用，可以置空

    local call_params = {
        server = EG.player_info().server_id or EG.user_info().server,
        game = E.CONFIG.get_config("product"),
        receipt = receipt,
        token = EG.user_info().token,
        env = E.CONFIG.get_config("env"),
        player_info = EG.player_info()
    }

    E.LOG.debug(TAG, 'apple notify server')
    local order_id = IAP_ORDER_ID:get()
    if order_id then
        E.LOG.debug(TAG, 'order id: ' .. tostring(order_id))
        call_params.order_id = order_id
    end

    E.LOG.debug(TAG, 'transactionId: ' .. tostring(transactionId))

    ET.publish('purchasing', ER.order.PURCHASING)
    local url = EG.gangplank_url('/notify/apple/v2')
    E.HTTP.post(url, {}, E.HTTP.CT_JSON, call_params, function(resp)
        --E.log(resp)
        if resp.status == 200 then
            local body = resp.body
            if body.code == 200 then
                _ejoysdk.iap_finish_transaction()
                IAP_ORDER_ID:delete()
                ET.publish('purchased', true, ER.order.OK)
                M.opt.pay_listener(true, body.order._id, body.order)
            elseif body.code == 10006 then
                _ejoysdk.iap_finish_transaction()
                IAP_ORDER_ID:delete()
            else
                if body.code == 10005 then
                    _ejoysdk.iap_finish_transaction()
                    IAP_ORDER_ID:delete()
                    ET.publish('purchased', false, ER.order.TRING)
                end
                if body.code == 10004 then
                    ET.publish('purchased', false, ER.order.APPLE_TRING)
                end
                M.opt.pay_listener(false, order_id, {code = body.code, msg = body.message or ''})
            end
        else
            ET.publish('purchased', false, ER.order.UNKNOWN)
        end
    end)
end

local event_dispatch = {
    [P_CANCEL] = function()
        local order_id = IAP_ORDER_ID:get()
        ET.publish('purchased', false, ER.order.CANCEL)
        IAP_ORDER_ID:delete()
        M.opt.pay_listener(false, order_id, {code = 2, msg = 'cancel'})
    end,
    [P_ERROR] = function(code, err)
        local order_id = IAP_ORDER_ID:get()
        ET.publish('purchased', false, ER.order.APPLE_ERROR)
        IAP_ORDER_ID:delete()
        M.opt.pay_listener(false, order_id, {code = code, msg = err})
    end,
    [P_PURCHASING] = function()
        local order_id = IAP_ORDER_ID:get()
        E.LOG.debug(TAG, {status = 'purchasing', order_id = order_id})
        ET.publish('purchasing', ER.order.APPLE_PURCHASING)
    end,
    [P_DEFERRED] = function()
        local order_id = IAP_ORDER_ID:get()
        E.LOG.debug(TAG, {status = 'deferred', order_id = order_id})
    end,
    [P_COMPLETED] = M.notify_server,
}

_ejoysdk.register_cb(PURCHASE_EVENT, function(cbid, ...)
    local handler = event_dispatch[cbid]
    if handler then
        handler(...)
    end
end)

_ejoysdk.register_cb("LOAD_PRODUCT", function(_cbid, succ)
    print("product loaded", _cbid, succ)
    if succ then
        local infos = _ejoysdk.iap_product_infos({})
        if infos then
            E.LOG.debug(TAG, 'product loaded lua')
            E.LOG.debug(TAG, infos)
            set_inited(infos)
        end
    end
end)


local function billboard_show_purchasing(info)
    if info then
        E.Toast.show(info)
    end
end

local function billboard_show_purchased(_succ, info)
    if info then
        E.Toast.show(info)
        E.Timer.once(3, E.Toast.hide)
    end
end

function M.billboard_show()
    ET.subscribe('purchasing', billboard_show_purchasing)
    ET.subscribe('purchased', billboard_show_purchased)
end

function M.make_token(info)
    local token = {
        player_id = info.player_id,
        team_player_id = info.team_player_id,
        game_player_id = info.game_player_id,
        display_name = info.displayName,
        alias = info.alias,
        bundle_id = info.bundle_id,
        underage = info.underage,
        public_key_url = info.public_key_url,
        signature = _ejoysdk_crypt.base64encode(info.signature),
        salt = _ejoysdk_crypt.base64encode(info.salt),
        timestamp = info.timestamp,
        sign_version = info.sign_version or ""
    }

    local jsonstr = JSON.encode(token)
    return _ejoysdk_crypt.base64encode(jsonstr)
end

M:is_implemented({"ACCOUNT", "PAY"})

return M
