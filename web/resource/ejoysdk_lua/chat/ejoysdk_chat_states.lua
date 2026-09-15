local ET = require "ejoysdk_lua.ejoysdk_topic"
local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"

local M = {}

local TAG = EM.MODULE.CHAT .. "chat_states"

M.NO_PLAYER_TOKEN = 'no_player_token'  -- 稳定状态，收到player_token后 才会—> get_player_token，能不能收到是由HOLO模块决定的。  处于这个状态，不能重连
M.GET_PLAYER_TOKEN = 'get_player_token'  -- 稳定状态，游戏可以调用手动登录接口chat.login()，触发连接。初始化聊天时，AUTO_LOGIN=false时，HOLO获取到player_token会处于这个状态
M.GET_PLAYER_TOKEN_AUTO_LOGIN = 'get_player_token_auto_login' -- 不稳定状态，马上会 -> get_chat_token
M.GET_CHAT_TOKEN = 'get_chat_token'  -- 不稳定状态，拿到chat_token后(聊天登录V2协议) 或者 获取chat_token 3次都失败后(聊天登录V1协议)，会 -> connect_invoke；特例get_chat_token的error_code是401(表示player_token已失效)时， 会 -> no_player_token
M.CONNECT_INVOKE = 'connect_invoke'  -- 不稳定状态，马上会 -> connect_start (如果遇到lua error 会 -> connect_error)
M.CONNECT_START = 'connect_start'  -- 不稳定状态，马上会 -> connecting (如果遇到error 会 -> connect_error)
M.CONNECTING = 'connecting'   -- 不稳定状态，连接成功会 -> connected (如果失败 会 -> connect_error)
M.CONNECTED = 'connected'  -- 不稳定状态，登录成功会 -> login_succ (如果失败 会 -> login_fail)
M.DISCONNECT = 'disconnect'  -- 稳定状态，可以重连
M.CONNECT_ERROR = 'connect_error'  -- 不稳定状态，马上会 -> retry_connect
M.ERROR = 'error' -- 不稳定状态，马上会 -> retry_connect
M.LOGIN_SUCC = 'login_succ'  -- 稳定状态，遇到error 才会 -> error
M.LOGIN_FAIL = 'login_fail'  -- 不稳定状态，马上会 -> retry_connect
M.RETRY_CONNECT = 'retry_connect'  -- 不稳定状态，如果player_token还有效，就 -> get_chat_token，反之 -> no_player_token
M.SERVER_OFFLINE = 'server_offline'  -- 稳定状态，游戏可以调用retry_connect接口，触发重连
M.USER_CLOSE = 'user_close'  -- 稳定状态，游戏可以调用retry_connect接口，触发重连

M.NO_LIMIT_RECONNECT_AT_NEXT_LOOP = 'no_limit_reconnect_at_next_loop'  -- 不算是状态，之前做无限重连的时候加的，只做打点用
M.CONNECT_LOST = 'connect_lost'  -- 不算是状态，打点用 + 给游戏一个connect_lost的回调

-- 当前状态，默认是no_player_token
local current_state = M.NO_PLAYER_TOKEN
local inited = false

function M.can_retry_connect()
    local map = {
        [M.CONNECT_ERROR]=true,
        [M.ERROR]=true,
        [M.SERVER_OFFLINE]=true,
        [M.USER_CLOSE]=true,
        [M.LOGIN_FAIL]=true,
        [M.DISCONNECT]=true,
        [M.GET_PLAYER_TOKEN]=true
    }

    return map[current_state] or false
end

function M.get_current_state()
    return current_state
end

function M.reset_current_state()
    current_state = M.NO_PLAYER_TOKEN
end

function M.init()
    if inited then
        return
    end

    inited = true

    ET.subscribe(ET.chat.UPDATE_STATE, function(new_state, login_result_params)
        if new_state == M.LOGIN_SUCC or new_state == M.LOGIN_FAIL then
            -- 登录成功、登录失败，只取destination=chat的
            if login_result_params and login_result_params.destination == 'chat' then
                current_state = new_state
                E.LOG.d(TAG, 'current_chat_state=' .. tostring(current_state))
            end
        else
            current_state = new_state
            E.LOG.d(TAG, 'current_chat_state=' .. tostring(current_state))
        end
    end)
end

return M