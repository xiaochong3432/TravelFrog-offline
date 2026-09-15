--[[ ****************************************************
Copyright (c) 2021 灵犀互娱
-------------------------------
Created Time: 2021/11/19 10:08 上午
File: apus.lua
Author: 三傻
Email: sansha.hw@alibaba-inc.com
Desc:  apus-sdk 对外的访问API
       ##TODO 注意事项: 本模块所有的API以及以后新增的API 都要考虑APUS插件未初始化的情况下调用会不会有问题
-- **************************************************** ]]
local E = require "ejoysdk_lua.ejoysdk"

local Event = require "ejoysdk_lua.apm-sdk-lua.event.event"
local Labeler = require "ejoysdk_lua.apm-sdk-lua.label.labeler"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local JSONUtils = require "ejoysdk_lua.apm-sdk-lua.common.json_utils"
local ErrUtils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"
local ApiStats = require "ejoysdk_lua.apm-sdk-lua.stats.api_stats"
local RpcStats = require "ejoysdk_lua.apm-sdk-lua.stats.rpc_stats"
local Stats = require "ejoysdk_lua.apm-sdk-lua.stats.stats"
local EngineStats = require "ejoysdk_lua.apm-sdk-lua.stats.engine_stats"
local TraceCollector = require "ejoysdk_lua.apm-sdk-lua.trace.collector"
local APM = require "ejoysdk_lua.apm-sdk-lua.apm"
local AbnormalMetricsCb = require "ejoysdk_lua.apm-sdk-lua.stats.abnormal_metrics_callback"
local MemProfiling = require "ejoysdk_lua.apm-sdk-lua.profiling.mem_profiling"
local Flamegraph = require "ejoysdk_lua.apm-sdk-lua.profiling.flamegraph"

local M = {
    -- 设置命名空间 用于区分不同游戏的自定义维度指标名 建议以项目代号指定 如S3,M2,S6等 最大6字节长度
    set_namespace = Labeler.set_namespace,
    -- 设置画质 (0:超高 1:高 2:中 3:低 4:超低)
    set_quality_level = Labeler.set_quality_level,
    -- 设置机型分档信息 (0:超高 1:高 2:中 3:低 4:超低)
    set_device_level = Labeler.set_device_level,
    -- 设置游戏版本
    set_game_version = Labeler.set_game_version,
    -- 设置登录后的回调函数
    set_login_func = Labeler.set_login_func,
    -- 设置登出后的回调函数
    set_logout_func = Labeler.set_logout_func,
    -- 设置自定义的静态标签
    set_static_label = Labeler.set_static_label,
    -- 设置自定义的动态标签，提供获取标签值的方法和参数
    add_dynamic_label = Labeler.add_dynamic_label,
    -- 删除自定义的动态标签
    del_dynamic_label = Labeler.del_dynamic_label,
    -- 设置获取场景的方法
    set_scene_func = Labeler.set_scene_func,
    -- 坐标。提供获取坐标的方法，支持三维，可以只使用二维。
    set_position_func = Labeler.set_position_func,
    -- 上报api调用情况
    count_platform_api_call = ApiStats.count_platform_api_call,
    -- 上报rpc调用情况
    count_game_rpc_call = RpcStats.count_game_rpc_call,
    -- 新建自定义的stats
    new_custom_stats = Stats.new,
    -- 更新引擎的delta_time(帧切换的耗时)
    engine_stats_update_delta_time = EngineStats.update,
    -- 设置引擎信息
    set_engine = EngineStats.set_engine,
    -- 采集trace数据
    trace_collect = TraceCollector.collect,
    -- 发布一条Event
    event_post = Event.post,
    -- 新建EventPoster,用于发布event
    new_event_poster = Event.new_poster,
    -- 注册自定义的apm模块，如增加apm自定义label或自定义指标等
    register_module = APM.register_module,
    -- 设置cjson解析库的链接 需要在apus模块init之前设置
    set_cjson_lib_path = JSONUtils.set_cjson_lib_path,
    -- 注册异常指标阈值以及回调函数
    -- 支持的指标名有: mem,lua_mem,rss_mem,runtime,cpu,cpu_total,以及接入的引擎指标和自定义指标
    register_abnormal_metrics_cb = AbnormalMetricsCb.register_abnormal_metrics_cb,
    -- 采集内存profiling信息 参数为内存对象 格式为table
    -- 此方法的性能损耗与参数table的大小成正相关 对于比较大的内存对象 请勿频繁调用
    collect_mem_profiling = MemProfiling.collect_mem_profiling,
    -- 注册火焰图的相关函数 函数register_flamegraph_fns(flamegraph_fn,remove_file_fn)各个参数解释如下
    -- flamegraph_fn 生成火焰图的函数 function类型 声明:function(task_id, duration, file_name, callback)各个参数解释如下
    --  task_id: 任务ID string 类型
    --  duration 抓取火焰图的持续时间 number类型 单位是秒 有效值范围是 0 ~ 300
    --  file_name 文件名 string 类型
    --  callback 回调函数 function callback(is_succ, file_path, extra_labels)各个参数解释如下
    --     is_succ 生成火焰图是否成功 bool类型
    --     file_path 火焰图文件绝对路径 string类型
    --     extra_labels 额外的标签信息 游戏可以给这个火焰图打一些自定义的标签信息 table类型
    -- remove_file_fn 删除文件的函数 function类型 声明:function(file_full_path)各个参数解释如下
    --   file_full_path 完整文件路径 string 类型
    register_flamegraph_fns = Flamegraph.register_flamegraph_fns
}

M.__index = M

local LOGGER = "apm_interface"

