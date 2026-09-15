-- Created Date: 2021.08.19
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local ECC = require "ejoysdk_lua.ejoysdk_config_center"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local CfgHelper = require "ejoysdk_lua.apm-sdk-lua.config.helper"

local cfg = {}
local update_callback = {}

local M = {}
M.CATEGORY_STATS = "stats"
M.CATEGORY_EVENT = "event"
M.CATEGORY_LOG = "log"
M.CATEGORY_TRACE = "trace"
M.CATEGORY_REPORT = "report"
M.CATEGORY_GLOBAL = "global"
M.CATEGORY_LABELER = "labeler"

M.KEY_ENABLED = "enabled"

local LOGGER = "apm_config"

-- 异常捕获处理函数
local hanlder_err_fn = function(err)
    E.LOG.debug(LOGGER, err)
end

-- 默认配置项
local default_cfg = {
    -- global apm全局开关
    global = {
        enabled = true
    },
    labeler = {
        http_post_timeout = 10, -- 单位 秒
        normal_refresh_token_interval = 21600, -- 正常情况的刷新token间隔 六个小时
        abnormal_refresh_token_interval = 60 -- 异常情况的刷新token间隔 1 分钟
    },
    stats = {
        enabled = true,
        collect_interval = 60,
        max_series_num = 100,
        modules = {
            apm_stats = {enabled = true},
            app_stats = {enabled = true},
            api_stats = {
                enabled = true,
                api_pattern = {
                    -- 已知的平台服务方会出现的api_pattern
                    {
                        ["ann/v2/detail/%w+"] = "ann/v2/detail/id",
                        ["ann/realm/detail/%w+"] = "ann/realm/detail/id"
                    }
                }
            },
            rpc_stats = {enabled = true},
            engine_stats = {enabled = true}
        },
        -- verbose 控制是否收集高性能损耗的指标 为false的时候不收集 true的时候才收集
        verbose = false
    },
    event = {
        enabled = true,
        rate_limit = 10, -- 限流器的速率
        burst = 100, --限流器的总容量
        max_length = 1000000,
        -- event的event_name如果处于该blacklist数据，则不采集
        blacklist = {}
    },
    log = {
        enabled = true,
        rate_limit = 10, -- 限流器的速率
        burst = 100, --限流器的总容量
        max_length = 1000000,
        level = Global.LogLevelEnum.ERROR,
        -- bucket = "console|file|cloud",
        bucket = "console|cloud",
        bucket_conf = {
            console = {format = "simple_text", color = false},
            cloud = {format = "cloud_text", color = false},
            file = {format = "text", color = true, file_pattern = "game_$Y$m$d_$H$M$S.log"}
        },
        -- 是否通过日志文件上传日志到云端 v1.1.3版本及以上默认开启
        send_log_to_cloud_through_file = true,
        open_log_param = {
            -- 是否写入文件
            is_save = true,
            -- 是否在控制台打印 线上环境默认不开启
            is_console = false,
            -- 日志级别 控制写入文件和在控制台打印日志的级别 支持的配置有 error,warn,info,debug
            level = "error"
        },
        -- log的event_name如果处于该blacklist数据，则不采集
        blacklist = {},
        -- 是否允许最小化日志的标签数量
        enable_minimised_log_labels = false,
        -- label处于whitelist的全量采集
        whitelist_labels = {},
        -- debug stack比较耗性能，这里增加一个开关控制
        disable_debug_stack = false,
        collect_line_info = false -- 默认不采集日志的行信息
    },
    trace = {
        enabled = true,
        rate_limit = 10, -- 限流器的速率
        burst = 100, --限流器的总容量
        default_ratio = 1
    },
    report = {
        enabled = true,
        report_interval = 60,
        ingester_server = {
            formal_domain = "https://apus-ingester.ejoy.com",
            test_domain = "https://apus-ingester-test.ejoy.com",
            is_formal_env = true
        },
        transport = "http",
        skip_auth = false, -- 忽视鉴权 默认不忽视
        -- buff_size 用于数据达到指定的条数时触发上报
        buff_size = {200, 200, 200, 200}
    }
}

function M.init()
    -- 加载sdkconfig_apm.json中的apm配置
    local cfg_from_file = E.CONFIG.get_vendor_config_v2("apm")
    E.LOG.debug(LOGGER, "read config from file:")
    E.LOG.debug(LOGGER, cfg_from_file)
    cfg = Utils.merge_table(default_cfg, cfg_from_file)

    local cfg_from_cc = M.get_from_config_center()
    E.LOG.debug(LOGGER, "retrieve config from config center:")
    E.LOG.debug(LOGGER, cfg_from_cc or {})
    cfg = Utils.merge_table(cfg, cfg_from_cc, true)

    E.LOG.debug(LOGGER, "generated apm config:")
    E.LOG.debug(LOGGER, cfg)

    Global.set_disable_debug_stack(M.disable_debug_stack())

    -- 监听配置中心的配置变化
    local safely_handle_update = function(new_cfg)
        local handle_update = function()
            return M.handle_update(new_cfg)
        end
        xpcall(handle_update, hanlder_err_fn)
    end
    ECC.subscribe(ECC.NAMESPACE.APM, safely_handle_update)
