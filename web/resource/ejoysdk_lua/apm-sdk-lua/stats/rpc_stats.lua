-------------------------------------------------------------------------------
-- 收集游戏服务RPC调用性能指标数据的Collector模块

-- Created Date: 2021.12.16
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

local LOGGER = "apm_rpc_stats"
local stats_name = "rpc_stats"

local M = {}
local rpc_stats

local function get_rpc_stats()
    return Common.get_stats(M.agg_group)
end

function M.init()
    rpc_stats = Stats.new(stats_name, Global.namespace_rpc_stats)
    M.agg_group = Metrics.new_aggregate_group("rpc_agg_group")
    M.invalid_report_counter = ApmStats:new_counter("invalid_report_rpc_count", true)
    rpc_stats:set_calc_func(get_rpc_stats)
end

local function check_param(service, succ, response_code, cost_ms)
    if service == nil or service == "" then
        return "invalid service"
    end
    if type(succ) ~= "boolean" then
        return "invalid succ"
    end
    if (type(response_code) ~= "number" and type(response_code) ~= "string") or response_code == "" then
        return "invalid response_code"
    end
    if type(cost_ms) ~= "number" or cost_ms < 0 then
        return "invalid cost_ms"
    end
    return nil
end

-- apus内定的rpc调用响应成功码
M.RESPONSE_CODE_SUCC_FOR_RPC_CALL = 0

-- 上报游戏服务接口调用情况
-- 参数说明如下
--      service:        调用游戏服务的接口名  必填
--      succ:           rpc调用是否成功，bool型，true是调用成功 false是调用失败 (如果是不关心返回值的远程调用，此处填true即可) 必填
--      response_code:  响应状态码 (如果是不关心返回值的远程调用，此处填0即可)必填
--      cost_ms:        请求耗时 单位毫秒 必填
--      caller_module:  调用方所处的模块 例如是在聊天模块 选填
function M.count_game_rpc_call(service, succ, response_code, cost_ms, caller_module)
    if rpc_stats and not rpc_stats.enabled then
        return
    end
    -- 可能尚未初始化
    if M.agg_group == nil then
        return
    end

    if not Global.is_apus_sdk_initialized() then
        return
    end

    local err = check_param(service, succ, response_code, cost_ms)
    if err ~= nil then
        E.LOG.debug(LOGGER, "illegal count_game_rpc_call param,err:" .. err)

        M.invalid_report_counter:inc()
        return
    end
    service, err = Common.apply_pattern(service)
    if err ~= nil then
        E.LOG.debug(LOGGER, "illegal count_game_rpc_call param.service,err:" .. err)
        M.invalid_report_counter:inc()
        return
    end
    M.agg_group:update(
        cost_ms,
        {
            -- sls单字段最大长度为16k(默认2k),这里为了能一次性发送更多的stats，采用命名缩写
            svc = service,
            succ = succ and 1 or 0,
            rc = tostring(response_code),
            cm = caller_module
        }
    )
end

return M
