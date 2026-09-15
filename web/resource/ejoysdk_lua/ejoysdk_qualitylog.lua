local E = require "ejoysdk_lua.ejoysdk"
local ET  = require "ejoysdk_lua.ejoysdk_topic"
local guuid = require "ejoysdk_lua.ejoysdk_uuid"
local V   = require "ejoysdk_lua.version"
local EU = require "ejoysdk_lua.ejoysdk_uuid"
local EM = require "ejoysdk_lua.ejoysdk_module"
local subscribe = ET.subscribe
local sformat = string.format

local M = {}

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'qualitylog'

--操作定义
M.TRACE_NAMES = {
    INIT =  'init',   --初始化
    LOGIN = 'login',  --登录
    PAY =   'pay',    --支付
    CHAT_CONNECT = 'chat_connect' --聊天连接
}

M.EVENT_NAMES = {
    --端启动
    SDK_START_UP = "sdk.init.invoke",
    --端启动成功
    SDK_START_UP_END = "sdk.init.end",

    --vendor登录开始
    SDK_VENDOR_LOGIN_INVOKE = "sdk.vendorlogin.invoke",
    --vendor登录成功完成
    SDK_VENDOR_LOGIN_END = "sdk.vendorlogin.end",

    --vendor登录开始
    SDK_ACQUIRE_INVOKE = "sdk.acquire.invoke",
    --vendor登录成功完成
    SDK_ACQUIRE_END = "sdk.acquire.end",
    -- acquire结束后的HTTP打点
    SDK_ACQUIRE_HTTP_DATA = "sdk.acquire.http.data",

    -- 注册成功事件
    SDK_REGISTER_SUCC = "sdk.register.succ",

    --登录开始
    SDK_ROLE_LOGIN_INVOKE = "sdk.login.invoke",
    --登录成功完成
    SDK_ROLE_LOGIN_END = "sdk.login.end",

    --支付开始
    SDK_PAY_INVOKE = "sdk.pay.invoke",
    --支付下单
    SDK_PAY_CREATE_ORDER_INVOKE = "sdk.pay.createorder.invoke",
    --支付成功
    SDK_PAY_END = "sdk.pay.end",
    --http开始
    SDK_HTTP_INVOKE = "sdk.http.invoke",
    --http结束
    SDK_HTTP_FINISH = "sdk.http.finish",
    -- 实名制扫码打点
    SDK_REALNAME_QRSCAN = "sdk.realname.qrscan",
    -- socket聊天建连成功率相关打点
    SDK_CHAT_CONNECT = "sdk.chat.connect"
}

--CAST_COMMIT_EVENT
local ql_inited = false
local log_state = {}

--------------基本参数初始化
local make_state_param = function(trace_name)
    M.init()
    local trace_id = string.gsub(guuid(), "-", "")

    local state_params = 
    {
        trace_name = trace_name,
        trace_id = trace_id, 
        start_timestamp = E.system_clock(),
    }
    return state_params
end

local make_base_param = function(state_params)
    local consuming_time = 0
    local trace_id = ""
    --local trace_name = ""
    if state_params then
        --trace_name = state_params.trace_name 
        trace_id = state_params.trace_id
        consuming_time = E.system_clock() - state_params.start_timestamp
    end

    local param = 
    {
        trace_id = trace_id,
        sdk_version = E.get_sdk_version_name('EJOYSDK'), --sdk版本号
        net_type = E.Sysinfo.network_type(), --网络类型
        net_type_name = E.Sysinfo.network_type_name(),
        trace_consuming_time = consuming_time, --操作耗时
        lua_vesion = V.LUA_VERSION,
    }

    return param
end

local function get_start_log_param(trace_name, sub_params)
    local state_params = make_state_param(trace_name)

    if log_state[trace_name] then
        --not finish
        _ejoysdk.log(sformat('trace %s not finish, trace id = %s', trace_name, tostring(state_params.trace_id)))
    end

    log_state[trace_name] = state_params
    local params = make_base_param(state_params)

    params.sub_params = sub_params

    sub_params.trace_consuming_time = params.trace_consuming_time
    params.trace_consuming_time = nil

    sub_params.trace_id = params.trace_id
    params.trace_id = nil

    return params
