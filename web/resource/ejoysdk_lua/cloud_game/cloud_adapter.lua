local CG = require "ejoysdk_lua.vendors.cloud_game"
local E = require "ejoysdk_lua.ejoysdk"
local download_utils = require "ejoysdk_lua.cloud_game.download_utils"
local cloud_config = require "ejoysdk_lua.cloud_game.cloud_config"
local stat = require "ejoysdk_lua.ejoysdk_stat"
local ELU = require "ejoysdk_lua.lang.util"
local EM = require "ejoysdk_lua.ejoysdk_module"
local cloud_floater = require "ejoysdk_lua.cloud_game.cloud_ui.cloud_floater"
local CIPM = require 'ejoysdk_lua.cloud_game.cloud_install_pkg_manager'

local M = {}
local TAG = EM.MODULE.CLOUD_GAME .. "cloud_adapter"

local change_to_local = false
local function get_cloud_start_config()
    local start_config
    if cloud_config.DEBUG_OPTIONS.cloudStartWithIpEnabled then
        start_config =
            CG.get_remote_config(
            CG.START_MODE.MODE_IP_PORT,
            cloud_config.DEBUG_OPTIONS.TestCloudServerIP,
            cloud_config.DEBUG_OPTIONS.TestCloudServerPort
        )
    else
        start_config = CG.get_remote_config(CG.START_MODE.MODE_AUTO_SCHEDULE)
    end

    E.LOG.debug(TAG, "get_cloud_start_config >>")
    E.LOG.debug(TAG, start_config)
    return start_config
end

--启动云游戏
function M.run_cloud_game(cb, ex_params)
    E.LOG.debug(TAG, "[cloud game] run_cloud_game")

    --_ejoysdk.log("start_game result >>>>>>>>>>>>>>>>> 1")
    --if true then
    --    _ejoysdk.log("start_game result >>>>>>>>>>>>>>>>> 2")
    --    cb(false, 123, "test run cloud error")
    --    return
    --end

    local remote_config = get_cloud_start_config()
    CG.start_game(
        remote_config,
        function(succ, ...)
            if succ then
                E.LOG.debug(TAG, "run_cloud_game succ")
                cb(true)
            else
                local code, msg = ...
                E.LOG.warn(TAG, "run_cloud_game failed, code: " .. tostring(code) .. ", msg:" .. tostring(msg))
                cb(false, ...)
            end
        end,
        ex_params
    )
end

function M.stop_cloud_game(cb)
    local cg = require "ejoysdk_lua.vendors.cloud_game"
    cg.stop_game(
        function(succ, ...)
            E.LOG.debug(TAG, "stop_cloud_game " .. tostring(succ))
            if cb then
                cb(succ, ...)
            end
        end
    )
end

--启动本地游戏
function M.run_local_game()
    E.LOG.debug(TAG, "[cloud game] run_local_game")
    --避免重复切换
    if change_to_local then
        E.LOG.debug(TAG, "[cloud game] change_to_local already true, return")
        return
    end
    change_to_local = true
    E.Toast.hide()
    M.set_cloud_visibility(false)
    M.set_floater_visibility(false)
    download_utils.set_finish_down_assets()
    CG.start_game_activity()

    -- update cloud run mode is with local resource
    local cloud_mgr = require "ejoysdk_lua.cloud_game.cloud_manager"
    local cstat = require "ejoysdk_lua.cloud_game.cloud_stat"
    -- 启动打点
    cloud_mgr.set_mobile_run_mode(cstat.MOBILE_RUN_MODE.MODE_RUN_WITH_LOCAL_RES)
    cstat.mini_start_begin()
end

--启动本地安装的大包
function M.start_installed_local_game()
    E.LOG.debug(TAG, "[cloud game] start installed local game")

    -- update cloud run mode is with local resource
    --local cloud_mgr = require "ejoysdk_lua.cloud_game.cloud_manager"
    local cstat = require "ejoysdk_lua.cloud_game.cloud_stat"
    -- 启动打点， 在下载安装包这种场景，不需要切云游模式
    --cloud_mgr.set_mobile_run_mode(cstat.MOBILE_RUN_MODE.MODE_RUN_WITH_LOCAL_RES)
    cstat.mini_start_begin()
    CIPM.run_local_game()
end

--下载完打开切换本地按钮
function M.open_change_to_local_dialog()
    CG.show_start_game_activity_entrace(
        function(succ)
            if succ then
                E.LOG.debug(TAG, "open_change_to_local_dialog click start game activity")
                M.cloud_stat_action("label_click_reload_button")
                M.run_local_game()
            else
                E.LOG.warn(TAG, "open_change_to_local_dialog failed")
            end
        end
    )

    --取消进度条窗口
    M.set_download_progress(0, 0, "")
