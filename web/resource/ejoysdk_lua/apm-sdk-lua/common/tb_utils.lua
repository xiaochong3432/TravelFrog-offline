-------------------------------------------------------------------------------
-- Created Date: 2023.08.16
-- Author: 三傻
-- Desc:   traceback信息获取
-- Copyright (c) 2023 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"

local LOGGER = "apm_tb_utils"


local M = {}
M.__index = M



local function get_traceback_info()
    -- 打印错误栈比较耗性能，如果关闭此功能，则不打印
    if Global.disable_debug_stack() then
        E.LOG.debug(LOGGER, "disable_debug_stack ...")
        return ""
    end
    local lines = {}
    local stack = debug.traceback()
    for line in stack:gmatch("[^\r\n]+") do
        if line:find("in upvalue ") then
            table.insert(lines, line)
        end
    end
    return table.concat(lines, "\n")
end

M.get_traceback_info = get_traceback_info


return M