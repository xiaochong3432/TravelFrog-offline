local BASE_API = require 'ejoysdk_lua.libs.base_api'
local vortex_api = BASE_API:New('vortex') -- 新建 stake api 模块
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.SERVER_API .. 'vortex'

local M = {}

-- 提供玩家帐号到角色绑定的能力,允许在此之上配置对应的规则
-- https://yuque.antfin-inc.com/ejoy-platform/user_guide/kbh4kv#9a0efd43
function M.get_rt_counter(rtc_id, cb)
    local body = {
        rtc_id = rtc_id
    }
    local opt = {use_moment_token = true}
    vortex_api:post('/client_api/get_rt_counter', {}, body, opt, cb)
end

return M