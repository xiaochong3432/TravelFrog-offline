local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"
local VER_CHECK = require 'ejoysdk_lua.ejoysdk_version_check'
local ECC = require 'ejoysdk_lua.ejoysdk_config_center'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local EF = require "ejoysdk_lua.res.custom_res_facade"
local RTM = require "ejoysdk_lua.res.model.ejoy_res_type_model"
local M = {}
local TAG = EM.MODULE.RES .. "ejoysdk_lua_update"
local RES_BUILTIN_PATH = 'ejoysdk_res'
local inited = false
local ejoysdk_lua_info = {} -- 当前的ejoysdk_lua信息
local res_state_changed_list = {} -- 标记资源状态变更
local res_update_list = {} -- 更新列表

M.RES_KEY = 'ejoysdk_lua'

-- 资源配置的字段信息
M.RES_CONFIG_KEY = {
    -- 版本号
    KEY_VERSION = "version",
    -- 资源类型
    KEY_RES_TYPE = "key",
    -- 资源的入口路径
    KEY_PATH = "path",
    -- 资源是否有更新
    KEY_RESOURCE_UPDATED = "res_updated",
    -- 是否需要从bundle释放资源
    KEY_NEED_RELEASE_FROM_BUNDLE = "need_release_from_bundle"
}

-- 资源类型
M.RES_TYPE = {
    EJOYSDK_LUA = "ejoysdk_lua"
}

local ejoysdk_lua_cb

local function stat(action, key, succ, params)
    local ejoysdk_stat = require 'ejoysdk_lua.ejoysdk_stat'
    E.LOG.debug(TAG, "action=" .. tostring(action) .. ', key=' .. tostring(key) .. ', succ=' .. tostring(succ or 'nil'))
    ejoysdk_stat.stat_action(action, key, succ, params)
end

local function get_ejoy_biz_config()
    local ejoy_biz_config = ECC.get_config(ECC.NAMESPACE.EJOYSDK_BIZ)
    return ejoy_biz_config
end

local function is_lua_use_local_res()
    local usercenter_config = get_ejoy_biz_config()
    return usercenter_config and usercenter_config.config and usercenter_config.config.ejoy_lua_update_enable == true
end

local function is_support_use_local_res(key)
    local pkg_info = E.get_pkg_info()
    local is_device_support = E.File.is_support_handling_file_cache() --避免native是低版本
            and pkg_info.os ~= 'windows' -- 暂时先不支持windows，虽然windows支持缓存，但是没有测试过lua热更新和h5资源热更新
            -- 判断 ios 10 以上才开启, 涉及CORS
            and (pkg_info.os ~= 'android' or (pkg_info.os == 'android' and VER_CHECK.compare_versions(pkg_info.versions.os_version, 23) >= 0))
            and (pkg_info.os ~= 'ios' or (pkg_info.os == 'ios' and VER_CHECK.compare_versions(pkg_info.versions.os_version, "10.0") >= 0))

    return is_device_support
end

-- 获取本地可用资源的版本号，优先取缓存目录的版本号，如果没有则看包体的资源是否需要释放，需要释放则为版本号不可用，不需要释放则返回包体的版本号）
local function get_local_available_res_version()
    local local_cached_res = ejoysdk_lua_info
    E.LOG.debug(TAG, "local cached version: " .. ((local_cached_res and local_cached_res.version) or 'nil'))

    local local_res_version
    if local_cached_res and local_cached_res[M.RES_CONFIG_KEY.KEY_VERSION] then
        local_res_version = local_cached_res[M.RES_CONFIG_KEY.KEY_VERSION]
    end
    return local_res_version
end

