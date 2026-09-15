-------------------------------------------------------------------------------
-- mem_profiling 数据采集模块
-- Created Date: 2022.06.13
-- Author: 三傻
--
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------

local JSON = require "ejoysdk_lua.apm-sdk-lua.common.json_utils"
local Event = require "ejoysdk_lua.apm-sdk-lua.event.event"
local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.init"

local M = {}

M.__index = M

local Node = {
    v = 0,
    n = "",
    c = {}
}

Node.__index = Node

function Node.new(val, name)
    val = type(val) == "number" and val or 0
    local obj = {
        v = val,
        n = name,
        c = {}
    }
    return setmetatable(obj, Node)
end

-- 限制最大递归深度为1000 防止爆栈
local MAX_STACK_DEPTH = 1000

local function cvt2ntree(name, data, stack_depth)
    stack_depth = stack_depth + 1
    local result = Node.new(0, name)
    if stack_depth > MAX_STACK_DEPTH then
        return result
    end
    for k, v in pairs(data) do
        if type(v) == "table" then
            table.insert(result.c, cvt2ntree(k, v, stack_depth))
        else
            table.insert(result.c, Node.new(v, k))
        end
    end
    return result
end

local mem_profiling_event_name = "mem_profiling"
local root_node_name = "root"
-- 采集内存profiling信息 参数为内存对象 格式为table
-- 此方法的性能损耗与参数table的大小成正相关 对于比较大的内存对象 请勿频繁调用
function M.collect_mem_profiling(mem_profiling)
    if type(mem_profiling) ~= "table" then
        return
    end
    local labels = {report_time = Time.now_ms()}

    local start = Time.system_clock()
    local r = cvt2ntree(root_node_name, mem_profiling, 0)
    local event_msg = JSON.encode(r)
    local elapsed = Time.system_clock() - start
    local stats = {cost_ms = elapsed}
    Event.post_with_high_priority(mem_profiling_event_name, labels, event_msg, stats)
end

return M