end

-- 为了避免循环引用 由err_utils模块注册异常处理函数进来
function M.set_hanlder_err_fn(hanlder_err_func)
    if type(hanlder_err_func) == "function" then
        hanlder_err_fn = hanlder_err_func
    end
end

function M.get_http_post_timeout()
    return cfg[M.CATEGORY_LABELER]["http_post_timeout"]
end

function M.get_normal_refresh_token_interval()
    return cfg[M.CATEGORY_LABELER]["normal_refresh_token_interval"]
end

function M.get_abnormal_refresh_token_interval()
    return cfg[M.CATEGORY_LABELER]["abnormal_refresh_token_interval"]
end

function M.get_ingester_server()
    local result = cfg[M.CATEGORY_REPORT]["ingester_server"]["formal_domain"]
    local is_formal_env = cfg[M.CATEGORY_REPORT]["ingester_server"]["is_formal_env"]
    if not is_formal_env then
        result = cfg[M.CATEGORY_REPORT]["ingester_server"]["test_domain"]
    end
    return result
end

function M.get_log_blacklist()
    return cfg[M.CATEGORY_LOG]["blacklist"]
end

function M.get_event_blacklist()
    return cfg[M.CATEGORY_EVENT]["blacklist"]
end

function M.get_stats_verbose()
    return cfg[M.CATEGORY_STATS]["verbose"]
end

function M.get_api_pattern()
    return cfg[M.CATEGORY_STATS]["modules"]["api_stats"]["api_pattern"]
end

function M.get_log_bucket()
    return cfg[M.CATEGORY_LOG]["bucket"] or "console"
end

function M.is_log_enabled()
    return cfg[M.CATEGORY_LOG][M.KEY_ENABLED]
end

function M.disable_debug_stack()
    return cfg[M.CATEGORY_LOG]["disable_debug_stack"]
end

function M.should_collect_line_info()
    return cfg[M.CATEGORY_LOG]["collect_line_info"]
end

function M.should_send_log_to_cloud_through_file()
    return cfg[M.CATEGORY_LOG]["send_log_to_cloud_through_file"]
end

function M.get_open_log_param()
    return cfg[M.CATEGORY_LOG]["open_log_param"]
end

function M.enable_minimised_log_labels()
    return cfg[M.CATEGORY_LOG]["enable_minimised_log_labels"]
end

function M.get_log_whitelist_labels()
    return cfg[M.CATEGORY_LOG]["whitelist_labels"]
end

function M.is_formal_env()
    return cfg[M.CATEGORY_REPORT]["ingester_server"]["is_formal_env"]
end

function M.get_log_bucket_conf()
    return cfg[M.CATEGORY_LOG]["bucket_conf"]
end

function M.get_final_conf()
    return cfg
end

function M.set(category, key, value)
    CfgHelper.set(cfg, category, key, value)
end

function M.get(category, key, default_value)
    return CfgHelper.get(cfg, category, key, default_value)
end

-- 设置配置更新的callback函数
-- callback函数的参数为(key, value)
function M.set_update_callback(category, func)
    update_callback[category] = func
end

function M.get_version()
    local meta = E.CONFIG.get_config("unisdk_meta")
    if not meta or not meta.sdks then
        return
    end
    for _, i in ipairs(meta.sdks) do
        if i.name == "apm" then
            return i.version
        end
    end
end

function M.get_from_config_center()
    local data = ECC.get_config(ECC.NAMESPACE.APM)
    if data ~= nil then
        return data.config
    end
end

function M.handle_update(new_cfg)
    E.LOG.debug(LOGGER, "got update from config center:")
    E.LOG.debug(LOGGER, new_cfg)
    if new_cfg.config == nil then
        E.LOG.error(LOGGER, "invalid new config")
        return
    end
    -- 按category遍历比较配置更新
    for cat, cat_cfg in pairs(new_cfg.config) do
        if type(cat_cfg) == "table" and cfg[cat] ~= nil then
            CfgHelper.handle_cat_update(cfg, update_callback, cat, cat_cfg)
        else
            E.LOG.debug(LOGGER, "invalid new config: " .. cat)
        end
    end
end

return M
