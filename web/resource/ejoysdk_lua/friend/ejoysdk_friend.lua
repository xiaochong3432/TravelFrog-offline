local E = require 'ejoysdk_lua.ejoysdk'
local EH = require 'ejoysdk_lua.ejoysdk_holo'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local Class = require "ejoysdk_lua.ejoysdk_class"
local player_cache  = require "ejoysdk_lua.player.player_info_cache"
local player_info = require 'ejoysdk_lua.player.player_info'
local friend_cache = require 'ejoysdk_lua.friend.ejoysdk_friend_cache'
local STATES = require 'ejoysdk_lua.chat.ejoysdk_chat_states'
local util = require 'ejoysdk_lua.ejoysdk_utils'
local player_scene = require 'ejoysdk_lua.player.player_info_scene'
local friend_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local EM = require "ejoysdk_lua.ejoysdk_module"
local friend_jf = require 'ejoysdk_lua.friend.ejoysdk_friend_jf'
local friend_log_util = require 'ejoysdk_lua.friend.ejoysdk_friend_log_util'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'

local url_items = {
    accept_friend_apply = '/friend/accept_friend_apply',
    accept_friend_apply_batch = '/friend/accept_friend_apply_batch',
    del_friend = '/friend/del_friend',
    get_friend_id_list = '/friend/get_friend_id_list',
    refuse_friend_apply = '/friend/refuse_friend_apply',
    refuse_friend_apply_batch = '/friend/refuse_friend_apply_batch',
    del_friend_apply = '/friend/del_friend_apply',
    add_friend_black = '/friend/add_friend_black',
    del_friend_black = '/friend/del_friend_black',
    get_channel_friend_list = '/friend/channel/v1.0/get_friend_list',
    refresh_channel_friend_list = '/friend/channel/v1.0/refresh_friend_list',
    add_follow = '/follow/add_follow',
    del_follow = '/follow/del_follow',
    get_follow_ext = '/follow/get_follow_ext',
    get_follow_id_list = '/follow/get_follow_id_list',
    get_follow_list = '/follow/get_follow_list',
    get_followed_list = '/follow/get_followed_list',
    get_new_followed_list = '/follow/get_new_followed_list',
    add_friend_group = '/friend/add_friend_group',
    del_friend_group = '/friend/del_friend_group',
    get_friend_group = '/friend/get_friend_group',
    add_friend_group_member = '/friend/add_friend_group_member',
    del_friend_group_member = '/friend/del_friend_group_member',
    update_friend_group_info = '/friend/update_friend_group_info'
}
--[[
/friend/v2.0/get_friend_list：是获取好友间信息，包括 ext 之类的 info；
/friend/v2.0/get_friend_info_list：是获取好友自己的信息，包括好友的等级，称号等；
--]]
local url_items_v2 = {
    add_friend_apply = '/friend/v2.0/add_friend_apply',
    get_friend_apply_list = '/friend/v2.0/get_friend_apply_list',
    get_friend_black_list = '/friend/v2.0/get_friend_black_list',
    get_friend_group_member = '/friend/v2.0/get_friend_group_member',
    get_friend_list = '/friend/v2.0/get_friend_list', -- 除了好友 id，还会返回好友的其他信息，如好友备注，待开发
    get_friend_to_apply_list = '/friend/v2.0/get_friend_to_apply_list',
    get_new_friend_apply_list = '/friend/v2.0/get_new_friend_apply_list',
    get_new_friend_list = '/friend/v2.0/get_new_friend_list',
    get_friend_info_list = '/friend/v2.0/get_friend_info_list' -- 仅是好友的角色, 注意区别于旧的get_friend_info_list
}

local TAG = EM.MODULE.FRIEND .. 'friend'
local M = {}

local module_inited = false
local player_entered = false

local player_scene_ready_flag = {
    [player_scene.OFFICIAL_SCENE.FRIEND_APPLY] = false,
    [player_scene.OFFICIAL_SCENE.BLACK_LIST] = false,
    [player_scene.OFFICIAL_SCENE.FOLLOW] = false
}

local real_get_channel_friends_on_request_map = {}  -- 正在请求get_channel_friends的记录， 结构：[{fail_cb=cb1, succ_cb=cb2}, {fail_cb=cb3, succ_cb=cb4}]
local real_get_friend_id_list_on_request_map = {}  -- 正在请求get_friend_id_list的记录, 结构：{rtype1= [cb1, cb2], rtype2= [cb3, cb4]}
local real_refresh_channel_friends_on_request_map = {}  -- 正在请求refresh_channel_friends的记录， 结构：{channel1=[cb1,cb2], channel2=[cb3, cb4]}
local auto_refresh_time_gap = 60*60 -- 60分钟
local all_friend_channels = {} --用来保存生命周期内所有的channel, auto_refresh时，会根据all_friend_channels去刷新channel_friend
local already_get_friend_id_list_data = {} --标记是否已经请求到好友id的数据, eg {'friend':true,'hus':true}
local refresh_channel_friends_cache = {}   -- refresh_channel_friends接口的数据缓存，结构：{time=1680847281, is_succ=false, error_code=-1, error_msg='error_msg'}，is_succ为true时，error_code、error_msg为nil
local http_default_timeout = 20  --http的超时时间

local function require_params()
    local player_token = EH.get_player_token()
    --_ejoysdk.log(TAG.."player_token>>"..(player_token or 'nil'))
    return {
        acceptable = E.HTTP.CT_JSON,
        headers = {['moment-Token']= player_token},
        timeout = http_default_timeout
    }
end

local func_call_cache = {}

local post = function(url, params, cb)
    --_ejoysdk.log(TAG..'post url:'..url)
    if not player_entered then
        --_ejoysdk.log(TAG..'not inited and return')
        --E.log(params)
        local func_call = {
            url = url,
            params = params,
            cb = cb
        }
        table.insert(func_call_cache, func_call)
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

local friend_post = function(type, params, cb)
    local friend_url_prefix = E.CONFIG.get_config('friend')
    local use_v1 = E.CONFIG.get_config('friend_use_v1')
    local url
    if use_v1 then
        url = friend_url_prefix .. url_items[type]
    else
        if url_items_v2[type] then
            url = friend_url_prefix .. url_items_v2[type]
        else
            url = friend_url_prefix .. url_items[type]
        end
    end
    post(url, params, cb)
end

local invoke_cache_func = function()
    for _, func_call in pairs(func_call_cache) do
        post(func_call.url, func_call.params, func_call.cb)
    end
    func_call_cache = {}
end

--清掉所有的标志位，避免切换账号或相互顶号时缓存数据串号
local function clearLocalVariables(is_player_offline)
    if is_player_offline then
        -- 登出场景，把正在请求的callback缓存清空，是安全的
        real_get_channel_friends_on_request_map = {}
        real_get_friend_id_list_on_request_map = {}
        real_refresh_channel_friends_on_request_map = {}
    end
    refresh_channel_friends_cache = {} -- 把refresh_channel_friends接口的缓存清空
    all_friend_channels = {}
    already_get_friend_id_list_data = {}
end

local function login_handler()
    player_entered = false
end

local function logout_handler()
    player_entered = false
    friend_cache.clear()
    clearLocalVariables(true)
end

local function player_offline_handler()
    player_entered = false
    friend_cache.clear()
    clearLocalVariables(true)
end

