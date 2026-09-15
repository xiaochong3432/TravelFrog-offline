-------------------------------------------------------------------------------
-- 收集APP性能指标数据的Collector模块
-- ejoysdk相关接口见：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/dxs7a2
--
-- Created Date: 2021.08.09
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Stats = require "ejoysdk_lua.apm-sdk-lua.stats.stats"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local EjoysdkUtils = require "ejoysdk_lua.apm-sdk-lua.common.ejoysdk_utils"

local cpu = nil
local cpu_total = nil
local memory = nil
local rss_mem = nil

-- 电池温度
local temperature = nil
-- 电压
local voltage = nil

-- 程序运行时间
local run_time = nil

local device_info_filter = {"cpu", "memory"}
local battery_ext_filter = {"temperature", "voltage"}

-- 获取程序运行的时间
local function get_run_time()
    local sysinfo = E.Sysinfo
    -- 非windows系统 直接用同步获取的方式
    if not EjoysdkUtils.is_windows_os() then
        return math.floor(sysinfo.run_time() / 1000) -- app运行时间，单位为秒
    end

    -- windows系统 使用异步获取的方式
    sysinfo.run_time_async(
        function(ret)
            if ret and ret.succ then
                -- run_time是运行时长，单位毫秒
                run_time = math.floor(ret.run_time / 1000)
            end
        end
    )
    return run_time
end

local function get_app_stats()
    local sysinfo = E.Sysinfo

    -- 这是一个异步调用，执行完时已经完成了stats收集，因此只是记录上次异步执行的结果
    -- 如果要优化，需要Stats提供异步接口，改动稍大
    sysinfo.device_info(
        device_info_filter,
        function(ok, result)
            if ok and type(result) == "table" then
                -- 电量信息需要结合充电状态，没想好怎么使用，暂不上报
                -- battery = result.battery.level
                -- E.LOG.debug("apm_test", result)
                if type(result.cpu) == "table" then
                    cpu = result.cpu.usage_solaris_mode -- 归一的cpu使用率
                    cpu_total = result.cpu.usage -- 多核的总cpu使用率
                end
                -- 某些情况下result.memory 是一个number类型， 做一下保护
                if type(result.memory) ~= "table" then
                    return
                end
                -- android提供进程的PSS（非共享内存+分摊的共享内存），ios目前只能提供系统的内存占用（TODO）
                -- 某些低端机型或低系统版本获取不到 result.memory.appPSS, 或者存在溢出的情况，都需要过滤掉
                if result.memory.appPSS and result.memory.appPSS > 0 then
                    memory = result.memory.appPSS / 1048576 -- 1048576 = 2^20 转 MB
                end

                if result.memory.VmRSS and result.memory.VmRSS > 0 then
                    rss_mem = result.memory.VmRSS / 1048576 -- 1048576 = 2^20 转 MB
                end
            else
                cpu = nil
                cpu_total = nil
                memory = nil
                rss_mem = nil
            end
        end
    )

    -- 异步获取当前电池额外的信息
    sysinfo.battery_ext(
        battery_ext_filter,
        function(ret)
            if not ret then
                return
            end
            if ret.temperature and ret.temperature >= 0 then
                temperature = ret.temperature
            end
            if ret.voltage and ret.voltage >= 0 then
                voltage = ret.voltage
            end
        end
    )

    return {
        cpu = cpu,
        cpu_total = cpu_total,
        mem = memory,
        rss_mem = rss_mem,
        lua_mem = math.floor(collectgarbage("count") / 1024 + 0.5), -- MB
        temperature = temperature,
        voltage = voltage,
        runtime = get_run_time()
    }
end

local M = {}

function M.init()
    local app_stats = Stats.new("app_stats", Global.namespace_app_stats)
    app_stats:set_calc_func(get_app_stats)
end

return M
