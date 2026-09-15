-------------------------------------------------------------------------------
-- Created Date: 2021.08.23
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"

local M = {}

local gen_engine_data_func = nil
--  设置获取引擎性能数据的方法  这个方法目前只会被m2项目直接调用
function M.set_gen_engine_data_func(func)
    gen_engine_data_func = func
    Global.set_is_old_unity_project(true)
end

function M.get_engine_stats()
    if not gen_engine_data_func then
        return nil
    end
    local data = Utils.exec(gen_engine_data_func)
    if not data then
        return nil
    end
    local stats = {}

    -- unity性能数据文档见https://yuque.antfin-inc.com/alitech/ty2dva/axga9g
    stats.fps = data.fps
    stats.draw_call = data.drawCalls
    stats.tri_count = data.triangles
    stats.unity_vertices = data.vertices
    stats.unity_batches = data.batches
    stats.unity_setpasscalls = data.setPassCalls
    stats.unity_rendertime = data.renderTime
    stats.unity_timecpu = data.timeCPU
    stats.unity_usedmem = data.usedMems
    return stats
end

return M
