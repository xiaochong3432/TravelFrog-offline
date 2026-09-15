-------------------------------------------------------------------------------
-- 【 Stats类型的埋点数据 】
-- Stats代表一组有关联的APM指标，在stats collector中被定时采集。
-- Stats实例可以包含一组类型为Metrics的指标，也可以设置一个方法，在采集时通过该方法产生一组
--   table形式的指标。这两种用法可以并存。
--
-- Created Date: 2021.07.06
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Metrics = require "ejoysdk_lua.apm-sdk-lua.common.metrics"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"

local CFG_MODULES = "modules"

local instances = {}

local LOGGER = "apm_stats"

local mt = {}
mt.__index = mt

function mt:enable()
    self.enabled = true
end

function mt:disable()
    self.enabled = false
end

-- 增加指标到stats中
function mt:add(metric)
    self.metrics[metric.name] = metric
end

function mt:get(metric_name)
    return self.metrics[metric_name]
end

-- 在stats中删除指标
function mt:remove(metric)
    self.metrics[metric.name] = nil
end

-- 生成Counter类型指标，并注册到stats中
function mt:new_counter(metric_name, clearable, verbose)
    local m = Metrics.new_counter(metric_name, clearable, verbose)
    if m ~= nil then
        self:add(m)
        return m
    end
end

-- 目前存储使用Logstore，不适合存放多维度的指标（如访问不同后端api的响应时间）
-- APM SDK一期在Stats中暂不开放MetricGroup的使用
-- function mt:new_counter_group(metric_name)
--     local m = Metrics.new_counter_group(metric_name)
--     self:add(m)
--     return m
-- end

-- 生成Gauge类型指标，并注册到stats中，调用set()方法对该指标赋值
function mt:new_gauge(metric_name)
    local m = Metrics.new_gauge(metric_name)
    if m ~= nil then
        self:add(m)
        return m
    end
end

-- 生成带计算方法的Gauge指标，并注册到stats中，采集时刻将自动调用计算方法获取指标值
function mt:new_gauge_with_func(metric_name, verbose, func)
    local m = Metrics.new_gauge_with_func(metric_name, verbose, func)
    if m ~= nil then
        self:add(m)
        return m
    end
end

-- 生成Aggregate类型指标，并注册到stats中，通过update()方法更新count/sum/min/max统计值
function mt:new_aggregate(metric_name, verbose)
    local m = Metrics.new_aggregate(metric_name, verbose)
    if m ~= nil then
        self:add(m)
        return m
    end
end

-- 设置在被collector定时采集时用于生成stats的函数
function mt:set_calc_func(func, ...)
    self.calc_func = func
    self.calc_args = {...}
end

function mt:destroy()
    instances[self.name] = nil
    self.metrics = {}
end

-- 用于新建stats的时候 更新stats的开关状态
local function is_config_enabled(stats_name)
    local enabled = true
    local module_cfg = Cfg.get(Cfg.CATEGORY_STATS, CFG_MODULES)
    if module_cfg ~= nil and type(module_cfg) == "table" then
        for name, cfg in pairs(module_cfg) do
            if name == stats_name then
                enabled = not cfg[Cfg.KEY_ENABLED] == false
                break
            end
        end
    end
    return enabled
end

local M = {}

-- 新建stats模块，并注册到Collector中
-- 可以在stats中添加采集的指标。也可以通过可选参数func，在采集时通过改该方法生成一组指标值。
-- 这两种方式可以共用。
-- 参数：
--   name：     stats的名称，仅用于程序内部区分不同的stats
--   namespace：用于区分全局指标的命名空间，用作上报指标名的前缀。应少于或等于6个字符，超过会被截断。
function M.new(name, namespace)
    if not Utils.is_metric_name_valid(namespace) then
        E.LOG.error("namespace is invalid    #" .. tostring(namespace))
        return nil
    end
    if namespace ~= nil and #namespace >= 6 then
        namespace = string.sub(namespace, 1, 6)
    end

    if instances[name] ~= nil then
        E.LOG.error("Stats模块已存在：" .. name)
        return nil
    end

    local enabled = is_config_enabled(name)
    if not enabled then
        E.LOG.debug(LOGGER, "stats " .. name .. " is disabled in stats creation")
    end

    local obj = {
        enabled = enabled,
        name = name,
        namespace = namespace,
        metrics = {},
        calc_func = nil
    }
    setmetatable(obj, mt)
    instances[name] = obj
    E.LOG.debug(LOGGER, string.format("created stats with name=%s, namespace=%s", name, namespace))
    return obj
end

function M.get(name)
    return instances[name]
end

function M.get_instances()
    return instances
end

return M
