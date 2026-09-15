-------------------------------------------------------------------------------
-- 收集引擎性能指标数据的stats模块，兼容ejoy2dx和unity引擎
--
-- Created Date: 2021.06.30
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Labeler = require "ejoysdk_lua.apm-sdk-lua.label.labeler"
local Stats = require "ejoysdk_lua.apm-sdk-lua.stats.stats"
local Metrics = require "ejoysdk_lua.apm-sdk-lua.common.metrics"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local MathUtils = require "ejoysdk_lua.apm-sdk-lua.common.math_utils"

local M = {}
local engine = nil
local engine_stats = nil

local JANK_THRESHOLD = 1000.0 / 24 * 2 -- 2个电影帧的时间
local BIG_JANK_THRESHOLD = 1000.0 / 24 * 3 -- 3个电影帧的时间
local dt_queue = {}
local dt_total = 0
local dt_avg = 0

local jank_count = Metrics.new_counter("jank_count")
local big_jank_count = Metrics.new_counter("big_jank_count")
local jank_time = Metrics.new_counter("jank_time")
local delta_time = Metrics.new_aggregate("delta_time")

local fps_variance = MathUtils.new_variance()

local LOGGER = "apm_eng_stats"

-- 运行时引擎 由游戏lua注入
local _engine_type = nil

-- 设置引擎分类
local function set_engine_type(engine_type)
    if #engine_type >= 6 then
        engine_type = string.sub(engine_type, 1, 6)
    end
    _engine_type = engine_type
end

local gen_engine_data_func = nil

-- 设置获取引擎性能数据的方法
local function set_gen_engine_data_func(engine_data_func)
    gen_engine_data_func = engine_data_func
end

-- 设置引擎信息
-- engine_type:引擎类别 unity引擎可以填"unity" unreal引擎可以填"ue" 最多6个字节长
-- engine_data_func:生成引擎性能数据的方法
function M.set_engine(engine_type, engine_data_func)
    if type(engine_type) ~= "string" or not Utils.is_metric_name_valid(engine_type) or engine_data_func == nil then
        return
    end
    set_engine_type(engine_type)
    set_gen_engine_data_func(engine_data_func)
end

local function is_ejoy2d_engine()
    -- luacheck: globals ej2d CS
    -- ejoy2dx引擎
    -- ej2d是ejoy2d引擎中c语言注入的全局变量，不需要require
    return ej2d ~= nil and ej2d.get_debug_info ~= nil
end

local function add_prefix(data)
    if not _engine_type then
        return data
    end
    local stats = {}
    for k, v in pairs(data) do
        -- fps draw_call tri_count是诸多引擎共同的指标 不需要加前缀
        if k == "fps" or k == "draw_call" or k == "tri_count" then
            stats[k] = v
        else
            stats[_engine_type .. "_" .. k] = v
        end
    end
    return stats
end

local function get_original_engine_stats()
    -- ejoy2d 或者旧版的unity项目 用内建的获取引擎数据的方法获取
    if is_ejoy2d_engine() or Global.is_old_unity_project() then
        return engine and engine.get_engine_stats() or {}
    end

    -- 其他引擎 用注册进来的gen_engine_data_func 获取引擎数据
    if not gen_engine_data_func then
        return {}
    end
    local data = Utils.exec(gen_engine_data_func)
    if not data then
        return {}
    end
    return add_prefix(data)
end

local function get_engine_stats()
    local stats = get_original_engine_stats()
    local is_login = Labeler.get_resource("is_login")

    -- 增加一些通用指标，fps、卡顿率等
    if is_login == "1" then
        local dt = delta_time:get()
        if dt.count > 0 then
            stats.max_frame_time = dt.max
            stats.min_frame_time = dt.min
            stats.avg_fps = dt.sum > 0 and 1000.0 * dt.count / dt.sum or 0
            stats.var_fps = fps_variance:get_var()
            stats.jank_count = jank_count:get()
            stats.big_jank_count = big_jank_count:get()
            stats.stutter_percent = dt.sum > 0 and jank_time:get() * 100.0 / dt.sum or 0 -- 卡顿率
        end
    end

    delta_time:clear()
    fps_variance:clear()
    jank_count:clear()
    big_jank_count:clear()
    jank_time:clear()

    return stats
end

function M.init()
    local has_engine = true
    if is_ejoy2d_engine() then
        engine = require "ejoysdk_lua.apm-sdk-lua.stats.engine_stats_ejoy2d"
        Labeler.set_static_label("engine_version", ej2d.ENGINE_VER)
        E.LOG.debug(LOGGER, "engine stats collector is initialized with ejoy2d.")
    elseif _engine_type then
        -- 如果注册过引擎信息
        E.LOG.debug(LOGGER, "engine stats collector is initialized with " .. _engine_type .. ".")
    elseif Global.is_old_unity_project() then
        -- 如果是旧版的unity项目 例如m2
        engine = require "ejoysdk_lua.apm-sdk-lua.stats.engine_stats_unity"
        E.LOG.debug(LOGGER, "engine stats collector is initialized with unity.")
    else
        has_engine = false
        E.LOG.debug(LOGGER, "engine stats collector is initialized with no engine.")
    end
    if has_engine then
        engine_stats = Stats.new("engine-stats", Global.namespace_eng_stats)
        engine_stats:set_calc_func(get_engine_stats)
    end
end

-- 引擎每帧update时调用，用于计算fps、卡顿，及其他每帧性能指标数据
-- 参数为delta_time，单位是秒
function M.update(dt)
    -- 此方法调用频率较高 一个帧调用一次 如果apus sdk未初始化 直接返回
    if not Global.is_apus_sdk_initialized() then
        return
    end

    if type(dt) ~= "number" or dt <= 0 then
        return
    end
    -- 计算卡顿
    M.calc_jank(dt * 1000)
    -- 更新帧率方差
    fps_variance:update(1 / dt)
end

-- 计算卡顿
-- 参考https://bbs.perfdog.qq.com/article-detail.html?id=6
function M.calc_jank(dt)
    -- 只计算登录后的
    local is_login = Labeler.get_resource("is_login")
    if is_login ~= "1" then
        return
    end

    delta_time:update(dt)

    local is_jank = false
    if #dt_queue >= 3 then
        if dt > JANK_THRESHOLD and dt > dt_avg * 2 then
            E.LOG.debug(LOGGER, string.format("jank detected, delta_time=%.2f, avg=%.2f", dt, dt_avg))
            if dt > BIG_JANK_THRESHOLD then
                big_jank_count:inc()
            end

            jank_count:inc()
            jank_time:inc(dt)
            is_jank = true
        end
        -- 计算前三帧平均值
        local last = table.remove(dt_queue, 1)
        table.insert(dt_queue, 3, dt)
        dt_total = dt_total - last + dt
        dt_avg = dt_total / 3.0
    else
        dt_queue[#dt_queue + 1] = dt
        dt_total = dt_total + dt
        dt_avg = dt_total / #dt_queue
    end

    return is_jank
end

-- just for ut
function M.get_engine_stats()
    return get_engine_stats()
end

function M.shutdown()
    if engine_stats ~= nil then
        engine_stats:destroy()
    end
end

return M
