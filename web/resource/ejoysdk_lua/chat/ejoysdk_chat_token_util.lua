local E = require 'ejoysdk_lua.ejoysdk'

local M = {}

local _token_data = {}

local _TAG = 'ejoysdk_chat_token_util'

--[[
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
function M.update_token_data(token_data)
    _token_data = token_data
end

-- 重置token_data
function M.reset_token_data()
    _token_data = {}
end

-- 聊天登录用的token, 仅用于聊天登录，有效期10s
function M.get_chat_token()
    return _token_data['chat_token']
end

-- 用于聊天建连时加密
function M.get_chat_token_info_key()
    if _token_data and _token_data['chat_token_info'] then
        return _token_data['chat_token_info']['key']
    end

    return nil
end

function M.get_chat_token_expire_time()
    if _token_data and _token_data['chat_token_info'] then
        return _token_data['chat_token_info']['expire_time']
    end

    return 0
end

function M.is_chat_token_valid()
    local expire_time = M.get_chat_token_expire_time()
    -- 增加1s的宽松间隔，代码执行+网络请求，都需要花费时间的
    if expire_time - 1 > E.time()  then
        return true
    end

    return false
end

M.LOGIN_V1 = 'login_v1'
M.LOGIN_V2 = 'login_v2'

M.curr_login_version = M.LOGIN_V1

return M