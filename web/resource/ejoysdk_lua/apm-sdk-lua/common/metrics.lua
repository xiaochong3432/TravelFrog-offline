-------------------------------------------------------------------------------
-- APM SDK提供3种指标类型
-- 1. Gauge: 反映瞬时值，如内存、电量、以及状态枚举值等
-- 2. Counter：用于表示本次统计周期的计数，每次采集后会被清零，如接口请求次数等
-- 3. Aggregate：用于提供一些基本的统计数据，包括count/min/max/sum，主要针对响应时间、数据大小等
--
-- Created Date: 2021.07.06
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local APM_Global = require "ejoysdk_lua.apm-sdk-lua.global"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local StringUtils = require "ejoysdk_lua.apm-sdk-lua.common.string_utils"

local LOGGER = "apm_metrics"

local M = {}

-- 指标序列允许连续为空值的次数，超过会被清理
M.MAX_NIL_COUNT_BEFORE_CLEAR = 5

M.DEFAULT_MAX_SERIES_LIMIT = 100

-- 指标清单，用于判断是否重复，以及限定序列数量
-- table形式。key为metric_name，value无意义
-- TODO：区分是Stats还是Event中的指标，允许重复
local metrics_full_list = {}

local function sortedKeys(t)
    local tmp_table = {}
    for key, _ in pairs(t) do
        table.insert(tmp_table, key)
    end
    table.sort(tmp_table)
    return tmp_table
end

--   labels: 如果是一组指标，以table形式指定具体的label key/value。
--          如{api="/api/v1/someservice"}
-- 最终metric_name和labels被组装为一个字符串，代表唯一的序列名。序列名会用于发送到后端。
--   如 "cluster#$#s3|group#$#S102905|job#$#tadpole"

------- benchmark 性能数据如下
-- { a = "key", index = i }  2个key                     36.3W/s
-- {a = "key", index = i,c="value",d=true} 4个 key      23W/s
local function hash_labels(labels)
    if labels == nil then
        return nil
    end
    local sb = StringUtils.new_string_buffer()
    local label_size = Utils.table_size(labels)
    for i, k in ipairs(sortedKeys(labels)) do
        local v = tostring(labels[k])
        k = string.gsub(k, APM_Global.labels_kv_concate_str, "____")
        v = string.gsub(v, APM_Global.labels_kvpair_concate_str, "_")
        sb:append(k)
        sb:append(APM_Global.labels_kv_concate_str)
        sb:append(v)

        if i < label_size then
            sb:append(APM_Global.labels_kvpair_concate_str)
        end
    end
    return sb:to_string()
end

-- just for unit test
M.__hash_lables = hash_labels

-----------------------------
-- Metric基类
-----------------------------

local Metric = {
    __name = "Metric",
    name = "",
    type = APM_Global.MetricTypeEnum.NoneType,
    nil_count = 0 -- 空值的次数
}

Metric.__index = Metric

function Metric.new(metric_name, metric_type, clearable, verbose)
    -- 判断是否已存在
    if metrics_full_list[metric_name] ~= nil then
        E.LOG.error(LOGGER, "metric already exists: " .. metric_name)
        return nil
    end

    -- 同一指标名的序列数上限，防止以变量作为指标维度等误用情况，导致产生过多指标序列
    local max_series_limit = Cfg.get(Cfg.CATEGORY_STATS, "max_series_num", M.DEFAULT_MAX_SERIES_LIMIT)

    -- 判断改指标的序列数已经超限
    if M.get_series_count() >= max_series_limit then
        if M.exceed_max_series_counter then
            M.exceed_max_series_counter:inc()
        end
        return nil
    end

    local obj = {
        name = metric_name,
        type = metric_type,
        clearable = clearable, -- 可被清除，意味着如果连续N次未被更新则不被采集
        verbose = verbose, -- 如果verbose=true,并且配置的verbose等于false 则不会采集，其他情况都采集本metric
        nil_count = 0 -- 连续未被更新的次数
    }

    metrics_full_list[metric_name] = 0
    return setmetatable(obj, Metric)
end

function Metric:delete()
    metrics_full_list[self.name] = nil
end

function Metric:get_name()
    return self.name
end

function Metric:is_group() -- luacheck: ignore 212
    return false
end

function Metric:should_purge()
    return self.count == 0 and self.clearable and self.nil_count >= M.MAX_NIL_COUNT_BEFORE_CLEAR
end

function Metric:should_collect()
    -- verbose 为FALSE 默认采集
    if not self.verbose then
        return true
    end
    -- 如果verbose=true,并且配置的verbose等于false 则不会采集，
    return Cfg.get_stats_verbose()
end
-----------------------------
-- MetricGroup基类，未严格测试，建议先不使用
-----------------------------

-- 用于存放一组不同label值的指标
local MetricGroup = {
    __name = "MetricGroup",
    name = "",
    type = APM_Global.MetricTypeEnum.NoneType,
    -- 指标实例数
    count = 0,
    -- 指标值table
    vector = {}
}

