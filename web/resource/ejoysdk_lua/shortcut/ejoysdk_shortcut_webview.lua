-------------------------------------------------------------------------------
-- 微社区 https://yuque.antfin.com/ejoy-platform/ejoy-platform/qka2fe
--
-- Created Date: 2022.09.20
-- Author: 四境
--
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------

local E = require 'ejoysdk_lua.ejoysdk'
local CC = require 'ejoysdk_lua.ejoysdk_config_center'
local uuid = require "ejoysdk_lua.ejoysdk_uuid"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local M = {}
local TAG = 'base#sc_webview'
-- local DEFAULT_ID = 'default_sc_id'
local Utils = require "ejoysdk_lua.native.utils.Utils"
local WVMI = require 'ejoysdk_lua.webview.multi_instance'
local LAST_WV_STORAGE = E.LazyKeyStore:New("LAST_WV_STORAGE", false, true, false)
local ejoysdk_init = require 'ejoysdk_lua.ejoysdk_init'
local ejoysdk_topic = require 'ejoysdk_lua.ejoysdk_topic'
local EVS = require 'ejoysdk_lua.vendors.shortcut'
local e_utils = require "ejoysdk_lua.ejoysdk_utils"
local Live = require "ejoysdk_lua.webview.live_floater"

M.Type = {
    Community = 'community',
}

M.CONFIG_KEYS = {
    SC_ENV = "sdk_server_env",
    GAME_PRODUCT_ID = "game_product_id",
    DEBUGGABLE = "debuggable",
    Type = 'type'
}

M.DEBUG_OPTIONS = {
    Debug = false
}

M.LIVE_EVENT = Live.LIVE_EVENT

-- ======================== 1.配置相关 ========================
local sc_webview_maps = {}
local callback_maps = {}
local last_from_source_data_map = {}
-- ======================== 2.private ========================
local function get_config_from_cc_h5res(_type)
    local sc_params
    -- 从配置中心判断是否存在type的配置 config
    local cc_config = CC.get_config(CC.NAMESPACE.EJOYSDK_BIZ)
    local sc_configs = cc_config and cc_config.config and cc_config.config.shortcut
    if sc_configs and sc_configs.items then
        for _,v in pairs(sc_configs.items) do
            if v.type == _type then
                sc_params = v
                break
            end
        end
    end
    return sc_params
end

local function get_local_preload_config(_type)
    -- 从配置中心判断是否存在type的配置 config
    local cc_config = CC.get_config(CC.NAMESPACE.EJOYSDK_BIZ)
    local sc_configs = _type and cc_config and cc_config.config and cc_config.config[_type]
    return sc_configs
end

M.get_config_from_cc_h5res = get_config_from_cc_h5res

local subscribed_once = false
local is_opening_before_destroy_live = false

-- 直播cb通知：这里可能触发的原始webview已隐藏/销毁，也需要保留cb通知对应的处理，每个biz_type仅保留一个cb
local webview_live_callbacks = {}

local current_event = Live.LIVE_EVENT.ON_LIVE_DESTROY 
local function on_live_handler(event, disable_live_event)
    if event and not disable_live_event then
        for k, v in pairs(webview_live_callbacks) do
            if type(v) == 'function' then
                local is_open = M.is_opened_biz(k) or is_opening_before_destroy_live
                -- E.LOG.d(TAG, "is_opening_before_destroy_live:" .. tostring(is_opening_before_destroy_live))
                v(event, { biz_type = k, is_open = is_open })
                if event == Live.LIVE_EVENT.ON_LIVE_DESTROY and is_opening_before_destroy_live then
                    is_opening_before_destroy_live = false
                end
            end
        end
    end
    current_event = event
    -- E.LOG.d(TAG, "state:" .. tostring(current_event))
end

local function subscribe_webview_live_floater(biz_type, live_cb)

    if live_cb and type(live_cb) == 'function' then
        webview_live_callbacks[biz_type] = live_cb

        if not subscribed_once then 

            ejoysdk_topic.subscribe(ejoysdk_topic.live_floater.ON_CHANGED, on_live_handler)
            subscribed_once = true
        end
    end