end

local function get_end_log_param(trace_name, sub_params)
    local state_params = log_state[trace_name] or false
    log_state[trace_name] = nil

    if not state_params then
        _ejoysdk.log(sformat('trace %s not start', trace_name))
    end

    local params = make_base_param(state_params)
    params.sub_params = sub_params

    sub_params.trace_consuming_time = params.trace_consuming_time
    params.trace_consuming_time = nil

    sub_params.trace_id = params.trace_id
    params.trace_id = nil

    return params
end

local function commit_to_apus(event_name, params)
    local ETAPUS = require "ejoysdk_lua.ejoysdk_to_apus"
    ETAPUS.commit_event(event_name, params)
end

local function jf_commit_event(event_name, params, is_upload_now, is_upload_to_apus, is_priority_high)
    if ql_inited then
        local JF  = require 'ejoysdk_lua.vendors.jf'
        local options = {}
        if is_upload_now then
            options = {[JF.OPTION_KEY.IS_UPLOAD_NOW] = true}
        elseif is_priority_high then
            options = {[JF.OPTION_KEY.IS_PRIORITY_HIGH] = true}
        end

        JF.commit_event(event_name, params, options)

        if is_upload_to_apus then
            -- commit to apus
            commit_to_apus(event_name, params and params.sub_params or params)
        end
    end
end

local function jf_commit_action(action, action_type, result, params, is_upload_now, is_upload_to_apus, is_priority_high)
    if not ql_inited then
        E.LOG.warn(TAG, "jf_commit_action skip, ql not initted")
        return
    end

    local commit_params = params and params.sub_params or params or {}
    if is_upload_now then
        commit_params["is_upload_now"] = is_upload_now
    end
    commit_params["is_priority_high"] = is_priority_high or false

    local ESTAT = require "ejoysdk_lua.ejoysdk_stat"
    ESTAT.stat_action(action, action_type, result, commit_params)

    if is_upload_to_apus then
        -- commit to apus
        commit_to_apus("sdk.lua.action", commit_params)
    end
end

local function jf_commit_action_fail(action, action_type, code, msg, params, opts)
    if not ql_inited then
        E.LOG.warn(TAG, "jf_commit_action skip, ql not initted")
        return
    end

    local commit_params = params and params.sub_params or params or {}
    opts = opts or {}
    local is_upload_now = opts.is_upload_now
    local is_upload_to_apus = opts.is_upload_to_apus
    local is_priority_high = opts.is_priority_high or false
    if is_upload_now then
        commit_params["is_upload_now"] = is_upload_now
    end
    if is_priority_high then
        commit_params["is_priority_high"] = is_priority_high
    end

    commit_params.code = code
    commit_params.msg = msg

    local ESTAT = require "ejoysdk_lua.ejoysdk_stat"
    ESTAT.stat_action_fail(action, action_type, commit_params)

    if is_upload_to_apus then
        -- commit to apus
        commit_to_apus("sdk.lua.action", commit_params)
    end
end

--------------初始化操作
local function gangplank_init_start_handler()
    E.LOG.debug(TAG, "set a test action, jf_test_action")
    jf_commit_event(M.EVENT_NAMES.SDK_START_UP, get_start_log_param(M.TRACE_NAMES.INIT, {}), false, true, true)
end

local function gangplank_inited_handler(succ, msg)
    local params = get_end_log_param(M.TRACE_NAMES.INIT,
        {
            success = succ,
            msg = msg,
        }
    )
    jf_commit_event(M.EVENT_NAMES.SDK_START_UP_END, params, false, true, true)
end

--------------支付操作

