local E = require 'ejoysdk_lua.ejoysdk'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local DSP = require "ejoysdk_lua.protocal.ejoysdk_ds_protocal"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local EM = require "ejoysdk_lua.ejoysdk_module"
local VENDOR_NAME = 'CBA'
local TAG = EM.MODULE.VENDORS.CBA_INFO

local M = Vendor:Inherit(VENDOR_NAME)

local retry_config = {
    -- 请求平台服务器的当前重试次数
    retry_request_platform_service_times = 0,
    -- 请求平台服务器的最大重试次数
    max_retry_request_platform_service_times = 3
}

local timer_config = {
    -- 异步回调的最大等待时间
    async_action_max_wait_seconds = 5,
    -- 重试的延迟时间
    retry_delay_seconds = 5
}

local CBA_OBJECT = {}

-- 一级错误码
local TOP_ERROR_CODE = {
    -- 从Native获取CBA数据失败，Native版本太低了
    GET_CBA_INFO_FAIL = 10000,
    -- 上报平台时，失败
    UPLOAD_PLATFORM_FAIL = 20000
}

-- 更新CBA_OBJECT
local function update_cba_object(caid_data, error_code, sub_error_code, sub_error_msg)
    E.LOG.debug(TAG, 'start update cba_object')

    CBA_OBJECT.data = CBA_OBJECT.data or {}

    for key, value in pairs(caid_data) do
        CBA_OBJECT.data[key] = value
    end

    if error_code and type(error_code) == 'number' then
        CBA_OBJECT.error_code = error_code
    else
        CBA_OBJECT.error_code = nil
    end

    if sub_error_code and type(sub_error_code) == 'number' then
        CBA_OBJECT.sub_error_code = sub_error_code
    else
        CBA_OBJECT.sub_error_code = nil
    end

    if sub_error_msg and type(sub_error_msg) == 'string' then
        CBA_OBJECT.sub_error_msg = sub_error_msg
    else
        CBA_OBJECT.sub_error_msg = nil
    end

    E.log({after_update_CBA_OBJECT=CBA_OBJECT})
end

-- stat_action打点
local function report_jf()
    CBA_OBJECT["is_priority_high"] = true
    if CBA_OBJECT.error_code then
        E.LOG.debug(TAG, 'report_jf, ' .. 'action:cba_fail')
        E.LOG.debug(TAG, {report_jf_CBA_OBJECT=CBA_OBJECT})
        ESTAT.stat_action('cba_fail', nil, false, CBA_OBJECT)
    else
        E.LOG.debug(TAG, 'report_jf, ' .. 'action:cba_succ')
        E.LOG.debug(TAG, {report_jf_CBA_OBJECT=CBA_OBJECT})
        ESTAT.stat_action('cba_succ', nil, true, CBA_OBJECT)
    end
end

-- 上报CBA数据的重试方法
local request_platform_service_retry_action = function(resp_reach, ...)
    local _, code, msg = ...
    E.LOG.debug(TAG, {succ=false, code=code, msg=msg})

    if retry_config.retry_request_platform_service_times >= retry_config.max_retry_request_platform_service_times then
        -- 重试次数达到上限
        E.LOG.debug(TAG, 'upload platform_service, reach max retry times, max retry times:' .. tostring(retry_config.max_retry_request_platform_service_times))

        retry_config.retry_request_platform_service_times = 0
        -- 更新CBA_OBJECT
        CBA_OBJECT.error_code = TOP_ERROR_CODE.UPLOAD_PLATFORM_FAIL
        CBA_OBJECT.sub_error_code = code
        CBA_OBJECT.sub_error_msg = msg

        report_jf()
    else
        -- 重试次数未达上限
        retry_config.retry_request_platform_service_times = retry_config.retry_request_platform_service_times + 1
        E.LOG.debug(TAG, 'retry upload platform_service,current times:' .. tostring(retry_config.retry_request_platform_service_times))

        if resp_reach then
            -- 服务端返回错误，5s后，再重试1次
            E.Timer.once(timer_config.retry_delay_seconds, function()
                M.request_platform_service()
            end)
        else
            -- 超时时间到了，不用延迟，直接请求
            M.request_platform_service()
        end
    end
end

-- 上报CBA数据到平台服务器
local function request_platform_service()
    E.LOG.debug(TAG, 'start request platform_service')

    local req_platform_resp_reach = false
    local req_platform_timer_reach = false

    -- 带超时重试
    -- cb(resp_reach, ...), 服务端有数据返回，resp_reach为true；超时时间到，服务端无数据返回，resp_reach为false
    local dsp_req_with_timer = function(logObject, cb)
        local parm = {}
        parm.contentType = 2
        parm.logNum = 1
        parm.logValue = JSON.encode(logObject)

        E.LOG.debug(TAG, {request_platform_service_parm=parm})

        DSP.post('log.collect.ejoysdklog', parm, function(succ, ...)
            if req_platform_timer_reach then
                return
            end

            req_platform_resp_reach = true

            cb(true, succ, ...)
        end, 'ejoysdk', 'cba')

        E.Timer.once(timer_config.async_action_max_wait_seconds, function()
            if req_platform_resp_reach then
                return
            end

            req_platform_timer_reach = true

            cb(false)
        end)
    end

    local function http_action(logObject)
        -- dsp_req_with_timer方法，是带5s超时时间，ios默认的请求超时时间太长了
        dsp_req_with_timer(logObject, function(resp_reach, ...)
            E.LOG.debug(TAG, 'receive platform_service resp, resp_reach:' .. tostring(resp_reach))

            if not resp_reach then
                ESTAT.stat_action('cba_req_platform_timeout', nil, false, nil)

                M.request_platform_service_retry_action(false)
                return
            end

            local succ = ...
            if succ then
                local _, data = ...
                E.LOG.debug(TAG, {succ=true, data=data})
                retry_config.retry_request_platform_service_times = 0
                report_jf()
            else
                M.request_platform_service_retry_action(true, ...)
            end
        end)
    end

    -- 组装带经分公参的数据
    ESTAT.get_jf_format_data('sdk.caid', CBA_OBJECT or {}, function(log)
        -- 发请求
        http_action(log)
    end)
end

M.request_platform_service_retry_action = request_platform_service_retry_action
M.request_platform_service = request_platform_service

local function is_overseas ()
    return E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
end

function M.cba_action()
    -- cba是国内广告联盟的，只在国内用
    if is_overseas() then
        E.LOG.debug(TAG, 'is_overseas: true')
        return
    end

    -- 只有苹果才有上报cba
    if E.Sysinfo.os() ~= 'ios' then
        return
    end

    local cba_info = E.get_cba_tweleve_info()
    if not cba_info then
        E.LOG.debug(TAG, 'get cba info fail, native version too low')
        update_cba_object(nil, TOP_ERROR_CODE.GET_CBA_INFO_FAIL)
        report_jf()
        return
    end

    update_cba_object(cba_info)
    request_platform_service()
end

function M.init(_, cb)
    E.LOG.debug(TAG, 'cba info vendor init complete')
    M.cba_action()
    -- callback init success
    cb(true)
end

return M
