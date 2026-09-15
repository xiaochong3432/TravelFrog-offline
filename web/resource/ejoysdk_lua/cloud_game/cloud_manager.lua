local remote_logic = require "ejoysdk_lua.cloud_game.cloud_remote_logic"
local local_logic = require "ejoysdk_lua.cloud_game.cloud_local_logic"
local cloud_adapter = require "ejoysdk_lua.cloud_game.cloud_adapter"
local cloud_ui = require "ejoysdk_lua.cloud_game.cloud_ui"
local ui_text = require "ejoysdk_lua.cloud_game.cloud_ui.cloud_text_normal"
local download_utils = require "ejoysdk_lua.cloud_game.download_utils"
local cloud_config = require "ejoysdk_lua.cloud_game.cloud_config"
local E = require "ejoysdk_lua.ejoysdk"
local CSTAT = require "ejoysdk_lua.cloud_game.cloud_stat"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local CG = require "ejoysdk_lua.vendors.cloud_game"
local ELU = require "ejoysdk_lua.lang.util"
local EM = require "ejoysdk_lua.ejoysdk_module"
local CSM = require "ejoysdk_lua.cloud_game.cloud_state_manager"
local free_data = require "ejoysdk_lua.cloud_game.cloud_free_data_pkg"

local M = {}
local TAG = EM.MODULE.CLOUD_GAME .. "cloud_mgr"

M.CLOUD_MODE = {
    MODE_CLOUD = cloud_config.CLOUD_MODE.CLOUD,
    MODE_MOBILE = cloud_config.CLOUD_MODE.MOBILE,
    MODE_UNKNOWN = cloud_config.CLOUD_MODE.UNKNOWN
}

local data = {
    product = nil,
    logic = nil,
    is_cloud_remote = false,
    retry_down_cnt = 0,
    cg_error_obj_cache = nil,
    cg_visibility = false,
    is_record_splash_time = false,
    splash_time_begin = 0
}

local cloud_info = {}

local cloud_mode = nil
--local mobile_run_mode = nil
local restrict_state = {}

local init_tag = false

local is_show_close_bluetooth_tips = false

local function get_native_result(succ, ...)
    local result = {}
    if succ then
        result.result = true
        result.code = 200
    else
        local code, msg, body = ...
        result.result = false
        result.code = code
        result.msg = msg
        result.body = body
    end

    return result
end

--[[
cloud_run_mode分4种：连接云端玩游戏-MODE_RUN_CONNECT_REMOTE，运行在移动端本地资源-MODE_RUN_WITH_LOCAL_RES，在云端运行-MODE_RUN_IN_CLOUD_SIDE，普通游戏内-MODE_NORMAL_GAME

MODE_RUN_WITH_LOCAL_RES：
1. 云试玩&云微端：
a. 切大包场景设置该标记，即在cloud_biz_download_statemachine.lua的GAME_RES_READY状态时，且确定切本地包操作的情况下设置，这里的切换是cloud_game_facade的start_game_activity里处理(该方法有多个外部调用，需要再次检查是否下载完成)
b. 云试玩关闭时的下载状态是完成
2. 云微端：自有的切大包方法，cloud_adapter.run_local_game()

MODE_RUN_CONNECT_REMOTE & MODE_NORMAL_GAME
1. 云试玩：
 a. 限于打开和关闭场景。MODE_RUN_CONNECT_REMOTE：在cloud_game_facade的start_cloud_game的成功回调，MODE_NORMAL_GAME：在cloud_game_facade的 close_cloud_game_view 和 start_cloud_game的失败回调
 b. 正常启动（下载是禁用，且游戏没有打开云试玩的场景）默认为 MODE_NORMAL_GAME
 c. 云试玩关闭时如果下载状态是未完成则是 MODE_NORMAL_GAME
2. 云微端：启动检查完资源切换到边下边玩状态：cloud_biz_download_statemacine 的 DOWNLOAD_WITH_PLAY，设置 MODE_RUN_CONNECT_REMOTE，其它为 nil。
3. 常规游戏包: 走默认逻辑为 MODE_NORMAL_GAME
3. 仅云游：此时无下载，直接在cloud_state_manager.init的时候设置为 MODE_RUN_CONNECT_REMOTE

MODE_RUN_IN_CLOUD_SIDE：
1. 云端包：在init_mode时设置

--]]
function M.set_mobile_run_mode(mode)
    -- update cloud info
    local UIM = require "ejoysdk_lua.user_info_manager"
    cloud_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_RUN_MODE] = mode
    UIM.set_cloud_game_info(cloud_info)

    CSTAT.set_mobile_run_mode(mode)

    -- 云游业务依赖处理
    cloud_adapter.set_mobile_run_mode(mode)
