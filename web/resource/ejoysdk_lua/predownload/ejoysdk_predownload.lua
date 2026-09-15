-------------------------------------------------------------------------------
-- 预约下载 https://yuque.antfin.com/ejoy-platform/user_guide/predownload
--
-- Created Date: 2023.02.16
-- Author: 四境
--
-- Copyright (c) 2023 灵犀互娱
-------------------------------------------------------------------------------

local E = require 'ejoysdk_lua.ejoysdk'
local CC = require 'ejoysdk_lua.ejoysdk_config_center'
local Utils = require "ejoysdk_lua.native.utils.Utils"
local ejoysdk_init = require 'ejoysdk_lua.ejoysdk_init'
local ejoysdk_topic = require 'ejoysdk_lua.ejoysdk_topic'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local PDRES = require 'ejoysdk_lua.predownload.predownload_res'

local M = {}
local TAG = 'predownload'
local LAST_PREDOWNLOAD_STORAGE = E.LazyKeyStore:New("LAST_PREDOWNLOAD_STORAGE", false, true, false)
local RES_PREDOWNLOAD_ACTIVITY = "${brand}_predownload_${game_id}"
local is_first_downloading = false
-- ======================== 1.配置相关 ========================
M.CONFIG_KEYS = {
    SDK_SERVER_ENV = "sdk_server_env",
    GAME_PRODUCT_ID = "game_product_id",
    DEBUGGABLE = "debuggable",
    URL = 'url',
    ORIENTATION = 'orientation',
    OVERSEAS = 'overseas',
    OPTIONS = 'options',
    URL_RES_KEY = 'url_res_key'
}

M.DEBUG_OPTIONS = {
    Debug = false
}

M.PREDOWNLOAD_NAMESPACE = 'predownload'

M.ACTION = {
    DOWNLOAD_FINISH = 'predownload_download_finish',
    TRANSFORM_CONFIRM = 'predownload_transform_confirm',
    TRANSFORM_FINISH = 'predownload_transform_finish'
}

local is_logined = false

-- ======================== 2.private ========================
function M.merge_webview_options(old_options, remote_options)
    local f_options = old_options or {}

    -- lua default options
    f_options.use_fragment = true
    f_options.hide_close_btn = true
    f_options.use_cutout = false
    f_options.disable_backkey_press = true
    f_options.screen_orientation = M.Orientation or 'portrait'

    -- sdkconfig options
    if M.Options then
        for k, v in pairs(M.Options) do
            f_options[k] = v
        end
    end
    
    -- cc options
    if remote_options then
        for k, v in pairs(remote_options) do
            f_options[k] = v
        end
    end

    return f_options
end

function M.get_save_storeage()
    return LAST_PREDOWNLOAD_STORAGE
end


-- only android
local function is_file_exists(path)
    local file = io.open(path, "rb")
    local file_exists = file ~= nil
    if file then
        file:close()
    end
    return file_exists
end

-- ======================== 3.public =========================
function M.get_config_from_cc_h5res()
    local final_params
    -- 从配置中心判断是否存在type的配置 config
    local cc_config = CC.get_config(CC.NAMESPACE.PREDOWNLOAD)
    local final_configs = cc_config and cc_config.config and cc_config.config.predownload
    if final_configs and final_configs.webview then
        final_params = final_configs.webview
    end
    return final_params
end

