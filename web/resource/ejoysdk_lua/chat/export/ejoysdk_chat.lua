--[[
角色聊天接口，文档见：
https://yuque.antfin.com/ejoy-platform/user_guide/xeqmw3
这个模块是出于兼容性目的保留。推荐使用 ejoysdk_chat_model
]]
local EC = require "ejoysdk_lua.chat.ejoysdk_chat"
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
E_UTILS.do_export_wrapping(EC)
return EC