end

function M.get_mobile_run_mode()
    return CSTAT.get_mobile_run_mode()
end

function M._connect_cloud_sucess()
    --记录闪屏时间
    if not data.is_record_splash_time then
        local splash_time = os.time() - data.splash_time_begin
        -- 闪屏结束
        local stat_params = {
            ["is_priority_high"] = true
        }
        CSTAT.stat_action("mini_client_splash_time", tostring(splash_time), true, stat_params)
        data.is_record_splash_time = true
    end
    cloud_adapter.set_retry_connected_tip("")
    cloud_adapter.set_cloud_visibility(true)
    cloud_ui.set_is_retry_connecting(false)
    cloud_ui.reset_error_ui_state()
end

function M._retry_connect_cloud(cb, last_err_code)
    if cloud_ui.get_is_retry_connecting() then
        return
    end
    CG.set_relink()
    cloud_ui.set_is_retry_connecting(true)
    cloud_ui.reconnect()

    local connect_time_begin = os.time()
    --倒计时
    local request_time_out = 10
    local request_interval = 4
    --下次请求时间
    local request_time = request_time_out - request_interval
    local retry_cnt = 0
    local finish = false
    local run_fail_code = last_err_code
    local request_connect_cloud = function()
        if finish then
            return
        end
        E.LOG.debug(TAG, "[cloud game] start_cloud_game retry " .. tostring(retry_cnt))
        retry_cnt = retry_cnt + 1
        --服务端发送尝试重连次数
        cloud_adapter.cloud_stat_action("server_send_relink_actual_frequency")
        cloud_adapter.run_cloud_game(
            function(succ2, ...)
                E.LOG.debug(TAG, "[cloud game] start_cloud_game retry result " .. tostring(succ2))
                if succ2 then
                    finish = true
                    cloud_adapter.cloud_stat_action("click_relink_enter_game_success")
                    cb(succ2, ...)
                else
                    run_fail_code = ...
                end
            end
        )
    end
    request_connect_cloud()

    local update_time_fun
    update_time_fun = function()
        local time_left = request_time_out - math.ceil(os.time() - connect_time_begin)
        if time_left < 1 then
            time_left = 0
        end
        E.LOG.debug(TAG, "[cloud game] -------cancel_update_time=" .. tostring(time_left))
        cloud_adapter.set_retry_connected_tip(string.format(ELU.getString(ui_text.RetryConnect.text), time_left))
        --结束了
        if not cloud_ui.get_is_retry_connecting() or finish or time_left <= 0 then
            --超时结束了，需要调用cb(false)
            if not finish then
                cb(false, run_fail_code)
                cloud_ui.check_and_show_error()
                E.LOG.debug(TAG, "[cloud game] -------超时没有连接成功")
            end
            finish = true
            cloud_ui.set_is_retry_connecting(false)
            cloud_adapter.set_retry_connected_tip("")
            return
        end

        --间隔一定时间重连，避免请求过于频繁
        if request_time >= time_left then
            request_time = time_left - request_interval
            request_connect_cloud()
        end

        E.Timer.once(
            1,
            function()
                update_time_fun()
            end
        )
    end

    --尝试重连页面弹窗
    cloud_adapter.cloud_stat_action("click_relink_page")
    update_time_fun()
end

-- 初始化云游相关rpc模块
function M._init_cloud_rpc(is_cloud, msg_logic)
    local message = msg_logic.get_msg()
    local cloud_input_rpc = require "ejoysdk_lua.cloud_game.cloud_input_rpc"
    cloud_input_rpc.init(is_cloud, message)
end

