local BASE_API = require 'ejoysdk_lua.libs.base_api'
local stake_api = BASE_API:New('stake') -- 新建 stake api 模块
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.SERVER_API .. 'stake'

local M = {}
-- 获取奖池信息
-- https://yuque.antfin-inc.com/ejoy-platform/user_guide/huy3sq
function M.get_stake_info(stake_id, cb)
    local body = {
        stake_id = stake_id
    }
    local opt = {use_moment_token = true}
    stake_api:post('/register/stake_info', {}, body, opt, cb)
end

-- 获取玩家报名抽奖信息
-- https://yuque.antfin-inc.com/ejoy-platform/user_guide/pd4f4i
function M.get_player_profile(stake_id, cb)
    local body = {
        stake_id = stake_id
    }
    local opt = {use_moment_token = true}
    stake_api:post('/draw/player_profile', {}, body, opt ,cb)
end

-- 获取抽奖结果
-- https://yuque.antfin-inc.com/ejoy-platform/user_guide/vocufc
function M.get_result(stake_id, batch_id, reward_id, last_page_index, cb)
    local query = {
        stake_id = stake_id,
        batch_id = batch_id,
        reward_id = reward_id,
        last_page_index = last_page_index
    }
    local opt = {use_moment_token = true}
    stake_api:get('/draw/get_result', {}, query, opt, cb)
end

-- 获取报名抽奖批次列表
-- https://yuque.antfin-inc.com/ejoy-platform/user_guide/kgccug
function M.get_batch_list(stake_id, descending_order, page, count, cb)
    local body = {
        stake_id = stake_id,
        descending_order = descending_order,
        page = page or 1,
        count = count or 10
    }
    local opt = {use_moment_token = true}
    stake_api:post('/register/get_batch_list', {}, body, opt ,cb)
end

return M
