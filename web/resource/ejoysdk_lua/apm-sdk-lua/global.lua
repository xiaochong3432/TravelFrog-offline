-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
-- Created Date: 2021.08.18
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local M = {}

M.MetricTypeEnum = {
    -- 类型枚举值
    NoneType = 0,
    CounterType = 1,
    GaugeType = 2,
    AggregateType = 3
}

M.LogLevelEnum = {
    -- 日志级别枚举值
    DEBUG = 5,
    INFO = 4,
    WARNING = 3,
    ERROR = 2,
    CRITICAL = 1
}

M.DataTypeEnum = {
    -- 数据类型枚举值
    STATS_TYPE = 1, --定期采集的性能指标数据
    EVENT_TYPE = 2, --事件触发的指标+日志数据
    LOG_TYPE = 3, --文本形式的日志数据
    TRACE_TYPE = 4, --调用链数据
    FILE_TYPE = 5 --日志文件数据
}

M.DataCgrEnum = {
    -- 上传至SLS的数据分类
    APM_STATS = "apm_stats", --apm+app的指标
    API_STATS = "api_stats", --api调用指标
    RPC_STATS = "rpc_stats", --rpc调用指标
    APM_EVENT_STATS = "apm_event_stats", --事件指标
    APM_EVENT_LOG = "apm_event_log", --事件日志
    APM_LOG = "apm_log", --纯日志
    APM_SPAN = "apm_span" --调用链的span
}

M.OpEnum = {
    -- 操作符枚举值
    GE = 0, --  大于等于
    GT = 1, --  大于
    LE = 2, --  小于等于
    LT = 3, --  大于
    EQ = 4, --  等于
    NE = 5 --  不等于
}

M.HTTPStatusCodeEnum = {
    UNKOWN = -1, --  未知错误
    SUCC = 200, --  成功
    BAD_REQUST = 400, -- 参数错误
    TOO_MANY_REQUEST = 429, -- 太多的请求
    INTERNAL_ERR = 500, -- 内部执行错误
    BAD_GATEWAY = 502, -- 网关收到无效响应
    SERVICE_UNAVAILABLE = 503, -- 服务不可用
    GATEWAY_TIMEOUT = 504 -- 网关超时
}

M.namespace_api_stats = "api"
M.namespace_apm_stats = "apm"
M.namespace_app_stats = "app"
M.namespace_eng_stats = "eng"
M.namespace_rpc_stats = "rpc"

-- 连接kv的字符 在metrics.lua中使用 主要和labels_kvpair_concate_str一起串联labels成sls metric格式的字符串
M.labels_kv_concate_str = "#$#"
-- 连接kv对的字符
M.labels_kvpair_concate_str = "|"

-- 是否是旧版的unity项目 m2 接的apus-v1.0.1 是旧版项目
local _is_old_unity_project = false

function M.set_is_old_unity_project(is_old_unity_project)
    if type(is_old_unity_project) == "boolean" then
        _is_old_unity_project = is_old_unity_project
    end
end

function M.is_old_unity_project()
    return _is_old_unity_project
end

local has_apus_sdk_initialized = false
function M.set_apus_sdk_initialized(apus_sdk_initialized)
    if type(apus_sdk_initialized) == "boolean" then
        has_apus_sdk_initialized = apus_sdk_initialized
    end
end

function M.is_apus_sdk_initialized()
    return has_apus_sdk_initialized
end

local _disable_debug_stack = false
function M.set_disable_debug_stack(disable_debug_stack)
    if type(disable_debug_stack) == "boolean" then
        _disable_debug_stack = disable_debug_stack
    end
end

function M.disable_debug_stack()
    return _disable_debug_stack
end

return M