function M._run_test()
    if not cloud_config.DEBUG_OPTIONS.Debug then
        return
    end
    --测试
    if cloud_config.DEBUG_OPTIONS.TestCloudTimeLimit then
        E.Timer.once(
            cloud_config.DEBUG_OPTIONS.TestCloudTimeLimit,
            function()
                cloud_ui.show_stop_cloud_game_by_server()
            end
        )
    end
    local check_cg_error
    check_cg_error = function()
        E.Timer.once(
            3,
            function()
                --模拟云cg失败
                if download_utils.is_file_exist(cloud_config.DEBUG_OPTIONS.TestCloudCGErrorFile) then
                    os.remove(download_utils.download_folder .. cloud_config.DEBUG_OPTIONS.TestCloudCGErrorFile)
                    M.on_cg_error(123, "test")
                end
                check_cg_error()
            end
        )
    end
    check_cg_error()
end

local function check_pending_errors()
    cloud_ui.check_and_show_error()
end

local function _show_download_splash_ui(total_size, downloading_size, cb)
    --没有文件需要下载，则跑本地游戏
    --首次请求下载信息弹ui
    cloud_ui.set_state(cloud_ui.State.FlashScreen)
    --第一时间闪屏
    cloud_ui.set_download_progress(downloading_size, total_size)
    cloud_ui.show_flash_screen()

    cloud_adapter.set_download_progress(total_size, downloading_size)

    local splash_ui_dimiss_listener = function()
        E.LOG.debug(TAG, "splash dismissed, now show peding errors")
        -- 闪屏完后检查其他错误
        check_pending_errors()
        -- 闪屏完后监听网络变化
        cloud_ui.check_mobile_network_change()
    end

    --闪屏完开始下载
    E.Timer.once(
            1,
            function()
                --重新刷新闪屏
                if math.floor(downloading_size / total_size * 100) >= 1 then
                    E.LOG.debug(
                            TAG,
                            "ui_update_flash_screen yes downloading_size = " .. tostring(downloading_size / 1024 / 1024)
                    )
                    cloud_ui.set_download_progress(downloading_size, total_size)
                    cloud_ui.show_flash_screen()
                    cloud_adapter.set_download_progress(total_size, downloading_size)
                end
                cloud_ui.hide_flash_screen(4, function()
                    cloud_ui.set_state(cloud_ui.State.FlashScreenDismiss)
                    -- 闪屏消失后检查
                    splash_ui_dimiss_listener()

                    if cb then
                        -- 回调闪屏消失
                        cb(true)
                    end
                end)
            end
    )
end

-- 连接云端玩游戏
function M.connect_with_remote_game(params, cb)
    -- 设置云游运行模式为本地运行
    CSM.connect_remote(params, function(succ, ...)
        if not succ then
            local code, msg = ...
            E.LOG.warn(TAG, "connect_with_remote_game failed, code:" .. tostring(code) .. ", msg:" .. tostring(msg))
        end

        cb(succ, ...)
    end)
end

function M.stop_connect_with_remote_game(cb)
    CSM.stop_connect_remote({}, function(succ, ...)
        if not succ then
            local code, msg = ...
            E.LOG.warn(TAG, "stop_connect_with_remote_game failed, code:" .. tostring(code) .. ", msg:" .. tostring(msg))
        end

        if cb then
            cb(succ, ...)
        end
    end)
end

function M.run_local_game()
    -- 启动本地
    cloud_adapter.run_local_game()
end

function M.start_installed_local_game()
    -- 启动本地
    cloud_adapter.start_installed_local_game()
end

