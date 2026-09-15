local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.CHAT .. 'chat_jf'

-- 注意：这里的经分打点，一旦定下来了，不能随便改，后台会有脚本实时分析的！！！

local M = {}

M.ACTION_TYPE = {
    ERROR = 'chat_err',
    EVENT = 'chat_event'
}

M.ACTION = {
    CONNECT_FAIL = 'chat_connect_fail',
    LOGIN_GROUP_EMPTY = 'chat_login_group_empty',
    LOGIN_FAIL_CAUSE_BY_RPC = 'chat_login_fail_cause_by_rpc',
    LOGIN_FAIL_CAUSE_BY_CHECK_GROUPS = 'chat_login_fail_cause_by_check_groups',
    GET_LATEST_SESSION_FAIL = 'chat_get_latest_session_fail',
    GET_MSG_FAIL = 'chat_get_msg_fail',
    SEND_MSG_FAIL = 'chat_send_msg_fail',
    GET_GROUP_FAIL = 'chat_get_group_fail'
}

function M.connect_fail(params)
    params = params or {}
    params['is_priority_high'] = true
    local stat_key = M.ACTION.CONNECT_FAIL .. '-' .. M.ACTION_TYPE.ERROR
    ESTAT.stat_error_with_limit(TAG, stat_key, M.ACTION.CONNECT_FAIL,  M.ACTION_TYPE.ERROR, params)
end

function M.login_succ(_params)
    -- 登录成功，不需要打经分，服务端有状态的
end

function M.login_fail(action, params)
    params = params or {}
    params['is_priority_high'] = true
    local stat_key = action .. '-' .. M.ACTION_TYPE.ERROR
    ESTAT.stat_error_with_limit(TAG, stat_key, action, M.ACTION_TYPE.ERROR, params)
end

function M.login_result_group_empty(params)
    params = params or {}
    params['is_priority_high'] = true
    local stat_key = M.ACTION.LOGIN_GROUP_EMPTY .. '-' .. M.ACTION_TYPE.ERROR
    ESTAT.stat_error_with_limit(TAG, stat_key, M.ACTION.LOGIN_GROUP_EMPTY, M.ACTION_TYPE.ERROR, params)
end

function M.re_login(_params)
    -- 重登这个行为，也不用打经分
end

function M.get_latest_session_fail(chat_type, params)
    params = params or {}
    params['_chat_type'] = chat_type
    params['is_priority_high'] = true
    local stat_key = M.ACTION.GET_LATEST_SESSION_FAIL .. '-' .. M.ACTION_TYPE.ERROR
    ESTAT.stat_error_with_limit(TAG, stat_key, M.ACTION.GET_LATEST_SESSION_FAIL, M.ACTION_TYPE.ERROR, params)
end

function M.get_msg_fail(chat_type, params)
    params = params or {}
    params['_chat_type'] = chat_type
    params['is_priority_high'] = true
    local stat_key = M.ACTION.GET_MSG_FAIL .. '-' .. M.ACTION_TYPE.ERROR
    ESTAT.stat_error_with_limit(TAG, stat_key, M.ACTION.GET_MSG_FAIL, M.ACTION_TYPE.ERROR, params)
end

function M.send_msg_fail(chat_type, params)
    params = params or {}
    params['_chat_type'] = chat_type
    params['is_priority_high'] = true
    local stat_key = M.ACTION.SEND_MSG_FAIL .. '-' .. M.ACTION_TYPE.ERROR
    ESTAT.stat_error_with_limit(TAG, stat_key, M.ACTION.SEND_MSG_FAIL, M.ACTION_TYPE.ERROR, params)
end

function M.get_group_fail(chat_type, params)
    params = params or {}
    params['_chat_type'] = chat_type
    params['is_priority_high'] = true
    local stat_key = M.ACTION.GET_GROUP_FAIL .. '-' .. M.ACTION_TYPE.ERROR
    ESTAT.stat_error_with_limit(TAG, stat_key, M.ACTION.GET_GROUP_FAIL, M.ACTION_TYPE.ERROR, params)
end

return M