end

local function reset_local_config()
    -- 重置正在关闭的标记
    is_opening_before_destroy_live = false
end

-- ======================== 3.public ========================
function M.register(biz_type, on_callbacks)
    callback_maps[biz_type] = on_callbacks

    local need_prepare_webview = false

    local c_config = get_local_preload_config(biz_type)
    if c_config and type(c_config) == 'table' and c_config.need_prepare_webview ~= nil then
        need_prepare_webview = c_config.need_prepare_webview
    end

    if need_prepare_webview then
        E.WebView.prepare({})
    end
end

function M.add_shortcut_webview(biz_type, cb, option)

    cb = cb or function() end
    option = option or {}
    if not biz_type then
        E.LOG.debug(TAG, 'add_shortcut_webview type is nil')
        cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER,'add_shortcut_webview type is nil')
        return
    end
    -- 从配置中心判断是否存在type的配置 config
    local sc_params = get_config_from_cc_h5res(biz_type)
    if sc_params and sc_params.title and sc_params.url then

        E.LOG.debug(TAG, sc_params)

        -- 根据下发配置生成
        local params = {
            title = sc_params.title,
            url = sc_params.url,
            android_long_title = sc_params.android_long_title, -- Android
            android_icon_name = "shortcut_" .. biz_type .. "_icon", -- Android, 图标的规则是固定的
            id = biz_type, -- 可以不传默认是 biz_type
            ios_icon_url = sc_params.ios_icon_url, -- iOS
            ios_gen_url = sc_params.ios_gen_url, -- iOS
            biz_type = biz_type,
            page_type = EVS.Type.WebView --int
        }
        EVS.add_shortcut(params, cb, option)
    else
        E.LOG.debug(TAG, 'add_shortcut_webview config is not ready or error')
        cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_CONFIG_NOT_READY, 'add_shortcut_webview config is not ready or error')    
    end
end

local function wv_event_callback(biz_type, even_name, is_open)
    local callbacks = callback_maps[biz_type] or {}
    if callbacks.on_js_callback and type(callbacks.on_js_callback) == 'function' then
        -- value.args.type = 
        callbacks.on_js_callback({
            args = {
                type = even_name,
                params = {
                    biz_type = biz_type,
                    is_open = is_open,
                    from = 'lua'
                }
            }
        })
    end
end

