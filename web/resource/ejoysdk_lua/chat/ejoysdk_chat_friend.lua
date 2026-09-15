local _E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.CHAT .. 'friend'

local M = {}

-- friend 模块拆分，用于分发chat_base的业务，避免chat_base过于臃肿
-- 后续更新的friend推送可迁移到这个模块

function M.process_friend_player_apply_refuse(data, cb)
    --E.LOG.debug(TAG,'SDK 新好友下发 好友申请被拒绝')
    --E.log(data)
    if cb then
        cb(true, data)
    end
end

function M.process_friend_player_apply_delete(data, cb)
    --E.LOG.debug(TAG,'SDK 新好友下发 好友申请已删除')
    --E.log(data)
    if cb then
        cb(true, data)
    end
end

return M