MetricGroup.__index = MetricGroup

function MetricGroup.new(metric_name, type)
    local obj = {
        name = metric_name,
        type = type,
        -- 指标实例数
        count = 0,
        -- 指标值table
        vector = {}
    }
    return setmetatable(obj, MetricGroup)
end

function MetricGroup:get_or_create_metric(labels)
    if labels == nil then
        E.LOG.error(LOGGER, "get_or_create_metric| recv nil labels")
        return nil
    end
    local hash = hash_labels(labels)
    local metric = self.vector[hash]
    if metric == nil then
        -- 为防止MetricGroup自定义的labels过多，默认设置成可清理的
        metric = M.create_metric(hash, self.type, true)
        if metric then
            self.vector[hash] = metric
        end
    end
    return metric
end

function M.register_exceed_max_series_counter(exceed_max_series_counter)
    M.exceed_max_series_counter = exceed_max_series_counter
end

function MetricGroup:get(labels)
    if labels == nil then
        E.LOG.error(LOGGER, "get| recv nil labels")
        return nil
    end
    local hash = hash_labels(labels)
    local metric = self.vector[hash]
    if metric ~= nil then
        return metric:get()
    end
    return nil
end

function MetricGroup:get_all()
    return self.vector
end

function MetricGroup:delete(labels)
    if labels == nil then
        E.LOG.error(LOGGER, "delete| recv nil labels")
        return
    end
    local hash = hash_labels(labels)
    local metric = self.vector[hash]
    if metric ~= nil then
        self.vector[hash] = nil
        metric:delete()
    end
end

function MetricGroup:is_group() -- luacheck: ignore 212
    return true
end

function MetricGroup:get_group()
    local result = {}
    for _, v in pairs(self.vector) do
        result[v.name] = v:get()
    end
    return result
end

-----------------------------
-- Counter类
-----------------------------
local Counter = {__name = "Counter", type = APM_Global.MetricTypeEnum.CounterType, count = 0}
setmetatable(Counter, Metric)
Counter.__index = Counter

function Counter.new(metric_name, clearable, verbose)
    local obj = Metric.new(metric_name, APM_Global.MetricTypeEnum.CounterType, clearable, verbose)
    if obj ~= nil then
        return setmetatable(obj, Counter)
    end
    return nil
end

-- Counter累加操作，不带参数为加1
function Counter:inc(num)
    num = num or 1
    self.count = self.count + num
    return self.count
end

function Counter:get()
    if self.count == 0 and self.clearable and self.nil_count >= M.MAX_NIL_COUNT_BEFORE_CLEAR then
        return nil
    end
    if not self:should_collect() then
        return nil
    end
    return self.count
end

function Counter:clear()
    if self.clearable then
        if self.count == 0 then
            self.nil_count = self.nil_count + 1
            return
        else
            self.nil_count = 0
        end
    end
    self.count = 0
end

local CounterGroup = {__name = "CounterGroup", type = APM_Global.MetricTypeEnum.CounterType}
setmetatable(CounterGroup, MetricGroup)
CounterGroup.__index = CounterGroup

function CounterGroup.new(metric_name)
    local obj = MetricGroup.new(metric_name, APM_Global.MetricTypeEnum.CounterType)
    return setmetatable(obj, CounterGroup)
end

function CounterGroup:inc(num, labels)
    local counter = self:get_or_create_metric(labels)
    return counter:inc(num)
end

function CounterGroup:clear()
    for k, v in pairs(self.vector) do
        v:clear()
        -- 清理长期无更新对象
        if v:should_purge() then
            self.vector[k] = nil
            v:delete()
        end
    end
end

-----------------------------
-- Gauge类
-- Gauge没有clear操作，值保留到下一次set
-----------------------------
local Gauge = {__name = "Gauge", type = APM_Global.MetricTypeEnum.GaugeType, value = 0}
setmetatable(Gauge, Metric)
Gauge.__index = Gauge

function Gauge.new(metric_name, verbose)
    local obj = Metric.new(metric_name, APM_Global.MetricTypeEnum.GaugeType, false, verbose)
    if obj ~= nil then
        return setmetatable(obj, Gauge)
    end
    return nil
end

function Gauge:set_calc_func(func, ...)
    self.calc_func = func
    self.calc_args = {...}
end

function Gauge:set(value)
    local v = self.value
    self.value = value or 0
    return v
end

function Gauge:get()
    if not self:should_collect() then
        return nil
    end
    if self.calc_func == nil then
        return self.value
    end
    local v = Utils.exec(self.calc_func, self.calc_args)
    if type(v) == "number" then
        return v
    end
end

local GaugeGroup = {__name = "GaugeGroup", type = APM_Global.MetricTypeEnum.GaugeType}
setmetatable(GaugeGroup, MetricGroup)
GaugeGroup.__index = GaugeGroup

function GaugeGroup.new(metric_name)
    local obj = MetricGroup.new(metric_name, APM_Global.MetricTypeEnum.GaugeType)
    return setmetatable(obj, GaugeGroup)