function M.open_shortcut_webview(biz_type, _params, _option, _on_callbacks)

    --E.LOG.d(TAG, 'open_shortcut_webview >>')
    --E.LOG.d(TAG, 'biz_type=' .. tostring(biz_type))
    --E.LOG.d(TAG, '_params >>')
    --E.LOG.d(TAG, _params)
    --E.LOG.d(TAG, '_option >>')
    --E.LOG.d(TAG, _option)

    if not biz_type then
        E.LOG.debug(TAG, 'open_shortcut_webview biz_type is nil')
        return
    end
    _params = _params or {}
    local from_source_data = _params.from_source_data
    -- 赋值
    last_from_source_data_map[biz_type] = from_source_data or {}

    -- 从直播小窗来的需要先关闭直播
    if (from_source_data and from_source_data.open_type == "live_floater") or (current_event ~= Live.LIVE_EVENT.ON_LIVE_DESTROY) then
        E.LOG.debug(TAG, 'need destroy live first, state:' .. tostring(current_event))
        is_opening_before_destroy_live = true
        Live.destroy()
    end

    local hide_event_hander
    hide_event_hander = function (_value)
        -- E.LOG.debug(TAG, "webview_hide ==>")
        -- E.LOG.debug(TAG, _value)
        -- FIXME 目前仅处理返回键的逻辑，其他前端回调了
        if _value and _value.hideArgs == 'backkey' then
            wv_event_callback(biz_type, biz_type .. '_hide', false)
        end
        ejoysdk_topic.unsubscribe('webview_hide', hide_event_hander)
    end
    ejoysdk_topic.subscribe('webview_hide', hide_event_hander)

    if sc_webview_maps[biz_type] ~= nil then
        M.show_shortcut_webview(biz_type, from_source_data)
        -- 补一个show的callback，从通知或桌面图标过来的
        wv_event_callback(biz_type, biz_type .. '_show', true)
        return
    end
    
    local local_params = _params.local_params
    local sc_params = get_config_from_cc_h5res(biz_type)

    local url
    if sc_params and sc_params.url then
        -- 使用默认配置打开
        url = sc_params.url
    elseif local_params and local_params.url then 
        -- 使用缓存配置打开
        E.LOG.debug(TAG, 'open_shortcut_webview config is not ready or error, use local config')
        url = local_params.url
    end

    -- 使用default_url兜底
    if not url and _params and _params.default_url then
        url = _params.default_url
    end
    
    -- url = 'https://community-pre.hepinggames.com/119_test'

    if url then
        local prepare_data = {}
        if local_params then
            prepare_data = LAST_WV_STORAGE:get() or {}
            if not prepare_data.startupData then
                prepare_data.startupData = {}
            end
            prepare_data.startupData.from_source = local_params.from_source
        else
            prepare_data.startupData = {}
            prepare_data.startupData.from_source = biz_type
        end

        if from_source_data then
            prepare_data.startupData.from_source_data = from_source_data
        end
        
        local callbacks = callback_maps[biz_type] or {}
        
        -- 优先以后传入的入参为准
        if _on_callbacks then
            callbacks = _on_callbacks
        end

        local ori_close_callback = callbacks.on_close_callback
        local on_close_callback
        on_close_callback = function (_value)
            if ori_close_callback then
                ori_close_callback(_value)
            end
            sc_webview_maps[biz_type] = nil
        end

        callbacks.on_close_callback = on_close_callback

        if callbacks.on_live_callback then
            subscribe_webview_live_floater(biz_type, callbacks.on_live_callback)
        end

        local injection = {}
        if url and type(url) == "string" then
            local host_object = E.HTTP.parse(url)
            if host_object and host_object.host then
                local end_host = string.match(host_object.host, "^[%w%-]+(.*)")
                end_host = end_host or host_object.host
                E.LOG.debug(TAG,"inject host:" .. tostring(end_host))
                injection[end_host] = {
                    startupData = prepare_data.startupData or {}
                }
            end
        end

        -- EW.fill_injection_with_common_params(injection, {})
        
        local webview_id = biz_type or uuid()
        local params = {
            webview_id = webview_id,
            injection = injection,
            from_source = 'shortcut'
        }

        if not _option then 
            _option = {}
            _option.screen_orientation = "portrait"
            _option.use_fragment = false
        end

        -- android option
        _option.enable_auto_media_playback = true
        _option.disable_auto_fontsize = true

        if(_ejoysdk.os() == 'windows') then
            _option.draggable = true
            _option.show_title = true
            _option.nonmodal_window = true
        end

        if local_params and local_params.from_source == 'shortcut' then
            -- 快捷方式单独打开默认是关闭
            _option.backkey_action = 'exit'
            _option.hide_close_btn = true
            -- 支持控制快捷方式的快速打开开关
            if not M.disable_fast_open and _ejoysdk.os() == 'android' then
                if sc_params and sc_params.use_fragment then
                    _option.use_fragment = true
                end
                _option.enable_loading = false
            end

            -- 针对快捷方式也增加下发的控制，避免和端内互相影响，key值为 shortcut_ext_options
            if sc_params and sc_params.shortcut_ext_options and type(sc_params.shortcut_ext_options) == 'table' then
                for ext_k, ext_v in pairs(sc_params.shortcut_ext_options) do
                    if type(ext_k) == 'string' then
                        _option[ext_k] = ext_v
                    end
                end
            end

        elseif biz_type == M.Type.Community then
            -- 游戏内打开微社区默认返回是隐藏
            _option.backkey_action = 'hide'

            if sc_params and sc_params.ext_options and type(sc_params.ext_options) == 'table' then
                for ext_k, ext_v in pairs(sc_params.ext_options) do
                    if type(ext_k) == 'string' then
                        _option[ext_k] = ext_v
                    end
                end
            end
        end
        
        local sc_webview = WVMI:New(url, params, _option, callbacks)
        sc_webview_maps[biz_type] = sc_webview

        sc_webview:open()
        
        wv_event_callback(biz_type, biz_type .. '_show', true)

    else
        E.LOG.debug(TAG, 'open failed, config url is not ready')
        if local_params and local_params.from_source == 'shortcut' then
            M.start_game()
        end
    end
