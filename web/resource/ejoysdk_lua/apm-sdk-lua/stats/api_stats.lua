-------------------------------------------------------------------------------
-- 收集平台服务API性能指标数据的Collector模块

-- Created Date: 2021.11.03
-- Author: 三傻
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Stats = require "ejoysdk_lua.apm-sdk-lua.stats.stats"
local Common = require "ejoysdk_lua.apm-sdk-lua.stats.common"

local Metrics = require "ejoysdk_lua.apm-sdk-lua.common.metrics"
local ApmStats = require "ejoysdk_lua.apm-sdk-lua.stats.apm_stats"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"

local LOGGER = "apm_api_stats"

-- http_methods 枚举型定义
local HTTP_METHOD_GET = 1
local HTTP_METHOD_POST = 2
local HTTP_METHOD_PATCH = 3
local HTTP_METHOD_DELETE = 4
local HTTP_METHOD_PUT = 5

local M = {}

local stats_name = "api_stats"

local api_stats

local function get_api_stats()
    return Common.get_stats(M.agg_group)
end

function M.init()
    api_stats = Stats.new(stats_name, Global.namespace_api_stats)
    M.agg_group = Metrics.new_aggregate_group("api_agg_group")
    M.invalid_report_counter = ApmStats:new_counter("invalid_report_api_count", true)
    api_stats:set_calc_func(get_api_stats)
end

local function is_request_method_valid(request_method)
    if type(request_method) ~= "number" then
        return false
    end
    if
        request_method == HTTP_METHOD_GET or request_method == HTTP_METHOD_POST or request_method == HTTP_METHOD_PUT or
            request_method == HTTP_METHOD_DELETE or
            request_method == HTTP_METHOD_PATCH
     then
        return true
    end
    return false
end

local function check_param(server, api, response_code, cost, request_method)
    if server == nil or server == "" then
        return "invalid server"
    end
    if api == nil or api == "" then
        return "invalid api"
    end
    if response_code == nil or response_code == "" then
        return "invalid response_code"
    end
    if type(cost) ~= "number" or cost < 0 then
        return "invalid cost"
    end
    if not is_request_method_valid(request_method) then
        return "invalid request_method"
    end
    return nil
end

-- 上报api调用情况
-- 参数说明如下
--      server: 服务器的域名或IP   必填
--      api: http请求的uri(例如 /api/v1/login) 或者 rpc请求的接口名(例如 updatePanel)
--           温馨提示 避免在链接中出现变量 如 /api/v1/panel/3 /api/v1/panel/4 /api/v1/panel/5 (3 4 5动态变）
--           如果存在变量，可用固定的占位符表示 如/api/v1/panel/id
--      response_code: 响应状态码 必填
--      cost_ms: 请求耗时 单位毫秒 必填
--      request_method: http请求方法 枚举型(1:get 2:post 3:patch 4:delete 5:put) 填1到5 必填
--      caller_module: 所处的模块 选填
function M.count_platform_api_call(server, api, response_code, cost_ms, request_method, caller_module)
    if api_stats and not api_stats.enabled then
        return
    end
    -- 可能尚未初始化
    if M.agg_group == nil then
        return
    end

    if not Global.is_apus_sdk_initialized() then
        return
    end

    local err = check_param(server, api, response_code, cost_ms, request_method)
    if err ~= nil then
        E.LOG.debug(LOGGER, "illegal report_api_call param,err:" .. err)

        M.invalid_report_counter:inc()
        return
    end
    api, err = Common.apply_pattern(api)
    if err ~= nil then
        E.LOG.debug(LOGGER, "illegal report_api_call param,api:" .. err)
        M.invalid_report_counter:inc()
        return
    end
    M.agg_group:update(
        cost_ms,
        {
            -- sls单字段最大长度为16k(默认2k),这里为了能一次性发送更多的stats，采用命名缩写
            srv = server,
            api = api,
            rc = response_code,
            rm = request_method,
            cm = caller_module
        }
    )
end

return M
