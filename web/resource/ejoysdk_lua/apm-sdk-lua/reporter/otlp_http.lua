-------------------------------------------------------------------------------
-- OTLP(OpenTelemetry Protocol Specification)支持两种数据传输方式：gRPC和HTTP。
--   https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/otlp.md
-- 此模块为HTTP传输、JSON序列化的实现。
--
-- Created Date: 2021.08.23
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------
-- luacheck: no max comment line length

local E = require "ejoysdk_lua.ejoysdk"
local JSON = require "ejoysdk_lua.apm-sdk-lua.common.json_utils"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local E_UTILS = require "ejoysdk_lua.ejoysdk_utils"
local Labeler = require "ejoysdk_lua.apm-sdk-lua.label.labeler"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"

local M = {}

local data_type_map = {
    boolean = "boolValue",
    number = "doubleValue",
    string = "stringValue",
    table = "kvlistValue"
}

local LOGGER = "apm_otlp_http"

-- 缓存静态指标的对象和json值
local resource_cache = {
    [Global.DataCgrEnum.APM_STATS] = {},
    [Global.DataCgrEnum.API_STATS] = {},
    [Global.DataCgrEnum.RPC_STATS] = {},
    [Global.DataCgrEnum.APM_EVENT_STATS] = {},
    [Global.DataCgrEnum.APM_EVENT_LOG] = {},
    [Global.DataCgrEnum.APM_LOG] = {},
    [Global.DataCgrEnum.APM_SPAN] = {}
}

-- 允许的最大递归深度
local MAX_LUA_STACK = 10

local log_output_format =
    [[{"resourceLogs":[{"resource":{"attributes":%s},"instrumentationLibraryLogs":[{"logs":%s,"instrumentationLibrary":{}}]}]}]] -- luacheck: ignore
local span_output_format =
    [[{"resourceSpans":[{"resource":{"attributes":%s},"instrumentationLibrarySpans":[{"spans":%s}]}]}]]

-- 将table转为OpenTelemetry KeyValueList的格式
--   https://github.com/open-telemetry/opentelemetry-collector/blob/b336d3df8b9d483c1e07e4bc216d788289da7e9d/model/internal/data/protogen/common/v1/common.pb.go#L236
local function convert_kv_list(data, recursively_call_time, key)
    recursively_call_time = recursively_call_time or 0
    if data == nil then
        return nil
    end
    if recursively_call_time >= MAX_LUA_STACK then
        E.LOG.error(LOGGER, "recursively_call_time exceeds MAX_LUA_STACK:" .. MAX_LUA_STACK .. " key:" .. tostring(key))
        return nil
    end

    local kvlist = {}
    for k, v in pairs(data) do
        local t = type(v)
        if t == "table" then
            if #v == 0 then
                recursively_call_time = recursively_call_time + 1
                v = {values = convert_kv_list(v, recursively_call_time, k)}
            else
                -- 不应该有列表
                v = nil
            end
        end
        if v ~= nil and data_type_map[t] ~= nil then
            table.insert(kvlist, {key = k, value = {[data_type_map[t]] = v}})
        end
    end

    if #kvlist == 0 then
        -- lua的空table {}在json序列化时无法转为空数组[]，会引起上报接口报错。直接删掉即可
        return nil
    end
    return kvlist
end

local nano_time_counter = 0
-- timeUnixNano 总共19位 前10位将被SLS存储为"__time__"字段，后六位用于保证同一毫秒内的采集记录的有序性
local function cvt_to_time_unix_nano(timeMill)
    nano_time_counter = nano_time_counter + 1
    if nano_time_counter >= 1e7 then
        nano_time_counter = 1
    end
    return string.format("%d%06d", timeMill, nano_time_counter)
end

local function add_service_name(resource)
    -- 客户端tracer的service名称hardcode
    local key = "service.name"
    local value = "ejoysdk"
    if resource ~= nil then
        if resource[key] == nil then
            resource[key] = value
        end
    else
        resource = {[key] = value}
    end
    return resource
end

-- 获取静态指标的json值，避免每次都json序列化，设计缓存
-- 耗时统计说明 大对象序列化(0.4) > 2小对象序列化(0.35) > 缓存+1小对象序列化(0.15)
local function get_static_resource_json(resource, rtype, is_span)
    local cache = resource_cache[rtype]
    if cache.obj == nil or not Utils:is_table_equals(cache.obj, resource) then
        E.LOG.debug(LOGGER, "cache updated......rtype:" .. tostring(rtype))
        cache.obj = E_UTILS.deepcopy(resource)
        if is_span then
            local tmp_obj = E_UTILS.deepcopy(resource)
            tmp_obj = add_service_name(tmp_obj)
            cache.json = JSON.encode(convert_kv_list(tmp_obj))
        else
            cache.json = JSON.encode(convert_kv_list(cache.obj))
        end

        return cache.json
    end

    E.LOG.debug(LOGGER, "use cache......" .. ",rtype:" .. rtype)
    return cache.json
end

-- 按照OpenTelemetry Protocol的json encoding方式组装Log类型数据，见
--   https://github.com/open-telemetry/opentelemetry-collector/blob/main/model/internal/data/protogen/logs/v1/logs.pb.go
--   https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/logs/data-model.md
function M.build_otlp_logs_v2(resource, data)
    local logs = {}
    local rtype = ""
    for i, record in ipairs(data) do
        if i == 1 then
            rtype = record.type
        end
        table.insert(
            logs,
            {
                name = record.type,
                timeUnixNano = cvt_to_time_unix_nano(record.timestamp),
                attributes = convert_kv_list(record.attributes),
                body = {kvlistValue = {values = convert_kv_list(record.body)}}
            }
        )
    end
    local minimised_resource = resource
    if rtype == Global.DataCgrEnum.APM_LOG then
        minimised_resource = Labeler.minimise_resource(resource)
    end

    return string.format(
        log_output_format,
        get_static_resource_json(minimised_resource, rtype, false),
        JSON.encode(logs)
    )
end

-- 按照OpenTelemetry Protocol的json encoding方式组装Trace类型数据，见
--   https://github.com/open-telemetry/opentelemetry-collector/blob/main/model/internal/data/protogen/trace/v1/trace.pb.go
function M.build_otlp_spans_v2(resource, data)
    local spans = {}
    local rtype = Global.DataCgrEnum.APM_SPAN
    for _, record in ipairs(data) do
        if record.attributes ~= nil then
            record.attributes = convert_kv_list(record.attributes)
        end
        table.insert(spans, record)
    end

    return string.format(span_output_format, get_static_resource_json(resource, rtype, true), JSON.encode(spans))
end

-- just for ut
M.convert_kv_list = convert_kv_list

return M