function M.open_webview(_option)

    local webview_params = M.get_config_from_cc_h5res() or {}

    local url
    if webview_params.url then
        -- 优先使用配置中心的url
        url = webview_params.url
    else
        -- 使用sdkconfig默认配置的url打开
        url = M.Url
    end

    -- url = 'https://r.qookkagames.com/p/r/63f326e84422e30b0cf67f28'

    if url then

        local function open_predownload_webview(_final_url, _local_host)
            local EW = require 'ejoysdk_lua.ejoysdk_web'
            local options = _option
            options = EW.get_fill_default_options(options)
            
            local remote_options = webview_params.options
            options = M.merge_webview_options(options, remote_options)

            E.LOG.debug(TAG, options)

            local on_js_callback = function(_value)
            end
        
            local on_close_callback = function()
                E.LOG.debug(TAG, "on_close_callback >>")
                -- 活动页面不允许关闭，需要重开一下，避免404等外链引起的关闭
                E.Timer.once(1, function ()
                    if is_logined == true then
                        M.open_webview({})
                    end
                end)
            end

            local hosts = {
                '.aligames.com', '.lingxigames.com', '.ejoy.com', '.alibaba.net', '.qookkagames.com', '.sialiagames.com.tw'
            }

            if _local_host and type(_local_host) == 'string' then
                E.LOG.debug(TAG, "local_res_host: " .. tostring(_local_host))
                table.insert(hosts, _local_host)
            end

            EW.open_webview_with_options(_final_url, hosts, {}, options, on_js_callback, on_close_callback)
        end

        local LIGHTBOAT = require 'ejoysdk_lua.res.lightboat.ejoysdk_lightboat'
        local url_infos = LIGHTBOAT.get_url_infos_from_cache(url)

        local is_local_url = url_infos and url_infos.url ~= url or false
        local use_remote_res = url_infos and url_infos.use_remote_res or false

        -- 非local路径、轻舟开关、插件开关
        if not is_local_url and not use_remote_res and not webview_params.disable_local_res then
            -- 预约活动内置资源
            E.LOG.debug(TAG, 'try to use local res')
            local EJOYRES = require 'ejoysdk_lua.res.ejoysdk_res'
            local res_key = M.UrlKey
            if res_key == nil or res_key == "" then --走默认逻辑
                local is_overseas = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
                local airline_str
                if is_overseas then
                    local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
                    local gangplank_config = EGC.get_current_cdn_config()
                    if gangplank_config then
                        local airline_info = (gangplank_config['ext'] and gangplank_config['ext']['airline_info'])
                        airline_str = airline_info and airline_info.brand or 'qookka'
                    end
                else
                    -- airline设置
                    local airlineStr = E.get_pkg_info().airline or ''
                    if airlineStr == '' then
                        airline_str = 'lingxi'
                    end
                end
                if airline_str and type(airline_str) == 'string' then
                    res_key = string.gsub(RES_PREDOWNLOAD_ACTIVITY, "${brand}", airline_str)
                    local game_id_str = E.get_game_id()
                    res_key = string.gsub(res_key, "${game_id}", tostring(game_id_str))
                end
                E.LOG.debug(TAG, 'res_key:' .. tostring(res_key))
            end

            if res_key ~= nil then
                -- namespace 传nil表示仅使用内置能力，更新能力在轻舟
                EJOYRES.get_res(nil, res_key, function(succ, config)
                    local res_url = url
                    local local_host
                    if succ then
                        -- 使用缓存
                        if config and config.local_url then
                            if is_file_exists(config.local_url) then
                                E.LOG.debug(TAG, 'use local res:' .. tostring(config.local_url))
                                res_url = 'file://' .. config.local_url
                                local_host = config.local_url
                            else
                                E.LOG.debug(TAG, 'local res not exist, use remote res')
                            end
                        end
                    else
                        E.LOG.debug(TAG, 'disable local res, use remote res')
                    end
                    open_predownload_webview(res_url, local_host)
                end)

                return
            end

            -- 兜底走线上
            open_predownload_webview(url)
        else
            -- 线上或者走轻舟底层进行替换，使用url自动填充白名单host
            -- 这里可能是轻舟、或关掉了内置的资源
            E.LOG.debug(TAG, 'use lightboard res or close local')
            open_predownload_webview(url)
        end
    else
        E.LOG.warn(TAG, 'open failed, config url is not ready')
    end
end

function M.start_game()
    local VPRD = require "ejoysdk_lua.vendors.predownload"
    VPRD.start_game_activity()
end

function M.start_download()

    E.LOG.debug(TAG, "start_download")

    PDRES.start_download(function (succ, update_info_exist, ...)

        if succ then
            if update_info_exist then
                -- 下载完成
                E.LOG.warn(TAG, 'download finish')
                -- 下载完成打点
                local stat_params = {
                    ["is_priority_high"] = true
                }
                ESTAT.stat_bizid(M.ACTION.DOWNLOAD_FINISH, '1', '1', stat_params)
            else
                -- 未有资源下载
                E.LOG.debug(TAG, 'start_download no resource')
            end
        else
            -- 更新失败
            E.LOG.warn(TAG, 'start_download failed')
            -- 下载完成, 失败打点
            local stat_params = {
                ["is_priority_high"] = true,
                ["update_info_exist"] = update_info_exist
            }
            ESTAT.stat_bizid(M.ACTION.DOWNLOAD_FINISH, '1', '0', stat_params)
        end
    end)
