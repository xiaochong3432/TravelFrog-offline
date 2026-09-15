-------------------------------------------------------------------------------
-- Stats Collector模块，负责定时收集指标数据
--
-- Created Date: 2021.07.30
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local APM_Global = require "ejoysdk_lua.apm-sdk-lua.global"

local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Stats = require "ejoysdk_lua.apm-sdk-lua.stats.stats"
local apm_stats = require "ejoysdk_lua.apm-sdk-lua.stats.apm_stats"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local Labeler = require "ejoysdk_lua.apm-sdk-lua.label.labeler"
local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.init"
local ErrUtils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"
local Store = require "ejoysdk_lua.apm-sdk-lua.store.store"
local AbnormalMetricsCb = require "ejoysdk_lua.apm-sdk-lua.stats.abnormal_metrics_callback"

local CFG_INTERVAL = "collect_interval"
local CFG_MODULES = "modules"
local LOGGER = "apm_stats_collector"

local M = {}
M.__index = M

local stopping = true

local function run()
    if not stopping then
        E.Timer.once(M.interval, run)
    end
    xpcall(M.process, ErrUtils.handle_err)
end

local function config_modules(module_cfg)
    for name, cfg in pairs(module_cfg) do
        local s = Stats.get(name)
        if s ~= nil and type(cfg.enabled) == "boolean" then
            s.enabled = cfg.enabled
            E.LOG.debug(LOGGER, string.format("stats %s is %s", name, cfg.enabled and "enabled" or "disabled"))
        else
            E.LOG.error(LOGGER, "invalid config for stats module " .. name)
        end
    end
end

local function handle_config_update(key, value)
    if key == Cfg.KEY_ENABLED then
        if value == true and stopping == true then
            M.start()
        elseif value == false and stopping == false then
            M.stop()
        end
    elseif key == CFG_INTERVAL and type(value) == "number" then
        -- 下次生效
        E.LOG.debug(
            LOGGER,
            string.format("stats collector interval is changed from %d to %d seconds", M.interval, value)
        )
        M.interval = value
        Labeler.set_static_label("collect_interval", value)
    elseif key == CFG_MODULES and type(value) == "table" then
        config_modules(value)
    else
        E.LOG.error(LOGGER, "invalid config change of stats: " .. key)
    end
end

function M.init()
    ErrUtils.set_collect_stopper(M.stop)
    local interval = Cfg.get(Cfg.CATEGORY_STATS, CFG_INTERVAL, 60)
    local enabled = Cfg.get(Cfg.CATEGORY_STATS, Cfg.KEY_ENABLED, true)
    if enabled then
        M.start(interval)
        E.LOG.debug(LOGGER, "Stats collector initialized with interval " .. tostring(interval))
    end

    -- 有些模块可能在apm初始化之前已经注册(如apm_stats)，需要在此判断是否被禁用
    local module_cfg = Cfg.get(Cfg.CATEGORY_STATS, CFG_MODULES)
    if module_cfg ~= nil and type(module_cfg) == "table" then
        for name, cfg in pairs(module_cfg) do
            local s = Stats.get(name)
            if s ~= nil and not cfg.enabled then
                s.enabled = false
                E.LOG.debug(LOGGER, "stats " .. name .. " is disabled in collector init")
            end
        end
    end

    Cfg.set_update_callback(Cfg.CATEGORY_STATS, handle_config_update)

    if M.collector_cost == nil then
        M.collector_cost = apm_stats:new_counter("stats_collector_cost_ms")
    end
end

function M.start(interval)
    if interval ~= nil then
        M.interval = interval
    end

    -- trigger timer
    if stopping == true then
        stopping = false
        E.Timer.once(M.interval, run)
        E.LOG.debug(LOGGER, "stats collector started")
    end
end

function M.stop()
    -- E.Timer没有cancel方法，还会跑最后一次
    stopping = true
    E.LOG.debug(LOGGER, "stats collector stopping")
end

-- 生成上报数据提交到Reporter队列中
function M.process()
    E.LOG.debug(LOGGER, "stats collector is invoked.")
    local data = M.collect()
    if data ~= nil then
        Store.submit_stats(data)
    end
end

local function add_metric(name, metric, output)
    local value = metric:get()
    if value == nil then
        return
    end
    if metric.type == APM_Global.MetricTypeEnum.GaugeType then
        output[name] = value
    elseif metric.type == APM_Global.MetricTypeEnum.CounterType then
        output[name] = value
        metric:clear()
    elseif metric.type == APM_Global.MetricTypeEnum.AggregateType then
        for k, v in pairs(value) do
            output[name .. "_" .. k] = v
        end
    end
end

local function add_metrics(stats, prefix, output)
    for _, metric in pairs(stats.metrics) do
        local name = prefix and prefix .. metric.name or metric.name
        add_metric(name, metric, output)
    end
end

local function should_collect(stats, metric_value)
    return (type(metric_value) == "number" or stats.namespace == Global.namespace_api_stats or
        stats.namespace == Global.namespace_rpc_stats)
end

local function collect_stats(stats, output)
    if not stats.enabled then
        return
    end
    E.LOG.debug(LOGGER, "collecting stats " .. stats.name)
    local s = Time.system_clock()

    -- 以namespace作为上报指标名的前缀
    local prefix = nil
    if stats.namespace ~= nil then
        prefix = stats.namespace .. "_"
    end

    -- 遍历stats的所有指标，取值加到output table中
    add_metrics(stats, prefix, output)

    -- 有计算函数，调用计算函数取值
    if stats.calc_func ~= nil then
        local result = Utils.exec(stats.calc_func, stats.calc_args)
        if result ~= nil then
            for k, v in pairs(result) do
                AbnormalMetricsCb.check(k, v)
                local full_metric_name = prefix and prefix .. k or k
                if should_collect(stats, v) then
                    output[full_metric_name] = v
                end
            end
        end
    end
    E.LOG.debug(LOGGER, string.format("collecting stats %s cost %.4f ms", stats.name, Time.system_clock() - s))
end

-- 遍历stats列表采集指标，生成上报数据
function M.collect()
    local start = Time.system_clock()
    local output = {}
    for _, stats in pairs(Stats.get_instances()) do
        collect_stats(stats, output)
    end
    local elapsed = Time.system_clock() - start
    if elapsed > 0 and M.collector_cost then
        M.collector_cost:inc(elapsed)
    end

    return output
end

-- 改变采集间隔
function M.set_interval(interval)
    M.interval = interval
end

return M