end

function M.open_from_webview(biz_type, params, _option, cb)

    if params and type(params) ~= 'table' then
        E.LOG.debug(TAG, 'invalid params')
        if cb then cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_INVALID_PARAMETER, 'invalid params') end
        return
    end

    -- 当前是在社区内的模块可以直接忽略
    if M.is_opened_biz(biz_type) then
        E.LOG.debug(TAG, 'already open ' .. tostring(biz_type))
        if cb then cb(false, CONSTANTS.BASE_API_COMMON_ERROR.CODE_CONFIG_CAN_IGNORE, 'already open ' .. tostring(biz_type)) end
        return
    end

    -- 当前是否开启了webview队列，需要先清理并关闭
    if E.WebView.is_opened() then
        local EWB = require 'ejoysdk_lua.ejoysdk_webview_manager'
        EWB.hide_all_web()
        -- 打开biz_type的webview
        E.Timer.once(1, function()
            M.open_shortcut_webview(biz_type, params, _option)
            if cb then cb(true) end
        end)
    else
        M.open_shortcut_webview(biz_type, params, _option)
        if cb then cb(true) end
    end
end

function M.start_game()
    local SCV = require "ejoysdk_lua.vendors.shortcut"
    SCV.start_game_activity()
end

function M.show_shortcut_webview(biz_type, _params)
    local sc_webview = sc_webview_maps[biz_type]
    if sc_webview then
        sc_webview:show(_params)
    else
        -- 如果没有则转发给当前webview处理
        _params = _params or {}
        if not E.WebView.is_opened() then
            E.WebView.show(_params)
        end
    end
end

function M.hide_shortcut_webview(biz_type)
    local sc_webview = sc_webview_maps[biz_type]
    if sc_webview then
        sc_webview:hide()
    else
        -- 如果没有则转发给当前webview处理
        E.WebView.hide({ webview_id = biz_type })
    end

    -- 重置变量
    reset_local_config()
end

function M.close_shortcut_webview(biz_type)
    local sc_webview = sc_webview_maps[biz_type]
    if sc_webview then
        sc_webview:close()
        sc_webview_maps[biz_type] = nil
    else
        -- 如果没有则转发给当前webview处理，因为前端页可能其他地方打开了webview
        E.WebView.close()
    end

    reset_local_config()
end

function M.reload(biz_type)
    local sc_webview = sc_webview_maps[biz_type]
    if sc_webview then
        sc_webview:reload()
    else
        -- 如果没有则转发给当前webview处理，因为前端页可能其他地方打开了webview
        E.WebView.reload()
    end
end

function M.remove_hide_cache(biz_type)
    local sc_webview = sc_webview_maps[biz_type]
    if sc_webview then
        sc_webview:remove_hide_cache()
        sc_webview_maps[biz_type] = nil
    else
        -- 如果没有则转发给当前webview处理，因为前端页可能其他地方打开了webview
        E.WebView.remove_hide_cache({})
    end
end

function M.get_webview(biz_type)
    return sc_webview_maps[biz_type]
end

function M.call_js(biz_type, js_script, is_fallback)
    local sc_webview = sc_webview_maps[biz_type]
    if sc_webview then
        sc_webview:call_js(js_script)
    elseif is_fallback then
        E.WebView.call_js(js_script)
    end
end

function M.is_opened_biz(biz_type)
    local sc_webview = sc_webview_maps[biz_type]
    if sc_webview then
        return sc_webview:is_opened()
    end
    return false
end