--初始化，云游戏才需要调用(运行本地模式时不要调用)
function M.init_mode(params, cb)
    cb = cb or function()
        E.LOG.debug(TAG, "[cloud game] -------init_mode cb nil-------")
    end

    if init_tag then
        E.LOG.debug(TAG, "init manager inited, return")
        local result = get_native_result(true)
        cb(result)
        return
    end

    init_tag = true
    local log_config = {is_console = true}
    E.open_log_with_config(log_config)
    E.set_log_level(E.LOG_LEVEL.debug)

    E.LOG.debug(TAG, "[cloud game] -------init_mode -------")
    E.LOG.debug(TAG, params)
    params = params or {}
    cloud_config.init_config(params)
    cloud_mode = cloud_config.CloudGameMode
    local UIM = require "ejoysdk_lua.user_info_manager"
    cloud_info[UIM.PKG_INFO_KEY.KEY_CLOUD_GAME_MODE] = cloud_mode
    UIM.set_cloud_game_info(cloud_info)

    data.is_cloud_remote = false
    if M.CLOUD_MODE.MODE_CLOUD == cloud_mode then
        data.is_cloud_remote = true
    end

    E.LOG.debug(TAG, "init_mode cloud_mode: " .. tostring(cloud_config.CloudGameMode))

    E.LOG.debug(TAG, "init_mode cloud_mode begin:" .. tostring(cloud_mode))
    --运行在云端
    if data.is_cloud_remote then
        E.LOG.debug(TAG, "start remote logic")
        data.logic = remote_logic
        data.logic.init_message()
        M._init_cloud_rpc(true, data.logic)
        local result = get_native_result(true)
        cb(result)
        -- 设置在云端运行模式
        M.set_mobile_run_mode(CSTAT.MOBILE_RUN_MODE.MODE_RUN_IN_CLOUD_SIDE)
    else
        -- 设置在云端运行模式
        M.set_mobile_run_mode(nil)
        E.LOG.debug(TAG, "start local logic")
        data.retry_down_cnt = 0
        data.product = require "ejoysdk_lua.cloud_game.product_adapter"

        E.LOG.debug(TAG, "begin init cloud_state_machine")

        -- 检查是否开启luaprofile
        if cloud_config.DEBUG_OPTIONS.TestEnableLuaProfile then
            E.LOG.debug(TAG, "lua profile enabled, now start lua profile")
            local profile = require "ejoysdk_lua.cloud_game.debug.profile"
            profile.lua_profile_start()
        end

        -- 初始化云游SDK
        CSM.init(function(succ, ...)
            E.LOG.debug(TAG, "start up cloud game succ >> " ..  tostring(succ))
            local result = get_native_result(succ, ...)
            cb(result)
        end)
        -- 初始化免流SDK
        free_data.init()
    end
end

function M.init_local_logic()
    E.LOG.debug(TAG, "init_local_logic begin")
    data.logic = local_logic
    data.logic.init_message()
    M._init_cloud_rpc(false, data.logic)
end

-- 判断错误是不是需要处理，
-- 比如是因为试玩模式没有时间了，需要交给instant处理，-5001 是云游错误码
-- 前缀是5002及其以上的是非云游错误或者SDK错误，抛出去处理
-- 如 当前业务5003是instant试玩的错误码，需要抛出
function M.need_intercept_error(error_code)
    local code = tostring(error_code)
    if code ~= 'nil' and #code > 4 then
        local prefix = string.sub(code, 1, 4)
        local prefix_number = tonumber(prefix)
        if prefix_number then
            return prefix_number < 5002
        end
    end
    return true
end

--接收云消息
function M.receive_data(json_str)
    if data.logic then
        data.logic.get_msg():receive_data(json_str)
    end
end

function M.invoke_remote(error_handle, module, func, params)
    if data.logic then
        E.LOG.debug(TAG, "invoke_remote begin, module:" .. tostring(module) .. ", func:" .. tostring(func))
        data.logic.get_msg():invoke_remote(error_handle, module, func, params)
    else
        E.LOG.warn(TAG, "invoke_remote skip, logic obj is invalid")
    end
end

function M.on_cg_error(err_code, err_msg)
    E.LOG.debug(TAG, "on_cg_error received")
    CSM.on_connect_error(cloud_ui.ErrorType.CloudCGError, err_code, err_msg)
end

local last_update_restrict_time = 0
local function update_retrict_ui()
    if restrict_state and restrict_state.notify_type ~= nil then
        E.LOG.debug(TAG, "update_retrict_ui")
        local current_time = os.time()
        if current_time - last_update_restrict_time >= 1 then
            last_update_restrict_time = current_time
            cloud_ui.show_restrict_ui(restrict_state)
        end
    end
end

