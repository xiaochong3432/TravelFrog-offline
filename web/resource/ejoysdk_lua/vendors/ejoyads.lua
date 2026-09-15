local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EH = require 'ejoysdk_lua.ejoysdk_holo'
local UNI = require "ejoysdk_lua.vendors.unisdk"
local QL = require "ejoysdk_lua.ejoysdk_qualitylog"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local EM = require "ejoysdk_lua.ejoysdk_module"

local ADS_VENDER_NAME= 'EJOYADS'
local ADS_INIT = "ADS_INIT"
local ADS_LOAD = "ADS_LOAD"
local ADS_STATUS = "ADS_STATUS"
local ADS_SHOW= "ADS_SHOW"
local ADS_CLOSE= "ADS_CLOSE"
local ADS_SUPPORT_AD_TYPES= "ADS_SUPPORT_AD_TYPES"

local IS_SUPPORT_INIT_AD_SDK = "IS_SUPPORT_INIT_AD_SDK"

-- EventName for stat
local EVENT_CREATE_ORDER = "sdk.ejoy_ads_order"
local EVENT_CREATE_ORDER_SUCC = "sdk.ejoy_ads_order_succ"
local EVENT_CREATE_ORDER_FAIL = "sdk.ejoy_ads_order_fail"
local EVENT_GET_SERVICE_SUCC = "sdk.ejoy_ads_get_service_succ"
local EVENT_GET_SERVICE_FAIL = "sdk.ejoy_ads_get_service_fail"
local EVENT_LOAD= "sdk.ejoy_ads_load"
local EVENT_LOAD_SUCC = "sdk.ejoy_ads_load_succ"
local EVENT_LOAD_FAIL = "sdk.ejoy_ads_load_fail"
local EVENT_SHOW = "sdk.ejoy_ads_show"
local EVENT_SHOW_START = "sdk.ejoy_ads_show_start"
local EVENT_SHOW_SUCC = "sdk.ejoy_ads_show_succ"
local _EVENT_SHOW_CLICK = "sdk.ejoy_ads_show_click"  -- 这个打点，在native打的，这里只是写出来，标示的作用
local EVENT_SHOW_FAIL = "sdk.ejoy_ads_show_fail"
local EVENT_NOTIFY = "sdk.ejoy_ads_notify"
local EVENT_NOTIFY_SUCC = "sdk.ejoy_ads_notify_succ"
local EVENT_NOTIFY_FAIL = "sdk.ejoy_ads_notify_fail"
local EVENT_CLOSE = "sdk.ejoy_ads_close"
local EVENT_CLOSE_SUCC = "sdk.ejoy_ads_close_succ"
local EVENT_CLOSE_FAIL = "sdk.ejoy_ads_close_fail"

--local urlPrefix = E.CONFIG.get_config('ad-server'):lower() .. "/client_api/"
local MAX_NOFITY_RETRY=3 --最大重试通知次数
-- 当前所有的广告商都是走客户端通知发奖
--local NOTIFY_SERVICE={
--    vivo=true,
--    oppo=true,
--    huawei=true,
--    xiaomi=true,
--    byte_dance=true,
--    ninegame=true,
--    ohayoo=true
--}

local CHANNEL = "EJOYADS"
local M = Vendor:Inherit(CHANNEL)

local TAG = EM.MODULE.VENDORS.EJOY_ADS

M.status = {
    --lua层返回值
    AD_ERR_C_ORDER_FAIL = -99,
    AD_ERR_NO_TOKEN = -98,
    AD_ERR_C_AD_SERVICE_FAIL = -97,  -- 获取广告服务商失败
    AD_ERR_C_UNSUPPORT_TYPE = -96,  -- 不支持的广告类型

    --初始化
    AD_INIT_SUCC = 10300,
    AD_INIT_FAIL = 10301,

    --显示
    AD_SHOW_ERR = 10200,
    AD_SHOW_FAIL = 10201,
    AD_SHOW_CLOSE = 10202,
    AD_SHOW_COMPLETED = 10203, -- 有一些特殊的渠道需要在收到这个回调后请求服务器通知发奖
    AD_CLOSE_FAIL = 10204,
    AD_SHOW_START = 10205,
    AD_SHOW_CLICK = 10206,

    --加载
    AD_LOAD_ERR = 10100,
    AD_LOAD_LOADING = 10101,
    AD_LOAD_FAIL = 10102,
    AD_LOAD_SUCC = 10103,

    --预加载
    AD_STATUS_ERR = 10000,
    AD_STATUS_NOT_EXISTS = 10001,
    AD_STATUS_NOT_LOAD = 10002,
    AD_STATUS_LOADING = 10003,
    AD_STATUS_READY = 10004,
    AD_STATUS_SHOWING = 10005,
    AD_STATUS_FINISHED = 10006,
}