end

--获取硬盘空间
function M.get_disk_capacity(cb)
    E.LOG.debug(TAG, "[cloud game] request_disk_capacity")
    local storage = E.Sysinfo.storage()
    E.LOG.debug(TAG, string.format("[cloud game] get_disk_capacity %.2f", storage.availableInternalStorage / 1024 / 1024))

    --测试没有空间
    if cloud_config.DEBUG_OPTIONS.Debug and download_utils.is_file_exist(cloud_config.DEBUG_OPTIONS.TestNoStorageFile) then
        storage.availableInternalStorage = 0
    end

    cb(storage.availableInternalStorage)
end

function M.is_network_available()
    return E.Sysinfo.network_type() ~= 0
end

function M.cloud_stat_action(action, action_type, result, params)
    E.LOG.debug(TAG, "[cloud_stat_action] " .. tostring(action) .. " " .. tostring(action_type or "nil"))
    -- 云游的日志统一都改为立即上传
    params = params or {}
    params[stat.STAT_KEY.IS_PRIORITY_HIGH] = true
    stat.stat_action(action, action_type, result, params)
end

function M.cloud_stat_action_upload(action, action_type, result, params)
    params = params or {}
    params[stat.STAT_KEY.IS_PRIORITY_HIGH] = true
    M.cloud_stat_action(action, action_type, result, params)
end

function M.cloud_stat_action_fail(action, action_type, code, msg)
    E.LOG.debug(TAG,
        "[cloud_stat_action] " ..
            tostring(action) .. " " .. tostring(action_type or "nil") .. ", code:" .. tostring(code) .. ", msg:" .. tostring(msg)
    )
    stat.stat_action_fail(action, action_type, code, msg)
end

function M.cloud_stat_action_fail_upload(action, action_type, code, msg)
    E.LOG.debug(TAG,
        "[cloud_stat_action] " ..
            tostring(action) .. " " .. tostring(action_type or "nil") .. ", code:" .. tostring(code) .. ", msg:" .. tostring(msg)
    )
    local params = {
        code = code,
        msg = msg,
        [stat.STAT_KEY.IS_PRIORITY_HIGH] = true
    }
    stat.stat_action_fail(action, action_type, params)
end

function M.is_mobile_network()
    --测试移动网络
    if
        cloud_config.DEBUG_OPTIONS.Debug and
            download_utils.is_file_exist(cloud_config.DEBUG_OPTIONS.TestMobileNetworkFile)
     then
        return true
    end

    local type = E.Sysinfo.network_type()
    return type == 2 or type == 3
end

function M.exit_app()
    local cg = require "ejoysdk_lua.vendors.cloud_game"
    cg.exit_game()
end

function M.exit_cloud_game_app()
    local cg = require "ejoysdk_lua.vendors.cloud_game"
    cg.exit_cloud_game_app()
end

function M.close_cloud_game_view(params, cb)
    CG.close_cloud_game_view(params, cb)
end

--只显示一次
local is_record_download_progress_flg = false
local is_show_download_complete_tips_flg = false

-- 设置当前下载进度
function M.set_download_progress(total_size, downloading_size, text)
    local params = {
        ["total_download_size"] = total_size,
        ["downloading_size"] = downloading_size,
    }

    local percent = 0
    if total_size > 0 then
        percent = math.floor(downloading_size / total_size * 100)
    end

    E.LOG.debug(TAG, "current download progress >> " .. tostring(percent))

    M.notify_download_progress(params, percent, text)
end

-- 将原来的set_download_progress方法拆分一下，方便外部直接传 percent进来
function M.notify_download_progress(params, percent, text)
    params["alpha"] = 128
    if text then
        params["text"] = text
    elseif percent >= cloud_config.ShowProgressByPercent then
        local ui_text = require "ejoysdk_lua.cloud_game.cloud_ui.cloud_text_normal"
        params["text"] = string.format(ELU.getString(ui_text.DownloadProgress.text), percent)

        --只显示一次
        if not is_record_download_progress_flg then
            M.cloud_stat_action("download_progress_float_windows")
            is_record_download_progress_flg = true
        end
    end

    CG.cloud_sync_call("SYNC_SET_DOWNLOAD_PROGRESS", params)

    if percent >= cloud_config.ShowDownloadCompleteTipsPercent then
        if not is_show_download_complete_tips_flg then
            is_show_download_complete_tips_flg = true
            cloud_floater.show_download_complete_coming(5)

            -- stat show 95 percent tips
            local CSTAT = require "ejoysdk_lua.cloud_game.cloud_stat"
            CSTAT.stat_action("mini_client_progress_95_tips")
        end
    end