local function player_online_handler(_player_token)
    local get_scene_infos_after_action = function()
        player_entered = true
        friend_cache.clear()
        clearLocalVariables(false)
        --_ejoysdk.log('friend get player token: ' .. player_token)
        ET.publish(ET.friend.INITED, true)
        invoke_cache_func()
    end

    local scene_ids = {
        player_scene.OFFICIAL_SCENE.DEFAULT,
        player_scene.OFFICIAL_SCENE.FRIEND,
        player_scene.OFFICIAL_SCENE.FRIEND_APPLY,
        player_scene.OFFICIAL_SCENE.BLACK_LIST,
        player_scene.OFFICIAL_SCENE.FOLLOW
    }

    -- 新增重试逻辑
    local get_scene_infos_action_max_retry_count = 3
    local get_scene_infos_action_curr_retry_count = 0
    local get_scene_infos_action
    get_scene_infos_action = function()
        get_scene_infos_action_curr_retry_count = get_scene_infos_action_curr_retry_count + 1
        player_scene.get_scene_infos(scene_ids, function (succ, ...)
            if not succ then
                local code, msg = ...
                if get_scene_infos_action_curr_retry_count > get_scene_infos_action_max_retry_count then
                    ESTAT.stat_action_with_limit('friend', 'get_scenes_fail_on_reach_max_retry_count', 'get_scenes_fail_on_reach_max_retry_count', 'friend_err', {code = code, msg = msg})
                    get_scene_infos_after_action()
                    return
                end

                get_scene_infos_action()
                return
            end

            local return_scene_infos = ...
            if return_scene_infos[player_scene.OFFICIAL_SCENE.FRIEND_APPLY] then
                player_scene_ready_flag[player_scene.OFFICIAL_SCENE.FRIEND_APPLY] = true
            end

            if return_scene_infos[player_scene.OFFICIAL_SCENE.BLACK_LIST] then
                player_scene_ready_flag[player_scene.OFFICIAL_SCENE.BLACK_LIST] = true
            end

            if return_scene_infos[player_scene.OFFICIAL_SCENE.FOLLOW] then
                player_scene_ready_flag[player_scene.OFFICIAL_SCENE.FOLLOW] = true
            end

            get_scene_infos_after_action()
        end)
    end

    get_scene_infos_action()
end

function M.init()
    friend_log.call_api(friend_log_util.header(), TAG, 'init', friend_log.LOG_LEVEL.HIGH, {})

    if module_inited then
        --E.LOG.debug(TAG, 'already init and return')
        return
    end

    friend_cache.init()
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, logout_handler)
    ET.subscribe(ET.gangplank.PLAYER_ONLINE, player_online_handler)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, player_offline_handler)

    module_inited = true
end