--读取assets下lua资源的lua版本号，只用于SDK的lua热更新
local function get_lua_version()
    local bundle_ejoy_lua_path = nil
    -- ios native sdk 的 lua资源是放在ejoysdk_assets.bundle下面，使用lread读取时IOS需要在路径前加上ejoysdk_assets.bundle。Android则不需要
    if _ejoysdk.os() == "ios" then
        bundle_ejoy_lua_path = "ejoysdk_assets.bundle/ejoysdk_lua/version.lua"
    elseif _ejoysdk.os() == "android" then
        bundle_ejoy_lua_path = "ejoysdk_lua/version.lua"
    end

    local version_lua_content
    if bundle_ejoy_lua_path then
        E.LOG.debug(TAG, "get_lua_version path:" .. bundle_ejoy_lua_path)
        version_lua_content = _ejoysdk.lread(bundle_ejoy_lua_path)
    end

    local bundle_lua_version = ''
    if version_lua_content then
        local func = load(version_lua_content, 'ejoysdk_lua/version.lua', "bt")
        if func == nil then
            E.LOG.debug("ejoysdk_lua/version.lua load fail")
        else
            local ret, V = pcall(func)
            if ret then
                bundle_lua_version = (V or {}).LUA_VERSION or ''
                E.LOG.warn(TAG, "get_lua_version read lua version succ:" .. tostring(bundle_lua_version))
            end
        end
    else
        E.LOG.warn(TAG, "get_lua_version version_lua_content nil from path:" .. tostring(bundle_ejoy_lua_path))
    end

    return bundle_lua_version
end

local function get_cached_path()
    if _ejoysdk.os() == "ios" then
        local paths = _ejoysdk.sysinfo_paths()
        return paths['document_path']
    elseif _ejoysdk.os() == "android" then
        return E.File.get_ext_file_dir()
    else
        return E.File.get_ext_file_dir()
    end
end

-- 处理更新请求
local function update(res_info, cb)
    local stat_action = 'res_update'
    local res_key = res_info.key

    local notify = function(succ, ...)
        -- 存一个外部的回调，存在则回调
        if cb then
            cb(succ, ...)
            cb = nil
        end
        res_update_list[res_key] = nil -- 无论成功与否，清理待更新信息
    end

    local download_block = function()
        E.LOG.debug(TAG, "res_key: " .. tostring(res_key) .. ' 开始下载更新')
        -- 从内部释放的不计入更新
        stat(stat_action, res_key)
        -- 本地没有这个资源或者版本不匹配才会触发更新
        local lua_update_engine_handler = {
            on_res_apply = function(_res_key, res_location, res_state_infos, apply_cb)
                E.LOG.debug(TAG, "lua update res apply")
                E.log(res_location)
                E.log(res_state_infos)
                local file_list_info = res_state_infos[RTM.INFO_TYPE_KEY.TYPE_PENDING_FILE_LIST_INFO] or {}
                if file_list_info[1] == nil or  file_list_info[1].name == nil then
                    apply_cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_GET_FILE_NAME_FAILED, "资源文件名获取失败")
                    return
                end
                local file_name = file_list_info[1].name
                local save_path = E.Utils.trim_end(res_location, "/") .. "/" .. file_name
                E.LOG.debug(TAG, "下载路径为: " .. tostring(save_path))
                --ejoysdk_res/ejoysdk_lua/2.23.11
                local unzip_path = RES_BUILTIN_PATH .. '/' .. M.RES_TYPE.EJOYSDK_LUA .. '/' .. res_info.version .. '/'
                local ext_file_dir = E.File.get_ext_file_dir()
                unzip_path = string.format("%s/%s", ext_file_dir, unzip_path)
                E.LOG.debug(TAG, 'save_path is ' .. tostring(save_path))
                E.LOG.debug(TAG, 'unzip_path is ' .. tostring(unzip_path))
                E.File.unzip_full_path(save_path, unzip_path, function(ret)
                    if ret.succ then
                        E.LOG.debug(TAG, tostring(res_key) .. " 解压成功")
                        ejoysdk_lua_info = res_info.config_info -- 更新内存信息
                        stat(stat_action .. '_unzip', res_key, true)
                        E.File.remove_fullpath(save_path) -- 删除zip文件
                        E.LOG.debug(TAG, 'on_res_apply succ')
                        apply_cb(true)
                    else
                        apply_cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_UNZIP_FAILED, ret.msg)
                        E.LOG.debug(TAG, tostring(res_key) .. " 解压失败")
                        stat(stat_action .. '_unzip', res_key, false)
                    end
                end)
                stat(stat_action .. '_unzip', res_key)
            end
        }

        local current_res_info = {
            res_key = M.RES_TYPE.EJOYSDK_LUA,
            engine_handler = lua_update_engine_handler
        }

        local _on_confirm_res_update_handler = function(_res_key, res_state_info, confirm_update_cb)
            local update_info = res_state_info[EF.RES_STATE_INFOS.TYPE_RES_UPDATE_STATE] or {}
            local update_ver = update_info[EF.UPDATE_INFO_KEY.VERSION_NAME]
            local has_new_update = update_info[EF.UPDATE_INFO_KEY.HAS_NEW_UPDATE] or false
            E.LOG.debug(TAG, "on_receive_res_update_confirm, res_key:" .. tostring(res_key) .. ", ver:" .. tostring(update_ver))
            if has_new_update then
                confirm_update_cb(true)
                E.LOG.debug(TAG, "on_receive_res_update_confirm has update, confirm true")
            else
                confirm_update_cb(false)
                E.LOG.debug(TAG, "on_receive_res_update_confirm has not update, confirm false")
            end
        end

        local on_res_update_complete_handler = function(update_result, ...)
            if update_result then
                E.LOG.debug(TAG, "res_key: " .. tostring(res_key) .. ' 下载成功')
                -- 更新结束，通知更新结束
                E.LOG.debug(TAG, "config info >>>>")
                E.LOG.debug(TAG, res_info.config_info)
                notify(true, res_info.config_info)
            else
                -- 下载失败就没了，这个更新就完了，如果是强制更新，需要走兜底方案
                E.LOG.debug(TAG, "res_key: " .. tostring(res_key) .. ' 下载失败')
                local code, msg = ...
                notify(false, code, msg, res_info.config_info)

                stat(stat_action, res_key, false)
            end
        end

        local listeners = {
            on_confirm_res_update = _on_confirm_res_update_handler,
            on_res_update_complete = on_res_update_complete_handler
        }
        E.LOG.debug(TAG, "check and update start")
        local opts = {
            [EF.NAMESPACE_UPDATE_OPTIONS.FOREGROUND_NOTIFICATION_ENABLED] = false,
            [EF.NAMESPACE_UPDATE_OPTIONS.USING_CC_CACHE_DATA] = true
        }
        EF.check_and_update(current_res_info, opts, listeners)
    end

    download_block()
