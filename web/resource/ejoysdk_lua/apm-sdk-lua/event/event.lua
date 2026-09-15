-------------------------------------------------------------------------------
-- 【 Event类型的埋点数据 】
-- Event包含指标和日志文本。与Stats不同的是，由代码显式调用触发。
-- 用于收集某事件发生时的状态信息。
--
-- Created Date: 2021.07.08
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local Ratelimit = require "ejoysdk_lua.apm-sdk-lua.common.ratelimit"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local Store = require "ejoysdk_lua.apm-sdk-lua.store.store"
local ErrUtils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"

local CFG_MAX_LENGTH = "max_length"
local CFG_RATE = "rate_limit"
local CFG_BURST = "burst"

local LOGGER = "apm_event"

local M = {
    enabled = true,
    max_length = 1000000,
    burst = 100,
    rate_limit = 10
}

local function assert_greater_than(value, key, boundary)
    if type(value) == "number" and type(boundary) == "number" and value > boundary then
        E.LOG.debug(LOGGER, string.format("event.%s is changed to %.2f", key, value))
        return true
    end
    E.LOG.debug(LOGGER, string.format("invalid %s ,type:%s,value:%s", key, type(value), tostring(value)))
    return false
end

local key_changes_handlers = {
    [Cfg.KEY_ENABLED] = function(value)
        M.enabled = value
        E.LOG.debug(LOGGER, "event is " .. (value and "enabled" or "disabled"))
    end,
    [CFG_MAX_LENGTH] = function(value)
        if assert_greater_than(value, CFG_MAX_LENGTH, 0) then
            M.max_length = value
        end
    end,
    [CFG_RATE] = function(value)
        if type(value) == "number" then
            M.rate_limit = value
            if M.ratelimiter then
                M.ratelimiter:set_rate(value)
            end
        end
    end,
    [CFG_BURST] = function(value)
        if assert_greater_than(value, CFG_BURST, 0) then
            M.burst = value
            if M.ratelimiter then
                M.ratelimiter:set_burst(value)
            end
        end
    end
}

local function handle_config_update(key, value)
    local handler = key_changes_handlers[key]
    if handler ~= nil then
        handler(value)
    else
        E.LOG.debug(LOGGER, "event " .. key .. " changes to " .. value .. " but ignored. ")
    end
end

function M.init()
    M.enabled = Cfg.get(Cfg.CATEGORY_EVENT, Cfg.KEY_ENABLED, true)
    M.max_length = Cfg.get(Cfg.CATEGORY_EVENT, CFG_MAX_LENGTH, 1000000)
    M.rate_limit = Cfg.get(Cfg.CATEGORY_EVENT, CFG_RATE, 10)
    M.burst = Cfg.get(Cfg.CATEGORY_EVENT, CFG_BURST, 100)
    Cfg.set_update_callback(Cfg.CATEGORY_EVENT, handle_config_update)
    local err
    M.ratelimiter, err = Ratelimit.new_limiter(M.rate_limit, M.burst, "event")
    if err ~= nil then
        E.LOG.error(LOGGER, "new limiter err:" .. err)
    else
        E.LOG.debug(LOGGER, "new limiter succ")
    end
end

local function add_namespace(stats)
    if stats == nil then
        return stats
    end
    local result = {}
    for k, v in pairs(stats) do
        result["ev_" .. k] = v
    end
    return result
end


-- 过滤掉非法labels
local has_printed_clean_labels_err = {}
local function clean_labels(labels)
    if type(labels) ~= "table" then
        return
    end
    for k, _ in pairs(labels) do
        if type(k) ~= "string" then
            if not has_printed_clean_labels_err[k] then
                E.LOG.error(LOGGER, string.format("value of [key:%s] expects string type,but got %s", k, type(k)))
                has_printed_clean_labels_err[k] = true
            end
            labels[k] = nil
        end
    end
    return labels
end

