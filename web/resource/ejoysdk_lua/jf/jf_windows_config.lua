--经分配置项
local M = {}

--经分事件
M.EVENT_NAMES = {
    --端启动
    SDK_START_UP = "sdk.startup",
    --端启动成功
    SDK_START_UP_SUCCESS = "sdk.startup.success",
    --安装事件
    SDK_INSTALL = "sdk.install",
    --心跳
    SDK_HEARTBEAT = "sdk.heartbeat"
}

--默认事件白名单
local default_white_event_prefix_arr = { "game.", "client.", "sdk." }
--额外设置的事件白名单
local ext_white_event_prefix_arr = {}
--事件黑名单
local black_event_config = {}
--windows投放事件
local jf_media_event_aar = M.EVENT_NAMES
--隐私白名单字段
local white_privacy_fields = {}
--经分上报api
local jf_api_server = 'http://abcsdk-log.aligames.com/client/'

function M.init(params)
    ext_white_event_prefix_arr = params.white_event_prefix_arr or ext_white_event_prefix_arr
    black_event_config = params.black_event_arr or black_event_config
    white_privacy_fields = params.white_privacy_fields or white_privacy_fields
    jf_api_server = params.api_server or jf_api_server
end

function M.get_default_white_event_prefix_arr()
    return default_white_event_prefix_arr
end

function M.get_ext_white_event_prefix_arr()
    return ext_white_event_prefix_arr
end

function M.get_black_event_config()
    return black_event_config
end

function M.get_media_event_arr()
    return jf_media_event_aar
end

function M.get_white_privacy_fields()
    return white_privacy_fields
end

function M.get_api_server()
    return jf_api_server
end

--更新jf_api_server
function M.update_config(params)
    if params and params.api_server then
        jf_api_server = params.api_server
    end
end

return M