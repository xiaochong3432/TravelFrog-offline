-------------------------------------------------------------------------------
-- Ejoy2d引擎的性能指标获取实现

-- Created Date: 2021.08.23
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"

local M = {}
local LOGGER = "apm_eng_ejoy2d"

local has_ejoy2dx_lib, os_utils = pcall(require, "ejoy2dx.os_utils")

local function get_ejoy2d_app_mem()
    if has_ejoy2dx_lib and os_utils and os_utils.get_used_memory then
        return os_utils.get_used_memory()
    end
    return nil
end

function M.get_engine_stats()
    -- ej2d是ejoy2d引擎中c语言注入的全局变量，不需要require
    -- luacheck: globals ej2d
    local di = ej2d.get_debug_info()

    if di ~= nil then
        return {
            fps = di.fps,
            draw_call = di.draw_call,
            tri_count = di.tri_count,
            ej2d_node_a_count = di.node_a_count,
            ej2d_node_count = di.node_count,
            ej2d_node_3d_a_count = di.node_3d_a_count,
            ej2d_node_3d_count = di.node_3d_count,
            ej2d_ptc_layer_count = di.ptc_layer_count,
            ej2d_ptc_particle_count = di.ptc_particle_count,
            ej2d_ptc3d_layer_count = di.ptc3d_layer_count,
            ej2d_ptc3d_par_layer_count = di.ptc3d_par_layer_count,
            ej2d_ptc3d_particle_count = di.ptc3d_particle_count,
            ej2d_tex_mem = di.tex_memory_size,
            ej2d_rt_mem = di.rt_memory_size,
            ej2d_vb_mem = di.vb_memory_size,
            ej2d_ib_mem = di.ib_memory_size,
            -- ej2d_lua_mem = di.lua_memory_size,       -- 已放入app_lua_mem
            ej2d_available_vram = di.available_vram_size,
            ej2d_app_mem = get_ejoy2d_app_mem()
        }
    end

    E.LOG.error(LOGGER, "ej2d profiler returns nil.")
    return nil
end

return M