local load_succ_result = {}  -- {"ad_id1":{"ad_type":"banner"}, "ad_id2":{"ad_type":"video"}}
local support_ad_types = {}

local VENDOR_ADS= {}

local function request_params()
    local token = EH.get_player_token()
    return {
        acceptable = E.HTTP.CT_JSON,
        headers = { ['moment-Token'] = token }
    }
end

local function base_url()
    return E.CONFIG.get_config('ad-server'):lower() .. "/client_api/"
end

local function player_online_handler(_player_token)
    --E.log("ejoyads: ads player token="..(player_token or "null"))

    --query ad list after get player's info succ
    M.query_list(function(succ, adlist)
        if (succ) then
            for i = 1, #adlist do
                --预加载
                M.load_ad(adlist[i], function(succ2,...)
                    if succ2 then
                        E.log("ejoyads: 预加载成功")
                    else
                        E.log("ejoyads: 预加载失败")
                    end
                end)
            end
        end
    end)
end

function M.fill_support_ad_types()
    support_ad_types = VENDOR_ADS.support_ad_types() or {["video"]=1}
end

function M.initAd()
    E.LOG.debug(TAG, "ejoyads: start initAd")
    local init_callback = function (succ, ...)
        if succ then
            E.LOG.debug(TAG, "ejoyads: 初始化成功")
        else
            E.LOG.debug(TAG, "ejoyads: 初始化失败")
        end
    end
    local ad_plugins = UNI.get_sdk(Vendor.ABILITY.CHANNEL_AD)
    E.LOG.debug(TAG, {table_print=ad_plugins})
    if ad_plugins == nil or ad_plugins.sdks == nil or next(ad_plugins.sdks) == nil then
        --无ability初始化也正常进行
        UNI.async_call(ADS_VENDER_NAME, ADS_INIT, {}, nil, init_callback)
    else
        local sdk_infos = UNI.get_sdk_infos()
        local ad_configs = {}
        for name, config in pairs(sdk_infos) do
            for _index, ad_plugin_name in pairs(ad_plugins.sdks) do
                if name == ad_plugin_name then
                    table.insert(ad_configs, config.meta)
                    break
                end
            end
        end
        if next(ad_configs) == nil then
            UNI.async_call(ADS_VENDER_NAME, ADS_INIT, {}, nil, init_callback)
        else
            UNI.async_call(ADS_VENDER_NAME, ADS_INIT, {ad_configs = ad_configs}, nil, init_callback)
        end
    end
end

