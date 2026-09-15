local E = require 'ejoysdk_lua.ejoysdk'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local ER = require 'ejoysdk_lua.ejoysdk_resource'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local USER = require 'ejoysdk_lua.user_center.ejoysdk_usercenter'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local EM = require "ejoysdk_lua.ejoysdk_module"

local VENDOR_NAME = 'GOOGLE'
local VENDOR_NAME_GOOGLE_PLAY = 'GOOGLE_PLAY'
local TAG = EM.MODULE.VENDORS.GOOGLE

--local SYNC_GET_CURRENT_USER = 'SYNC_GET_CURRENT_USER'

local M = Vendor:Inherit(VENDOR_NAME)

--local auth_listener = nil
--local logout_listener = nil

local pay_listener = nil
local pay_inited = false
local product_infos = {}

local last_product_id = nil
local last_order_id = nil
local logout_invoke = false -- 谷歌在登录失败时主动logout自己

local EVENT_NOTIFY_SERVER = "EVT_NOTIFY_SERVER"
local CAST_INIT_GOOGLE = "CAST_INIT_GOOGLE"
local CAST_CONSUME_OLD = "CAST_CONSUME_OLD"
local CAST_CONSUME_NEW = "CAST_CONSUME_NEW"

local multi_regions_enabled = nil -- true，使用用户中心支付; false，使用 gangplank 支付
local options = {}

local function login_handler()
    if pay_inited then
        return
    end

    EG.product_infos_base(VENDOR_NAME, function(succ, infos)
        if succ then
            E.LOG.debug(TAG, "获取谷歌商品列表 成功")
            E.LOG.debug(TAG, infos)

            product_infos = infos
            ET.publish('purchase_inited', VENDOR_NAME)

            pay_inited = true

            UNI.cast(VENDOR_NAME, CAST_INIT_GOOGLE, {})
        else
            E.LOG.warn(TAG, "获取谷歌商品列表 失败")
        end
    end)
end

function M.is_access_token_invalid(server_status, ...)
    return server_status == 406 or server_status == USER.USER_CENTER_ERROR_CODES.ERR_SERVER_THIRD_PART
end

local function is_system_time_diff_one_hour()
    local server_time = E.time()
    local os_time = os.time()
    local time_diff = math.abs(server_time - os_time)
    local google_token_expire_time_seconds = 60 * 60
    local is_diff_one_hour = time_diff >= google_token_expire_time_seconds
    if is_diff_one_hour then
        E.LOG.debug(TAG, "is_system_time_diff_one_hour true:"..tostring(time_diff)..', os_time:'..tostring(os_time))
    else
        E.LOG.debug(TAG, "is_system_time_diff_one_hour false:"..tostring(time_diff)..', os_time:'..tostring(os_time))
    end

    return is_diff_one_hour
end

function M.login_fail(status, last_login_params, fail_cb)
    local ql_params = {}
    ql_params.os_time = tostring(os.time())
    ql_params.server_time = tostring(E.time())
    ql_params.server_status = tostring(status)
    ql_params.vendor_name = VENDOR_NAME
    ql_params.region = E.CONFIG.get_config('region') or 'unknown'

    last_login_params = last_login_params or {}
    local stat_params = {
        outsource = last_login_params.outsource or {},
        info= last_login_params.info or {}
    }

    ql_params.login_params = stat_params

    if E.Sysinfo.os() == 'android' and is_system_time_diff_one_hour() and status == USER.USER_CENTER_ERROR_CODES.ERR_SERVER_THIRD_PART then
        ql_params.is_diff_one_hour = "true"
        ESTAT.stat_action("third.login", VENDOR_NAME, false, ql_params)

        if fail_cb then
            fail_cb(CONSTANTS.USER_CENTER_ERROR_CODES.CODE_SYSTEM_TIME_NOT_SYNC, "system time not sync, need check")
            return true
        end
    else
        ql_params.is_diff_one_hour = "false"
        ESTAT.stat_action("third.login", VENDOR_NAME, false, ql_params)
    end

    return false
end

local login_type= VENDOR_NAME
function M.login(params)
    logout_invoke = false
    login_type = (params or {}).vendor or VENDOR_NAME

    if _ejoysdk.os() ~= 'windows' then
        UNI.login(VENDOR_NAME, {use_games=(VENDOR_NAME_GOOGLE_PLAY == login_type),install_guide=true})
    else
        local option = options[login_type]
        option.auth_listener(false,{code=CONSTANTS.OFFICIAL_ERR_CODES.CODE_LOGIN_NOT_SUPPORT,msg='Not Support'})
    end
    --UNI.login(VENDOR_NAME, {})
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

function M.logout(params)
    params = params or {}
    logout_invoke = params.manual or false
    login_type = params.vendor or VENDOR_NAME
    UNI.logout(VENDOR_NAME)
end

function M.can_pay()
    return pay_inited
end

