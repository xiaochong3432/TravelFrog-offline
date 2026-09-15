-------------------------------------------------------------------------------
-- Created Date: 2022.08.02
-- Author: 三傻
-- Desc: 火焰图任务配置
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local ECC = require "ejoysdk_lua.ejoysdk_config_center"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local CfgHelper = require "ejoysdk_lua.apm-sdk-lua.config.helper"
local ErrUtils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"

local M = {
    CATEGORY_FRAMRGRAPH_TASKS = "flamegraph_tasks"
}
M.__index = M

local LOGGER = "apm_flamegraph_config"

local namespace = "apus_flamegraph"

local conf = {
    flamegraph_tasks = {
        -- 配置项-任务的最大生效时间 单位毫秒
        ttl = 300 * 1000,
        -- 最大的火焰图生成时间 单位秒
        max_duration = 300,
        -- 最大的可接收的下发的任务数
        max_concurrent_tasks = 10,
        enabled = true,
        -- 任务列表
        tasks = {},
        -- 可重试次数
        retry_budget = 3,
        -- 可重试的错误码列表
        retry_code_list = {}
    }
}

-- 配置更新的回调函数map
local update_callbacks = {}

local function get_from_config_center()
    local data = ECC.get_config(namespace)
    if data ~= nil then
        return data.config
    end
end

function M.init()
    local cfg_from_cc = get_from_config_center()
    E.LOG.debug(LOGGER, "retrieve config from config center:")
    E.LOG.debug(LOGGER, cfg_from_cc or {})
    conf = Utils.merge_table(conf, cfg_from_cc, true)

    E.LOG.debug(LOGGER, "generated apus_flamegraph config:")
    E.LOG.debug(LOGGER, conf)

    -- 监听配置中心的配置变化
    local safely_handle_update = function(new_cfg)
        local handle_update = function()
            return M.handle_update(new_cfg)
        end
        xpcall(handle_update, ErrUtils.handle_err)
    end
    ECC.subscribe(namespace, safely_handle_update)
end

-- 设置配置更新的callback函数
-- callback函数的参数为(key, value)
function M.set_update_callback(category, func)
    update_callbacks[category] = func
end

function M.get(category, key, default_value)
    return CfgHelper.get(conf, category, key, default_value)
end

function M.handle_update(new_cfg)
    E.LOG.info(LOGGER, "got update from config center:")
    E.LOG.info(LOGGER, new_cfg)
    if new_cfg.config == nil then
        E.LOG.error(LOGGER, "invalid new config")
        return
    end
    -- 按category遍历比较配置更新
    for cat, cat_cfg in pairs(new_cfg.config) do
        if type(cat_cfg) == "table" and conf[cat] ~= nil then
            CfgHelper.handle_cat_update(conf, update_callbacks, cat, cat_cfg)
        else
            E.LOG.debug(LOGGER, "invalid new config: " .. cat)
        end
    end
end

return M
