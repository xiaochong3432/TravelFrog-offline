-------------------------------------------------------------------------------
-- APM自身性能监控指标
-- Created Date: 2021.08.09
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local Stats = require "ejoysdk_lua.apm-sdk-lua.stats.stats"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"


local apm_stats = Stats.new("apm_stats", Global.namespace_apm_stats)

return apm_stats