end

-- 传bool值，已下载大包完成传true，否则传false
function M.refresh_app_download_state(is_downloaded)
    E.LOG.debug(TAG, 'refresh app download state >> ' .. tostring(is_downloaded))
    CG.refresh_app_download_state(is_downloaded)
end

function M.set_retry_connected_tip(text)
    local params = {
        ["text"] = text
    }
    CG.cloud_sync_call("SYNC_CLOUD_RETRY_CONNECTED", params)
end

function M.set_cloud_visibility(visible)
    local params = {
        ["visibility"] = visible
    }
    E.LOG.debug(TAG, "[cloud game] set_cloud_visibility " .. tostring(visible))
    CG.cloud_sync_call("SYNC_SET_CLOUD_VISIBILITY", params)
end

function M.set_floater_visibility(visible)
    if visible then
        cloud_floater.show_floater()
    else
        cloud_floater.hide_floater()
    end
end


function M.set_cloud_coutdown(text, time)
    local params = {
        ["text"] = text,
        ["time"] = time
    }
    CG.cloud_sync_call("SYNC_CLOUD_COUNTDOWN", params)
end

-- 发送消息
function M.send_data(json_str, cb, msg_id)
    E.LOG.debug(TAG, "send_data: " .. tostring(json_str))
    CG.send_msg(
        json_str,
        function(succ, ...)
            if succ then
                E.LOG.debug(TAG, "send_data succ")
            else
                local code, msg = ...
                E.LOG.warn(TAG, "send_data failed, code: " .. tostring(code) .. ", msg:" .. tostring(msg))
            end

            if cb then
                cb(succ, ...)
            end
        end,
        msg_id
    )
end

function M.get_cloud_mode()
    local cm = require "ejoysdk_lua.cloud_game.cloud_manager"
    local mode = CG.get_cloud_mode()
    -- map mode
    if mode then
        if mode == CG.CLOUD_MODE.CLOUD then
            mode = cm.CLOUD_MODE.MODE_CLOUD
        else
            mode = cm.CLOUD_MODE.MODE_MOBILE
        end
    else
        mode = cm.CLOUD_MODE.MODE_UNKNOWN
    end

    E.LOG.debug(TAG, "get_cloud_mode in adapter, mode:" .. tostring(mode))
    return mode
end

function M.get_play_config()
    return CG.get_current_play_config()
end

function M.show_tips(msg)
    CG.show_tips(msg)
end

function M.hide_tips()
    CG.hide_tips()
end

function M.show_input_method(cb, params)
    CG.show_input_method(cb, params)
end

function M.clip_plain_text(label, text)
    CG.clip_plain_text(label, text)
end

function M.get_server_config_data()
    return CG.get_server_config_data()
end

function M.request_cloud_server_config(cb)
    CG.request_cloud_server_config(cb)
end

function M.request_cloud_static_config(cb)
    CG.request_cloud_static_config(cb)
end

-- 监听配置中心下发成功
function M.observer_cloud_static_config_refresh(cb)
    CG.observer_cloud_static_config_refresh(cb)
end

function M.get_cloud_static_config()
    return CG.get_cloud_static_config()
end

function M.get_cloud_server_config()
    E.LOG.debug(TAG, "get_cloud_config begin")
    return CG.get_cloud_server_config()
end

function M.get_cloud_env()
    return CG.get_cloud_env()
end

function M.check_game_file_valid(params, cb)
    CG.check_game_file_valid(params, cb)
end

function M.get_config_game_res_info()
    return CG.get_config_game_res_info()
end

function M.resume_game()
    CG.resume_game()
    M.set_floater_visibility(true)
end

function M.get_min_download_speed()
    return CG.get_min_download_speed()
end

function M.set_cloud_game_visibility_change_listener(listener)
    CG.set_cloud_game_visibility_change_listener(listener)
end

function M.set_get_current_download_speed_listener(listener)
    CG.set_get_current_download_speed_listener(listener)
end

function M.show_loading()
    CG.show_loading()
end

function M.hide_loading()
    CG.hide_loading()
end

function M.set_mobile_run_mode(mode)
    CG.set_mobile_run_mode(mode)
end

return M