function M.on_restrict(restrict_obj)
    restrict_state.last_restrict_time = os.time()
    E.LOG.debug(TAG, "on_restrict >>")
    E.log(restrict_obj)
    if restrict_obj.notify_type then
        restrict_state.notify_type = restrict_obj.notify_type
        restrict_state.msg = restrict_obj.message
        restrict_state.msg_no_download = restrict_obj.message_no_download
        cloud_ui.show_restrict_ui(restrict_state)
        ET.subscribe(cloud_ui.CLOUD_TOPIC.TOPIC_DOWNLOAD_PROGRESS_CHANGED, update_retrict_ui)
    end

    if restrict_obj.game_res_download_limit_kps and restrict_obj.game_res_download_limit_kps > 0 then
        E.LOG.debug(TAG, "on_restrict download limit:" .. tostring(restrict_obj.game_res_download_limit_kps))
        cloud_config.force_http_kps_limit(restrict_obj.game_res_download_limit_kps)
    end
end

-- 云游SDK通知网络状态变化
function M.cloud_network_quality_low()
    E.LOG.debug(TAG, "receive network quality low")
    -- 如果是iOS, 第一次先提示关闭蓝牙
    if not is_show_close_bluetooth_tips and _ejoysdk.os() == 'ios' then
        is_show_close_bluetooth_tips = true
        cloud_ui.show_close_bluetooth_tips()
        return
    end
    -- 如果云游是连接状态，才显示弱网提示
    if CSM.is_cloud_connected() then
        cloud_ui.show_network_quality_low()
    end
end


local function hide_restrict()
    E.LOG.debug(TAG, "recover HttpKpsLimit: " .. tostring(cloud_config.force_http_kps))
    cloud_config.force_http_kps_limit(nil)

    E.LOG.debug(TAG, "hide_restrict begin")
    cloud_ui.hide_restrict_ui(restrict_state)

    restrict_state = {}

    ET.unsubscribe(cloud_ui.CLOUD_TOPIC.TOPIC_DOWNLOAD_PROGRESS_CHANGED, update_retrict_ui)
end

function M.on_remove_restrict()
    local current_time = os.time()
    local last_restrict_time = restrict_state.last_restrict_time or current_time
    local last_show_duration = current_time - last_restrict_time
    if last_show_duration < 2 then
        E.LOG.debug(TAG, "last show not larger than 2 sec, delay remove")
        E.Timer.once(
            2,
            function()
                hide_restrict()
            end
        )

        return
    end

    hide_restrict()
end

-- {@see M.CLOUD_MODE}
function M.get_cloud_mode()
    if cloud_mode then
        E.LOG.debug(TAG, "get_cloud_mode find current cloud_mode cache: " .. tostring(cloud_mode))
        return cloud_mode
    end

    cloud_mode = cloud_adapter.get_cloud_mode()
    E.LOG.debug(TAG, "get_cloud_mode in cloud_adapter: " .. tostring(cloud_mode))
    return cloud_mode
end

-- 返回云游初始化时服务端提供的token信息，包含token, open_id, msg_token
function M.get_server_config_data()
    return cloud_adapter.get_server_config_data()
end

function M.start_cloud_game(cb, ex_params)
    cloud_adapter.run_cloud_game(cb, ex_params)
end

function M.stop_game(cb)
    cloud_adapter.stop_cloud_game(cb)
end

function M.open_full_download()
    E.LOG.debug(TAG, "open_full_download begin")
    CSM.open_full_download()
end

function M.exit_app()
    cloud_adapter.exit_app()
end

-- 完整退出云游app
function M.exit_cloud_game_app()
    cloud_adapter.exit_cloud_game_app()
end

-- 退出云游画面
function M.close_cloud_game_view(params, cb)
    CSM.close_cloud_game_view(params, cb)
end

function M.cloud_view_not_visible()
    cloud_ui.hide_all_ui()
end


function M.disable_download()
    cloud_config.DEBUG_OPTIONS.TestDisableDownload = true
end

function M.is_mobile_network()
    return cloud_adapter.is_mobile_network()
end

function M.is_network_available()
    return cloud_adapter.is_network_available()
end

function M.get_play_config()
    return cloud_adapter.get_play_config() or {}
end

function M.get_product()
    return data.product
end

function M.notify_remote_local_device_info()
    local_logic.notify_remote_local_device_info()
end

function M.register_cloud_state_change_listener(cb)
    CSM.register_cloud_state_change_listener(cb)
end

return M
