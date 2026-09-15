-------------------------------------------------------------------------------
-- 异常指标回调处理
--
-- Created Date: 2022.04.28
-- Author: 三傻
--
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"

local M = {}
M.__index = M
local LOGGER = "apm_abnormal_metrics_cb"

local settings_constraint = {
    threshold = {type = "number"},
    op = {type = "number"}
}

local default_handler = function(threshold, value)
    return value >= threshold
end

local op_handlers = {
    [Global.OpEnum.GE] = default_handler,
    [Global.OpEnum.GT] = function(threshold, value)
        return value > threshold
    end,
    [Global.OpEnum.LE] = function(threshold, value)
        return value <= threshold
    end,
    [Global.OpEnum.LT] = function(threshold, value)
        return value < threshold
    end,
    [Global.OpEnum.EQ] = function(threshold, value)
        return value == threshold
    end,
    [Global.OpEnum.NE] = function(threshold, value)
        return value ~= threshold
    end
}

local _abnormal_metrics_settings = {}
local _cb

-- abnormal_metrics_settings 异常指标配置  table类型
--    配置范例: {mem={threshold=100,op=Global.OpEnum.GE},cpu={threshold=0.5,op=Global.OpEnum.GT}}
--cb function 类型 函数申明:
--   function(metric_name,value) -- metric_name:指标名 string ; value: 值 number
function M.register_abnormal_metrics_cb(abnormal_metrics_settings, cb)
    if type(abnormal_metrics_settings) ~= "table" then
        E.LOG.error(
            LOGGER,
            "param abnormal_metrics_settings expects a table, but got " .. type(abnormal_metrics_settings)
        )
        return
    end
    if type(cb) ~= "function" then
        E.LOG.error(LOGGER, "param cb expects a function, but got " .. type(cb))
        return
    end
    for _, settings in pairs(abnormal_metrics_settings) do
        if type(settings) ~= "table" or not next(table) then
            E.LOG.error(LOGGER, "settings expect a table type with at least one element")
            return
        end
        for f, v in pairs(settings) do
            local c = settings_constraint[f]
            if not c then
                E.LOG.error(LOGGER, "settings should not contain field:" .. tostring(f))
                return
            end
            local ct = c.type
            if type(v) ~= ct then
                E.LOG.error(LOGGER, "type mismatch for field: " .. f)
                return
            end
        end
    end
    _abnormal_metrics_settings = abnormal_metrics_settings
    _cb = cb
end

function M.check(metric_name, value)
    local settings = _abnormal_metrics_settings[metric_name]
    if not settings then
        return
    end
    local handler = op_handlers[settings.op] or default_handler
    if handler(settings.threshold, value) then
        Utils.exec(_cb, {metric_name, value})
    end
end

return M