end

function GaugeGroup:set(value, labels)
    local gauge = self:get_or_create_metric(labels)
    return gauge:set(value)
end

-----------------------------
-- Aggregate类
-----------------------------
local Aggregate = {
    __name = "Aggregate",
    type = APM_Global.MetricTypeEnum.AggregateType,
    count = 0,
    sum = 0,
    min = 0,
    max = 0
}
setmetatable(Aggregate, Metric)
Aggregate.__index = Aggregate

function Aggregate.new(metric_name, clearable, verbose)
    local obj = Metric.new(metric_name, APM_Global.MetricTypeEnum.AggregateType, clearable, verbose)
    if obj ~= nil then
        return setmetatable(obj, Aggregate)
    end
    return nil
end

-- 更新count/sum/min/max统计值
function Aggregate:update(value)
    if not self:should_collect() then
        return nil
    end
    if self.count > 0 then
        self.count = self.count + 1
        self.sum = self.sum + value
        if self.min > value then
            self.min = value
        end
        if self.max < value then
            self.max = value
        end
    else
        self.count = 1
        self.sum = value
        self.min = value
        self.max = value
    end
end
function Aggregate:get_min()
    if not self:should_collect() then
        return nil
    end
    return self.min
end
function Aggregate:get_max()
    if not self:should_collect() then
        return nil
    end
    return self.max
end
function Aggregate:get_avg()
    if not self:should_collect() then
        return nil
    end
    if self.count == 0 then
        return 0
    end
    return self.sum / self.count
end
function Aggregate:get_count()
    if not self:should_collect() then
        return nil
    end
    if self.count > 0 then
        self.nil_count = 0
    end
    return self.count
end

function Aggregate:get()
    if not self:should_collect() then
        return nil
    end
    if self.count > 0 then
        self.nil_count = 0
        return {count = self.count, sum = self.sum, min = self.min, max = self.max}
    else
        return {count = 0, sum = 0}
    end
end

function Aggregate:clear()
    if self.count == 0 then
        self.nil_count = self.nil_count + 1
    end
    self.count = 0
    self.sum = 0
    self.min = 0
    self.max = 0
end

local AggregateGroup = {__name = "AggregateGroup", type = APM_Global.MetricTypeEnum.AggregateType}
setmetatable(AggregateGroup, MetricGroup)
AggregateGroup.__index = AggregateGroup

function AggregateGroup.new(metric_name)
    local obj = MetricGroup.new(metric_name, APM_Global.MetricTypeEnum.AggregateType)
    return setmetatable(obj, AggregateGroup)
end

local has_print_aggr_update_err = false
function AggregateGroup:update(value, labels)
    local aggr = self:get_or_create_metric(labels)
    if aggr == nil then
        if not has_print_aggr_update_err then
            E.LOG.warn(LOGGER, "get_or_create_metric return a nil aggr,update opr is ignored,value:" .. value)
            E.LOG.warn(LOGGER, labels)
            has_print_aggr_update_err = true
        end
        return
    end
    return aggr:update(value)
end

function AggregateGroup:clear()
    for k, v in pairs(self.vector) do
        v:clear()
        -- 清理长期无更新对象
        if v:should_purge() then
            self.vector[k] = nil
            v:delete()
        end
    end
end

-----------------------------
-- Module
-----------------------------

local MetricType = {
    [APM_Global.MetricTypeEnum.NoneType] = nil,
    [APM_Global.MetricTypeEnum.CounterType] = Counter,
    [APM_Global.MetricTypeEnum.GaugeType] = Gauge,
    [APM_Global.MetricTypeEnum.AggregateType] = Aggregate
}

function M.create_metric(metric_name, metric_type, clearable)
    return MetricType[metric_type].new(metric_name, clearable)
end

-- 生成Counter类型指标
function M.new_counter(metric_name, clearable, verbose)
    return Counter.new(metric_name, clearable, verbose)
end

function M.new_counter_group(metric_name)
    return CounterGroup.new(metric_name)
end

-- 生成Gauge类型指标，调用set()方法对该指标赋值
function M.new_gauge(metric_name, verbose)
    return Gauge.new(metric_name, verbose)
end

-- 生成带计算方法的Gauge指标，采集时刻将自动调用计算方法获取指标值
function M.new_gauge_with_func(metric_name, verbose, func, ...)
    local gauge = Gauge.new(metric_name, verbose)
    gauge:set_calc_func(func, ...)
    return gauge
end

function M.new_gauge_group(metric_name)
    return GaugeGroup.new(metric_name)
end

-- 生成Aggregate类型指标，通过update()方法更新count/sum/min/max统计值
function M.new_aggregate(metric_name, verbose)
    return Aggregate.new(metric_name, verbose)
end

function M.new_aggregate_group(metric_name)
    return AggregateGroup.new(metric_name)
end

function M.get_series_count()
    return Utils.table_size(metrics_full_list)
end

return M