end

function M.stat_finish()
    local stat_params = {
        ["is_priority_high"] = true
    }
    ESTAT.stat_bizid(M.ACTION.TRANSFORM_FINISH, '3', '1', stat_params)
end
-- ======================== 4.api for webview ========================

function M.start_game_from_webview()
    local parmas = {
        is_start_game = true,
        timestamp = os.time()
    }
    LAST_PREDOWNLOAD_STORAGE:set(parmas)

    local stat_params = {
        ["is_priority_high"] = true
    }
    ESTAT.stat_bizid(M.ACTION.TRANSFORM_CONFIRM, '2', '1', stat_params)

    M.start_game()
end

function M.is_confirmed_to_finish()
    local result = LAST_PREDOWNLOAD_STORAGE:get()
    return result ~= nil
end

function M.is_finish_predownload()
    return M.is_confirmed_to_finish()
end

function M.get_res_state()
    
    local res_state = PDRES.get_res_state()
    -- E.log(res_state)

    if res_state ~= nil then
        return res_state
    end

    return nil    
end

-- ======================== 5.lifecycle ========================
local auth_listener = function(succ, ...)
    if succ then
        E.LOG.debug(TAG,"-------gangplank login success-------")
    else
        local code, message = ...
        E.LOG.debug(TAG,"code: " .. code .. " ,message: " .. message)
        -- 返回手势等异常情况处理
        if code == CONSTANTS.OFFICIAL_ERR_CODES.CODE_LOGIN_CANCEL then
            M.vm_login()
        end
    end
end

-- 监听webview完成后开始下载
local add_webview_life_cycle = function ()

    local add_webview_life_cycle_subscribe
    add_webview_life_cycle_subscribe = function (value)
        -- E.LOG.debug(TAG, 'webview_life_cycle')
        -- E.LOG.debug(TAG, value)
        if value and value.type and tostring(value.type) == '1' then
            ejoysdk_topic.unsubscribe('webview_life_cycle', add_webview_life_cycle_subscribe)
            if is_first_downloading then
                E.LOG.debug(TAG, "start_download, is_first_downloading already and return")
                return
            else
                is_first_downloading = true
                M.start_download()
            end
        end
    end

    ejoysdk_topic.unsubscribe('webview_life_cycle', add_webview_life_cycle_subscribe)
    ejoysdk_topic.subscribe('webview_life_cycle', add_webview_life_cycle_subscribe)
end


local acquire_listener = function(succ, ...)
    if succ then
        E.LOG.debug(TAG, "-------gangplank acquire success-------")
        is_logined = true
        add_webview_life_cycle()
        M.open_webview({})

        -- 兜底启动下载逻辑
        E.Timer.once(3, function ()
            if is_first_downloading then
                E.LOG.debug(TAG, "start_download, is_first_downloading already and return")
                return
            else
                is_first_downloading = true
                M.start_download()
            end
        end)
    else
        local code, message = ...
        E.LOG.debug(TAG, "-------gangplank acquire failure, code: " .. code .. " ,message:"  .. message)
        -- 重新尝试登录
        E.Timer.once(1, function ()
            if is_logined == false then
                M.vm_login()
            end
        end)
    end
end

function M.logout()
    is_logined = false
    E.WebView.close()

    local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    EG.logout()
end

local logout_listener = function()
    E.LOG.debug(TAG, "-------gangplank logout success-------")
    -- 尝试重新拉起登录页
    E.Timer.once(1, function ()
        if is_logined == false then
            M.vm_login()
        end
    end)
end

local exit_listener = function(succ)
    if succ then
        E.LOG.debug(TAG, "-------gangplank exit success-------")
    else
        E.LOG.debug(TAG, "-------gangplank exit failure-------")
    end
end

-- vm_ 前缀方法为sdk vm调用的方法
function M.vm_login()
    local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
    EG.acquire_token()
end

local is_gp_inited = false
local current_init_retry_times = 1