end

-- 直接使用远程资源配置判断是否需要更新
local function res_config_update(key, remote_res, cb)
    cb = cb or function() end
    E.LOG.debug(TAG, "remote_res >>> ")
    E.LOG.debug(TAG, remote_res)
    if not is_support_use_local_res(key) then
        cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_CACHE_NOT_SUPPORT, "not support")
        return
    end

    if next(remote_res) == nil then
        E.LOG.debug(TAG, "res_update_by_key response nil, skip")
        cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_RES_CONFIG_INVALID, "ejoysdk_lua config is nil")
        return
    end

    if (not is_lua_use_local_res()) then
        cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_RES_UPDATE_SWITCH_OFF, "switch off");
        return
    end

    local res_key = remote_res.key
    remote_res.force_update = (remote_res.force_update and remote_res.force_update == true) or false

    local updating_res = res_update_list[res_key]
    if updating_res then
        E.LOG.warn(TAG, "res_key: " .. tostring(res_key) .. ' 存在同时更新资源，等待返回')
        return
    end

    -- 保留记录到文件中的格式
    remote_res.config_info = {
        key = remote_res.key,
        version = remote_res.version,
    }

    -- 获取本地可用资源（本地需要释放则返回缓存的版本号）的版本号，比对服务端资源的版本号
    local local_res_version = get_local_available_res_version()
    local bundle_res_version = get_lua_version()
    E.LOG.debug(TAG, "local version: " .. tostring(local_res_version) .. ', remote version: ' .. tostring(remote_res.version) .. ', bundle version: ' .. tostring(bundle_res_version))

    if VER_CHECK.compare_versions(bundle_res_version, local_res_version) > 0 then
        local_res_version = bundle_res_version
        E.LOG.debug(TAG, "bundle version is bigger than local version, use bundle version as using version")
    end

    if VER_CHECK.compare_versions(local_res_version, remote_res.version) < 0 then

        res_update_list[res_key] = remote_res

        update(remote_res, function(update_succ, ...)
            if update_succ then
                E.LOG.debug(TAG, "update cb >>>>>>>")
                local res_config_data = ...
                res_config_data[M.RES_CONFIG_KEY.KEY_RESOURCE_UPDATED] = true
                -- 标记资源状态变更
                res_state_changed_list[res_key] = true
                E.LOG.debug(TAG, res_config_data)
                if ejoysdk_lua_cb then
                    ejoysdk_lua_cb(true, res_config_data)
                end
            else
                if ejoysdk_lua_cb then
                    --更新失败情况下，清掉本地的配置
                    ECC.delete_config(ECC.NAMESPACE.QZ_CUSTOM_RES)
                    ejoysdk_lua_cb(false, ...)
                end
            end
            ejoysdk_lua_cb = nil
        end)
    else
        -- 检查是否有资源变更
        local has_res_changed = res_state_changed_list[res_key] or false
        remote_res.config_info[M.RES_CONFIG_KEY.KEY_RESOURCE_UPDATED] = has_res_changed
        E.LOG.debug(TAG, "res_update_by_key resource is newest, skip update:" .. tostring(key) .. ", state changed:" .. tostring(has_res_changed))
        cb(true, remote_res.config_info)
    end
