local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
local EM = require "ejoysdk_lua.ejoysdk_module"
local EC = require 'ejoysdk_lua.ejoysdk_config'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'

--安全SDK
local CHANNEL = "SECURITY"
local TAG = EM.MODULE.VENDORS.SECURITY

local M = Vendor:Inherit(CHANNEL)

--更新数据
local CAST_UPDATE_DATA = "CAST_UPDATE_DATA"
local CAST_INIT_DATA = 'CAST_SECURITY_INIT_DATA'
local CAST_UPDATE_VANGUARD_CONFIG = 'CAST_UPDATE_VANGUARD_CONFIG'

-- 同步获取隐私信息，该方法会立即返回native的缓存信息
--local SYNC_GET_PRIVACY_INFO = "SYNC_GET_PRIVACY_INFO"
-- 是否支持获取隐私信息
local IS_SUPPORT_GET_PRIVACY_INFO = "IS_SUPPORT_GET_PRIVACY_INFO"
-- 异步获取隐私信息，每次会刷新安全SDK的隐私信息
local ASYNC_GET_PRIVACY_INFO = "ASYNC_GET_PRIVACY_INFO"

local cached_security_privacy_info = {}

-- 更新经分参数
local function update_data(params)
    UNI.cast(CHANNEL, CAST_UPDATE_DATA, params)
end

local function get_extra_params(_ext_params)

    local ext_params = _ext_params or {}

    local params = {
        publish_area = E.CONFIG.get_config(E.CONFIG.KEY.PUBLISH_AREA),
        region = E.CONFIG.get_config(E.CONFIG.KEY.REGION),
        accountId = ext_params.accountId or '',
        roleId = ext_params.roleId or '',
        gid = E.get_game_id(),
        serverId = ext_params.serverId or '',
        product = E.CONFIG.get_config('product'),
        sysTime = os.time() * 1000
    }

    local pkg_info = E.get_pkg_info()
    if pkg_info then
        params.ch = pkg_info.ds_channel_id or ''
        params.subCh = pkg_info.ds_sub_channel_id or ''
    end

    return params
end

-- 账号登录/登出/切换后，更新accountId到extra_config字段内容里
local login_handler = function(user_info)
    --登录成功打点
    -- update stat account param
    local params = {
        uid = user_info.uid,
        serverid = user_info.server,
        extra_params = get_extra_params({ accountId = user_info.uid, roleId = '', serverId = ''})
    }
    E.LOG.debug(TAG, 'login，update security data')
    update_data(params)

    local os = E.Sysinfo.os()
    if os == "windows" then
        -- 更新umid token
        M.update_umid_token()
    else
        E.LOG.debug(TAG, "login succ, now refresh security info ")
        -- 刷新安全隐私信息
        M.init_privacy_info()
    end
end

local acquire_succ_handler = function()
    local os = E.Sysinfo.os()
    if os == "windows" then
        -- 更新umid token
        M.update_umid_token()
    else
        E.LOG.debug(TAG, "acquire succ, now refresh security info ")
        -- 刷新安全隐私信息
        M.init_privacy_info()
    end
end

-- 在角色登录/登出/切换，更新roleId和accountId到extra_config字段内容里
local set_player_info_handler = function(player_info)
    E.LOG.debug(TAG, "set_player_info_handler, params >>")
    local EG = require "ejoysdk_lua.ejoysdk_gangplank"
    local user_info = EG.user_info() or {}
    -- 设置角色公参
    local params = {
        extra_params = get_extra_params({ 
            roleId = player_info and player_info.player_id or '',
            accountId = user_info.uid or '',
            serverId = player_info.server_id or ''
        })
    }
    E.LOG.debug(TAG, params)
    update_data(params)
    E.LOG.debug(TAG, "set_player_info_handler, now refresh security info ")
end