-- 初始化, 快捷入口的初始化
function M.vm_init(params, cb)
    
    -- E.LOG.debug(TAG, "init_vm begin")
    local sdk_meta_configs = params or {}
    cb = cb or function()
        E.LOG.debug(TAG, "init_vm cb nil")
    end

    -- load sdkdata
    local _meta_data_load = require "ejoysdk_lua.vendors.unisdk"

    M.DEBUG_OPTIONS.Debug = sdk_meta_configs[M.CONFIG_KEYS.DEBUGGABLE] or false

    -- 打开日志开关
    if M.DEBUG_OPTIONS.Debug then
        -- debug log 开关
        local ELOG = require 'ejoysdk_lua.ejoysdk_log'
        local ej_debugable = E.get_ej_debugable()
        -- _ejoysdk.log('=======>ej_debugable:' .. tostring(ej_debugable))
        ELOG.setup_ej_debugable(ej_debugable)
        if ej_debugable then
            E.open_log(ej_debugable)
        end
    end

    E.LOG.debug(TAG, sdk_meta_configs)

    -- 1.强更标记，这里标记并且传入到ejoysdk_init.config
    E.CONFIG.set_config(E.CONFIG.KEY.APP_VERSION_UPDATE_CHECK, true)

    -- 2.jf标识
    local UIM = require "ejoysdk_lua.user_info_manager"
    local predownload_game_info = {
        [UIM.PKG_INFO_KEY.KEY_PREDOWNLOAD_GAME_RUN_MODE] = 'predownload',
        [UIM.PKG_INFO_KEY.KEY_PKG_GAME_RUN_MODE_TYPE] = 'predownload'
    }
    UIM.set_predownload_game_mode(predownload_game_info)

    -- 3.初始化也能请求predownload的namespace
    CC.add_init_namespace(M.PREDOWNLOAD_NAMESPACE)

    M.ProductId = sdk_meta_configs[M.CONFIG_KEYS.GAME_PRODUCT_ID] or nil
    M.Url = sdk_meta_configs[M.CONFIG_KEYS.URL]
    M.UrlKey = sdk_meta_configs[M.CONFIG_KEYS.URL_RES_KEY]
    M.ProductEnv = sdk_meta_configs[M.CONFIG_KEYS.SDK_SERVER_ENV] or 'release'
    M.Options = sdk_meta_configs[M.CONFIG_KEYS.OPTIONS] or {}
    M.Orientation = sdk_meta_configs[M.CONFIG_KEYS.ORIENTATION]

    local is_overseas = sdk_meta_configs[M.CONFIG_KEYS.OVERSEAS]
    -- 默认海外
    if is_overseas == nil then
        is_overseas = true
    end

    local config_params = {
        open_log = M.DEBUG_OPTIONS.Debug,
        env = M.ProductEnv,
        overseas = is_overseas,
        open_app_version_update_check = true -- 适配ejoysdk_init.config 里面的强更逻辑，使生效
    }
    
    -- 4.初始化
    ejoysdk_init.config(M.ProductId, config_params)

    local sdk_list = params.sdk_list or {} --需要初始化的插件

    local function retry_init(interval)
        if is_gp_inited == false and current_init_retry_times <= 20 then
            E.Timer.once(interval, function ()
                E.LOG.debug(TAG, "retry init, retry_times:" .. tostring(current_init_retry_times))
                current_init_retry_times = current_init_retry_times + 1
                ejoysdk_init.init()
            end)
        end
    end

    ejoysdk_topic.subscribe(ejoysdk_init.SUBSCRIBE_GANGPLANK_INITED, function(succ, ...)
        if succ then
            is_gp_inited = true
            E.LOG.debug(TAG, "init succ")
            Utils.notify(cb, 200, "init succ", {vm = 'predownload'})
            
            if is_overseas then
                -- 聚合登录禁用返回键
                local overseas_login = require 'ejoysdk_lua.overseas.login'
                overseas_login.inject_webview_options({ disable_backkey_press = true })
            end

            -- 初始化完成，拉起登录
            M.vm_login()
        else
            local code, error_msg = ...
            Utils.notify(cb, -1, error_msg or "init failed", {code = code or -1, vm = 'predownload'})
            E.LOG.warn(TAG, "init failed:" .. tostring(code).. ", msg:" .. tostring(error_msg))
            retry_init(current_init_retry_times)
        end
    end)

    local vendors = sdk_list

    -- 常驻回调
    ejoysdk_init.gangplank(vendors, {
        auth_listener = auth_listener,
        acquire_listener = acquire_listener,
        logout_listener = logout_listener,
        exit_listener = exit_listener
    })

    ejoysdk_init.init()
    
end

return M