--[[
账号聊天接口，文档见：
https://yuque.antfin.com/ejoy-platform/user_guide/zqg47l
这个模块是出于兼容性目的保留。推荐使用 ejoysdk_chat_model
]]
local ECA = require "ejoysdk_lua.chat.ejoysdk_chat_account"
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
E_UTILS.do_export_wrapping(ECA)
return ECA