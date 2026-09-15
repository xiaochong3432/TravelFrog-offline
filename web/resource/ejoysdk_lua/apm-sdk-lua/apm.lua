-------------------------------------------------------------------------------
-- Created Date: 2021.08.09
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"

local M = {}
M.__index = M
M.modules = {}

M.cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
M.fg_cfg = require "ejoysdk_lua.apm-sdk-lua.config.flamegraph_config"
M.labeler = require "ejoysdk_lua.apm-sdk-lua.label.labeler"
M.reporter = require "ejoysdk_lua.apm-sdk-lua.reporter.reporter"
M.store = require "ejoysdk_lua.apm-sdk-lua.store.store"
M.stats_collector = require "ejoysdk_lua.apm-sdk-lua.stats.collector"
M.trace_collector = require "ejoysdk_lua.apm-sdk-lua.trace.collector"
M.event = require "ejoysdk_lua.apm-sdk-lua.event.event"
M.metrics = require "ejoysdk_lua.apm-sdk-lua.common.metrics"
M.stats = require "ejoysdk_lua.apm-sdk-lua.stats.stats"
M.apm_stats = require "ejoysdk_lua.apm-sdk-lua.stats.apm_stats"
M.json_utils = require "ejoysdk_lua.apm-sdk-lua.common.json_utils"
M.err_utils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"
M.ejoysdk_utils = require "ejoysdk_lua.apm-sdk-lua.common.ejoysdk_utils"
M.log = require "ejoysdk_lua.apm-sdk-lua.log.init"
M.flamegraph = require "ejoysdk_lua.apm-sdk-lua.profiling.flamegraph"

local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local builtin_stats_modules = {
    app_stats = "ejoysdk_lua.apm-sdk-lua.stats.app_stats",
    api_stats = "ejoysdk_lua.apm-sdk-lua.stats.api_stats",
    rpc_stats = "ejoysdk_lua.apm-sdk-lua.stats.rpc_stats",
    engine_stats = "ejoysdk_lua.apm-sdk-lua.stats.engine_stats"
}
local initialized = false
local LOGGER = "apm"

local function get_initial_log_level()
    local default_log_level = M.log.ERROR
    if not M.cfg.is_formal_env() then
        default_log_level = M.log.DEBUG
    end
    return M.cfg.get(M.cfg.CATEGORY_LOG, "level", default_log_level)
end

local function init()
    if initialized then
        return
    end
    initialized = true

    M.cfg.init()
    E.LOG.debug(LOGGER, "begin to open_log_with_config")
    E.open_log_with_config(M.cfg.get_open_log_param())

    local global_enabled = M.cfg.get(M.cfg.CATEGORY_GLOBAL, M.cfg.KEY_ENABLED, true)
    if not global_enabled then
        E.LOG.error(LOGGER, "apm modules is disabled by config center")
        local modules = {
            M.cfg.CATEGORY_STATS,
            M.cfg.CATEGORY_EVENT,
            M.cfg.CATEGORY_LOG,
            M.cfg.CATEGORY_TRACE,
            M.cfg.CATEGORY_REPORT
        }
        for _, v in ipairs(modules) do
            M.cfg.set(v, M.cfg.KEY_ENABLED, false)
        end
        return
    end
    M.fg_cfg.init()
    M.labeler.init()
    M.store.init()
    M.reporter.init()
    M.stats_collector.init()
    M.trace_collector.init()
    M.event.init()
    M.log.init()
    M.log.set_log_level(get_initial_log_level())
    M.flamegraph.init()
    M.json_utils.init()
    M.err_utils.init()

    M.init_modules()

    -- 为metric模块注册一个超过label序列数counter
    M.metrics.register_exceed_max_series_counter(M.apm_stats:new_counter("exceed_max_series_count", true))

    Global.set_apus_sdk_initialized(true)

    -- 上报最终生成的配置文件内容到服务器
    M.store.submit_log(
        {
            message = M.json_utils.encode(M.cfg.get_final_conf()),
            module = "conf" -- 用于筛选这类的日志
        }
    )
end

-- wrap xpcall
function M.init()
    xpcall(init, M.err_utils.handle_err)
end

function M.init_modules()
    -- 初始化自带的stats模块
    local stats_modules_cfg = M.cfg.get(M.cfg.CATEGORY_STATS, "modules")
    for name, path in pairs(builtin_stats_modules) do
        if stats_modules_cfg[name] ~= nil and stats_modules_cfg[name].enabled then
            local module = require(path)
            E.LOG.debug(LOGGER, string.format("initializing built-in stats %s from path %s", name, path))
            module.init()
        else
            E.LOG.debug(LOGGER, name .. " module is disabled.")
        end
    end

    -- 初始化json文件中定义的modules
    local modules = M.cfg.get("modules")
    if modules ~= nil then
        for name, path in pairs(modules) do
            local ok, module = pcall(require, path)
            if ok then
                M.modules[name] = module
                local enabled = stats_modules_cfg[name] and stats_modules_cfg[name].enabled
                if enabled == false then
                    E.LOG.debug(LOGGER, "module " .. name .. " is disabled by config center")
                else
                    E.LOG.debug(LOGGER, "initializing module " .. name)
                    module.init()
                end
            else
                E.LOG.error(
                    LOGGER,
                    string.format("failed to require module %s from %s during initialization.", name, path)
                )
            end
        end
    end
end

function M.shutdown()
    -- M.engine_stats.shutdown()
    M.stats_collector.stop()
    M.reporter.stop()
end

-- 注册自定义的apm模块，如增加apm自定义label或自定义指标等
-- 需包含init()方法
function M.register_module(name, module)
    if M.modules[name] ~= nil then
        E.LOG.warn(LOGGER, "module " .. name .. " has already been registered")
        return
    end

    if module == nil then
        E.LOG.error(LOGGER, "module " .. name .. " is nil")
        return
    end

    if module.init == nil then
        E.LOG.error(LOGGER, "module " .. name .. " doesn't have init()")
        return
    end

    local stats_modules_cfg = M.cfg.get(M.cfg.CATEGORY_STATS, "modules")
    if stats_modules_cfg ~= nil then
        local enabled = stats_modules_cfg[name] and stats_modules_cfg[name].enabled
        if enabled == false then
            E.LOG.debug(LOGGER, "module " .. name .. " is disabled by config center")
            return
        end
    end

    M.modules[name] = module
    E.LOG.debug(LOGGER, "initializing module " .. name)
    module.init()
end

return M