function M.init(opt, cb2)
    E.LOG.debug(TAG, "ejoyads: init vendor")
    do
        local os_config = E.CONFIG.get_config("os")
        if os_config == "android" then
            local is_support_init = M.is_support_init()
            if is_support_init then
                M.initAd()
            end

            function VENDOR_ADS.loadAd(params, cb)
                UNI.async_call(ADS_VENDER_NAME, ADS_LOAD, params, nil, cb)
            end
            function VENDOR_ADS.getAdStatus(params)
                return UNI.sync_call(ADS_VENDER_NAME, ADS_STATUS,params, nil)
            end
            function VENDOR_ADS.showAd(params,cb)
                UNI.async_call(ADS_VENDER_NAME, ADS_SHOW, params, nil, cb)
            end
            function VENDOR_ADS.closeAd(params,cb)
                UNI.async_call(ADS_VENDER_NAME, ADS_CLOSE, params, nil, cb)
            end
            function VENDOR_ADS.support_ad_types()
                return UNI.sync_call(ADS_VENDER_NAME, ADS_SUPPORT_AD_TYPES, {}, nil)
            end
        else
            if os_config == "ios" then
                function VENDOR_ADS.loadAd(params, cb)
                    UNI.async_call(ADS_VENDER_NAME, ADS_LOAD, params, nil, cb)
                end

                function VENDOR_ADS.getAdStatus(params)
                    return UNI.sync_call(ADS_VENDER_NAME, ADS_STATUS, params, nil)
                end

                function VENDOR_ADS.showAd(params,cb)
                    UNI.async_call(ADS_VENDER_NAME, ADS_SHOW, params, nil, cb)
                end
                function VENDOR_ADS.closeAd(params,cb)
                    UNI.async_call(ADS_VENDER_NAME, ADS_CLOSE, params, nil, cb)
                end
                function VENDOR_ADS.support_ad_types()
                    return UNI.sync_call(ADS_VENDER_NAME, ADS_SUPPORT_AD_TYPES, {}, nil)
                end
            end
        end

        M.fill_support_ad_types()

        ET.subscribe(ET.gangplank.PLAYER_ONLINE, player_online_handler)
        ET.subscribe(ET.gangplank.PLAYER_OFFLINE,function()
            -- logout, 用于清理
            UNI.logout(ADS_VENDER_NAME)
        end)
        ET.subscribe(ET.gangplank.LOGOUT,function()
            -- logout, 用于清理
            UNI.logout(ADS_VENDER_NAME)
        end)

        cb2(true)
    end
end

function M.is_support_init()
    local result = UNI.sync_call(ADS_VENDER_NAME, IS_SUPPORT_INIT_AD_SDK, {})
    if result == nil then
        return false
    else
        return result.value
    end
end

function M.query_list(cb)
    local url = base_url() .. "list_ad"

    --E.log("start to query ad list:"..url)
    local params={
        pkg_info=E.get_pkg_info()
    }

    E.HTTP.post(url, request_params(), E.HTTP.CT_JSON, params, function(resp)
        local status = resp.status
        local body = resp.body
        if status == 200 then
            cb(true, body.data)
            E.LOG.debug(TAG, "ejoyads:request ad list succ")
        else
            cb(false, {})
            E.LOG.debug(TAG, "ejoyads:request ad list fail")
        end
    end)
    E.LOG.debug(TAG, "ejoyads:start to query ad list")
end

local function createOrder(ad_id, callback)
    local url = base_url() .. "create_order"
    local params={
        id=ad_id,
        pkg_info=E.get_pkg_info()
    }
    E.LOG.debug(TAG, "ejoyads: create order for " .. tostring(ad_id))
    E.HTTP.post(url, request_params(), E.HTTP.CT_JSON, params, function(resp)
        local status = resp.status
        local body = resp.body or {}
        if status == 200 then
            local code=body.code or -1
            if code == 200 or code == 0 then
                E.LOG.debug(TAG, "ejoyads:create order succ")
                callback(code, body.data)
            else
                E.LOG.warn(TAG, "ejoyads:create order fail, code=" .. tostring(code) .. ", msg=".. (body.message or ""))
                callback(code, {})
            end
        end
    end)
end

local function getAdService(ad_id, callback)
    local url = base_url() .. "get_ad_service_by_id"
    local params={
        id=ad_id,
        pkg_info=E.get_pkg_info()
    }
    E.LOG.debug(TAG, "ejoyads: getAdService for " .. tostring(ad_id))
    E.HTTP.post(url, request_params(), E.HTTP.CT_JSON, params, function(resp)
        local status = resp.status
        local body = resp.body or {}
        if status == 200 then
            local code=body.code or -1
            if code == 200 or code == 0 then
                E.LOG.debug(TAG, "ejoyads:get ad service succ")
                E.LOG.debug(TAG, body)
                callback(code, body.data)
            else
                E.LOG.warn(TAG, "ejoyads:get ad service fail, code=" .. tostring(code) .. ", msg=".. (body.message or ""))
                callback(code, {})
            end
        end
    end)