local pay_invoke_handler = function()
    jf_commit_event(M.EVENT_NAMES.SDK_PAY_INVOKE, get_start_log_param(M.TRACE_NAMES.PAY, {}), false, true, true)
end

local pay_handler = function(pa)
    pa.success = true
    local params = get_end_log_param(M.TRACE_NAMES.PAY, pa)
    jf_commit_event(M.EVENT_NAMES.SDK_PAY_END, params, false, true, true)
end

local pay_failed_handler = function(pa)
    pa.success = false
    local params = get_end_log_param(M.TRACE_NAMES.PAY, pa)
    jf_commit_event(M.EVENT_NAMES.SDK_PAY_END, params, false, true, true)
end

-- 注册成功
local register_succ_handler = function()
    E.LOG.debug(TAG, "register_succ_handler received")
    jf_commit_event(M.EVENT_NAMES.SDK_REGISTER_SUCC, {}, false, true, true)
end

--------------登录操作
--- vendor login
function M.log_vendor_login_invoke(vendor_name)
    jf_commit_event(M.EVENT_NAMES.SDK_VENDOR_LOGIN_INVOKE, get_start_log_param(M.TRACE_NAMES.LOGIN, { type = vendor_name}), false, true, true)
end

function M.log_vendor_login(vendor_name, ...)
    --local sub_params = { ... }
    local params = get_end_log_param(M.TRACE_NAMES.LOGIN, { success = true, type = vendor_name})
    jf_commit_event(M.EVENT_NAMES.SDK_VENDOR_LOGIN_END, params, false, true, true)
end

function M.log_vendor_login_failed(vendor_name, code, msg)
    local sub_params = {}
    sub_params.code = code
    sub_params.msg = msg
    sub_params.success = false
    sub_params.type = vendor_name
    local params = get_end_log_param(M.TRACE_NAMES.LOGIN, sub_params)
    jf_commit_event(M.EVENT_NAMES.SDK_VENDOR_LOGIN_END, params, false, true, true)
end

local version_table_str = nil
local function get_sdk_plugin_versions()
    if version_table_str then
        return version_table_str
    end

    local version_table = {}
    local display_sdk_infos = E.get_display_sdk_infos()
    for k,v in pairs( display_sdk_infos ) do
        version_table[k or v.name] = tostring(v.version or '')
    end

    local JSON = require 'ejoysdk_lua.ejoysdk_json'
    version_table_str = JSON.encode(version_table)
    return version_table_str
end

-- acquire
function M.log_acquire_invoke(platform)
    jf_commit_event(M.EVENT_NAMES.SDK_ACQUIRE_INVOKE, get_start_log_param(M.TRACE_NAMES.LOGIN, { type = platform}), false, true, true)
end

function M.log_acquire(vendor_name, ...)
    --local sub_params = { ... }
    local params = get_end_log_param(M.TRACE_NAMES.LOGIN, { success = true, type = vendor_name})
    local UIM = require "ejoysdk_lua.user_info_manager"
    local channel_cloud_game_tag = UIM.get_channel_cloud_game_tag()
    params[UIM.PKG_INFO_KEY.KEY_CHANNEL_CLOUD_GAME_TAG] = channel_cloud_game_tag

    params[UIM.PKG_INFO_KEY.KEY_SDK_PLUGIN_VERSIONS] = get_sdk_plugin_versions()
    jf_commit_event(M.EVENT_NAMES.SDK_ACQUIRE_END, params, false, true, true)
end

function M.log_acquire_failed(vendor_name, code, msg)
    local sub_params = {}
    sub_params.code = code
    sub_params.msg = msg
    sub_params.success = false
    sub_params.type = vendor_name
    local params = get_end_log_param(M.TRACE_NAMES.LOGIN, sub_params)
    local UIM = require "ejoysdk_lua.user_info_manager"
    local channel_cloud_game_tag = UIM.get_channel_cloud_game_tag()
    params[UIM.PKG_INFO_KEY.KEY_CHANNEL_CLOUD_GAME_TAG] = channel_cloud_game_tag
    jf_commit_event(M.EVENT_NAMES.SDK_ACQUIRE_END, params, false, true, true)
