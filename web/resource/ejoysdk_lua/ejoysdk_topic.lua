local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'topic'

local M = {}

M.gangplank = {
    INITSTART = 'gangplank_initstart',
    INITED = 'gangplank_inited',
    ACQUIRE = 'acquire',
    USER_INFO_CHANGED = "gp_user_info_changed",
    ACQUIRE_FAILED = 'acquire_failed',
    AUTH_SUCC = 'auth_succ', -- 授权登录成功
    LOGIN_INVOKE = 'login_invoke', -- 登录调用,
    LOGIN = 'login', -- 登录成功
    LOGIN_FAILED = 'login_failed', -- 登录失败
    SCAN_LOGIN = 'scan_login', -- 扫码登陆成功
    SCAN_QUERY_FINISH = "qrcode_scan_query_finish",
    PAY_INVOKE = 'pay_invoke', -- 支付调用,
    PAY = 'pay_success', -- 支付成功
    PAY_FAILED = 'pay_failed', -- 支付失败
    SET_PLAYER_INFO = 'set_player_info',
    SET_PLAYER_INFO_WITH_TYPE = 'set_player_info_with_type',
    PLAYER_ONLINE = 'player_online',
    PLAYER_OFFLINE = 'player_offline',
    LOGOUT = 'logout', -- 注销成功
    EXIT = 'exit',
    GLOBAL_CDN_CONFIG_SUCC = 'global_cdn_config_succ',
    VENDOR_LOGIN_BEGIN = "ejoysdk_vendor_login_begin",
    VENDOR_LOGIN_END = "ejoysdk_vendor_login_end",
    USER_INFO_UPDATE = "user_info_update",
    NETWORK_STATE_CHANGE = "network_state_change"
}

M.holo = {
    INITED = 'holo_inited',
    GET_PLAYER_TOKEN = 'get_player_token',
    GET_PLAYER_TOKEN_FAIL = 'get_player_token_fail',
    CLEAR_PLAYER_TOKEN = 'holo_clear_player_token'
}

M.launcher = {
    INITED = 'launcher_inited'
}

M.friend = {
    INITED = 'friend_inited'
}

M.favor = {
    INITED = 'favor_inited'
}

M.chat = {
    INITED = 'chat_inited',
    UPDATE_STATE = 'chat_update_state'
}

M.account_chat = {
    OPEN = 'account_chat_open'
}

M.push = {
    INITED = 'push_inited'
}

M.player = {
    INITED = 'player_inited'
}

M.analytics = {
    REGISTER = 'analytics_register',
    LOGIN = 'analytics_login',
    CREATE_ORDER = 'analytics_create_order',
    PURCHASE_SUCC = 'analytics_purchase_succ',
    EXIT = 'analytics_exit'
}

M.block = {
    INITED = 'block_inited'
}

M.age = {
    INITED = 'age_inited'
}

M.config = {
    CONFIG_CHANGED = 'ejoysdk_config_changed'
}

M.user_center = {
    USER_CENTER_INIT_SUCCESS = "user_center_init_success"
}

M.aligames = {
    SYSTEM_DEVICE_INIT = "aligames_system_device_init"
}

M.config_center = {
    DATA_INITED = 'config_center_data_init'
}

M.live_floater = {
    ON_CHANGED = 'live_floater_on_changed'
}

M.download = {
    DOWNLOAD_STATE_CHANGED = "ejoy_download_state_changed",
    DOWNLOAD_PROGRESS_CHANGED = "ejoy_download_progress_changed",
    DOWNLOAD_MULTI_TASK_STATE_CHANGED = "ejoy_dl_multi_task_state_changed",
    DOWNLOAD_MULTI_TASK_DOWNLOAD_SPEED_CHANGED = "ejoy_dl_multi_task_speed_changed",
    DOWNLOAD_MULTI_TASK_DOWNLOAD_PROGRESS_CHANGED = "ejoy_dl_multi_task_progress_changed",
    DOWNLOAD_EVENT_SUBMIT = "download_event_submit"
}

M.qz_startup_update = {
    QZ_STARTUP_UPDATE_STATE_CHANGED = "qz_startup_update_state_changed"
}

M.lightboat = {
    INITED = 'lightboat_inited'
}

local dispatcher = {}

function M.subscribe(topic, cb)
    local handlers = dispatcher[topic]
    if not handlers then
        handlers = {}
        dispatcher[topic] = handlers
    end

    for _, handler in ipairs(handlers) do
        if handler == cb then
            return
        end
    end
    handlers[#handlers + 1] = cb
end

function M.unsubscribe(topic, cb)
    local handlers = dispatcher[topic]
    if handlers then
        local new = {}
        for _, handler in ipairs(handlers) do
            if cb ~= handler then
                new[#new + 1] = handler
            end
        end
        dispatcher[topic] = new
    end
end

function M.publish(topic, ...)
    local handlers = dispatcher[topic]
    if handlers then
        for _, cb in ipairs(handlers) do
            local succ, err = pcall(cb, ...)
            if not succ then
                _ejoysdk.log( TAG ..  'error topic ' .. tostring(topic) .. ': ' .. tostring(err))
            end
        end
    end
end

return M