end

-- 配置中心返回
local function ecc_update(config, cb)
    config = config or {}
    local has_config_ejoysdk_lua = false
    if config.config then
        for key, res_config in pairs(config.config) do
            -- 数据打平, 还是以res_key为索引
            if key == M.RES_TYPE.EJOYSDK_LUA then
                has_config_ejoysdk_lua = true
                res_config_update(key, res_config, cb)
            end
        end
    end
    -- 没配置ejoysdk_lua的情况, 有cb说明是拉的新的数据了，还没有则需要返回失败
    if not has_config_ejoysdk_lua and cb then
        cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_RES_CONFIG_INVALID, "ejoysdk lua res_key not exist")
    end
end

-- 遍历本地资源，收集版本信息上报，初始化时阻塞执行
function M.init(cb)
    E.LOG.debug(TAG, "ejoysdk lua update init")
    if inited then
        -- ejoysdk_res_manager 与 ejoysdk_gangplank 都有可能一齐起来
        E.LOG.debug(TAG, 'already init and return')
        if cb then
            cb(true)
        end
        return
    end

    cb = cb or function()
    end

    -- 本地资源状态初始化

    -- 初始化外置的lua资源版本信息
    local res_state = EF.get_res_state(M.RES_KEY)
    E.log("res_state is >>>>")
    E.log(res_state)
    if res_state then
        local using_res_info = res_state.using_res_info or {}
        local version = using_res_info.version
        if version then
            E.LOG.debug(TAG, "has cache ejoysdk_lua_info, version is " .. tostring(version))
            local res_info = {
                [M.RES_CONFIG_KEY.KEY_RES_TYPE] = M.RES_KEY,
                [M.RES_CONFIG_KEY.KEY_VERSION] = version
            }
            ejoysdk_lua_info = res_info
        end
    end

    -- 检查缓存资源状态
    M._check_cache_res_state()

    -- 主动设置一次，避免初始化时已经错过时机
    ecc_update(ECC.get_config(ECC.NAMESPACE.QZ_CUSTOM_RES))
    ECC.subscribe(ECC.NAMESPACE.QZ_CUSTOM_RES, ecc_update)

    inited = true
    cb(true)
end