local player_offline_handler = function()
    E.LOG.debug(TAG, "player_offline_handler")
    local EG = require "ejoysdk_lua.ejoysdk_gangplank"
    local user_info = EG.user_info() or {}
    -- 设置角色公参
    local params = {
        extra_params = get_extra_params({
            roleId = '',
            accountId = user_info.uid or '',
            serverId = ''
        })
    }
    update_data(params)
    E.LOG.debug(TAG, "player_offline_handler, now refresh security info ")
end

function M.test_update_data(params)
    update_data(params)
end

local function gangplank_logout_handler()
    --登出成功，更新经分数据
    -- update stat account param
    local params = {
        uid = '',
        extra_params = get_extra_params({})
    }
    E.LOG.debug(TAG, 'logout，update security data')
    update_data(params)
end

local function gangplank_exit_handler()
    -- update stat account param
    local params = {
        uid = '',
    }
    E.LOG.debug(TAG, 'exit，update security data')
    update_data(params)
end

local function cast_update_vanguard_config(global_config)
    if global_config and global_config['vanguard-config'] then
        UNI.cast(CHANNEL, CAST_UPDATE_VANGUARD_CONFIG, global_config['vanguard-config'])

        E.LOG.debug(TAG, "cast_update_vanguard_config vanguard-config >>")
        E.LOG.debug(TAG, global_config['vanguard-config'])
    end
end

local function global_config_handler(global_config)
    ET.unsubscribe(ET.gangplank.GLOBAL_CDN_CONFIG_SUCC, global_config_handler)
    cast_update_vanguard_config(global_config)
end

local function region_config_change_handle(new_region)
    local params = {
        region = new_region
    }
    E.LOG.debug(TAG, 'security update region: ' .. tostring(new_region))
    update_data(params)
end

--[[
安全SDK返回的安全隐私信息如下：
{
       ["wua"] => "foAX_YYkaG/t9fgpZHsW25qVcYKC3Wt/X8do3xYxuHoYSl+909ih2Wl8c3r60U3zEG47AWH75Iem1v4/sDX2yBEyyZp9T+paO4qoxJvUaicjVOJN6kN1hIHL1E3hiUVjaxRgnB9dYm+GcMKYfZA7MjbuBloipniD2utq92RbNM7/t2OKM9AJYOBIqA/XXmuNEnYZFLXhafAa1E+cHIUe6Zy4TwFxnzWlG6QMOqQ2gf7Ns7lLBm0bLNilZ0kM80YOXRwgEJ/wCHmhBtgKFzR+E4iutUljACsPqzSNXD1fej5BP3+a6tM9HuE2Isfhj9G/BToAusE6qXRrBx6SPN+aAcxjatH+prh78gAbioc47KOfrd+vb7buP7PKtt/EZSmn1EHhVhZ2INCdYmXE4f9hGwSzG1tUrMbXymR1hLatf+ad/WoO2ILLR3h1vo4un9iOklNWr"
       ["x-utdid"] => "X4AegcktD3cDAPv7qYAi7NUt"
       ["x-bx-version"] => "6.5.14198574"
       ["x-umt"] => "GEBLKTBLOsKbnjV7qSN6W4tMlt6iVcYw"
       ["x-sign"] => "azPMaH003xAAO+YNhU0p1b8UvdeGK+YL5jMVHf4AtHf3j+K5dQ9Vp8+yBVxcmdGuXr8vZgwuumjtAZoHBjKiDDQ8PZtmK+YL5ivmC+"
       ["x-mini-wua"] => "HHnB_ogmWWW9Xlwy2abFFoooGzCzi7IA3l6N8x2s5c6SKzzUvN45584am0kCRRxE0HWJiiPpyJGtQl2GzwqhkjLryslXvhrv01ZsKXDmcN4iL9QeFcx0T1wB38iBPkStEuzStWP9IUvcUQnKXU8SJ9XbFQA=="
       ["asac"] => "2A20709L44B917R8NEBBPA"
       ["s-smlt"] => "8"
       ["data"] => "gamesecdata"
       ["x-sgext"] => "JAHc7R3GWJ39vrqv86dYhO3t3ejV7s7r2OrV/98="
       ["s-sec-version"] => "1.8.4.12"
    }
]]
local function get_umid_token()
    local umid_token = nil
    local os = E.Sysinfo.os()
    if os == "windows" then
        if _ejoysdk.sysinfo then
            local sysinfo = _ejoysdk.sysinfo() or {}
            -- 安全提供的security token 对应 umid_token，用于给服务端换umid使用
            umid_token = sysinfo.security_token
        end
    else
        if cached_security_privacy_info then
            umid_token = cached_security_privacy_info["x-umt"]
        end
    end

    E.LOG.debug(TAG,"umid_token:" .. tostring(umid_token))
    return umid_token
