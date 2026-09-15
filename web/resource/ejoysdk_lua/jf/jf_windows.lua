local E = require 'ejoysdk_lua.ejoysdk'
local JF_WINDOWS_CONFIG = require 'ejoysdk_lua.jf.jf_windows_config'
local PARAMS_MANAGER = require 'ejoysdk_lua.jf.jf_windows_params_manager'
local UPLOAD_UTILS = require 'ejoysdk_lua.jf.base_jf_windows_api'
local EM = require "ejoysdk_lua.ejoysdk_module"
local ET = require "ejoysdk_lua.ejoysdk_topic"

local TAG = EM.MODULE.JF .. 'JF_WINDOWS'

local WINDOWS_EXE_UPDATE_TIME = E.LazyKeyStore:New('WINDOWS_EXE_UPDATE_TIME', false, false, false)

local cache_event = {}
local cache_event_priority_high = {}  -- 存放高优先级的打点，5秒上报时间间隔
local DEFAULT_CACHE_COUNT = 20

local is_start_upload_cache_action = false

-- 关闭投放事件上报，默认为false
local disable_media_event = false

local M = {}

local function support_jf()
    local version = E.Sdkinfo.getSDKVersionName("EJOYSDK")
    local version_check = require "ejoysdk_lua.ejoysdk_version_check"
    -- 2.2.1版本开始支持PC经分打点
    local result = version_check.compare_versions(version,'2.2.1')
    if tonumber(result) >= 0 then
        return true
    end

    return false
end

local set_player_info_handler = function(_player_info)

end

--存储白名单，黑名单等数据
function M.init(params)
    E.LOG.debug(TAG, "jf_windows init")
    E.LOG.debug(TAG, params)
    --配置初始化
    JF_WINDOWS_CONFIG.init(params)
    -- 关闭媒体事件，心跳不打
    if disable_media_event == false then
        M.heartbeat()
    end
    --两分钟清理一次缓存事件
    if not is_start_upload_cache_action then
        is_start_upload_cache_action = true
        M.check_upload_cache_log()
        M.check_upload_cache_log_priority_high()
    end

    ET.subscribe(ET.gangplank.SET_PLAYER_INFO, set_player_info_handler)
end

function M.heartbeat()
    local event_log = {
        event_name = JF_WINDOWS_CONFIG.EVENT_NAMES.SDK_HEARTBEAT
    }
    PARAMS_MANAGER.fill_role_info_params(event_log)
    M.commit_event(event_log)
    -- 2分钟循环一次
    E.Timer.once(60*2, function()
        M.heartbeat()
    end)
end

local function check_install_event(event_params)
    local event_name = event_params.event_name
    if event_name == JF_WINDOWS_CONFIG.EVENT_NAMES.SDK_START_UP_SUCCESS then
        --判断是否首次安装
        local cache_update_time = tostring(WINDOWS_EXE_UPDATE_TIME:get())
        local update_time = tostring(E.Sysinfo.update_time())
        --不相等则需要上报
        if update_time ~= cache_update_time then
            local install_time = tostring(E.Sysinfo.install_time())
            WINDOWS_EXE_UPDATE_TIME:set(update_time)
            local install_event = {}
            install_event.params = {}
            install_event.params.installTime = install_time
            install_event.params.updateTime = tostring(math.floor(E.system_clock()))
            install_event.event_name = JF_WINDOWS_CONFIG.EVENT_NAMES.SDK_INSTALL
            install_event.opts = event_params.opts
            M.commit_event(install_event)
        end
    end
end

local upload_callback = function(succ, ...)
    if succ then
        E.LOG.debug(TAG, 'upload event succ, ')
    else
        local code, msg = ...
        E.LOG.debug(TAG, 'upload event fail, code is ' .. tostring(code) .. ', msg is ' .. tostring(msg))
    end
end

local function upload_cache_event()
    if cache_event and next(cache_event) then
        E.LOG.debug(TAG, 'jf_windows upload cache event')
        UPLOAD_UTILS.upload(cache_event, upload_callback)
    end
    cache_event = {}
end

local function upload_cache_event_priority_high()
    if cache_event_priority_high and next(cache_event_priority_high) then
        E.LOG.debug(TAG, 'jf_windows upload cache event priority high')
        UPLOAD_UTILS.upload(cache_event_priority_high, upload_callback)
    end
    cache_event_priority_high = {}
end

local function check_log_count_upload()
    local log_count = #cache_event
    if log_count >= DEFAULT_CACHE_COUNT then
        upload_cache_event()
    end
end

local function check_log_count_upload_priority_high()
    local log_count = #cache_event_priority_high
    if log_count >= DEFAULT_CACHE_COUNT then
        upload_cache_event_priority_high()
    end
end