function M.is_support_shortcut(biz_type)
     --支持配置中心关闭指定业务的快捷方式添加入口
    local sc_params = get_config_from_cc_h5res(biz_type)
    if sc_params and sc_params.disable_shortcut then
        return false
    end

    return EVS.is_support_shortcut()
end

function M.get_from_source_data(biz_type)
    local last_from_source_data = last_from_source_data_map[biz_type] or {}
    return e_utils.deepcopy(last_from_source_data)
end

function M.get_preload_config(biz_type)
    local pre_config = get_local_preload_config(biz_type)
    -- E.LOG.debug(TAG, pre_config)
    return pre_config
end

function M.set_from_source_data(biz_type, from_source_data)
    last_from_source_data_map[biz_type] = e_utils.deepcopy(from_source_data)
end

function M.save_shortcut_webview_data()
    local EW = require 'ejoysdk_lua.ejoysdk_web'
    local injections = {}
    EW.fill_injection_with_common_params(injections, {})
    local local_startup_data 
    for _host, sub_injection in pairs(injections) do
        if sub_injection.startupData then
            -- 取其中一个startupData存储即可
            local_startup_data = sub_injection.startupData
            break
        end
    end
    if local_startup_data and local_startup_data.tokens then
        local_startup_data.last_tokens = local_startup_data.tokens
    end
    local params = {
        startupData = local_startup_data
    }
    LAST_WV_STORAGE:set(params)
end

function M.clear_shortcut_webview_data()
    LAST_WV_STORAGE:delete()

    -- 如果在打开状态下需要先关掉
    if M.is_opened_biz(M.Type.Community) then
        local sc_webview = sc_webview_maps[M.Type.Community]
        if sc_webview then
            sc_webview:close()
            sc_webview_maps[M.Type.Community] = nil
        end
    end

    -- 触发过logout, 标记下一次进入刷新webview
    for k, v in pairs(sc_webview_maps) do
        v:remove_hide_cache()
        E.LOG.debug(TAG,"move hide cache: " .. tostring(k))
    end

    sc_webview_maps = {}

    -- 账号退出时关掉浮窗
    if current_event ~= Live.LIVE_EVENT.ON_LIVE_DESTROY then
        Live.destroy()
    end
    reset_local_config()
end
-- ======================== 4.lifecycle ========================

local auth_listener = function(succ, ...)
    if succ then
        E.LOG.debug(TAG,"-------gangplank login success-------")
    else
        local code, message = ...
        E.LOG.debug(TAG,"code: " .. code .. " ,message: " .. message)
    end
end

do
    -- 未接入shortcut的情况下，需要管理账号切换的生命周期；已接入情况下全部由shortcut进行管理
    ejoysdk_topic.subscribe(ejoysdk_topic.gangplank.LOGOUT, function()
        local EC = require 'ejoysdk_lua.ejoysdk_config'
        if not EC.has_vendor_config('shortcut') then
            E.LOG.debug(TAG, "gangplank logout and clear shortcut data")
            M.clear_shortcut_webview_data()
        end
    end)
end