function M.pay(product_id, _count, order_id, _body)
    if not M.can_pay() then
        ET.publish('purchased', false, ER.order.CANT_PURCHASE)
        return
    end

    assert(product_infos[product_id], "product_id " .. tostring(product_id) .. " not found")

    E.LOG.debug(TAG, 'google pay for product_id: ' .. tostring(product_id) .. ' ,order_id: ' .. tostring(order_id))

    last_product_id = product_id
    last_order_id = order_id

    local server = EG.user_info().server
    local payload = '{1}'..server..':'..order_id

    local pay_params = {
        product_id = product_id,
        payload = payload
    }

    UNI.pay(VENDOR_NAME, order_id, pay_params)
end

function M.product_list()
    return product_infos
end

local function notify_order_url()
    return EG.gangplank_url('/notify/google')
end

local function notify_server(purchase)
    E.LOG.debug(TAG, 'google lua notify server')
    E.LOG.debug(TAG, {notify_purchase = purchase })

    local call_params = {
        game = E.CONFIG.get_config('product'),
        token = EG.user_info().token,
        receipt = purchase.signatureData,
        signature = purchase.signature,
        player_info = EG.player_info()
    }

    ET.publish('purchasing', ER.order.PURCHASING)

    E.HTTP.post(notify_order_url(), {}, E.HTTP.CT_URLENCODED, call_params, function(resp)
        --E.LOG.debug(TAG, {resp=resp})

        if resp.status ~= 200 then
            ET.publish('purchased', false, ER.order.UNKNOWN)
            return
        end

        local body = resp.body

        -- 0 表示完成正常购买流程
        -- 10005 表示游戏服务器还没确认订单，但是可以消耗掉
        -- 10006 无效订单，比如被 Google Play 退款的情况
        if body.code == 0 or body.code == 10005 or body.code == 10006 then
            if purchase.productId == last_product_id then

                E.LOG.debug(TAG, 'cast consume new in lua')

                UNI.cast(VENDOR_NAME, CAST_CONSUME_NEW, {product_id = last_product_id})
                pay_listener(true, last_order_id, {})
            else

                E.LOG.debug(TAG, 'cast consume old in lua')

                UNI.cast(VENDOR_NAME, CAST_CONSUME_OLD, {product_id = purchase.productId})
            end

            if body.code == 0 then
                ET.publish('purchased', true, ER.order.OK)
            elseif body.code == 10005 then
                ET.publish('purchased', false, ER.order.TRING)
            end
        end

        -- 其它情况不用管，等下次再向服务器检查
    end)
end

function M.init(opt, cb)
    -- For login
    local vendor_name = (opt.proxy or {}).vendor_name or VENDOR_NAME
    options[vendor_name]=opt

    local register_login_callback = function (succ, info, _ext_paramas)
        local option = options[login_type]
        if succ then
            E.LOG.debug(TAG, 'register_login_listener succ, info.token:'..tostring(info.token))
            local outsource = {
                platform = login_type,
                ptoken = info.token,
                uid = info.user_id,
                guest = false
            }
            local ext = {}
            option.auth_listener(succ,outsource,ext)
        else
            E.LOG.warn(TAG, "register_login_listener failed >>")
            E.LOG.debug(TAG, info)
            option.auth_listener(false,info)
        end
    end
    local register_logout_callback = function(ext_params)
        E.LOG.debug(TAG, "logout_listener >>")
        if not logout_invoke then
            -- 主动触发不返回给游戏
            local option = options[login_type]
            option.logout_listener(ext_params)
        end
    end

    UNI.register_login_listener(VENDOR_NAME, register_login_callback)
    UNI.register_logout_listener(VENDOR_NAME, register_logout_callback)
    ET.subscribe(ET.gangplank.ACQUIRE_FAILED,function(_fail_info)
        -- 谷歌自己也会有自动登录，为了正常弹出账号选择，在登录异常时需要先提前logout
        E.LOG.debug(TAG, "google login fail>>")
        M.logout({manual=true})
    end)

    -- For pay
    pay_listener = opt.pay_listener
    multi_regions_enabled = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
    -- 使用 OFFICIAL 的商品列表
    if not multi_regions_enabled then
        ET.subscribe(ET.gangplank.LOGIN, login_handler)
    end
    UNI.register_pay_listener(VENDOR_NAME, function(succ, order_id, ext_params)
        E.LOG.debug(TAG, 'lua pay listener: ' .. tostring(succ))
        pay_listener(succ, order_id, ext_params)
    end)
    UNI.register_event_cb(VENDOR_NAME, function(type, body)
        if type == EVENT_NOTIFY_SERVER then
            E.LOG.debug(TAG, 'handle EVENT_NOTIFY_SERVER >>>>')
            E.LOG.debug(TAG, body)
            for _, purchase in pairs(body) do
                notify_server(purchase)
            end
        end
    end)

    -- callback init success
    cb(true)
end

M:is_implemented({"ACCOUNT", "PAY"})

return M
