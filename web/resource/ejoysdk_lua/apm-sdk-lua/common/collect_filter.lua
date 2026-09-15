-------------------------------------------------------------------------------
-- Created Date: 2022.01.17
-- Author: 三傻
-- Desc:   采集过滤器 适用于日志和事件
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local E = require "ejoysdk_lua.ejoysdk"

local M = {}
M.__index = M

local function is_in_blacklist(blacklist, event_name)
    if type(blacklist) ~= "table" or type(event_name) ~= "string" then
        return false
    end
    for _, item in ipairs(blacklist) do
        if item == event_name then
            E.LOG.debug("apm_collect_filter", event_name .. " is_in_blacklist,ignored")
            return true
        end
    end
    return false
end

-- 是否是日志的黑名单event_name
function M.is_in_log_blacklist(event_name)
    local blacklist = Cfg.get_log_blacklist()
    return is_in_blacklist(blacklist, event_name)
end

-- 是否是事件的黑名单event_name
function M.is_in_event_blacklist(event_name)
    local blacklist = Cfg.get_event_blacklist()
    return is_in_blacklist(blacklist, event_name)
end

return M