end

-- 更新umid token
function M.update_umid_token()
    local umid_token = get_umid_token()
    if umid_token then
        local user_info_manager = require "ejoysdk_lua.user_info_manager"
        user_info_manager.set_umid_token(umid_token)
    else
        E.LOG.debug(TAG, "umid token is nil, skip update")
    end
end

function M.init_privacy_info()
    E.LOG.debug(TAG, "init_privacy_info begin, is support result >>")
    local result_data = UNI.sync_call(CHANNEL, IS_SUPPORT_GET_PRIVACY_INFO, {})
    local is_support
    E.LOG.debug(TAG, result_data)
    if result_data == nil then
        is_support = false
    else
        is_support = result_data.value
    end

    if not is_support then
        E.LOG.debug(TAG, "init_privacy_info skip, not support")
        return
    else
        E.LOG.debug(TAG, "init_privacy_info support, now get privacy info")
    end

    UNI.async_call(CHANNEL, ASYNC_GET_PRIVACY_INFO, {}, nil, function(succ, ...)
        if succ then
            local data = ...
            cached_security_privacy_info = data or {}
            E.LOG.debug(TAG, "init_privacy_info succ >>")
            E.LOG.debug(TAG, cached_security_privacy_info)

            local user_info_manager = require "ejoysdk_lua.user_info_manager"
            user_info_manager.set_security_privacy_info(cached_security_privacy_info)
            -- 更新umid token
            M.update_umid_token()
        else
            local code = ...
            E.LOG.warn(TAG, "init_privacy_info failed, code:" .. tostring(code))
        end
    end)
end

function M.init(opt, cb)
    E.LOG.debug(TAG, 'security stat start init!')
    local init_params = {
        game_version = E.CONFIG.get_config('game_version') or '',
        region = E.CONFIG.get_config("region"),
        gameid = E.get_game_id(),
        product = E.CONFIG.get_config('product'),
        extra_params = get_extra_params({})
    }

    -- PC端可以检测，sdkconfig有没有被恶意去除SECURITY插件
    local os = E.Sysinfo.os()
    if os == "windows" and opt and opt.open_check and not EC.has_vendor_config('SECURITY') then
        ESTAT.stat_action('umid_sdkconfig_miss_security', 'umid_err', false, nil)
    end

    UNI.cast(CHANNEL, CAST_INIT_DATA, init_params)

    E.LOG.debug(TAG, "init params >>")
    E.LOG.debug(TAG, init_params)

    local global_config = EGC.get_global_cdn_config()
    if global_config then
        cast_update_vanguard_config(global_config)
    else
        ET.subscribe(ET.gangplank.GLOBAL_CDN_CONFIG_SUCC, global_config_handler)
    end

    ET.subscribe(ET.gangplank.ACQUIRE, acquire_succ_handler)
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)
    ET.subscribe(ET.gangplank.EXIT, gangplank_exit_handler)
    ET.subscribe(ET.config.CONFIG_CHANGED .. '_' .. 'region', region_config_change_handle)

    ET.subscribe(ET.gangplank.SET_PLAYER_INFO, set_player_info_handler)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, player_offline_handler)

    -- 初始化用户隐私信息
    M.init_privacy_info()

    -- 更新umid token
    M.update_umid_token()

    -- callback init success
    cb(true)
end

return M