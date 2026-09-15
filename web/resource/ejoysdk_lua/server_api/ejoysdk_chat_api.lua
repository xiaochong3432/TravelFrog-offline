local E = require 'ejoysdk_lua.ejoysdk'
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local chat_api = BASE_API:New('chat-wsclient')
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local M = {}

local TAG = 'server_api#chat_api'

--[[
    服务端返回data的示例如下，chat_token_info.key是用来加密连接的，chat_token是用来登录聊天的。
    table: 0x7c7bc20280{
           ["message"] => "ok"
           ["chat_token_info"] => table: 0x7c7bc202c0{
              ["expire_time"] => 1642164139
              ["key"] => "K7wKpxyV+tyjwj/eHQzbtIA6qljO/aBm/Tq3jgwFxBIRGMRLXx2blw=="
           }
           ["chat_version"] => "0.1.0"
           ["chat_token"] => "AuYW9Owfx8h0TevhO3M/dMECY2p5BlAxMDExOQIgMEVBQ0ZEQTMwQjU3RDgxQjQ5QzJDQURCMzJEOTAyMjQEY2hhdKtv4WE2MWUxNmY2ZjZmYTMzMTliM2I2OTM1ZGE="
           ["code"] => 0
        }
--]]
function M.get_chat_token(cb)
    local holo = require 'ejoysdk_lua.ejoysdk_holo'
    local player_token = holo.get_player_token()
    if player_token == nil then
        cb(false, CONSTANTS.CHAT_ERROR_CODES.CODE_PLAYER_TOKEN_NIL, 'player token is nil')
        return
    end

    local chat_base_url = E.CONFIG.get_config('chat-wsclient')
    E.LOG.debug(TAG, 'chat_base_url=' .. tostring(chat_base_url))


    local opt = {use_moment_token = true, trace = true}
    local url = '/api/get_chat_token'

    local http_finish = false
    local time_out = false
    E.Timer.once(3, function ()
        time_out = true
        if not http_finish then
            E.LOG.debug(TAG, 'get_chat_token, succ=false, time out')
            cb(false, -1, 'time out')
        end
    end)

    chat_api:post(url, {}, {}, opt, function(succ, ...)
        http_finish = true
        if time_out then
            return
        end

        E.LOG.debug(TAG, 'get_chat_token, succ=' .. tostring(succ) .. ', no time out')
        if succ then
            local data = ...
            cb(true, data)
        else
            cb(false, ...)
        end
    end)
end

return M