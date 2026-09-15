--[[
    聊天消息工具类
--]]
local M = {}
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local EC = require 'ejoysdk_lua.chat.ejoysdk_chat_base'

--- 获取会话类型
--- @param session_id string 会话id
--- @return table 会话类型数据
---@example
--    假设: 自己的账号id=a10001, 自己的角色id=10001
--
--    角色与角色之间的会话
--    chat_session_util.get_session_type('10001:10002') -> {
--        type = 'personal',
--        personal_user_type = 'player',
--        from = '10002',
--        from_chat_user_id = '10002',
--        my = '10001',
--        my_chat_user_id = '10001'
--    }
--
--    账号与账号之间的会话
--    chat_session_util.get_session_type('acc_a10001:acc_a10002') -> {
--        type = 'personal',
--        personal_user_type = 'account',
--        from = 'a10002',
--        from_chat_user_id = 'acc_a10002',
--        my = 'a10001',
--        my_chat_user_id = 'acc_a10001'
--    }
--
--    账号与客服的会话
--    chat_session_util.get_session_type('acc_a10001:cs_77') -> {
--        type = 'personal',
--        personal_user_type = 'cs',
--        from = 'cs_77',
--        from_chat_user_id = 'cs_77',
--        my = 'a10001',
--        my_chat_user_id = 'acc_a10001'
--    }
--
--    群组会话
--    chat_session_util.get_session_type('group_5e69e0ad24bbe4f4a90b84d5') -> {
--        type = 'group',
--        from = 'group_5e69e0ad24bbe4f4a90b84d5'
--    }
--
--    系统会话(精确到具体某个系统服务)
--    chat_session_util.get_session_type('system_chat_rule_msg:10001') -> {
--        type = 'system',
--        from = 'chat_rule_msg'
--    }
--
--    系统会话
--    chat_session_util.get_session_type('system:10001') -> {
--        type = 'system',
--        from = ''
--    }
function M.get_session_type(session_id)
    return EC.get_session_type(session_id)
end

E_UTILS.do_export_wrapping(M)
return M