end

function M.log_acquire_http_data(temp_params)
    local sub_params = temp_params
    local params = make_base_param()
    params.sub_params = sub_params
    local UIM = require "ejoysdk_lua.user_info_manager"
    local channel_cloud_game_tag = UIM.get_channel_cloud_game_tag()
    params[UIM.PKG_INFO_KEY.KEY_CHANNEL_CLOUD_GAME_TAG] = channel_cloud_game_tag

    jf_commit_event(M.EVENT_NAMES.SDK_ACQUIRE_HTTP_DATA, params, false, false, true)
end

-- login role
function M.log_login_invoke()
    jf_commit_event(M.EVENT_NAMES.SDK_ROLE_LOGIN_INVOKE, get_start_log_param(M.TRACE_NAMES.LOGIN, {}), false, true, true)
end

function M.log_login(...)
    --local sub_params = { ... }
    local params = get_end_log_param(M.TRACE_NAMES.LOGIN, { success = true })
    jf_commit_event(M.EVENT_NAMES.SDK_ROLE_LOGIN_END, params, false, true, true)
end

function M.log_login_failed(...)
    local code, msg = ...
    local sub_params = { code = tostring(code), msg = tostring(msg) }
    sub_params.success = false
    local params = get_end_log_param(M.TRACE_NAMES.LOGIN, sub_params)
    jf_commit_event(M.EVENT_NAMES.SDK_ROLE_LOGIN_END, params, false, true, true)
end
--------------

--普通技术打点
function M.commit_event(event_name, params, is_priority_high)
    local event_params = make_base_param()
    event_params.sub_params = params
    jf_commit_event(event_name, event_params, false, true, is_priority_high)
end

-- 主路径的打点，默认会直接上传
function M.commit_action_main(action_name, action_type, result, params)
    jf_commit_action(action_name, action_type, result, params, false, true, true)
end

function M.commit_action_succ_main(action, action_type, params)
    jf_commit_action(action, action_type, true, params, false, true, true)
end

function M.commit_action_fail_main(action, action_type, code, msg, params)
    local opts = {
        is_priority_high = true,
        is_upload_to_apus = true
    }
    jf_commit_action_fail(action, action_type, code, msg, params, opts)
end

--------------http

local function log_http_invoke(uuid, url)
    local sub_params = { url = url }
    local params = get_start_log_param(uuid, sub_params, sub_params)
    jf_commit_event(M.EVENT_NAMES.SDK_HTTP_INVOKE, params)
end

local function log_http_finish(uuid, is_post, url, resp)
    local body = resp.body or {}
    local body_code = body["code"]
    local body_msg = body["message"]
    local sub_params = { is_post = is_post, url = url, status = resp.status, code = body_code, msg = body_msg}
    local params = get_end_log_param(uuid, sub_params)
    jf_commit_event(M.EVENT_NAMES.SDK_HTTP_FINISH, params) 
end

local function log_to_apus(url, resp, start_clock, is_post)
    -- 如果有APM相关组件
    local ok, m_api_stats = pcall(require, "ejoysdk_lua.apm-sdk-lua.apus")
    if ok then
        if m_api_stats ~= nil then
            --local url = 'https://carbon-api-test.lingxigames.com/client/api.config.query?ver=1.3&df=json&gt=ng&cver=2.9.17&os=ios';
            --local u_domain,u_api = string.match(url, "([%w%-%.]*%.[%w%-]+%.%w+)%/([^?#]*)");print(u_domain);print(u_api);
            local u_domain,u_api = string.match(url, "([%w%-%.]*%.[%w%-]+%.%w+)%/([^?#]*)")
            if u_domain and u_api then
                local e_cost
                -- 优先使用native的耗时统计
                if resp.http_ext_params and resp.http_ext_params.cost then
                    e_cost = resp.http_ext_params.cost
                else
                    e_cost = E.system_clock() - start_clock
                end
                -- E.LOG.debug(TAG, "count_platform_api_call=> domain:"..tostring(u_domain).." api:"..tostring(u_api).." cost:"..tostring(e_cost) .. " status:" .. tostring(resp.status))
                if m_api_stats.count_platform_api_call then
                    local r_method = 1
                    if is_post then 
                        r_method = 2 
                    end
                    m_api_stats.count_platform_api_call(u_domain, u_api, resp.status, e_cost, r_method)
                end
            end
        end
    end
