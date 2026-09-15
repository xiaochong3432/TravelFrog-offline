-------------------------------------------------------------------------------
-- Created Date: 2022.08.02
-- Author: 三傻
-- Desc: 配置模块的公共处理逻辑
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"

local M = {}
M.__index = M

local LOGGER = "apm_config_common"

local is_cat_cfg_valid = function(base_cfg, update_cbs, k, v, cat)
    local old = base_cfg[cat][k]
    if old == nil then
        E.LOG.debug(LOGGER, string.format("%s.%s in new config doesn't exist", cat, k))
        return nil, false
    end

    if v == old then
        E.LOG.debug(LOGGER, string.format("%s.%s keeps unchanged in new config.", cat, k))
        return nil, false
    end

    E.LOG.debug(
        LOGGER,
        string.format("%s.%s has changed in new config. old:%s, new:%s", cat, k, tostring(old), tostring(v))
    )

    local cb = update_cbs[cat]
    if cb == nil then
        E.LOG.debug(LOGGER, cat .. " has not config update callback")
        return nil, false
    end
    return cb, true
end

function M.handle_cat_update(base_cfg, update_cbs, cat, cat_cfg)
    for k, v in pairs(cat_cfg) do
        local cb, ok = is_cat_cfg_valid(base_cfg, update_cbs, k, v, cat)
        if ok then
            Utils.exec(cb, {k, v})
        end
        -- 本地的配置变更不应受到订阅者的影响
        -- update local config
        M.set(base_cfg, cat, k, v)
    end
end

function M.set(base_cfg, category, key, value)
    if key == nil then
        base_cfg[category] = value
    elseif base_cfg[category] == nil then
        base_cfg[category] = {[key] = value}
    else
        base_cfg[category][key] = value
    end
end

function M.get(base_cfg, category, key, default_value)
    local c = base_cfg[category]
    if type(c) ~= "table" then
        return default_value
    end
    if key == nil then
        return c
    elseif c[key] == nil then
        return default_value
    else
        return c[key]
    end
end

return M