-- 初始化, 快捷入口的初始化
function M.init_vm(params, cb)
    
    -- E.LOG.debug(TAG, "init_vm begin")
    local sdk_meta_configs = params or {}
    cb = cb or function()
        E.LOG.debug(TAG, "init_vm cb nil")
    end

    -- local sdk_meta_configs = E.CONFIG.get_vendor_config_v2(SHORTCUT)
    -- local UNI = require "ejoysdk_lua.vendors.unisdk"
    -- local sdk_infos = UNI.get_sdk_infos()
    -- E.LOG.debug(TAG, sdk_infos)

    M.DEBUG_OPTIONS.Debug = sdk_meta_configs[M.CONFIG_KEYS.DEBUGGABLE] or false
        
    -- 打开日志开关
    if M.DEBUG_OPTIONS.Debug then
        -- debug log 开关
        local ELOG = require 'ejoysdk_lua.ejoysdk_log'
        -- 后续改动留意不支持Windows
        local ej_debugable = E.get_ej_debugable()
        -- _ejoysdk.log('=======>ej_debugable:' .. tostring(ej_debugable))
        ELOG.setup_ej_debugable(ej_debugable)
        if ej_debugable then
            E.open_log(ej_debugable)
        end
    end

    E.LOG.debug(TAG, sdk_meta_configs)

    M.ShortcutEnv = sdk_meta_configs[M.CONFIG_KEYS.SC_ENV] or 'release'
    -- fix 适配旧版本native过来的scheme的废弃字段
    if M.ShortcutEnv == 'product' then
        M.ShortcutEnv = 'release'
    end

    M.ShortcutGameId = sdk_meta_configs[M.CONFIG_KEYS.SC_GAME_ID] or 0
    M.ProductId = sdk_meta_configs[M.CONFIG_KEYS.GAME_PRODUCT_ID] or nil
    
    -- 快速打开配置开关
    local vm_type = sdk_meta_configs.biz_type or 'community'
    local sc_params = get_config_from_cc_h5res(vm_type)
   
    M.disable_fast_open = true
    local os_str = _ejoysdk.os()
    if os_str == 'android' then
         -- 仅android默认是false启动优化，开关可以关掉启动优化 
        M.disable_fast_open = false
    end
    if sc_params and sc_params.disable_fast_open then
        M.disable_fast_open = true
    end
    
    -- config productid
    -- E.CONFIG.autoconfig("", M.ProductId)
    local config_params = {
        open_log = M.DEBUG_OPTIONS.Debug,
        env = M.ShortcutEnv
    }
    ejoysdk_init.config(M.ProductId, config_params)

    local sdk_list = params.sdk_list or {} --需要初始化的插件
    

    local function open_wv_from_shortcut()
        -- open webview
        local _params = {
            local_params = {}
        }
        _params.local_params.from_source = 'shortcut'
        if sdk_meta_configs['biz_data'] then
            local JSON = require 'ejoysdk_lua.ejoysdk_json'
            local biz_data = JSON.safe_decode(sdk_meta_configs['biz_data'])
            if biz_data then
                _params.from_source_data = _params.from_source_data or {}
                _params.from_source_data.biz_data = biz_data
            end
        end

        local callbacks = callback_maps[vm_type] or {}
        callbacks.on_close_callback = function ()
             -- 快捷方式网络异常的路径，尝试重新拉起页面
            E.Timer.once(2, function()
                open_wv_from_shortcut()
            end)
        end
        M.open_shortcut_webview(vm_type, _params, nil, callbacks)
    end

    local is_wv_opened = false
    ejoysdk_topic.subscribe(ejoysdk_init.SUBSCRIBE_GANGPLANK_INITED, function(succ, ...)
        if succ then
            E.LOG.debug(TAG, "init succ")
            -- local result = get_native_result(true)
            -- cb(result)
            Utils.notify(cb, 200, "init succ", {vm = 'shortcut'})

            -- 安全打开，兜底无法打开情况
            if not is_wv_opened then
                E.LOG.debug(TAG, "open shortcut webview after GANGPLANK_INITED")
                is_wv_opened = true
                open_wv_from_shortcut()
            end

        else
            local code, error_msg = ...
            -- local result = get_native_result(false, code, error_msg)
            -- cb(result)
            Utils.notify(cb, -1, error_msg or "init failed", {code = code or -1, vm = 'shortcut'})

            -- Utils.notify(cb, 200, "初始化成功", {test=1})

            E.LOG.warn(TAG, "init failed:" .. tostring(code).. ", msg:" .. tostring(error_msg))
        end
    end)

    -- 快速打开，需要先订阅再初始化
    if not M.disable_fast_open then
        ejoysdk_topic.subscribe(ejoysdk_topic.lightboat.INITED, function (...)
            if not is_wv_opened then
                is_wv_opened = true
                E.LOG.debug(TAG, "open shortcut webview after lightboat.INITED")
                open_wv_from_shortcut()
            end
        end)
    end

    local vendors = sdk_list -- from test_cases/configs

    -- 常驻回调
    ejoysdk_init.gangplank(vendors, {
        auth_listener = auth_listener,
    })

    ejoysdk_init.init()

end

return M