end

function M.make_log_http_callback(url, is_post, params, cb, start_clock, is_apm_collect)
    local cb_inner = cb
    if params.trace then
        local trace_uuid = string.gsub(EU(), "-", "")
        if not params.headers then
            params.headers = {}
        end
        params.headers["trace-id"] = trace_uuid
        log_http_invoke(trace_uuid, url)
        cb_inner = function(resp)
            log_http_finish(trace_uuid, is_post, url, resp)
            if is_apm_collect then
                log_to_apus(url, resp, start_clock, is_post)
            end
            return cb(resp)
        end
    elseif is_apm_collect then
        M.init()
        cb_inner = function(resp)
            log_to_apus(url, resp, start_clock, is_post)
            return cb(resp)
        end
    end
    return cb_inner
end

--------------socket 聊天
function M.socket_connect_statistics(state, temp_param, error_msg)
    local params = temp_param or {}
    params.detail_msg = error_msg or ""
    local CHATSTATES = require 'ejoysdk_lua.chat.ejoysdk_chat_states'
    if state == CHATSTATES.CONNECT_INVOKE then
        params.action = "connect_invoke"
        params = get_start_log_param(M.TRACE_NAMES.CHAT_CONNECT, params)
    elseif state == CHATSTATES.CONNECT_START then
        params.action = "connect_start"
        params = get_start_log_param(M.TRACE_NAMES.CHAT_CONNECT, params)
    elseif state == CHATSTATES.CONNECT_ERROR then
        params.action = "connect_error"
        params = get_end_log_param(M.TRACE_NAMES.CHAT_CONNECT, params)
    elseif state == CHATSTATES.CONNECTED then
        params.action = "connect_connected"
        params = get_end_log_param(M.TRACE_NAMES.CHAT_CONNECT, params)
    elseif state == CHATSTATES.ERROR then
        params.action = "connect_readwrite_error"
        params = get_end_log_param(M.TRACE_NAMES.CHAT_CONNECT, params)
    elseif state == CHATSTATES.CONNECT_LOST then
        params.action = "connect_lost"
        params = get_end_log_param(M.TRACE_NAMES.CHAT_CONNECT, params)
    elseif state == CHATSTATES.NO_LIMIT_RECONNECT_AT_NEXT_LOOP then
        params.action = "no_limit_reconnect_at_next_loop"
        params = get_end_log_param(M.TRACE_NAMES.CHAT_CONNECT, params)
    end

    jf_commit_event(M.EVENT_NAMES.SDK_CHAT_CONNECT, params)

    E.LOG.debug(TAG, "socket_connect_statistics, state:"..state..", params >>")
    E.log(params)
end


--------------

function M.init()
    if ql_inited then
        return
    end
    E = require "ejoysdk_lua.ejoysdk"
    _ejoysdk.log('qualitylog stat start init!')

    log_state = {}

    subscribe(ET.gangplank.INITSTART, gangplank_init_start_handler)
    subscribe(ET.gangplank.INITED, gangplank_inited_handler)

    subscribe(ET.gangplank.PAY_INVOKE, pay_invoke_handler)
    subscribe(ET.gangplank.PAY, pay_handler)
    subscribe(ET.gangplank.PAY_FAILED, pay_failed_handler)
    subscribe(ET.analytics.REGISTER, register_succ_handler)
    ql_inited = true
end

return M
