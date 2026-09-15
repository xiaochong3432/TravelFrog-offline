local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local message = require "ejoysdk_lua.cloud_game.message".create()
local BL = require "ejoysdk_lua.cloud_game.base_logic"
local E = require "ejoysdk_lua.ejoysdk"
local STAT = require "ejoysdk_lua.ejoysdk_stat"
local CSTAT = require "ejoysdk_lua.cloud_game.cloud_stat"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local cloud_config = require "ejoysdk_lua.cloud_game.cloud_config"
local user_info = require "ejoysdk_lua.user_info_manager"
local EM = require "ejoysdk_lua.ejoysdk_module"
local CSM = require "ejoysdk_lua.cloud_game.cloud_connect_statemachine"
local CC = require "ejoysdk_lua.ejoysdk_constants"

local M = {}
local TAG = EM.MODULE.CLOUD_GAME .. "cloud_local_logic"

local activity_foreground_state

local function init_applog()
    E.LOG.debug(TAG, "init_applog begin")
    local uni = require "ejoysdk_lua.vendors.unisdk"
    local sdk_infos = uni.get_sdk_infos()
    local app_config_info = sdk_infos["APPLOG"]
    local app_opt = {}
    if app_config_info and app_config_info.meta then
        app_opt = app_config_info.meta
    end

    local app_log_init_cb = function(succ)
        E.LOG.debug(TAG, "init_applog app init result:" .. tostring(succ))
    end
    message:invoke_remote(nil, "vendors.applog", "init", {app_opt, app_log_init_cb})
end

function M.init_remote_modules()
    -- 初始化云端applog
    init_applog()
end

function M.on_remote_init_succ()
    E.LOG.debug(TAG, "remote init succ, now do local logics")
    M.init_remote_modules()
end

--通知云端移动端初始化完成
function M.notify_remote_local_device_info()
    local cb = function(data)
        E.LOG.debug(TAG, 'notify local device info to remote ' .. tostring(data))
        local msg_content = {
            type = 'device_info',
            content = data
        }
        local error_handler = {
            cb = function(code, msg)
                E.LOG.debug(TAG, "invoke remote logic receive message error code >> " .. code .. ", msg >> " .. msg)
            end
        }
        message:invoke_remote(error_handler, "cloud_game.cloud_remote_logic", "receive_message", {msg_content})
    end
    E.LOG.debug(TAG, 'get device info then sync to remote >>  ')
    user_info.get_device_info_async(cb)
end

local INJECT_METHODS = {
    ["ejoysdk_lua.ejoysdk_gangplank"] = {
        ["logout"] = function(origin_method, ...)
            -- call origin method
            origin_method(...)
            --
            E.LOG.debug(TAG, "start call remote logout")
            message:invoke_remote(nil, "ejoysdk_gangplank", "logout", {...})
        end,
        ["open_user_center"] = function(_origin_method, ...)
            E.LOG.debug(TAG, "start call open_user_center")
            -- call origin method
            _origin_method(...)

            -- stat cloud_request_mini_client_usercenter_page_success
            STAT.stat_action("cloud_request_mini_client_usercenter_page_success")
        end
    },
    ["ejoysdk_lua.vendors.aligames"] = {
        ["show_user_center"] = function(_origin_method, ...)
            E.LOG.debug(TAG, "aligames user_center show call begin")
            -- call origin method
            _origin_method(...)

            -- 打开本地用户中心成功
            -- stat cloud_request_mini_client_usercenter_page_success
            STAT.stat_action("cloud_request_mini_client_usercenter_page_success")
        end
    },
    ["ejoysdk_lua.user_info_manager"] = {
        ["get_device_info_async"] = function(_origin_method, ...)
            E.LOG.debug(TAG, "receive remote call local device_info")
            -- call origin method
            _origin_method(...)

            -- 首个握手代表云端初始化完成
            M.on_remote_init_succ()
        end
    }
}

local login_handler = function()
    E.LOG.debug(TAG, "login_handler, receive login from remote")
    ET.publish(ET.analytics.LOGIN, EG.user_info())
end

local activity_state_change_handler = function(state_info)
    local state = ''
    if state_info then
        state = state_info.state or ''
    end

    activity_foreground_state = state
    E.LOG.debug(TAG, "receive activity_state_change_handler:" .. tostring(state))
    message:invoke_remote(nil, "ejoysdk_topic", "publish", {cloud_config.CLOUD_TOPIC.TOPIC_ACTIVITY_STATE_CHANGED, state})
end

-- 语言配置变化监听器
local function lang_config_changed(value)
    E.LOG.debug(TAG, "received lang_config_changed:" .. tostring(value))

    local ejoy_lang = require "ejoysdk_lua.ejoysdk_lang"
    ejoy_lang.set(value)
end