end

local function notifyFinish(origin_body,retry_count,callback)
    local url=base_url().."finish_order"
    local data=origin_body.data
    local stat_params={order_id=data.order_id or '', service=data.service or '',retry=retry_count}
    QL.commit_event(EVENT_NOTIFY,stat_params)
    if(data.order_id and data.service) then
        E.LOG.debug(TAG, "ejoyads: notify check succ")
        local params={
            order_id=data.order_id
        }
        E.LOG.debug(TAG, "ejoyads: notify ad finish about " .. tostring(data.order_id))
        E.HTTP.post(url,request_params(),E.HTTP.CT_JSON,params,function(resp)
            local status = resp.status
            local body = resp.body
            local code=-1
            if status == 200 then
                code=body.code
                if code == 200 or code == 0 then
                    E.LOG.debug(TAG, "ejoyads:notify finish succ")
                    QL.commit_event(EVENT_NOTIFY_SUCC,stat_params)
                    callback(true, origin_body)
                    return
                end
            end

            E.LOG.debug(TAG, "ejoyads: notify finish fail, retry ".. tostring(retry_count) .. " ,code=" .. tostring(code) .. ",msg=" .. (body.message or ""))
            if(retry_count<MAX_NOFITY_RETRY)then
                notifyFinish(origin_body,retry_count+1,callback)
            else
                QL.commit_event(EVENT_NOTIFY_FAIL,stat_params)
                callback(false,{err_code=M.status.AD_SHOW_ERR,err_msg='通知服务器失败'})
            end
        end)
    else
        -- 不走服务端通知发奖的模式，直接返回true
        callback(true,origin_body)
    end
end