function M.accept_friend_apply_v2(player_id, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'accept_friend_apply_v2', friend_log.LOG_LEVEL.HIGH, {}, player_id, rtype, ext, cb)

    local params = {
        player_id = player_id,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('accept_friend_apply', params, function (status, body)
        --_ejoysdk.log('接受好友申请 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'accept_friend_apply_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end

            friend_jf.accept_friend_apply_fail({method = 'accept_friend_apply_v2', code = body.code or status, msg = body.message or ''})

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'accept_friend_apply_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.accept_friend_apply(player_id, cb)
    M.accept_friend_apply_v2(player_id, nil, nil, cb)
end

--[[
    参考：https://aliyuque.antfin.com/ejoy-platform/user_guide/nunsrw#accept_friend_apply_batch
    player_ids：table, 字符串数组
    rtype：关系类型
    ext: table, 透传参数
    cb: function(succ, ...)
        请求成功则 cb(true, body)
            请求成功情况下，body: table，包含以下字段
                code: number 错误码，1.全部好友申请记录找不到，会直接返回错误码 20004； 2. 其他情况都是返回code = 0，一条条处理好友请求，把成功的汇总到 apply_player_ids， 失败的汇总到 failed_players
                apply_player_ids: table, 字符串数组，表示成功成为好友的id列表
                failed_players: table, 旧服务端可能返回nil, 表示列表中失败的好友请求, 包含失败code和msg:
                    code: number, 失败错误码
                    message: string, 失败原因
                    player_id: string, 失败player_id
        请求失败则 cb(false, code, msg)
]]
function M.accept_friend_apply_batch_v2(player_ids, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'accept_friend_apply_batch_v2', friend_log.LOG_LEVEL.HIGH, {}, player_ids, rtype, ext, cb)

    local params = {
        player_ids = player_ids,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('accept_friend_apply_batch', params, function (status, body)
        --_ejoysdk.log('接受批量好友申请 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true, body or {})
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'accept_friend_apply_batch_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end

            friend_jf.accept_friend_apply_fail({method = 'accept_friend_apply_batch_v2', code = body.code or status, msg = body.message or ''})

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'accept_friend_apply_batch_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

--[[
    参考：https://aliyuque.antfin.com/ejoy-platform/user_guide/nunsrw#accept_friend_apply_batch
    player_ids：table, 字符串数组
    cb: function(succ, ...)
        请求成功则 cb(true, body)
            请求成功情况下，body: table，包含以下字段
                code: number 错误码，1.全部好友申请记录找不到，会直接返回错误码 20004； 2. 其他情况都是返回code = 0，一条条处理好友请求，把成功的汇总到 apply_player_ids， 失败的汇总到 failed_players
                apply_player_ids: table, 字符串数组，表示成功成为好友的id列表
                failed_players: table, 旧服务端可能返回nil, 表示列表中失败的好友请求, 包含失败code和msg:
                    code: number, 失败错误码
                    message: string, 失败原因
                    player_id: string, 失败player_id
        请求失败则 cb(false, code, msg)
]]
function M.accept_friend_apply_batch(player_ids, cb)
    M.accept_friend_apply_batch_v2(player_ids, nil, nil, cb)
end

function M.add_friend_apply_v2(player_id, apply_content, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'add_friend_apply_v2', friend_log.LOG_LEVEL.HIGH, {}, player_id, apply_content, rtype, ext, cb)

    local params = {
        player_id = player_id,
        content = apply_content,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('add_friend_apply', params, function (status, body)
        --_ejoysdk.log('提交好友申请 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_apply_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end

            friend_jf.add_friend_fail({code = body.code or status, msg = body.message or ''})

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_apply_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.add_friend_apply(player_id, apply_content, cb)
    M.add_friend_apply_v2(player_id, apply_content, nil, nil, cb)
end

function M.del_friend_v2(friend_player_id, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'del_friend_v2', friend_log.LOG_LEVEL.LOW, {}, friend_player_id, rtype, ext, cb)

    local params = {
        friend_player_id = friend_player_id,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('del_friend', params, function (status, body)
        --_ejoysdk.log('删除好友 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.del_friend(friend_player_id, cb)
    M.del_friend_v2(friend_player_id, nil, nil, cb)
end

local function get_friend_apply_list_inner(state, last_time_index, cb)
    local params = {
        state = state,
        last_time_index = last_time_index
    }

    friend_post('get_friend_apply_list', params, function (_status, body)
        --_ejoysdk.log('获取好友申请列表 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        cb( body.last_indexTime, body.friend_apply_list)
    end)
end

local simple_cursor = Class:Inherit("FriendSimpleCursor")

function simple_cursor:_init(type, list_field_name, state)
    assert(type, 'simple_cursor type should be string')
    assert(list_field_name, 'list_field_name type should be string')
    self.type = type
    self.list_field_name = list_field_name
    self.state = state

    self.list = {}

    self.last_index_time = nil
end

function simple_cursor:load(cb)
    --if self.last_index_time then
    --    _ejoysdk.log('when load, last_time_index: ' .. self.last_index_time)
    --else
    --    _ejoysdk.log('when load, last_time_index is nil')
    --end
    local params = {
        state = self.state,
        last_index_time = self.last_index_time
    }
    friend_post(self.type, params, function(status, body)
        if status == 200 then
            cb(true, body)
        else
            cb(false, body.code or status, body.message or '')
        end
    end)
end

local function fill_player_infos(list, cb, fail_cb, scene)
    local use_v1 = E.CONFIG.get_config('friend_use_v1')
    if not use_v1 then
        local id_to_object = {}
        local ids = {}
        for _, info in pairs(list) do
            if info.user_id then
                table.insert(ids, info.user_id)
                if not id_to_object[info.user_id] then
                    id_to_object[info.user_id] = {}
                end
                table.insert(id_to_object[info.user_id], info)
            end
        end

        -- 外面传了scene，就使用外面的scene, 否则使用好友场景
        player_info.get_player_infos(ids, {playerid_to_info = true, scene=scene or player_scene.OFFICIAL_SCENE.FRIEND},  function(succ, ...)
            if succ then
                local players = ...
                for player_id, player in pairs(players) do
                    -- 填充或更新list的play信息
                    local obj_array = id_to_object[player_id]
                    for _, obj in pairs(obj_array) do
                        local copy_player = util.deepcopy(player)
                        obj.player = copy_player
                        obj.player_info = copy_player.player_info
                    end
                end
                cb(list)
            else
                fail_cb()
            end
        end)
    else
        cb(list)
    end
end

function simple_cursor:load_all(cb, scene)
    local function listener(succ, body)
        if succ then
            self.last_index_time = body.last_index_time
            local cur_list = body[self.list_field_name]
            if cur_list and #cur_list > 0 then
                for _, item in pairs(cur_list) do
                    -- insert all
                    table.insert(self.list, item)
                end
                self:load(listener)
            else
                local safe_scene = player_scene.OFFICIAL_SCENE.FRIEND
                if player_scene_ready_flag[scene] then
                    safe_scene = scene
                end

                fill_player_infos(self.list, function(replace_list)
                    cb(true, replace_list)
                end, function()
                    cb(false, -1, 'get player info fail')
                end, safe_scene)
            end
        else
            cb(false, -1, '')
        end
    end

    self:load(listener)
end

-- 可分页加载的cursor，未开发完成，暂时用不到
local cursor = Class:Inherit("FriendCursor")

-- state 是table：0 => 待处理， 1 =>同意， 2 => 拒绝
function cursor:_init(state)
    self.state = state or { 0, 1, 2}
    self.index = 1 -- 从1开始是因为和table的最小索引相同
    self.list = {}
end

function cursor:load(cb)
    local cur_item = self.list[self.index]
    if cur_item then
        cb(cur_item)
        return
    end

    local last_time_index = (self.index == 1 and nil or self.list[self.index - 1].last_time_index)
    local listener = function(index, list)
        local new_item = {
        last_time_index = index,
        list = list
        }
        self.list[self.index] = new_item
        cb(new_item)
    end
    get_friend_apply_list_inner(self.state, last_time_index, listener)
end

local function real_get_friend_id_list(rtype, ext, cb)
    -- rtype没传 或者 传的是空字符串，就赋默认值'friend'
    if not rtype or (#rtype == 0) then
        rtype = 'friend'
    end

    local params = {
        rtype=rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    if not real_get_friend_id_list_on_request_map[rtype] or (real_get_friend_id_list_on_request_map[rtype] and next(real_get_friend_id_list_on_request_map[rtype]) == nil) then
        -- 为nil 或者 为空table, 说明是 同url+同rtype 的第一个请求，不用return拦截
        real_get_friend_id_list_on_request_map[rtype] = {}
        table.insert(real_get_friend_id_list_on_request_map[rtype], cb)
    else
        -- 已经有正在进行的请求了，return拦截掉，加入callback缓存即可，不用重复请求
        table.insert(real_get_friend_id_list_on_request_map[rtype], cb)
        return
    end

    friend_post('get_friend_id_list', params, function (status, body)
        -- bugfix: 增加默认值{}规避lua error。出现lua error的场景：正在请求时，调了player_offline/logout把real_get_friend_id_list_on_request_map清空了，引发lua error
        local callback_cache_list = real_get_friend_id_list_on_request_map[rtype] or {}

        if status == 200 then
            friend_cache.clear_friend_ids(rtype)  -- 要先把缓存清掉
            friend_cache.add_friend_ids(body.friend_id_list, rtype)
            friend_cache.merge_wait_operation()
            already_get_friend_id_list_data[rtype] = true

            for _, callback in pairs(callback_cache_list) do
                -- friend_cache.get_all_friend_ids 内部已经拷贝过
                util.safe_call_cb(callback, true, friend_cache.get_all_friend_ids(rtype))
            end
        else
            for _, callback in pairs(callback_cache_list) do
                util.safe_call_cb(callback, false, body.code or status, body.message or '')
            end
        end

        real_get_friend_id_list_on_request_map[rtype] = {}
    end)
end

function M.is_process_get_friend_id_list(rtype)
    local cache_key = 'friend'
    if rtype and (#rtype > 0) then
        cache_key = rtype
    end

    -- 正在请求friend_id_list接口的callback_list不为空，则表示正在请求
    if real_get_friend_id_list_on_request_map[cache_key] and next(real_get_friend_id_list_on_request_map[cache_key]) ~= nil then
        return true
    else
        return false
    end
end

ET.subscribe(ET.chat.UPDATE_STATE, function(state, login_result_params)

    if state == STATES.LOGIN_SUCC then
        --_ejoysdk.log('socket 建立连接成功，好友模块收到通知，开始准备请求接口')
        --_ejoysdk.log('准备请求 get_friend_id_list 接口')
        -- (tag, log_level, action, action_type, params, opt)
        -- friend_log.debug(friend_log_util.header(), TAG, 'auto_get_friend_id_list_on_socket_connect', 'friend_handle', {}, {})

        -- 只有destination为chat的登录成功，才代表重连
        if login_result_params and login_result_params.destination == 'chat' then
            -- 重连了，就先清一下好友缓存标识，防止断连期间，有新好友的消息没有收到
            already_get_friend_id_list_data = {}
        end

        M.get_friend_id_list_v2(nil, nil, function (...) end)

        friend_log.info(friend_log_util.header(), TAG, 'auto_get_channel_friends_on_socket_connect', 'friend_handle', {all_friend_channels = all_friend_channels}, {})

        -- 遍历所有channel，分别请求另外两个接口，受请求频率和缓存限制
        for channel, _value in pairs(all_friend_channels) do
            --_ejoysdk.log('准备请求 ' .. channel .. ' 渠道的好友信息')
            M.get_channel_friends(channel, function (...) end)
            M.refresh_channel_friends(channel, function (...) end)
        end
    end
end)

function M.get_friend_id_list_v2(rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_id_list_v2', friend_log.LOG_LEVEL.HIGH, {}, rtype, ext, cb)

    if not rtype or (#rtype == 0) then
        rtype = 'friend'
    end

    -- 只用already_get_friend_id_list_data标识来判断缓存是否存在
    -- 有缓存则返回缓存
    if already_get_friend_id_list_data[rtype] then
        util.safe_call_cb(cb, true, friend_cache.get_all_friend_ids(rtype))
        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_id_list_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, true, friend_cache.get_all_friend_ids(rtype))
        return
    end

    real_get_friend_id_list(rtype, ext, function (succ, ...)
        if not succ then
            local code, msg = ...
            friend_jf.get_friend_list_fail({method = 'get_friend_id_list_v2', code = code, msg = msg})
        end

        util.safe_call_cb(cb, succ, ...)
        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_id_list_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, succ, ...)
    end)
end

function M.get_friend_id_list(cb)
    M.get_friend_id_list_v2(nil, nil, cb)
end

function M.get_friend_info_list(player_id_list, cb)
    M.get_friend_info_list_v2(player_id_list, cb)
end

function M.get_friend_info_list_v2(player_id_list, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_info_list_v2', friend_log.LOG_LEVEL.LOW, {}, player_id_list, cb)

    player_info.get_player_infos(player_id_list, { scene=player_scene.OFFICIAL_SCENE.FRIEND }, function (succ, ...)
        if not succ then
            local code, msg = ...
            friend_jf.get_friend_list_fail({method = 'get_friend_info_list_v2', code = code, msg = msg})
        end
        if cb then
            cb(succ, ...)
        end
        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_info_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
    end)
end

function M.get_my_friend_info_list_v2(rtype, _params, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_my_friend_info_list_v2', friend_log.LOG_LEVEL.LOW, {}, rtype, _params, cb)

    local params = {
        rtype = rtype
    }

    for k, v in pairs(_params) do
        params[k] = v
    end

    local function friend_post_succ_action(_status, body)
        local friend_players = body.friend_info_list
        local player_infos = {}
        local player_ids = {}
        for _, player in pairs(friend_players) do
            -- 先写入缓存，再读取缓存的数据，缓存保证返回的是最新的数据
            player_cache.add_player_info_unsafe(player.player_id, player, 'user_info_http', player_scene.OFFICIAL_SCENE.FRIEND)
            -- 保持每次获取的顺序一致
            local friend_player_info = player_cache.get_player_info(player.player_id, player_scene.OFFICIAL_SCENE.FRIEND)

            if friend_player_info ~= nil then
                table.insert(player_infos, friend_player_info)
            end

            if player.player_id ~= nil then
                table.insert(player_ids, player.player_id)
            end
        end

        -- 之前有项目组反馈，客户端缓存的friend_cache不够实时，可以在get_my_friend_info_list接口调用成功后，设置一下friend_cache，get_my_friend_info_list返回的好友数据是最准确的
        -- 更新一下本地缓存的friend_id数组
        friend_cache.clear_friend_ids(params.rtype)
        friend_cache.add_friend_ids(player_ids, params.rtype)

        if cb then
            cb(true, player_infos)
        end

        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_my_friend_info_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true, player_infos)
    end

    local function friend_post_fail_action(status, body)
        local code = body.code or status
        local msg = body.message or ''
        util.safe_call_cb(cb, false, code, msg)

        friend_jf.get_friend_list_fail({method = 'get_my_friend_info_list_v2', code = code, msg = msg})
        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_my_friend_info_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, code, msg)
    end

    player_scene.get_scene_info(player_scene.OFFICIAL_SCENE.FRIEND, function (succ, ...)
        if not succ then
            util.safe_call_cb(cb, false, CONSTANTS.FRIEND_ERROR_CODES.CODE_FRIEND_SCENE_FETCH_FAIL, 'friend scene data fetch fail')
            return
        end
        
        friend_post('get_friend_info_list', params, function (status, body)
            --_ejoysdk.log('好友场景下角色的获取 result')
            --[[
            E.log({
                status = status,
                body = body
            })
            --]]
            if status == 200 then
                friend_post_succ_action(status, body)
            else
                friend_post_fail_action(status, body)
            end
        end)
    end)
end

-- 仅是好友场景的角色, 注意区别于get_friend_info_list
-- 注意：旧版对外已经使用了get_friend_info_list接口名，此接口语义上进行区分
-- _params.rtype: 关系类型
function M.get_my_friend_info_list(_params, cb)
    M.get_my_friend_info_list_v2(nil, _params, cb)
end

function M.get_friend_list_v2(rtype, _params, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_list_v2', friend_log.LOG_LEVEL.HIGH, {}, rtype, _params, cb)

    local params = {
        rtype = rtype
    }

    for k, v in pairs(_params) do
        params[k] = v
    end
    friend_post('get_friend_list', params, function (status, body)
        --_ejoysdk.log('好友场景下角色的获取 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            local friend_players = body.friend_list
            local friend_ids = {}
            for _, player in pairs(friend_players) do
                if player.user_id ~= nil then
                    table.insert(friend_ids, player.user_id)
                end
            end

            -- 之前有项目组反馈，客户端缓存的friend_cache不够实时，可以在get_my_friend_info_list接口调用成功后，设置一下friend_cache，get_my_friend_info_list返回的好友数据是最准确的
            -- 更新一下本地缓存的friend_id数组
            friend_cache.clear_friend_ids(params.rtype)
            friend_cache.add_friend_ids(friend_ids, params.rtype)

            if cb then
                cb(true, friend_players)
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_list_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, true, friend_players)
        else
            local code = body.code or status
            local msg = body.message or ''

            friend_jf.get_friend_list_fail({method = 'get_friend_list_v2', code = code, msg = msg})

            if cb then
                cb(false, code, msg)
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_list_v2', friend_log.LOG_LEVEL.HIGH, {}, cb, false, code, msg)
        end
    end)
end

-- get_friend_list接口返回的数据，不是按friend场景的角色字段设置，来返回的，所以在请求成功时，不能去操作player_cache
-- 本接口是获取好友间信息，包括 ext 之类的 info；
-- _params.rtype
function M.get_friend_list(_params, cb)
    M.get_friend_list_v2(nil, _params, cb)
end

function M.get_friend_apply_list(state, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_apply_list', friend_log.LOG_LEVEL.LOW, {}, state, cb)

    local type = 'get_friend_apply_list'
    local list_field_name = 'friend_apply_list'

    -- 这里兼容native传过来的state的item是string类型，把string类型转成int类型
    if state then
        local safe_state = {}
        for _, value in ipairs(state) do
            table.insert(safe_state, tonumber(value))
        end
        state = safe_state
    end

    local apply_list_cursor = simple_cursor:New(type, list_field_name, state or {0, 1, 2})

    apply_list_cursor:load_all(function (...)
        if cb then
            cb(...)
        end
        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, ...)
    end, player_scene.OFFICIAL_SCENE.FRIEND_APPLY)
end

function M.get_friend_to_apply_list(state, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_to_apply_list', friend_log.LOG_LEVEL.LOW, {}, state, cb)

    local type = 'get_friend_to_apply_list'
    local list_field_name = 'friend_apply_list'

    -- 这里兼容native传过来的state的item是string类型，把string类型转成int类型
    if state then
        local safe_state = {}
        for _, value in ipairs(state) do
            table.insert(safe_state, tonumber(value))
        end
        state = safe_state
    end

    local to_apply_list_cursor = simple_cursor:New(type, list_field_name, state or {0, 1, 2})

    to_apply_list_cursor:load_all(function(succ, ...)
        if not succ then
            if cb then
                cb(false, ...)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_to_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, false, ...)
            return
        end

        -- 还需要添加目标 player_id 对应的 player_info
        local apply_list = ...
        local target_ids = {}
        for _, apply in ipairs(apply_list) do
            if apply.target_id then
                table.insert(target_ids, apply.target_id)
            end
        end

        if #target_ids == 0 then -- 兼容服务器没有返回 target id 的情况
            if cb then
                cb(true, apply_list)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_to_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, true, apply_list)
            return
        end

        local scene = player_scene.OFFICIAL_SCENE.FRIEND
        if player_scene_ready_flag[player_scene.OFFICIAL_SCENE.FRIEND_APPLY] then
            scene = player_scene.OFFICIAL_SCENE.FRIEND_APPLY
        end
        player_info.get_player_infos(target_ids, {playerid_to_info = true, scene=scene}, function(succ2, ...)
            if succ2 then
                local player_infos = ...
                for _, apply in ipairs(apply_list) do
                    if apply.target_id then
                        apply.target_player = player_infos[apply.target_id]
                    end
                end
                if cb then
                    cb(true, apply_list)
                end

                friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_to_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, true, apply_list)
            else
                if cb then
                    cb(false, ...)
                end
                friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_to_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, false, ...)
            end
        end)
    end, player_scene.OFFICIAL_SCENE.FRIEND_APPLY)
end

-- 这个接口是获取新的申请列表，新的意思是说，服务端会给客户端记录一个时间戳，服务端会返回这个时间戳之后的新好友，客户端调用该接口后，服务端会后移时间戳
function M.get_new_friend_apply_list(_params, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_new_friend_apply_list', friend_log.LOG_LEVEL.LOW, {}, _params, cb)

    local params = _params or {}
    friend_post('get_new_friend_apply_list', params, function (status, body)
        --_ejoysdk.log('get_new_friend_apply_list result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            -- 还需要添加目标 player_id 对应的 player_info
            local apply_list = body.friend_apply_list
            local target_ids = {}
            for _, apply in ipairs(apply_list) do
                if apply.target_id then
                    table.insert(target_ids, apply.target_id)
                end
            end

            if #target_ids == 0 then -- 兼容服务器没有返回 target id 的情况
                if cb then
                    cb(true, apply_list)
                end
                friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_friend_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, true, apply_list)
                return
            end

            local scene = player_scene.OFFICIAL_SCENE.FRIEND
            if player_scene_ready_flag[player_scene.OFFICIAL_SCENE.FRIEND_APPLY] then
                scene = player_scene.OFFICIAL_SCENE.FRIEND_APPLY
            end

            player_info.get_player_infos(target_ids, {playerid_to_info = true, scene=scene}, function(succ2, ...)
                if succ2 then
                    local player_infos = ...
                    for _, apply in ipairs(apply_list) do
                        if apply.target_id then
                            apply.target_player = player_infos[apply.target_id]
                        end
                    end

                    if cb then
                        cb(true, apply_list)
                    end

                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_friend_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, true, apply_list)
                else

                    if cb then
                        cb(false, ...)
                    end

                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_friend_apply_list', friend_log.LOG_LEVEL.LOW, {}, cb, false, ...)
                end
            end)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_friend_apply_list', friend_log.LOG_LEVEL.HIGH, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- get_new_friend_list：是获取所有rtype的好友，且是"新"好友，就是服务端会给客户端记录一个时间戳，服务端会返回这个时间戳之后的新好友，客户端调用该接口后，服务端会后移时间戳
-- get_friend_list：是获取某一个rtype的好友
-- get_new_friend_list、get_friend_list都是获取好友间信息，包括 ext之类的info, 不是friend_scene的角色字段
function M.get_new_friend_list(_params, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_new_friend_list', friend_log.LOG_LEVEL.LOW, {}, _params, cb)

    local params = _params or {}
    friend_post('get_new_friend_list', params, function (status, body)
        --_ejoysdk.log('get_new_friend_list result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            local friend_players = body.friend_list
            if cb then
                cb(true, friend_players)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_friend_list', friend_log.LOG_LEVEL.LOW, {}, cb, true, friend_players)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_friend_list', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.refuse_friend_apply_v2(player_id, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'refuse_friend_apply_v2', friend_log.LOG_LEVEL.LOW, {}, player_id, rtype, ext, cb)

    local params = {
        player_id = player_id,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('refuse_friend_apply', params, function (status, body)
        --_ejoysdk.log('拒绝好友申请 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'refuse_friend_apply_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'refuse_friend_apply_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.refuse_friend_apply(player_id, cb)
    M.refuse_friend_apply_v2(player_id, nil, nil, cb)
end

function M.refuse_friend_apply_batch_v2(player_ids, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'refuse_friend_apply_batch_v2', friend_log.LOG_LEVEL.LOW, {}, player_ids, rtype, ext, cb)

    local params = {
        player_ids = player_ids,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('refuse_friend_apply_batch', params, function (status, body)
        --_ejoysdk.log('拒绝批量好友申请 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'refuse_friend_apply_batch_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'refuse_friend_apply_batch_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.refuse_friend_apply_batch(player_ids, cb)
    M.refuse_friend_apply_batch_v2(player_ids, nil, nil, cb)
end

function M.del_friend_apply_v2(player_id, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'del_friend_apply_v2', friend_log.LOG_LEVEL.LOW, {}, player_id, rtype, ext, cb)

    local params = {
        player_id = player_id,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('del_friend_apply', params, function(status, body)
        --_ejoysdk.log('删除好友申请 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_apply_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_apply_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.del_friend_apply(player_id, cb)
    M.del_friend_apply_v2(player_id, nil, nil, cb)
end

function M.add_friend_black(player_id, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'add_friend_black', friend_log.LOG_LEVEL.LOW, {}, player_id, cb)

    local params = {
        player_id = player_id
    }

    friend_post('add_friend_black', params, function(status, body)
        --_ejoysdk.log('添加黑名单 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_black', friend_log.LOG_LEVEL.HIGH, {}, cb, true)
        else
            local code = body.code or status
            local msg = body.message or ''
            friend_jf.add_black_fail({code = code, msg = msg})

            if cb then
                cb(false, code, msg)
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_black', friend_log.LOG_LEVEL.HIGH, {}, cb, false, code, msg)
        end
    end)
end

function M.del_friend_black(player_id, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'del_friend_black', friend_log.LOG_LEVEL.LOW, {}, player_id, cb)

    local params = {
        player_id = player_id
    }

    friend_post('del_friend_black', params, function(status, body)
        --_ejoysdk.log('删除黑名单 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_black', friend_log.LOG_LEVEL.HIGH, {}, cb, true)
        else
            local code = body.code or status
            local msg = body.message or ''

            friend_jf.del_black_fail({code = code, msg = msg})

            if cb then
                cb(false, code, msg)
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_black', friend_log.LOG_LEVEL.HIGH, {}, cb, false, code, msg)
        end
    end)
end

function M.get_friend_black_list(cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_black_list', friend_log.LOG_LEVEL.LOW, {}, cb)

    local type = 'get_friend_black_list'
    local list_field_name = 'friend_black_list'
    local black_list_cursor = simple_cursor:New(type, list_field_name)
    black_list_cursor:load_all(function (...)
        if cb then
            cb(...)
        end

        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_black_list', friend_log.LOG_LEVEL.LOW, {}, cb, ...)
    end, player_scene.OFFICIAL_SCENE.BLACK_LIST)
end

-- 参数cb是失败的回调，参数channel_friends_callback是成功的回调
local function real_get_channel_friends(channel, cb, channel_friends_callback)
    friend_log.info(friend_log_util.header(), TAG, 'real_http_get', 'get_channel_friends', {channel=channel}, {})

    local params = {}
    params.channel = channel

    if not real_get_channel_friends_on_request_map[channel] or (real_get_channel_friends_on_request_map[channel] and next(real_get_channel_friends_on_request_map[channel]) == nil) then
        -- 为nil 或者 为空table, 说明是 同url+同channel 的第一个请求，不用return拦截
        real_get_channel_friends_on_request_map[channel] = {}
        table.insert(real_get_channel_friends_on_request_map[channel], {['fail_cb']=cb, ['succ_cb']=channel_friends_callback})
    else
        -- 已经有正在进行的请求了，return拦截掉，加入callback缓存即可，不用重复请求
        table.insert(real_get_channel_friends_on_request_map[channel], {['fail_cb']=cb, ['succ_cb']=channel_friends_callback})
        return
    end

    friend_post('get_channel_friend_list', params, function(status, body)
        -- bugfix: 增加默认值{}规避lua error。出现lua error的场景：正在请求时，调了player_offline/logout把real_get_channel_friends_on_request_map清空了，引发lua error
        local callback_cache_list = real_get_channel_friends_on_request_map[channel] or {}

        if status == 200 then
            local channel_friends = body.user_list
            friend_cache.add_channel_friends(channel, channel_friends)
            for _, callback_fail_succ_pair in pairs(callback_cache_list) do
                util.safe_call_cb(callback_fail_succ_pair.succ_cb, util.deepcopy(channel_friends))
            end

            local channel_friend_ids = {}
            for _,v in pairs(channel_friends) do
                if v.user_id then
                    table.insert(channel_friend_ids, v.user_id)
                end
            end

            friend_log.info(friend_log_util.header(), TAG, 'real_http_get_succ', 'get_channel_friends', {channel_friend_ids=channel_friend_ids}, {})
        else
            local code = body.code or status
            local msg = body.message or ''
            friend_log.warn(friend_log_util.header(), TAG, 'real_http_get_fail', {code = code, msg = msg}, {})

            for _, callback_fail_succ_pair in pairs(callback_cache_list) do
                util.safe_call_cb(callback_fail_succ_pair.fail_cb, false, code, msg)
            end
        end

        real_get_channel_friends_on_request_map[channel] = {}
    end)
end

-- 填充账号信息，渠道好友信息
local function fill_channel_friend_infos(channel, user_list, cb)
    local item_maps = {}
    local account_ids = {}
    for _, item in ipairs(user_list) do
        local account_id = item.user_id
        if account_id then
            item.account_id = account_id
            item_maps[account_id] = item
            table.insert(account_ids, item.user_id)
        end
    end

    if #account_ids == 0 then
        cb(true, user_list)
        return
    end

    --E.LOG.debug(TAG, "fill_channel_friend_infos before replace >>")
    --E.log(user_list)

    local function callback_with_infos(succ, ...)
        if succ then
            local new_user_list = {}
            for _account_id, mix_item in pairs(item_maps) do
                table.insert(new_user_list, mix_item)
            end

            --E.LOG.debug(TAG, "fill_channel_friend_infos after replace result >>")
            --E.log(new_user_list)
            cb(true, new_user_list)
        else
            cb(false, ...)
        end
    end

    if channel == friend_cache.CHANNELS.CUSTOMER then
        player_info.get_customer_infos(account_ids, function(succ, ...)
            if succ then
                local customer_infos = ...
                for _, info in ipairs(customer_infos) do
                    item_maps[info.account_id].channel_ext_info = info.account_info
                end

                if #customer_infos > 0 then
                    ET.publish(ET.account_chat.OPEN, customer_infos)
                end

                callback_with_infos(succ, item_maps)
            else
                callback_with_infos(false, ...)
            end
        end)
    else
        player_info.get_filled_player_account_infos(account_ids, function(succ, ...)
            if succ then
                local info_map = ...
                for account_id, info in pairs(info_map) do
                    item_maps[account_id].account_info = info
                end

                callback_with_infos(true, item_maps)
            else
                callback_with_infos(false, ...)
            end
        end)
    end
end

function M.get_channel_friends(channel, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_channel_friends', friend_log.LOG_LEVEL.HIGH, {}, channel, cb)

    -- 成功回调的wraper，作用是填充客服信息、账号信息(如果channel是客服，就填充客服信息；如果channel是FB等等其他渠道，就填充账号信息)
    local channel_friends_callback = function(channel_friends)
        fill_channel_friend_infos(channel, channel_friends, function (succ, ...)
            if not succ then
                local code, msg = ...
                friend_jf.get_friend_list_fail({method = 'get_channel_friends', code = code, msg = msg})
            end

            util.safe_call_cb(cb, succ, ...)
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_channel_friends', friend_log.LOG_LEVEL.LOW, {}, cb, succ, 'channel_friends_placeholder')
        end)
    end

    all_friend_channels[channel] = 1 -- 记录一下所有的channel, 后面自动刷新逻辑，会根据all_friend_channels刷新所有channels

    local channel_friends_cache = friend_cache.get_channel_friends(channel) -- 内部已经拷贝过
    if channel_friends_cache then
        local cache_user_ids = {}
        for _,item in pairs(channel_friends_cache) do
            if item.user_id then
                table.insert(cache_user_ids, item.user_id)
            end
        end

        friend_log.info(friend_log_util.header(), TAG, 'has_channel_friends_cache', 'get_channel_friends', {channel=channel, cache_user_ids=cache_user_ids}, {})
        channel_friends_callback(channel_friends_cache)
        return
    end

    real_get_channel_friends(channel, function (succ, ...)
        -- 只有请求失败，才会进这个cb
        if not succ then
            local code, msg = ...
            friend_jf.get_friend_list_fail({method = 'get_channel_friends', code = code, msg = msg})
        end

        util.safe_call_cb(cb, succ, ...)
        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_channel_friends', friend_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
    end, channel_friends_callback)
end

local function real_refresh_channel_friends(channel, cb)
    cb = cb or function(_is_succ, _error_code, _error_msg) end  -- 设置一个默认值作为兜底，后面要添加进table的，防止lua异常
    local params = {}
    params.channel = channel

    if not real_refresh_channel_friends_on_request_map[channel] or (real_refresh_channel_friends_on_request_map[channel] and next(real_refresh_channel_friends_on_request_map[channel]) == nil) then
        -- 为nil 或者 为空table, 说明是 同url+同channel 的第一个请求，不用return拦截
        real_refresh_channel_friends_on_request_map[channel] = {}
        table.insert(real_refresh_channel_friends_on_request_map[channel], cb)
    else
        -- 已经有正在进行的请求了，return拦截掉，加入callback缓存即可，不用重复请求
        table.insert(real_refresh_channel_friends_on_request_map[channel], cb)
        return
    end

    friend_post('refresh_channel_friend_list', params, function(status, body)
        -- bugfix: 增加默认值{}规避lua error。出现lua error的场景：正在请求时，调了player_offline/logout把real_refresh_channel_friends_on_request_map清空了，引发lua error
        local callback_cache_list = real_refresh_channel_friends_on_request_map[channel] or {}
        if status == 200 then
            refresh_channel_friends_cache = {['time']=os.time(), ['is_succ']=true}

            for _, callback in pairs(callback_cache_list) do
                util.safe_call_cb(callback, true)
            end
        else
            local error_code = body.code or status
            local error_msg = body.message or ''
            refresh_channel_friends_cache = {['time']=os.time(), ['is_succ']=false, ['error_code']=error_code, ['error_msg']=error_msg}

            for _, callback in pairs(callback_cache_list) do
                util.safe_call_cb(callback, false, error_code, error_msg)
            end
        end

        real_refresh_channel_friends_on_request_map[channel] = {}
    end)
end

function M.refresh_channel_friends(channel, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'refresh_channel_friends', friend_log.LOG_LEVEL.LOW, {}, channel, cb)

    all_friend_channels[channel] = 1 -- 记录一下所有的channel, 后续60min自动刷新，会根据all_friend_channels去刷新

    -- 缓存有效期60s, https://aliyuque.antfin.com/ejoy-platform/user_guide/oqoa0f#uekl8
    if next(refresh_channel_friends_cache) and os.time() <= refresh_channel_friends_cache.time + 60 then
        if refresh_channel_friends_cache.is_succ then
            util.safe_call_cb(cb, true)
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'refresh_channel_friends', friend_log.LOG_LEVEL.HIGH, {}, cb, refresh_channel_friends_cache.is_succ)
        else
            util.safe_call_cb(cb, false, refresh_channel_friends_cache.error_code or -1, refresh_channel_friends_cache.error_msg or '')
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'refresh_channel_friends', friend_log.LOG_LEVEL.HIGH, {}, cb, refresh_channel_friends_cache.is_succ, refresh_channel_friends_cache.error_code or -1, refresh_channel_friends_cache.error_msg or '')
        end
        return
    end

    real_refresh_channel_friends(channel, function (succ, ...)
        if not succ then
            local code, msg = ...
            friend_jf.get_friend_list_fail({method = 'refresh_channel_friends', code = code, msg = msg})
        end

        util.safe_call_cb(cb, succ, ...)
        friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'refresh_channel_friends', friend_log.LOG_LEVEL.LOW, {}, cb, succ, ...)
    end)
end

local function start_timer_60_minute()
    --_ejoysdk.log('60分钟的时限到了，开始准备请求几个接口')

    -- 好友id是实时的，可以不用做过期轮询
    --real_get_friend_id_list(function (success, ...) end)

    --if util.tablelength(all_friend_channels) == 0 then
        --_ejoysdk.log("all_friend_channels 数据是空的")
    --end

    --每60分钟请求一次，刷新缓存
    -- 遍历所有channel，分别请求另外两个接口，不被是否有缓存和时间所拦截
    for channel, _value in pairs(all_friend_channels) do
        --_ejoysdk.log('准备实际请求 ' .. channel .. ' 渠道的好友信息')
        real_get_channel_friends(channel, function (...) end, function (...) end)
        real_refresh_channel_friends(channel, function (...) end)
    end

    E.Timer.once(auto_refresh_time_gap, start_timer_60_minute)
end

E.Timer.once(auto_refresh_time_gap, start_timer_60_minute) -- 先执行一次

-- 关注相关逻辑 begin

function M.add_follow_v2(player_id, follow_type, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'add_follow_v2', friend_log.LOG_LEVEL.LOW, {}, player_id, follow_type, ext, cb)

    --_ejoysdk.log(TAG..'add_follow_start, player_id:'..(player_id or 'nil'))
    local params = {
        follow_user_id = player_id,
        follow_type = follow_type
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('add_follow', params, function (status, body)
        --_ejoysdk.log('添加关注 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true, body.follow_info)
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_follow_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.follow_info)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_follow_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- @description: 添加关注
-- @params: player_id: 角色ID, follow_type: 关系维度类型, cb：异步回调
-- @return true: 添加关注成功，false：添加关注失败，code: 错误码，message: 错误信息
function M.add_follow(player_id, cb)
    M.add_follow_v2(player_id, nil, nil, cb)
end

function M.del_follow_v2(player_id, follow_type, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'del_follow_v2', friend_log.LOG_LEVEL.LOW, {}, player_id, follow_type, ext, cb)

    local params = {
        follow_user_id = player_id,
        follow_type = follow_type
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end
    
    friend_post('del_follow', params, function (status, body)
        --_ejoysdk.log('删除关注 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_follow_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_follow_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- @description: 删除关注
-- @params: player_id: 角色ID, follow_type: 关系维度类型, cb：异步回调
-- @return true: 删除关注成功，false：添加关注失败，code: 错误码，message: 错误信息
function M.del_follow(player_id, cb)
    M.del_follow_v2(player_id, nil, nil, cb)
end

-- @description: 获得自己关注模块的玩家拓展信息
-- @params: cb：异步回调
-- @return
--- true: 获取成功
--- false：获取失败，code: 错误码，message: 错误信息
function M.get_follow_ext(cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_follow_ext', friend_log.LOG_LEVEL.LOW, {}, cb)

    friend_post('get_follow_ext', {}, function (status, body)
        --_ejoysdk.log('获得关注模块的玩家拓展信息 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            -- 信息列表
            if cb then
                cb(true, body.follow_ext)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_follow_ext', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.follow_ext)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_follow_ext', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.get_follow_id_list_v2(player_id, follow_type, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_follow_id_list_v2', friend_log.LOG_LEVEL.LOW, {}, player_id, follow_type, ext, cb)

    local params = {
        user_id = player_id,
        follow_type = follow_type
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('get_follow_id_list', params, function (status, body)
        --_ejoysdk.log('获得一个人的关注者用户id列表 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            -- 透传服务端返回信息
            if cb then
                cb(true, body.user_id_list)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_follow_id_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.user_id_list)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_follow_id_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- @description: 获得一个人的关注者用户id列表
-- @params: player_id: 目标角色ID，follow_type: 关系维度类型，cb：异步回调
-- @return
--- true:  获取成功
--- false：获取失败，code: 错误码，message: 错误信息
function M.get_follow_id_list(player_id, cb)
    M.get_follow_id_list_v2(player_id, nil, nil, cb)
end

local function get_player_info_map(player_ids, cb, scene)
    local player_maps = {}

    local safe_scene = player_scene.OFFICIAL_SCENE.FRIEND
    if player_scene_ready_flag[scene] then
        safe_scene = scene
    end

    player_info.get_player_infos(player_ids, {scene=safe_scene},function(succ, ...)
        if succ then
            local player_infos = ...
            for _, pinfo in ipairs(player_infos) do
                player_maps[pinfo.player_id] = pinfo
            end

            --_ejoysdk.log(TAG..'get_player_info_map succ')
            --E.log(player_maps)
            cb(true, player_maps)
        else
            local code, message = ...
            --_ejoysdk.log('get_player_info_map, get player infos fail')
            cb(false, code, message)
        end
    end)
end

local function fill_object_player_info(obj_list, player_id_key, cb, scene)
    if obj_list == nil then
        --_ejoysdk.log('fill_object_player_info failed obj_list is nil')
        cb(false, -1, 'obj_list is nil')
    end

    --收集player_ids
    local player_ids = {}
    for i=1, #obj_list do
        local player_id = obj_list[i][player_id_key]
        table.insert(player_ids, player_id)
    end

    get_player_info_map(player_ids, function(succ, ...)
        if succ then
            --_ejoysdk.log(TAG..'fill_object_player_info get_player_info_map succ')
            local player_maps = ...

            for i=1, #obj_list do
                local info = obj_list[i]
                info.player_detail_info = player_maps[info[player_id_key]]
            end

            --E.log(obj_list)
            cb(true, obj_list)
        else
            local code, msg = ...
            --_ejoysdk.log(TAG..'fill_object_player_info get_player_info_map failed, code:'..code..', msg:'..msg)
            cb(false, code, msg)
        end
    end, scene)
end

function M.get_follow_list_v2(player_id, follow_type, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_follow_list_v2', friend_log.LOG_LEVEL.LOW, {}, player_id, follow_type, ext, cb)

    local params = {
        user_id = player_id,
        follow_type = follow_type
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('get_follow_list', params, function (status, body)
        -- follow_user_id to player_infos
        --_ejoysdk.log('get_follow_list result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]

        if status == 200 then
            fill_object_player_info(body.follow_list, 'follow_user_id', function (...)

                if cb then
                    cb(...)
                end
                friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_follow_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, ...)
            end, player_scene.OFFICIAL_SCENE.FOLLOW)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_follow_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- @description: 获得一个人的关注列表
-- @params: player_id: 目标角色ID，follow_type: 关系维度类型，cb：异步回调
-- @return
--- true:  获取成功
--- false：获取失败，code: 错误码，message: 错误信息
function M.get_follow_list(player_id, cb)
    M.get_follow_list_v2(player_id, nil, nil, cb)
end

function M.get_followed_list_v2(last_index_time, follow_type, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, last_index_time, follow_type, ext, cb)

    local params = {
        last_index_time = last_index_time,
        follow_type = follow_type
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('get_followed_list', params, function (status, body)
        --_ejoysdk.log('获得一个玩家的被关注（粉丝）列表 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            fill_object_player_info(body.follow_list, 'follow_user_id', function(succ, ...)
                if succ then
                    if cb then
                        cb(true, body)
                    end
                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true, body)
                else
                    if cb then
                        cb(false, ...)
                    end
                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, ...)
                end
            end, player_scene.OFFICIAL_SCENE.FOLLOW)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- @description: 获得一个玩家的被关注（粉丝）列表
-- @params:
--  last_index_time： 上一分页的index_time, 当查询第一页时，不传该参数，
--  follow_type: 关系维度类型
--  cb：异步回调
-- @return
--- true:  获取成功
--- false：获取失败，code: 错误码，message: 错误信息
function M.get_followed_list(last_index_time, cb)
    M.get_followed_list_v2(last_index_time, nil, nil, cb)
end

function M.get_new_followed_list_v2(last_index_time, follow_type, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_new_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, last_index_time, follow_type, ext, cb)

    local params = {
        last_index_time = last_index_time,
        follow_type = follow_type
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end
    
    friend_post('get_new_followed_list', params, function (status, body)
        -- follow_user_id to player_infos
        --_ejoysdk.log('获得自己的新增的被关注（粉丝）列表 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        -]]
        if status == 200 then
            fill_object_player_info(body.follow_list, 'follow_user_id', function(succ, ...)
                if succ then
                    if cb then
                        cb(true, body)
                    end
                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true, body)
                else
                    if cb then
                        cb(false, ...)
                    end
                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, ...)
                end
            end, player_scene.OFFICIAL_SCENE.FOLLOW)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_new_followed_list_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

-- @description: 获得自己的新增的被关注（粉丝）列表
-- @params:
--  last_index_time： 上一分页的index_time, 当查询第一页时，不传该参数，
--  follow_type: 关系维度类型
--  cb：异步回调
-- @return
--- true:  获取成功
--- false：获取失败，code: 错误码，message: 错误信息
function M.get_new_followed_list(last_index_time, cb)
    M.get_new_followed_list_v2(last_index_time, nil, nil, cb)
end

function M.add_friend_group_v2(group_name, members, group_ext, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'add_friend_group_v2', friend_log.LOG_LEVEL.LOW, {}, group_name, members, group_ext, rtype, ext, cb)

    local params = {
        name = group_name,
        ext = group_ext,
        rtype = rtype
    }

    if #members > 0 then
        params.friend_player_id_list = members
    end

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    --E.log(params)

    friend_post('add_friend_group', params, function (status, body)
        --E.log('新建好友分组 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true, body.friend_group)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_group_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.friend_group)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_group_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.add_friend_group(group_name, members, group_ext, cb)
    M.add_friend_group_v2(group_name, members, group_ext, nil, nil, cb)
end

function M.del_friend_group(group_id, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'del_friend_group', friend_log.LOG_LEVEL.LOW, {}, group_id, cb)

    local params = {
        group_id = group_id
    }
    --E.log(params)

    friend_post('del_friend_group', params, function (status, body)
        --E.log('删除好友分组 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_group', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_group', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.get_friend_group_v2(rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_group_v2', friend_log.LOG_LEVEL.LOW, {}, rtype, ext, cb)

    local params = {rtype = rtype}

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end

    friend_post('get_friend_group', params, function (status, body)
        --E.log('获取好友分组 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true, body.friend_group_list)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_group_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.friend_group_list)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_group_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.get_friend_group(cb)
    M.get_friend_group_v2(nil, nil, cb)
end

function M.add_friend_group_member_v2(friend_player_id_list, group_id, rtype, ext, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'add_friend_group_member_v2', friend_log.LOG_LEVEL.LOW, {}, friend_player_id_list, group_id, rtype, ext, cb)

    local params = {
        friend_player_id_list = friend_player_id_list,
        group_id = group_id,
        rtype = rtype
    }

    if ext then
        for k, v in pairs(ext) do
            params[k] = v
        end
    end
    
    --E.log(params)

    friend_post('add_friend_group_member', params, function (status, body)
        --E.log('好友分组添加成员 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_group_member_v2', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'add_friend_group_member_v2', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.add_friend_group_member(friend_player_id_list, group_id, cb)
    M.add_friend_group_member_v2(friend_player_id_list, group_id, nil, nil, cb)
end

function M.del_friend_group_member(group_id, friend_player_id, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'del_friend_group_member', friend_log.LOG_LEVEL.LOW, {}, group_id, friend_player_id, cb)

    local params = {
        group_id = group_id,
        friend_player_id = friend_player_id
    }

    --E.log(params)
    friend_post('del_friend_group_member', params, function (status, body)
        --E.log('好友分组删除成员 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            if cb then
                cb(true)
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_group_member', friend_log.LOG_LEVEL.LOW, {}, cb, true)
        else
            if cb then
                cb(false, body.code or status, body.message or '')
            end
            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'del_friend_group_member', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

function M.get_friend_group_member(group_id, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'get_friend_group_member', friend_log.LOG_LEVEL.LOW, {}, group_id, cb)

    local params = {
        group_id = group_id
    }

    --E.log(params)
    friend_post('get_friend_group_member', params, function (status, body)
        --E.log('获取好友分组成员 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            local ids = {}
            for _, info in ipairs(body.friend_list) do
                table.insert(ids, info.user_id)
            end
            player_info.get_player_infos(ids, {playerid_to_info = true, scene=player_scene.OFFICIAL_SCENE.FRIEND},  function(succ, ...)
                if succ then
                    local players = ...
                    for _, info in pairs(body.friend_list) do -- 往 friend_list 填充玩家信息
                        if info.user_id and players[info.user_id] then
                            info.player = players[info.user_id]
                        end
                    end

                    if cb then
                        cb(true, body.friend_list)
                    end

                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_group_member', friend_log.LOG_LEVEL.LOW, {}, cb, true, body.friend_list)
                else

                    if cb then
                        cb(false, -1, 'get player info fail')
                    end

                    friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_group_member', friend_log.LOG_LEVEL.LOW, {}, cb, false, -1, 'get player info fail')
                end
            end)
        else

            if cb then
                cb(false, body.code or status, body.message or '')
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'get_friend_group_member', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

--[[
    body的结构：
    table: 0x7449236980{
       ["body"] => table: 0x7449236880{
          ["message"] => "ok"
          ["invaild_list"] => table: 0x74492368c0{
             [1] => table: 0x7449236900{
                ["order"] => 1
                ["group_id"] => "610cd47d4bde7103a8212fa6"
                ["ext"] => table: 0x7449236940{
                }
                ["name"] => "敏感的人的名字XXX"
                ["code"] => 20100
             }
          }
          ["code"] => 0
       }
       ["status"] => 200
    }
--]]
function M.update_friend_group_info(group_infos, cb)
    friend_log.call_api(friend_log_util.header(), TAG, 'update_friend_group_info', friend_log.LOG_LEVEL.LOW, {}, group_infos, cb)

    local params = {
        update_list = group_infos
    }

    --E.log(params)

    friend_post('update_friend_group_info', params, function (status, body)
        --E.log('更新好友分组信息 result')
        --[[
        E.log({
            status = status,
            body = body
        })
        --]]
        if status == 200 then
            -- 把invaild_list返给游戏， body的结构，详见上方注释
            if cb then
                cb(true, body or {})
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'update_friend_group_info', friend_log.LOG_LEVEL.LOW, {}, cb, true, body or {})
        else

            if cb then
                cb(false, body.code or status, body.message or '')
            end

            friend_log.call_api_async_callback(friend_log_util.header(), TAG, 'update_friend_group_info', friend_log.LOG_LEVEL.LOW, {}, cb, false, body.code or status, body.message or '')
        end
    end)
end

return M