-- 更新指定资源,这里的cb只有外部真正调用才设置
function M.res_update(res_key, cb)
    cb = cb or function() end
    -- 存下来这个cb，等待返回时使用
    ejoysdk_lua_cb = cb
    local target_namespace = ECC.NAMESPACE.QZ_CUSTOM_RES

    local request_namespaces = { target_namespace }
    --lua热更的开关配置，需要先拉下来
    table.insert(request_namespaces, ECC.NAMESPACE.EJOYSDK_BIZ)
    ECC.get_configs_in_whitelist(request_namespaces, function(succ, ...)
        if not succ then
            cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_RES_UPDATE_FAILED, "update failed")
            return
        end

        local configs = ...
        if not (configs and next(configs)) then
            cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_RES_UPDATE_FAILED, "update config empty")
            return
        end
        -- configs内有多少个取决于请求参数里的namespace有多少个
        for _, config in pairs(configs) do
            -- 这个接口是增量的,有可能不会返回，如果不返回那就不需要更新了，由监听负责更新
            if config and next(config) and config.namespace == target_namespace then
                ecc_update(config, function(update_succ, ...)
                    if update_succ then
                        local res_config = ...
                        if res_config.key == res_key then
                            cb(true, res_config)
                        end
                    else
                        cb(update_succ, ...)
                    end
                end)
                return
            end
        end
        --增量更新没有namespace，同时本地数据也没有该namespace，认为没配置返回错误
        if ECC.get_config(target_namespace) == nil then
            cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_NAMESPACE_CONFIG_NOT_EXIST, "target namespace not exist")
        elseif res_update_list[res_key]  == nil then
            -- 本地有数据，但是没在更新状态中，即本地数据已经更新失败了，这时回调失败
            cb(false, CONSTANTS.RESOURCE_UPDATE_ERROR_CODES.RES_NAMESPACE_CONFIG_NOT_EXIST, "local target namespace exist, but not updating")
        end
    end)
end

function M.get_bundle_res_info()
    local bundle_lua_version = get_lua_version()
    local res_info = {
        [M.RES_CONFIG_KEY.KEY_RES_TYPE] = M.RES_TYPE.EJOYSDK_LUA,
        [M.RES_CONFIG_KEY.KEY_VERSION] = bundle_lua_version
    }

    E.LOG.debug(TAG, "read default ejoysdk_lua config info >>")
    E.LOG.debug(TAG, res_info)
    return res_info
end

-- 检查本地资源状态：包体比缓存新则删除缓存
function M._check_cache_res_state()
    if ejoysdk_lua_info and next(ejoysdk_lua_info) ~= nil then
        -- get_bundle_res_info also find bundle res info with lua
        local bundle_res_info = M.get_bundle_res_info()
        bundle_res_info = bundle_res_info or {}
        local bundle_res_version = bundle_res_info[M.RES_CONFIG_KEY.KEY_VERSION]
        local cached_res_conf_version = ejoysdk_lua_info[M.RES_CONFIG_KEY.KEY_VERSION]
        E.LOG.debug(TAG, "_check_cache_res_state, cached_res_conf_version:" .. tostring(cached_res_conf_version) .. ", bundle_res_version:" .. tostring(bundle_res_version))
        if VER_CHECK.compare_versions(cached_res_conf_version, bundle_res_version) < 0 then
            E.LOG.debug(TAG, "compare_versions old than bundle res, now do remove")
            --需要删除配置文件
            --lua资源正在使用，不能删除，只能删除配置文件
            local using_res_cfg_path = EF.static_get_using_res_config_path(M.RES_KEY)
            E.File.remove(using_res_cfg_path)
            ejoysdk_lua_info = nil
        end
    end
end


function M.get_res_location()
    local res_location
    if ejoysdk_lua_info and ejoysdk_lua_info.version then
        E.LOG.debug(TAG, "get_res_location has cache config, now read from config")
        local base_path = RES_BUILTIN_PATH .. '/' .. M.RES_TYPE.EJOYSDK_LUA .. '/'
        res_location = base_path .. ejoysdk_lua_info.version
        if _ejoysdk.os() ~= "ios" then
            -- ios是特殊的,它不能保存全路径, 有可能会变
            res_location = get_cached_path() .. '/' .. res_location
        end
    else
        -- 本地没资源/本地下载的资源版本小于包内，这里置为空，走回包内
        res_location = nil
    end

    return res_location
end

return M