function M.load_ad(oParams, cb)
    local token = EH.get_player_token()
    cb=(cb or function(...) end)
    if token == nil or token == '' then
        E.LOG.debug(TAG, "ejoyads:no player token, skip showing ad")
        local body = {
            err_code = M.status.AD_ERR_NO_TOKEN,
            err_msg = "没有用户角色token"
        }
        cb(false, M.status.AD_ERR_NO_TOKEN, body, nil)

        do
            return
        end
    end

    oParams = oParams or {}

    local ad_id = oParams.id
    local ad_type = oParams.type or 'video'  -- 默认是激励视频

    local params = {
        adId = ad_id,
        adType = ad_type
    }

    if ad_type ~= 'video' and not support_ad_types[ad_type] then
        local body = {
            err_code = M.status.AD_ERR_C_UNSUPPORT_TYPE,
            err_msg = "do not support this ad type"
        }
        cb(false, M.status.AD_ERR_C_UNSUPPORT_TYPE, body, nil)
        return
    end

    QL.commit_event(EVENT_CREATE_ORDER, params)

    if ad_type == 'video' then
        createOrder(ad_id, function(status, ad_detail)
            if status == 200 or status == 0 then
                if ad_detail ~= nil then

                    QL.commit_event(EVENT_CREATE_ORDER_SUCC, params)
                    QL.commit_event(EVENT_LOAD, params)
                    E.LOG.debug(TAG, "ejoyads: start load ad")

                    -- VENDOR_ADS.loadAd方法内部，会把type强制改成ADS_LOAD，所以这里需要重命名一下
                    ad_detail.ad_type = ad_detail.type

                    if (ad_detail.service == 'wechat_game') then

                        if load_succ_result[tostring(ad_id)] then
                            load_succ_result[tostring(ad_id)] = nil
                        end

                        --返回为cb(false, body.code, body.body, resp_chunk)
                        local body = {
                            err_code = M.status.AD_ERR_C_ORDER_FAIL,
                            err_msg = "do not support ad from wechat_game"
                        }
                        cb(false, M.status.AD_ERR_C_ORDER_FAIL, body, nil)
                        QL.commit_event(EVENT_LOAD_FAIL, params)

                        return
                    end

                    VENDOR_ADS.loadAd(ad_detail, function(succ, ...)
                        if succ then
                            local body = ...
                            local s = body.status
                            params["code"] = s;

                            if s == M.status.AD_LOAD_SUCC then
                                load_succ_result[tostring(ad_id)] = {["ad_type"]=ad_detail.ad_type}

                                QL.commit_event(EVENT_LOAD_SUCC, params)
                            end
                        else
                            if load_succ_result[tostring(ad_id)] then
                                load_succ_result[tostring(ad_id)] = nil
                            end

                            local _, body = ...
                            local err_code = body.err_code
                            params["code"] = err_code
                            if body.err_msg then
                                params["message"] = body.err_msg
                            end
                            QL.commit_event(EVENT_LOAD_FAIL, params)
                        end
                        cb(succ, ...)
                    end)
                else
                    E.LOG.debug(TAG, "ejoyads: 获取广告信息失败")

                    if load_succ_result[tostring(ad_id)] then
                        load_succ_result[tostring(ad_id)] = nil
                    end

                    --返回为cb(false, body.code, body.body, resp_chunk)
                    local body = {
                        err_code = M.status.AD_ERR_C_ORDER_FAIL,
                        err_msg = "ad detail is null"
                    }

                    QL.commit_event(EVENT_CREATE_ORDER_FAIL, params)

                    cb(false, M.status.AD_ERR_C_ORDER_FAIL, body, nil)
                end
            else
                if load_succ_result[tostring(ad_id)] then
                    load_succ_result[tostring(ad_id)] = nil
                end

                --返回为cb(false, body.code, body.body, resp_chunk)
                local body = {
                    err_code = M.status.AD_ERR_C_ORDER_FAIL,
                    err_msg = "创建订单失败"
                }

                QL.commit_event(EVENT_CREATE_ORDER_FAIL, params)

                cb(false, M.status.AD_ERR_C_ORDER_FAIL, body, nil)
            end
        end)
    elseif ad_type == 'banner' then
        getAdService(ad_id, function(status, ad_service)
            E.LOG.d(TAG, 'banner callback >>')
            E.LOG.d(TAG, status)
            E.LOG.d(TAG, ad_service)
            if status == 200 or status == 0 then
                if ad_service ~= nil then

                    QL.commit_event(EVENT_GET_SERVICE_SUCC, params)
                    QL.commit_event(EVENT_LOAD, params)
                    E.LOG.debug(TAG, "ejoyads: start load ad")

                    -- VENDOR_ADS.loadAd方法内部，会把type强制改成ADS_LOAD，所以这里需要重命名一下
                    ad_service.ad_type = ad_service.type

                    if (ad_service.service == 'wechat_game') then

                        if load_succ_result[tostring(ad_id)] then
                            load_succ_result[tostring(ad_id)] = nil
                        end

                        --返回为cb(false, body.code, body.body, resp_chunk)
                        local body = {
                            err_code = M.status.AD_ERR_C_ORDER_FAIL,
                            err_msg = "do not support ad from wechat_game"
                        }
                        cb(false, M.status.AD_ERR_C_ORDER_FAIL, body, nil)
                        QL.commit_event(EVENT_LOAD_FAIL, params)

                        return
                    end

                    VENDOR_ADS.loadAd(ad_service, function(succ, ...)
                        if succ then
                            local body = ...
                            local s = body.status
                            params["code"] = s;

                            if s == M.status.AD_LOAD_SUCC then
                                load_succ_result[tostring(ad_id)] = {["ad_type"]=ad_service.ad_type}

                                QL.commit_event(EVENT_LOAD_SUCC, params)
                            end
                        else
                            if load_succ_result[tostring(ad_id)] then
                                load_succ_result[tostring(ad_id)] = nil
                            end

                            local _, body = ...
                            local err_code = body.err_code
                            params["code"] = err_code
                            if body.err_msg then
                                params["message"] = body.err_msg
                            end
                            QL.commit_event(EVENT_LOAD_FAIL, params)
                        end
                        cb(succ, ...)
                    end)
                else
                    E.LOG.debug(TAG, "ejoyads: 获取广告服务商信息失败")

                    if load_succ_result[tostring(ad_id)] then
                        load_succ_result[tostring(ad_id)] = nil
                    end

                    local body = {
                        err_code = M.status.AD_ERR_C_ORDER_FAIL,
                        err_msg = "ad service is null"
                    }
                    QL.commit_event(EVENT_GET_SERVICE_FAIL, params)

                    cb(false, M.status.AD_ERR_C_AD_SERVICE_FAIL, body, nil)
                end
            else
                if load_succ_result[tostring(ad_id)] then
                    load_succ_result[tostring(ad_id)] = nil
                end

                --返回为cb(false, body.code, body.body, resp_chunk)
                local body = {
                    err_code = M.status.AD_ERR_C_AD_SERVICE_FAIL,
                    err_msg = "get ad service fail"
                }

                QL.commit_event(EVENT_GET_SERVICE_FAIL, params)

                cb(false, M.status.AD_ERR_C_AD_SERVICE_FAIL, body, nil)
            end
        end)
    else
        if load_succ_result[tostring(ad_id)] then
            load_succ_result[tostring(ad_id)] = nil
        end

        local body = {
            err_code = M.status.AD_ERR_C_UNSUPPORT_TYPE,
            err_msg = "不支持的广告类型"
        }
        cb(false, M.status.AD_ERR_C_UNSUPPORT_TYPE, body, nil)
        QL.commit_event(EVENT_LOAD_FAIL, params)
    end