-- 过滤掉stats的value类型校验
local has_printed_clean_stats_err = {}
local function clean_stats(stats)
    if type(stats) ~= "table" then
        return
    end
    for k, v in pairs(stats) do
        if type(v) ~= "number" then
            if not has_printed_clean_stats_err[k] then
                E.LOG.error(LOGGER, string.format("value of [key:%s] expects number type,but got %s", k, type(v)))
                has_printed_clean_stats_err[k] = true
            end
            stats[k] = nil
        end
    end
    return stats
end

local is_first_time_call_post = true
local function print_post_err_info(msg)
    if is_first_time_call_post then
        E.LOG.warn(LOGGER, msg)
        is_first_time_call_post = false
    end
end

-- 生成一条Event，Event中包含事件名、日志信息、指标数据等
-- 专For不限流场景 触发频率由游戏控制
-- 参数：
--    eventname: 事件名，可用于对Event进行分类
--    labels: table形式的维度key/value组合。默认为空
--    trace_id: 调用链ID，用于将日志与调用链做关联
--    msg: 日志文本
--    stats: table形式的一组指标值
function M.post_with_high_priority(event_name, labels, msg, stats)
    if not M.enabled then
        print_post_err_info("event post is not enabled")
        return
    end
    -- apus sdk 未初始化完 不接收事件处理
    if not Global.is_apus_sdk_initialized() then
        print_post_err_info("apus sdk has not initialized")
        return
    end

    is_first_time_call_post = false

    -- 日志截短
    E.LOG.debug("apm_event", "#msg:" .. #msg)
    if msg ~= nil and #msg > M.max_length then
        msg = string.sub(msg, 1, M.max_length)
    end

    stats = clean_stats(stats)
    labels = clean_labels(labels)

    local event = {
        event_name = event_name,
        labels = labels,
        msg = msg,
        stats = add_namespace(stats)
    }
    Store.submit_event(event)
end

-- 生成一条Event，Event中包含事件名、日志信息、指标数据等
-- 参数：
--    eventname: 事件名，可用于对Event进行分类
--    labels: table形式的维度key/value组合。默认为空
--    trace_id: 调用链ID，用于将日志与调用链做关联
--    msg: 日志文本
--    stats: table形式的一组指标值
local function post(event_name, labels, trace_id, msg, stats)
    if not M.enabled then
        print_post_err_info("event post is not enabled")
        return
    end
    -- apus sdk 未初始化完 不接收事件处理
    if not Global.is_apus_sdk_initialized() then
        print_post_err_info("apus sdk has not initialized")
        return
    end

    is_first_time_call_post = false

    -- 限流
    if M.rate_limit > 0 and M.ratelimiter ~= nil then
        if not M.ratelimiter:allow() then
            E.LOG.debug(LOGGER, "event post is rejected by ratelimiter")
            return
        end
    end

    -- 日志截短
    if msg ~= nil and #msg > M.max_length then
        msg = string.sub(msg, 1, M.max_length)
    end

    stats = clean_stats(stats)
    labels = clean_labels(labels)

    local event = {
        event_name = event_name,
        labels = labels,
        trace_id = trace_id,
        msg = msg,
        stats = add_namespace(stats)
    }
    Store.submit_event(event)
end

local EventPoster = {}
EventPoster.__index = EventPoster

-- 新建EventPoster，指定事件名和指标计算方法
-- 参数：
--    eventname: 事件名，可用于对Event进行分类
--    stats_func: 计算并以table形式返回指标值的方法
--    ... : 调用stats_func的参数
function M.new_poster(event_name, stats_func, ...)
    local obj = {
        event_name = event_name,
        func = stats_func,
        args = {...}
    }
    return setmetatable(obj, EventPoster)
end

-- 生成Event，可指定msg内容或留空
function EventPoster:post(labels, trace_id, msg)
    local stats = Utils.exec(self.func, self.args)
    if stats ~= nil then
        M.post(self.event_name, labels, trace_id, msg, stats)
    end
end

-- just for ut
M.clean_stats = clean_stats

M.post = function(event_name, labels, trace_id, msg, stats)
    local post_fn = function()
        return post(event_name, labels, trace_id, msg, stats)
    end
    xpcall(post_fn, ErrUtils.handle_err)
end

return M