function M.init_message()
    E.LOG.debug(TAG, "begin init_message")
    -- hook methods
    BL.inject_methods(INJECT_METHODS)

    local gp_listener = EG.get_listener()

    gp_listener.exit_listener = function(...)
        local succ = ...
        E.LOG.debug(TAG, "exit_listener succ:" .. tostring(succ))
        if succ then
            E.LOG.debug(TAG, "exit, invoke_remote ejoysdk_topic publish ET.gangplank.EXIT")
            message:invoke_remote(nil, "ejoysdk_topic", "publish", {ET.gangplank.EXIT})

            -- exit self
            local cloud_adapter = require "ejoysdk_lua.cloud_game.cloud_adapter"
            -- 在native接入的情况下，这里是退出云游， 不杀掉进程， ps 当前已经在Native云游壳插件拦截返回键，不会走到exit回调
            cloud_adapter.exit_app()
        else
            E.LOG.debug(TAG, "exit cancelled")
        end

    end

    EG.set_listener(gp_listener)

    E.LOG.debug(TAG, "init_message register_handle >>")
    --本地请求后需要返回给远端
    message:rpc_register_handle(
        "acquire_token",
        function(_error_response, response, ...)
            -- 如果云游界面不显示， 则不弹出登录
            local listener = EG.get_listener()
            local origin_acquire_listener = listener.acquire_listener

            if CSM.is_connect_pause() then
                E.LOG.debug(TAG, 'cloud connect state is pause, do not require')
                origin_acquire_listener(false, CC.GANGPLANK_ERROR_CODE.GANGPLANK_ACQ_FAIL_WITH_STOP_STATE, "acquire not complete in pause state", {})
                response(nil, false, CC.GANGPLANK_ERROR_CODE.GANGPLANK_ACQ_FAIL_WITH_STOP_STATE, "acquire not complete in pause state", {})
                return
            end

            if activity_foreground_state == 'onStop' then
                E.LOG.warn(TAG, "acquire received in stop state, now return failed")
                origin_acquire_listener(false, CC.GANGPLANK_ERROR_CODE.GANGPLANK_ACQ_FAIL_WITH_STOP_STATE, "acquire not complete in stop state", {})
                response(nil, false, CC.GANGPLANK_ERROR_CODE.GANGPLANK_ACQ_FAIL_WITH_STOP_STATE, "acquire not complete in stop state", {})
                return
            end

            E.LOG.debug(TAG, "set the cloud require listener")
            listener.acquire_listener =  function(succ, ...)
                local uinfo = EG.user_info()
                response(uinfo, succ, ...)

                -- 在连接云端的情况下本地登陆结果
                if succ then
                    E.LOG.debug(TAG, "send response succ to remote")
                    STAT.stat_action("mini_client_lingxi_login_complete_request_cloud", nil, true)
                else
                    local code, msg = ...
                    E.LOG.warn(TAG, "send response failed to remote, code:" .. tostring(code) .. ", msg:" .. tostring(msg))
                    STAT.stat_action_fail("mini_client_lingxi_login_complete_request_cloud", nil, code, msg)
                end
                -- reset the origin listener
                E.LOG.debug(TAG, "reset the origin listener")
                listener.acquire_listener = origin_acquire_listener
                EG.set_listener(listener)
            end
            EG.set_listener(listener)
            EG.acquire_token(...)

            -- 云端请求移动端登陆
            CSTAT.stat_action("mini_client_recieve_login_frequency")
        end
    )

    -- pay
    message:rpc_register_handle(
        "pay",
        function(_error_response, response, ...)
            if CSM.is_connect_pause() then
                E.LOG.debug(TAG, 'cloud connect state is pause, do not pay')
                return
            end
            local listener = EG.get_listener()
            local origin_pay_listener = listener.pay_listener
            E.LOG.debug(TAG,"[cloud game] pay ")
            E.LOG.debug(TAG, "set the cloud pay listener")
            listener.pay_listener = function(...)
                E.LOG.debug(TAG,"[cloud game] pay_listener ")
                response(...)
                -- reset the origin listener
                E.LOG.debug(TAG, "reset the origin listener")
                listener.pay_listener = origin_pay_listener
                EG.set_listener(listener)
            end

            -- iOS这次要支持支付了
            --if _ejoysdk.os() == "ios" then
            --    E.Modal.open('提示',{ message = "云游戏testflight测试期间暂不支持支付~敬请期待正式版上线。" }, nil)
            --
            --    CSTAT.stat_action("cloud_request_mini_client_pay_intercept", nil, true)
            --
            --    return -- iOS云游暂时不支持支付
            --end
            EG.set_listener(listener)
            EG.pay(...)
        end
    )

    -- 监听登陆成功
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(cloud_config.CLOUD_TOPIC.TOPIC_ACTIVITY_STATE_CHANGED_INNER, activity_state_change_handler)
    ET.subscribe(ET.config.CONFIG_CHANGED .. '_' .. 'lang', lang_config_changed)
end

---@return CloudMsg
function M.get_msg()
    return message
end

function M.init_sdk()
end

return M