end

--显示广告
function M.show_ad(params,cb)
    QL.commit_event(EVENT_SHOW,params)
    params = params or {}
    params.cutout = E.Sysinfo.cutout()

    VENDOR_ADS.showAd(params,function(succ,...)
        --只有通知成功才会回调成功，否则回调失败

        if(succ)then
            local ad_type = 'video'
            if load_succ_result[params.id] then
                local load_succ_item = load_succ_result[params.id]
                ad_type = load_succ_item["ad_type"]
            end

            local body=...
            if 'banner' == ad_type then
                if body.status==M.status.AD_SHOW_START then
                    E.LOG.debug(TAG, "ejoyads: show banner")
                    QL.commit_event(EVENT_SHOW_START,params, true)
                end
            elseif 'video' == ad_type then
                if body.status==M.status.AD_SHOW_COMPLETED then
                    E.LOG.debug(TAG, "ejoyads: show ad completedm, notify finish")
                    QL.commit_event(EVENT_SHOW_SUCC,params, true)
                    notifyFinish(body,1,cb)
                    return
                elseif body.status==M.status.AD_SHOW_START then
                    E.LOG.debug(TAG, "ejoyads: show video")
                    QL.commit_event(EVENT_SHOW_START,params, true)
                end
            else
                E.LOG.w(TAG, "不识别的ad_type")
            end
        else
            QL.commit_event(EVENT_SHOW_FAIL,params)
        end
        cb(succ,...)
    end)
end


--获取广告状态
function M.get_status(oParams)
    local status_info = VENDOR_ADS.getAdStatus(oParams)
    --如果未创建, 则走预加载流程

    status_info=(status_info or {})

    --if (status_info ~= nil) then
        --local code = status_info.code
        --local msg = status_info.msg

        --if (code == AD_STATUS_NOT_EXISTS or code == AD_STATUS_NOT_LOAD) then
        --    M.load_ad(oParams, nil) --预加载
        --end
    --end

    return status_info
end

-- 关闭广告
function M.close_ad(params, cb)
    QL.commit_event(EVENT_CLOSE, params)

    params = params or {}
    params.type = params.type or 'video'
    if params.type ~= 'banner' then
        QL.commit_event(EVENT_CLOSE_FAIL,params)
        cb(false, -1, {err_code = M.status.AD_CLOSE_FAIL, err_msg = '不支持的广告类型，close操作只支持banner广告'})
        return
    end

    VENDOR_ADS.closeAd(params, function(succ,...)
        if(succ)then
            local body=...
            if (body.status==M.status.AD_SHOW_CLOSE)then
                E.LOG.debug(TAG, "ejoyads: ad close succ")
                QL.commit_event(EVENT_CLOSE_SUCC,params)
            end
        else
            QL.commit_event(EVENT_CLOSE_FAIL,params)
        end
        cb(succ,...)
    end)
end

return M