local function event_common_check(cost_ms, msg, custom_labels, custom_stats)
    if type(cost_ms) ~= "number" or cost_ms < 0 then
        E.LOG.warn(LOGGER, "illegal cost_ms:" .. tostring(cost_ms))
        return false
    end
    if msg and type(msg) ~= "string" then
        E.LOG.warn(LOGGER, "illegal msg.type:" .. type(msg))
        return false
    end
    if custom_labels and type(custom_labels) ~= "table" then
        E.LOG.warn(LOGGER, "illegal custom_labels.type:" .. type(custom_labels))
        return false
    end
    if custom_stats and type(custom_stats) ~= "table" then
        E.LOG.warn(LOGGER, "illegal custom_stats.type:" .. type(custom_stats))
        return false
    end
    return true
end

-- record_login_event 记录登录事件
-- 参数说明如下
--     typ 登录类型 可以取(login:正常登录 reconnect:重连)等等，因项目而异 必填
--     ret   登录响应码 可以取(ok:登录成功 fail:登录失败 也可以是数字) 因项目而异 必填
--     cost_ms 登录响应耗时 单位毫秒 必填
--     msg    登录事件消息 日志文本，日志库展示用 选填 默认""
--     custom_labels 自定义的标签 选填
--     custom_stats  自定义的指标 选填
function M.record_login_event(typ, ret, cost_ms, msg, custom_labels, custom_stats)
    if typ == nil or type(typ) == "table" or typ == "" then
        E.LOG.warn(LOGGER, "illegal typ:" .. tostring(typ))
        return
    end
    if ret == nil or type(ret) == "table" or ret == "" then
        E.LOG.warn(LOGGER, "illegal ret:" .. tostring(ret))
        return
    end
    if not event_common_check(cost_ms, msg, custom_labels, custom_stats) then
        return
    end

    local labels = {type = typ, ret = ret}
    labels = Utils.merge_table(labels, custom_labels, true)
    local stats = {cost_ms = cost_ms}
    stats = Utils.merge_table(stats, custom_stats, true)

    Event.post(
        "game_login", -- event name，用于分类
        labels, -- 标签，用于过滤数据
        nil, -- trace id，现在不用填
        msg, -- 日志文本，日志库展示用，随便写
        stats -- 指标，配自定义图表的话必须要至少一个指标，至少可以用来统计登录次数
    )
end

local function is_from_scene_invalid(from_scene)
    return type(from_scene) == "table" or from_scene == ""
end

local function is_to_scene_invalid(to_scene)
    return to_scene and (type(to_scene) == "table" or to_scene == "")
end

-- record_loading_scene_event 记录加载场景事件
--     from_scene 前一个场景ID 必填
--     to_scene   后一个场景ID 如果已经通过apus.set_scene_func()设置了场景读取方法，to_scene填nil即可 否则填真实的场景ID 必填
--     cost_ms 登录响应耗时 单位毫秒 必填
--     msg    登录事件消息 日志文本，日志库展示用 选填 默认""
--     custom_labels 自定义的标签 选填
--     custom_stats  自定义的指标 选填
function M.record_loading_scene_event(from_scene, to_scene, cost_ms, msg, custom_labels, custom_stats)
    if is_from_scene_invalid(from_scene) then
        E.LOG.warn(LOGGER, "illegal from_scene:" .. tostring(from_scene))
        return
    end
    if is_to_scene_invalid(to_scene) then
        E.LOG.warn(LOGGER, "illegal to_scene:" .. tostring(to_scene))
        return
    end
    if not event_common_check(cost_ms, msg, custom_labels, custom_stats) then
        return
    end

    local labels = {from_scene = from_scene}
    if to_scene then
        labels["to_scene"] = to_scene
    end
    labels = Utils.merge_table(labels, custom_labels, true)
    local stats = {cost_ms = cost_ms}
    stats = Utils.merge_table(stats, custom_stats, true)

    Event.post(
        "loading_scene", -- event name，用于分类
        labels, -- 标签，用于过滤数据
        nil, -- trace id，现在不用填
        msg, -- 日志文本，日志库展示用，随便写
        stats -- 指标，配自定义图表的话必须要至少一个指标，至少可以用来统计登录次数
    )
end

-- just for ut, don't use
function M.add(x, y)
    return x + y
end

local mt = {}

local pack_fn = table.pack or function(...)
        return {...}
    end
local unpack_fn = table.unpack or unpack

local is_lua51 = (_VERSION == "Lua 5.1")

local function wrap_xpcall(t, k)
    local v = M[k]
    if type(v) ~= "function" then
        return v
    end
    local f = v
    v = function(...)
        local ok, result = xpcall(f, ErrUtils.handle_err, ...)
        if ok then
            return result
        end
        return
    end
    t[k] = v
    return v
end

local function wrap_xpcall_for_lua51(t, k)
    local v = M[k]
    if type(v) ~= "function" then
        return v
    end
    local f = v
    v = function(...)
        -- xpcall 在lua5.1版本不支持第三个参数 ...
        -- #TODO 所有用到xpcall的地方都需要检查一下是否使用了第三个参数，如是，就需要做lua5.1的兼容
        local args = pack_fn(...)
        local fn = function()
            return f(unpack_fn(args))
        end
        local ok, result = xpcall(fn, ErrUtils.handle_err)
        if ok then
            return result
        end
        return
    end
    t[k] = v
    return v
end

-- 为了不影响游戏主程逻辑，这里所有对外提供的API 都加一层xpcall保护，
-- 如短时间内多次遇到异常，则选择退出apus模块
if is_lua51 then
    mt.__index = wrap_xpcall_for_lua51
else
    mt.__index = wrap_xpcall
end

return setmetatable({}, mt)
