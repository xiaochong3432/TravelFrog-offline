local E = require 'ejoysdk_lua.ejoysdk'
local EH = require 'ejoysdk_lua.ejoysdk_holo'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local friend_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local friend_log_util = require 'ejoysdk_lua.friend.ejoysdk_friend_log_util'

local url_items = {
    get_favors_by_ids = '/favor/get_favors_by_ids',
    get_topn_favors   = '/favor/get_topn_favors'
}

local TAG = EM.MODULE.FRIEND .. 'favor'
local M = {}

local module_inited = false
local player_entered = false

local function require_params()
    local player_token = EH.get_player_token()
    --_ejoysdk.log(TAG.."player_token>>"..(player_token or 'nil'))
    return {
        acceptable = E.HTTP.CT_JSON,
        headers = {['moment-Token']= player_token}
    }
end

local post = function(url, params, cb)
    --_ejoysdk.log(TAG..'post url:'..url)
    if not player_entered then
        --_ejoysdk.log(TAG..'not inited and return')
        --E.log(params)
        return
    end

    E.HTTP.post(url, require_params(), E.HTTP.CT_JSON, params, function(resp)
        if resp.status == 200 then
            if resp.body.code == 0 then
                cb(200, resp.body)
            else
                cb(resp.body.code, resp.body)
            end
        else
            cb(resp.status, resp.body or {})
        end
    end)

end

local favor_post = function(type, params, cb)
    local favor_url_prefix = E.CONFIG.get_config('favor')
    local url = favor_url_prefix .. url_items[type]
    post(url, params, cb)
end

local function login_handler()
    player_entered = false
end

local function logout_handler()
    player_entered = false
end

local function player_online_handler(_player_token)
    player_entered = true
    --_ejoysdk.log('favor get player token: ' .. player_token)
    ET.publish(ET.favor.INITED, true)
end

local function player_offline_handler()
    player_entered = false
end

function M.init()
    friend_log.call_api(friend_log_util.header(), TAG, 'init', friend_log.LOG_LEVEL.HIGH, {})

    if module_inited then
        --E.LOG.debug(TAG, 'already init and return')
        return
    end

    --E.LOG.debug(TAG, 'init')
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, logout_handler)
    ET.subscribe(ET.gangplank.PLAYER_ONLINE, player_online_handler)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, player_offline_handler)

    module_inited = true
end

-- @description: 获取与其他玩家的亲密值(by ids) https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/qoc22g
-- @params: 
--  user_type: account 或 player
--  user_ids: array 限制500个
--  cb：异步回调
-- @return
--- true:  获取成功
--- false：获取失败，code: 错误码，message: 错误信息
function M.get_favors_by_ids(user_type, user_ids, cb)

    friend_log.call_api(friend_log_util.header(), TAG, 'get_favors_by_ids', friend_log.LOG_LEVEL.LOW, {}, user_type, user_ids, cb)

    --_ejoysdk.log('开始请求 get_favors_by_ids 接口')

    local params = {
        user_type = user_type,
        user_ids = user_ids
    }

    favor_post('get_favors_by_ids', params, function (status, body)
        --_ejoysdk.log('获取亲密关系列表by_ids result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true, body.data.list)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_favors_by_ids', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.data.list)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_favors_by_ids', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- @description: 获取TopN玩家的亲密值(by topn) https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/cnx8e2
-- @params: 
--  user_type: account 或 player
--  topn: int 请求的topN数量 限制500个
--  skip: 用于进行分页，譬如自动忽略 500 个，表示第二页
--  cb：异步回调
-- @return
--- true:  获取成功
--- false：获取失败，code: 错误码，message: 错误信息
function M.get_topn_favors(user_type, topn, skip, cb)

    friend_log.call_api(friend_log_util.header(), TAG, 'get_topn_favors', friend_log.LOG_LEVEL.LOW, {}, user_type, topn, skip, cb)

    --_ejoysdk.log('开始请求 get_topn_favors 接口')

    local params = {
        user_type = user_type,
        topn = topn,
        skip = skip
    }

    favor_post('get_topn_favors', params, function (status, body)
        --_ejoysdk.log('获取TopN玩家的亲密值 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true, body.data.list)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_topn_favors', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.data.list)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_topn_favors', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

return M