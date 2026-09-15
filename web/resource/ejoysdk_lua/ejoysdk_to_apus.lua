-------------------------------------------------------------------------------
-- 对接apus接口
--
-- Created Date: 2022.05.25
-- Author: 四境
--
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------
local E = require "ejoysdk_lua.ejoysdk"
local M = {}

local TAG = "EAPUS"
local APUSEVENT
local _EXISTS_APUS_LUA -- 是否存在apus lua的标志位，不需要每次 pcall require apus的模块
--local has_init_public_params = false
--local ejoysdk_ver = ''
--local lua_ver = ''
--local game_ver =''
--local os_ver =''
--local aligames_ver =''

local function report_apus_event(event_name, _lablels, _trace_id, _msg, _stats)
    if APUSEVENT ~= nil then
        local labels = _lablels or {}
        local trace_id = _trace_id or 0
        local stats = _stats or {}
        local msg = _msg or ''
        APUSEVENT.post(event_name, labels, trace_id, msg, stats)
    end
end

-- 添加lua打点的公参
local function add_public_params(params)
    --if not has_init_public_params then
    --    has_init_public_params = true
    --end

    params.ab_type = E.get_pkg_info().ab_type or ''

    -- 添加网络环境
    params.net_type_name = E.Sysinfo.network_type_name() or ''
end

function M.is_apus_enabled()
    if _EXISTS_APUS_LUA == false then
        return false
    end

    -- 未设置过，需要尝试引入
    if _EXISTS_APUS_LUA == nil then
        local ok, apus_event_module = pcall(require, "ejoysdk_lua.apm-sdk-lua.event.event")
        if ok then
            APUSEVENT = apus_event_module
            _EXISTS_APUS_LUA = true
        else
            _EXISTS_APUS_LUA = false
        end
    end

    return APUSEVENT and E.has_apus_vendor()
end

function M.commit_event(event_name, params)
    if not M.is_apus_enabled() then
        E.LOG.warn(TAG, "commit_event skip, apus not enabled")
        return
    end

    params = params or {}
    add_public_params(params)

    local _trace_id = E.get_pkg_info().sdk_trace_id
    -- 对齐apus协议
    -- 打平labels
    report_apus_event(event_name,
            params,
            _trace_id,
            tostring(params.msg or params.code or params.result or 'empty_msg'),
            {})
end


function M.add_dynamic_label(label, fun)
    if not label or label == "" then
        E.LOG.warn(TAG, "add_dynamic_label skip, label is nil or empty")
        return
    end

    local ok, apus = pcall(require, "ejoysdk_lua.apm-sdk-lua.apus")
    if not ok then
        E.LOG.warn(TAG, "add_dynamic_label skip for apus not exists, label:" .. tostring(label))
        return
    end

    E.LOG.debug(TAG, "add_dynamic_label begin, label:" .. tostring(label))
    apus.add_dynamic_label(label,fun)
end

return M