--五秒钟检查一次缓存事件(高优先级)的上报
function M.check_upload_cache_log_priority_high()
    E.Timer.once(5, function()
        upload_cache_event_priority_high()
        M.check_upload_cache_log_priority_high()
    end)
end

--两分钟检查一次缓存事件的上报
function M.check_upload_cache_log()
    E.Timer.once(60*2, function()
        upload_cache_event()
        M.check_upload_cache_log()
    end)
end

--提交windows事件上报
function M.commit_event(event_params)
    if not support_jf() then
        E.LOG.debug(TAG, 'jf_windows not support, need to update native sdk version')
        return
    end
    E.LOG.debug(TAG, 'jf_windows commit event ' .. tostring(event_params.event_name))
    if not M.can_commit(event_params.event_name) then
        return
    end
    if not event_params.params then
        event_params.params = {}
    end

    if not event_params.opts then
        event_params.opts = {}
    end

    check_install_event(event_params)

    local commit_action = function(event_log)
        E.LOG.debug(TAG, 'jf_windows cache event ' .. tostring(event_log.event))
        table.insert(cache_event, event_log)
        check_log_count_upload()
    end

    local commit_action_priority_high = function(event_log)
        E.LOG.debug(TAG, 'jf_windows cache event priority high ' .. tostring(event_log.event))
        table.insert(cache_event_priority_high, event_log)
        check_log_count_upload_priority_high()
    end

    local upload_action = function(event_log)
        E.LOG.debug(TAG, 'jf_windows upload event ' .. tostring(event_log.event))
        UPLOAD_UTILS.upload({event_log}, upload_callback)
    end

    --填充参数后上报
    PARAMS_MANAGER.fill_params(event_params, function(event_log)
        local is_upload_now = M.is_upload_now(event_log.event, event_params)
        local is_priority_high = M.is_priority_high(event_params)
        if is_upload_now then
            upload_action(event_log)
        elseif is_priority_high then
            commit_action_priority_high(event_log)
        else
            commit_action(event_log)
        end

    end)
end

--更新参数,jf_api_server,角色信息相关由于不在客户端上报角色相关事件，不再需要更新
function M.update_data(params)
    JF_WINDOWS_CONFIG.update_config(params)
    PARAMS_MANAGER.update_role_info(params)
end

function M.can_commit(event_name)
    local is_black_event = M.is_black_event(event_name)
    if is_black_event then
        E.LOG.debug(TAG, tostring(event_name) .. ' is black event, should not commit')
        return false
    end
    local is_white_event = M.is_white_event(event_name)
    if not is_white_event then
        E.LOG.debug(TAG, tostring(event_name) .. ' is not white event, should not commit')
        return false
    end
    return true
end

function M.is_black_event(event_name)
    local black_event_config = JF_WINDOWS_CONFIG.get_black_event_config()
    if not black_event_config then
        return false
    end

    local black_event_arr = {}
    if black_event_config['type'] == 'event_arr' then
        black_event_arr = black_event_config['data'] or {}
    end

    for _, black_event in pairs(black_event_arr) do
        if event_name == black_event then
            return true
        end
    end
    --windows媒体事件过滤
    if disable_media_event then
        local windows_black_event_arr = JF_WINDOWS_CONFIG.get_media_event_arr()
        for _, black_event in pairs(windows_black_event_arr) do
            if event_name == black_event then
                return true
            end
        end
    end

    return false
end

function M.disable_media_event()
    disable_media_event = true
end

function M.is_white_event(event_name)
    local default_white_event_prefix_arr = JF_WINDOWS_CONFIG.get_default_white_event_prefix_arr()
    local ext_white_event_prefix_arr = JF_WINDOWS_CONFIG.get_ext_white_event_prefix_arr()
    for _, event_prefix in pairs(default_white_event_prefix_arr) do
        if E.Utils.start_with(event_name, event_prefix) then
            return true
        end
    end
    for _, event_prefix in pairs(ext_white_event_prefix_arr) do
        if E.Utils.start_with(event_name, event_prefix) then
            return true
        end
    end
    return false
end

function M.is_upload_now(event_name, event_params)
    -- 默认媒体相关事件，立即上报
    local jf_event_names = JF_WINDOWS_CONFIG.EVENT_NAMES
    for _, media_event_name in pairs(jf_event_names) do
        if event_name == media_event_name then
            E.LOG.debug(TAG, tostring(event_name) .. ' is media event, upload now')
            return true
        end
    end
    --设置了is_upload_now的立即上报
    if event_params and event_params.opts and event_params.opts.is_upload_now then
        return true
    end
    return false
end

function M.is_priority_high(event_params)
    --设置了is_priority_high的高优先级上报(高优先级: 延迟5s上报)
    if event_params and event_params.opts and event_params.opts.is_priority_high then
        return true
    end
    return false
end

return M