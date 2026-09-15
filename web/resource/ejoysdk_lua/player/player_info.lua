local E = require 'ejoysdk_lua.ejoysdk'
local EH = require 'ejoysdk_lua.ejoysdk_holo'
local player_cache = require "ejoysdk_lua.player.player_info_cache"
local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local util = require 'ejoysdk_lua.ejoysdk_utils'
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local player_scene = require 'ejoysdk_lua.player.player_info_scene'
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local EM = require "ejoysdk_lua.ejoysdk_module"
local player_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local player_log_util = require 'ejoysdk_lua.player.player_log_util'
local ET = require "ejoysdk_lua.ejoysdk_topic"
local STATES = require 'ejoysdk_lua.chat.ejoysdk_chat_states'

local TAG = EM.MODULE.PLAYER .. 'player_info'
local M = {}
local HTTP = E.HTTP

local module_inited = false

M.CACHE = player_cache

M.INFO_TYPES = {
    TYPE_PLAYER_INFOS = "player_infos",
    TYPE_ACCOUNT_INFOS = "account_infos",
    TYPE_CUSTOMER_INFOS = "customer_infos"
}

M.IDS = {
    IDS_PLAYER = "player_ids",
    IDS_ACCOUNT = "account_ids",
    IDS_CUSTOMER = "customer_account_ids"
}

M.PERSONAL_USER_TYPE = {
    CUSTOMER = 'cs',
    ACCOUNT = 'account',
    PLAYER = 'player'
}

M.PERSONAL_USER_TYPE_TO_INFO_TYPE = {
    [M.PERSONAL_USER_TYPE.PLAYER] = M.INFO_TYPES.TYPE_PLAYER_INFOS,
    [M.PERSONAL_USER_TYPE.CUSTOMER] = M.INFO_TYPES.TYPE_CUSTOMER_INFOS,
    [M.PERSONAL_USER_TYPE.ACCOUNT] = M.INFO_TYPES.TYPE_ACCOUNT_INFOS
}

-- 聊天系统中账号类型user_id的前缀
M.USER_ID_PREFIX_ACCOUNT = 'acc_'
-- 聊天系统中客服类型user_id的前缀
M.USER_ID_PREFIX_CUSTOMER_SERVICE = 'cs_'

local start_with = E.Utils.start_with

function M.get_user_type_info(chat_user_id)
    player_log.call_api(player_log_util.header(), TAG, 'get_user_type_info', player_log.LOG_LEVEL.LOW, {}, chat_user_id)

    local chat_ret = {}
    chat_ret.chat_user_id = chat_user_id
    if start_with(chat_user_id, M.USER_ID_PREFIX_ACCOUNT) then
        chat_ret.personal_user_type = M.PERSONAL_USER_TYPE.ACCOUNT
        chat_ret.user_id = chat_user_id:gsub(M.USER_ID_PREFIX_ACCOUNT, '')
    elseif start_with(chat_user_id, M.USER_ID_PREFIX_CUSTOMER_SERVICE) then
        chat_ret.personal_user_type = M.PERSONAL_USER_TYPE.CUSTOMER
        -- 对于SDK侧，客服的user_id需要包含前缀，即cs_xxx
        chat_ret.user_id = chat_user_id
    else
        chat_ret.personal_user_type = M.PERSONAL_USER_TYPE.PLAYER
        chat_ret.user_id = chat_user_id
    end

    local res = chat_ret

    player_log.call_api_sync_return(player_log_util.header(), TAG, 'get_user_type_info', player_log.LOG_LEVEL.LOW, {}, res)

    return res
end

function M.classify_ids(ids, uid)
    player_log.call_api(player_log_util.header(), TAG, 'classify_ids', player_log.LOG_LEVEL.LOW, {}, ids, uid)

    if uid == nil or uid == '' then
        E.LOG.debug(TAG, "classify_ids user_id is nil or empty")
        return
    end

    local user_type_info = M.get_user_type_info(uid)
    local user_id = user_type_info.user_id
    local personal_user_type = user_type_info.personal_user_type
    E.LOG.debug(TAG, "classify_ids user_id:"..user_id..", personal_user_type:"..personal_user_type)
    if personal_user_type == M.PERSONAL_USER_TYPE.PLAYER then
        ids[M.IDS.IDS_PLAYER] = ids[M.IDS.IDS_PLAYER] or {}
        table.insert(ids[M.IDS.IDS_PLAYER], user_id)
    elseif personal_user_type == M.PERSONAL_USER_TYPE.ACCOUNT then
        ids[M.IDS.IDS_ACCOUNT] = ids[M.IDS.IDS_ACCOUNT] or {}
        table.insert(ids[M.IDS.IDS_ACCOUNT], user_id)
    elseif personal_user_type == M.PERSONAL_USER_TYPE.CUSTOMER then
        ids[M.IDS.IDS_CUSTOMER] = ids[M.IDS.IDS_CUSTOMER] or {}
        table.insert(ids[M.IDS.IDS_CUSTOMER], user_id)
    end

    player_log.call_api_sync_return(player_log_util.header(), TAG, 'classify_ids', player_log.LOG_LEVEL.LOW, {}, ids)
end

function M.find_and_copy_in_combined_infos(combined_user_infos, chat_user_id)
    player_log.call_api(player_log_util.header(), TAG, 'find_and_copy_in_combined_infos', player_log.LOG_LEVEL.LOW, {}, combined_user_infos, chat_user_id)

    if chat_user_id == nil or chat_user_id == '' then
        --E.LOG.d(TAG, "find_and_copy_in_combined_infos chat_user_id is nil return nil user_info")
        return nil
    end

    local account_infos = combined_user_infos[M.INFO_TYPES.TYPE_ACCOUNT_INFOS]
    local player_infos = combined_user_infos[M.INFO_TYPES.TYPE_PLAYER_INFOS]
    local customer_infos = combined_user_infos[M.INFO_TYPES.TYPE_CUSTOMER_INFOS]

    local user_type_info = M.get_user_type_info(chat_user_id)
    local real_user_id = user_type_info.user_id
    local personal_user_type = user_type_info.personal_user_type
    local base_user_infos = nil
    if personal_user_type == M.PERSONAL_USER_TYPE.ACCOUNT then
        base_user_infos = account_infos
    elseif personal_user_type == M.PERSONAL_USER_TYPE.PLAYER then
        base_user_infos = player_infos
    elseif personal_user_type == M.PERSONAL_USER_TYPE.CUSTOMER then
        base_user_infos = customer_infos
    end

    local user_info = nil
    if base_user_infos then
        user_info = base_user_infos[real_user_id]
        if user_info then
            user_info = util.deepcopy(user_info)
            user_info.user_id = real_user_id
            user_info.chat_user_id = chat_user_id
            user_info.user_type = user_type_info.personal_user_type
        end
    end

    --E.LOG.debug(TAG, "find_and_copy_in_combined_infos result >>")
    --E.log(user_info)

    player_log.call_api_sync_return(player_log_util.header(), TAG, 'find_and_copy_in_combined_infos', player_log.LOG_LEVEL.LOW, {}, user_info)

    return user_info
end

local function require_params(token)
    return {
        acceptable = E.HTTP.CT_JSON,
        headers = {['Ejoy-Token'] = token}
    }
end

local function require_player_params()
    local player_token = EH.get_player_token()
    local player_params = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['moment-Token'] = player_token},
        _log_config = {disable = true}
    }

    return player_params
end

local function https_get_player_infos(player_ids, params, cb)
    local user_info_url = E.CONFIG.get_config('user-info')
    local api_str = '/player_api/get_player_info_list'
    local url = user_info_url .. api_str

    local players = {}

    local count = #player_ids
    local MAX_COUNT_EACH_BATCH = 200

    local function get_one_batch_player_ids()
        local ids = {}
        if count > MAX_COUNT_EACH_BATCH then
            local i = MAX_COUNT_EACH_BATCH
            while i > 0 do
                table.insert(ids, table.remove(player_ids, 1))
                i = i - 1
                count = count - 1
            end
        else
            count = 0
            ids = player_ids
        end
        return ids
    end

    local https_func = nil

    local function callback(succ, ...)
        if succ then
            local new_players = ...
            for _, player in pairs(new_players) do
                table.insert(players, player)
            end
            if count > 0 then
                https_func()
            else
                cb(true, players)
            end
        elseif #players > 0 then -- 当批请求失败，但之前批有成功
            cb(true, players)
        else
            cb(false, ...)
        end
    end

    local function https_get_player_infos_inner()
        local ids = get_one_batch_player_ids()
        local http_body = {
            player_id_list = ids
        }
        for key, value in pairs(params) do
            http_body[key] = value
        end

        local http_params = require_player_params()

        E.LOG.debug(TAG, 'https_get_player_infos >>')
        player_log.debug(player_log_util.header(), TAG, 'https_get_player_infos_req', 'https_get_player_infos', {http_params=http_params, http_body=http_body, url=url}, {})

        E.HTTP.post(url, http_params, E.HTTP.CT_JSON, http_body, function(resp)
            --E.LOG.debug(TAG, '新获取玩家信息列表 result')
            --E.log(resp)
            if resp.status == 200 then
                if resp.body then
                    if resp.body.code == 0 then
                        callback(true, resp.body.player_list, resp.body.scene_info)

                        local log_players = player_log_util.simple_player_infos(resp.body.player_list)
                        local log_player_sections = player_log.list_by_section(log_players, 5)
                        for _,v in pairs(log_player_sections) do
                            player_log.debug(player_log_util.header(), TAG, 'https_get_player_infos_resp_succ', 'https_get_player_infos', {section=v}, {})
                        end

                        if #ids > #(resp.body.player_list or {}) then
                            local resp_player_ids = {}
                            for _,resp_player in pairs(resp.body.player_list) do
                                if resp_player.player_id then
                                    table.insert(resp_player_ids, resp_player.player_id)
                                end
                            end
                            ESTAT.stat_error_with_limit(TAG, 'get_player_infos_fail_on_count_less', 'get_player_infos_fail_on_count_less', 'chat_err_get_player_infos_fail', {player_id_list=ids, resp_player_list=resp_player_ids})
                        end
                    else
                        callback(false, resp.body.code, resp.body.message)

                        player_log.warn(player_log_util.header(), TAG, 'https_get_player_infos_resp_fail', {code=resp.body.code, msg=resp.body.message}, {})

                        ESTAT.stat_error_with_limit(TAG, 'get_player_infos_fail_on_server_error', 'get_player_infos_fail_on_server_error', 'chat_err_get_player_infos_fail', {player_id_list=ids, code=(resp.body.code or 'null'), msg=(resp.body.message or 'null')})
                    end
                else
                    callback(false, -1, 'http nil body')

                    player_log.warn(player_log_util.header(), TAG, 'https_get_player_infos_resp_fail', {code=-1, msg='http nil body'}, {})

                    ESTAT.stat_error_with_limit(TAG, 'get_player_infos_fail_on_body_nil', 'get_player_infos_fail_on_body_nil', 'chat_err_get_player_infos_fail', {player_id_list=ids})
                end
            else
                ESTAT.stat_error_with_limit(TAG, 'get_player_infos_fail_on_http_error', 'get_player_infos_fail_on_http_error', 'chat_err_get_player_infos_fail', {player_id_list=ids, status=(resp.status or 'null')})
                callback(false, resp.status, '')

                player_log.warn(player_log_util.header(), TAG, 'https_get_player_infos_resp_fail', {code=resp.status, msg=''}, {})
            end
        end)
    end

    https_func = https_get_player_infos_inner

    https_get_player_infos_inner()
end

local function get_cache_player(player_id, opts)
    if opts.use_cache == false then
        return player_cache.get_player_info_with_expire(player_id, 30, opts.scene)
    else
        return player_cache.get_player_info(player_id, opts.scene)
    end
end

--[[
opts.playerid_to_info
opts.use_cache
opts.scene:指定获取xx场景的角色信息

推荐业务方指定场景来获取，sdk侧内置了4个官方场景(default、chat、bbs、friend),
 这4个官方场景SDK提供了常量，详见player_info_scene.lua
 opts.scene=player_info_scene.official_scene.default表示的是获取defalut场景的角色，
 opts.scene=player_info_scene.official_scene.chat表示的是获取chat场景的角色，bbs场景、friend场景同理。

 针对这4个官方场景，SDK扩展了player_info的获取角色方法,新增4个方法：
 get_player_infos_default_scene()
 get_player_infos_chat_scene()
 get_player_infos_bbs_scene()
 get_player_infos_friend_scene()
 最佳实践：业务方如果是获取这4个官方场景的角色信息，推荐通过这4个便利方法去获取，只有获取自定义场景的角色信息，
 才应该使用get_player_infos()方法
--]]
function M.get_player_infos(player_ids, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, '<<<<<<<<<<<< get_player_infos >>>>>>>>>>', player_log.LOG_LEVEL.LOW, {}, player_ids, opts, cb)
    opts = opts or {}

    if type(opts) == 'function' then
        cb = opts
        opts = {}
    end

    -- 没有场景，就按默认场景去取
    if not opts.scene then
        opts.scene = player_scene.OFFICIAL_SCENE.DEFAULT
    end

    local unique_player_ids = {} -- 去重的ids

    for _, player_id in ipairs(player_ids) do
        unique_player_ids[player_id] = true -- 客户端做去重，避免一些场景发送大量重复的 player id 到服务器查询。比如聊天记录更新角色信息
    end

    local uncache_player_ids = {}
    local player_infos = {}

    for player_id, _ in pairs(unique_player_ids) do
        local cached_player = get_cache_player(player_id, opts)
        if cached_player then
            player_infos[player_id] = cached_player
        else
            table.insert(uncache_player_ids, player_id)
        end
    end

    E.log('get player, uncache player ids: ' .. tostring(#uncache_player_ids))
    E.log({
        uncache_player_ids = uncache_player_ids
    })

    local function callback_succ()
        if opts.playerid_to_info then
            if cb then
                cb(true, player_infos)
            end

            local temp_list = {}
            for _,v in pairs(player_infos) do
                table.insert(temp_list, v)
            end

            local simple_players = player_log_util.simple_player_infos(temp_list)
            local simple_player_sections = player_log.list_by_section(simple_players, 5)
            for _,v in pairs(simple_player_sections) do
                player_log.debug(player_log_util.header(), TAG, 'log_player_infos', 'chat_log_player_infos', {simple_player_section=v}, {})
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, 'player_infos_placeholder')
            --cb(true, player_infos)
        else
            local sorted_player_infos = {} -- 尽量按参数的 ids 进行排序
            for _, player_id in pairs(player_ids) do
                table.insert(sorted_player_infos, player_infos[player_id])
            end
            if cb then
                cb(true, sorted_player_infos)
            end

            local simple_players = player_log_util.simple_player_infos(sorted_player_infos)
            local simple_player_sections = player_log.list_by_section(simple_players, 5)
            for _,v in pairs(simple_player_sections) do
                player_log.debug(player_log_util.header(), TAG, 'log_player_infos', 'chat_log_player_infos', {simple_player_section=v}, {})
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, 'player_infos_placeholder')
            --cb(true, sorted_player_infos)
        end
    end

    local function get_uncache_player_infos_from_server(scene)
        --E.LOG.debug(TAG, 'get_uncache_player_infos_from_server')

        local params = {scene_id = scene}

        -- 已和服务端约定:
        -- 1、不传scene_hash表示不需要scene_info，为了兼容旧版本;
        -- 2、传scene_hash空串表示需要scene_info，且客户端本地没有scene_info
        --
        -- 本地找不到scene_hash, 就传空字符串，结合上述约定，一定要传空串
        local scene_for_md5 = 'default'
        if scene and #scene > 0 then
            scene_for_md5 = scene
        end
        local scene_md5 = player_scene.get_scene_md5(scene_for_md5)
        if #scene_md5 > 0 then
            params.scene_hash = scene_md5
        else
            params.scene_hash = ''
        end

        --E.log({params=params})

        https_get_player_infos(uncache_player_ids, params, function(succ, ...)
            if succ then
                local uncache_players, server_scene_info = ...

                --E.log({uncache_players=uncache_players, server_scene_info=server_scene_info})
                -- 存入内存缓存
                if server_scene_info then
                    local scene_info = player_scene.transform_to_scene_info(server_scene_info.params.player_info)
                    local selected_all = server_scene_info.params.player_info["selected_all"]
                    local md5 = server_scene_info.hash
                    player_scene.set_scene_info(scene, scene_info, selected_all, md5)
                end

                for _, player in pairs(uncache_players) do
                    -- 先写入缓存，再读取缓存的数据，缓存保证返回的是最新的数据
                    player_cache.add_player_info_unsafe(player.player_id, player, 'user_info_http', scene)
                    player_infos[player.player_id] = player_cache.get_player_info(player.player_id, scene)
                end
                callback_succ()
            else
                if cb then
                    cb(false, ...)
                end
                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
                --cb(false, ...)
            end
        end)
    end

    if #uncache_player_ids == 0 then
        callback_succ()
        return
    end

    if opts.scene then
        player_scene.get_scene_info(opts.scene, function(succ, ...)
            if succ then
                get_uncache_player_infos_from_server(opts.scene)
            else
                if cb then
                    cb(false, ...)
                end
                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
                --cb(false, ...)
            end
        end)
    else
        get_uncache_player_infos_from_server()
    end
end

-- 获取官方场景default场景的角色信息(批量)
function M.get_player_infos_default_scene(player_ids, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_infos_default_scene', player_log.LOG_LEVEL.LOW, {}, player_ids, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成default，因为该方法是专门获取默认场景的角色信息
    opts.scene = player_scene.OFFICIAL_SCENE.DEFAULT

    M.get_player_infos(player_ids, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos_default_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 获取官方场景chat的角色信息(批量)
function M.get_player_infos_chat_scene(player_ids, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_infos_chat_scene', player_log.LOG_LEVEL.LOW, {}, player_ids, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成chat，因为该方法是专门获取chat场景的角色信息
    opts.scene = player_scene.OFFICIAL_SCENE.CHAT

    M.get_player_infos(player_ids, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos_chat_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 获取官方场景bbs的角色信息(批量)
function M.get_player_infos_bbs_scene(player_ids, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_infos_bbs_scene', player_log.LOG_LEVEL.LOW, {}, player_ids, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成bbs，因为是bbs场景
    opts.scene = player_scene.OFFICIAL_SCENE.BBS

    M.get_player_infos(player_ids, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos_bbs_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 获取friend场景的角色信息(批量)
function M.get_player_infos_friend_scene(player_ids, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_infos_friend_scene', player_log.LOG_LEVEL.LOW, {}, player_ids, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成friend，因为该方法是专门获取friend场景的角色信息
    opts.scene = player_scene.OFFICIAL_SCENE.FRIEND

    return M.get_player_infos(player_ids, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_infos_friend_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

--[[
opts.use_cache
opts.scene：指定场景
该方法是 get_player_infos(player_ids, opts, cb) 的获取单个角色的版本

SDK增加 获取官方场景的角色方法：
 get_player_info_default_scene()
 get_player_info_chat_scene()
 get_player_info_bbs_scene()
 get_player_info_friend_scene()

最佳实践：业务方如果是获取这4个官方场景的角色信息，推荐通过这4个便利方法去获取，只有获取自定义场景的角色信息，
 才应该使用get_player_info()方法
--]]
function M.get_player_info(player_id, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_info', player_log.LOG_LEVEL.LOW, {}, player_id, opts, cb)

    if type(opts) == 'function' then
        cb = opts
        opts = {}
    end
    local player_ids = {}
    table.insert(player_ids, player_id)
    M.get_player_infos(player_ids, opts, function(succ, ...)
        if succ then
            local players = ...
            --cb(true, players[1])
            if cb then
                cb(true, players[1])
            end
            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_info', player_log.LOG_LEVEL.LOW, {}, cb, true, players[1])
        else
            --cb(false, ...)
            if cb then
                cb(false, ...)
            end
            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_info', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
        end
    end)
end

-- 获取官方场景default的角色信息
function M.get_player_info_default_scene(player_id, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_info_default_scene', player_log.LOG_LEVEL.LOW, {}, player_id, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成default，因为该方法是专门获取默认场景的角色信息
    opts.scene = player_scene.OFFICIAL_SCENE.DEFAULT

    M.get_player_info(player_id, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_info_default_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 获取官方场景chat的角色信息
function M.get_player_info_chat_scene(player_id, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_info_chat_scene', player_log.LOG_LEVEL.LOW, {}, player_id, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成chat，因为该方法是专门获取chat场景的角色信息
    opts.scene = player_scene.OFFICIAL_SCENE.CHAT

    return M.get_player_info(player_id, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_info_chat_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 获取官方场景bbs的角色信息
function M.get_player_info_bbs_scene(player_id, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_info_bbs_scene', player_log.LOG_LEVEL.LOW, {}, player_id, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成bbs，因为是bbs场景
    opts.scene = player_scene.OFFICIAL_SCENE.BBS

    M.get_player_info(player_id, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_info_bbs_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- 获取friend场景的角色信息
function M.get_player_info_friend_scene(player_id, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_info_friend_scene', player_log.LOG_LEVEL.LOW, {}, player_id, opts, cb)

    opts = opts or {}

    -- 不管外界传的scene是什么场景id, 强制改成friend，因为该方法是专门获取friend场景的角色信息
    opts.scene = player_scene.OFFICIAL_SCENE.FRIEND

    M.get_player_info(player_id, opts, function (...)
        if cb then
            cb(...)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_info_friend_scene', player_log.LOG_LEVEL.LOW, {}, cb, ...)
    end)
end

-- @Describe: get play vip info.
-- The vip info is not a basic info, and it should not affect the player_info logic, so it's a independent method, and it depends on the holo server
function M.get_player_vip_info(player_id, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_player_vip_info', player_log.LOG_LEVEL.LOW, {}, player_id, cb)

    --get ptoken, moment-token, server_id
    local user_info = EG.user_info()
    if not user_info.ptoken or not user_info.token then
        --_ejoysdk.log(TAG..'get_player_vip_info failed, ptoken:'..(user_info.ptoken or 'nil')..', ejoy_token:'..(user_info.token or 'nil'))
        --cb(false, -1, "user ptoken or ejoy_token is invalid");
        if cb then
            cb(false, -1, "user ptoken or ejoy_token is invalid")
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_vip_info', player_log.LOG_LEVEL.LOW, {}, cb, false, -1, "user ptoken or ejoy_token is invalid")
    else
        local server_id = EG.player_info().server_id
        --_ejoysdk.log(TAG..'获取角色信息 成功, player_id:'..(player_id or 'nil')..', server_id:'..(server_id or 'nil'))
        if not server_id or not player_id then
            --_ejoysdk.log(TAG..'get_player_vip_info failed, server_id or player_id is not valid: nil')
            --cb(false, -1, "user server_id or player_id is invalid");
            if cb then
                cb(false, -1, "user server_id or player_id is invalid")
            end
            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_vip_info', player_log.LOG_LEVEL.LOW, {}, cb, false, -1, "user server_id or player_id is invalid")
            return
        end

        local vip_info_url = EG.gangplank_logined_url('/account_vip_info', '2')
        --_ejoysdk.log(TAG..'get player vip info url: ' .. vip_info_url)

        local params = {}
        params.ptoken = user_info.ptoken
        params.server_id = server_id
        params.player_id = player_id

        HTTP.post(
                vip_info_url,
                require_params(user_info.token),
                HTTP.CT_JSON,
                params,
                function(resp)
                    --_ejoysdk.log('get player vip info resp, status:'..resp.status)
                    --E.log(resp)
                    if resp.status == 200 then
                        if resp.body.code == 0 then
                            if cb then
                                cb(true, resp.body.vipinfo or {})
                            end
                            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_vip_info', player_log.LOG_LEVEL.LOW, {}, cb, true, resp.body.vipinfo or {})
                        else
                            if cb then
                                cb(false, resp.body.code, resp.body.message)
                            end
                            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_vip_info', player_log.LOG_LEVEL.LOW, {}, cb, false, resp.body.code, resp.body.message)
                        end
                    else
                        if cb then
                            cb(false, resp.status, '')
                        end
                        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_player_vip_info', player_log.LOG_LEVEL.LOW, {}, cb, false, resp.status, '')
                    end
                end
        )
    end
end

local function rpc_get_account_infos(account_ids, cb)
    local prefix = E.CONFIG.get_config('user-info')
    local url = prefix .. '/client_api/get_account_infos'
    local token = EG.user_info().token

    local headers = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['Ejoy-Token']= token}
    }
    local params = {
        account_ids = account_ids
    }

    --E.LOG.debug(TAG, "rpc_get_account_infos, url:"..url..", params >>")
    --E.log(params)
    E.HTTP.post(url, headers, E.HTTP.CT_JSON, params, function(resp)
        --E.LOG.debug(TAG,'rpc_get_account_infos resp >>')
        --E.log(resp)
        if resp.status == 200 then
            if resp.body.code == 0 then
                cb(true, resp.body.account_list)
            else
                cb(false, resp.body.code, resp.body.message or '')
            end
        else
            cb(false, resp.status, '')
        end
    end)
end

local function http_get_customer_infos(account_ids, cb)
    local prefix = E.CONFIG.get_config('user-info')
    local api_str = '/player_api/get_chat_customer_info_list'
    local url = prefix .. api_str

    local params = {
        chat_user_ids = account_ids
    }

    --E.LOG.debug(TAG, "http_get_customer_infos, url:"..url..", params >>")
    --E.log(params)
    E.HTTP.post(url, require_player_params(), E.HTTP.CT_JSON, params, function(resp)
        --E.LOG.debug(TAG,'http_get_customer_infos response >>')
        --E.log(resp)
        if resp.status == 200 then
            if resp.body.code == 0 then
                cb(true, resp.body.account_list)
            else
                cb(false, resp.body.code, resp.body.message or '')
            end
        else
            cb(false, resp.status, '')
        end
    end)
end

-- 接口描述：游戏转服接口
function M.player_change_server(target_player_id, target_server_id, cb)
    player_log.call_api(player_log_util.header(), TAG, 'player_change_server', player_log.LOG_LEVEL.LOW, {}, target_player_id, target_server_id, cb)

    if not target_server_id or target_server_id == '' then
        cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_SERVERID_INVALID, 'server id is nil')
        return
    end

    local prefix = E.CONFIG.get_config('user-info')
    local url = prefix .. '/client_api/player_change_server'
    local token = EG.user_info().token

    local headers = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['Ejoy-Token']= token}
    }
    local params = {
        want_to_server_id = target_server_id,
        player_id = target_player_id
    }

    --E.LOG.debug(TAG, "player_change_server, url:"..url..", params >>")
    --E.log(params)
    E.HTTP.post(url, headers, E.HTTP.CT_JSON, params, function(resp)
        --E.LOG.debug(TAG,'player_change_server resp >>')
        --E.log(resp)
        if resp.status == 200 then
            if resp.body.code == 0 or resp.body.code == 200 then
                if cb then
                    cb(true, resp.body)
                end
                player_log.call_api_async_callback(player_log_util.header(), TAG, 'player_change_server', player_log.LOG_LEVEL.LOW, {}, cb, true, resp.body)
            else
                if cb then
                    cb(false, resp.body.code, resp.body.message or '')
                end
                player_log.call_api_async_callback(player_log_util.header(), TAG, 'player_change_server', player_log.LOG_LEVEL.LOW, {}, cb, false, resp.body.code, resp.body.message or '')
            end
        else
            if cb then
                cb(false, resp.status, '')
            end
            player_log.call_api_async_callback(player_log_util.header(), TAG, 'player_change_server', player_log.LOG_LEVEL.LOW, {}, cb, false, resp.status, '')
        end
    end)
end

-- 接口描述：游戏批量转服接口
function M.batch_player_change_server(change_list, cb)
    player_log.call_api(player_log_util.header(), TAG, 'batch_player_change_server', player_log.LOG_LEVEL.LOW, {}, change_list, cb)

    local prefix = E.CONFIG.get_config('user-info')
    local url = prefix .. '/client_api/batch_player_change_server'
    local token = EG.user_info().token

    local headers = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['Ejoy-Token']= token}
    }

    local change_info_list = {}

    for player_id, change_server in pairs(change_list) do
        --E.log('change player_id: ' .. tostring(player_id) .. ' to server: ' .. tostring(change_server))
        table.insert(change_info_list, {
            player_id = player_id,
            want_to_server_id = change_server
        })
    end

    local length = #change_info_list
    local count = 0
    local ONE_BATCH_LENGTH = 30

    local result = {}

    local function request_one_batch()
        local one_batch_change_info_list = {}

        local one_batch_count = 0
        while one_batch_count < ONE_BATCH_LENGTH and count < length do
            one_batch_count = one_batch_count + 1
            count = count + 1
            --E.log('count: ' .. tostring(count))
            table.insert(one_batch_change_info_list, change_info_list[count])
        end

        local params = {
            change_info_list = one_batch_change_info_list
        }

        E.HTTP.post(url, headers, E.HTTP.CT_JSON, params, function(resp)
            --E.LOG.debug(TAG,'batch_player_change_server resp >>')
            --E.log(resp.status)
            if resp.status == 200 then
                if resp.body.code == 0 or resp.body.code == 200 then
                    for _, item in ipairs(resp.body.change_result) do
                        table.insert(result, item)
                    end

                    if count < length then
                        request_one_batch()
                    else
                        if cb then
                            cb(true, result)
                        end
                        player_log.call_api_async_callback(player_log_util.header(), TAG, 'player_change_server', player_log.LOG_LEVEL.LOW, {}, cb, true, result)
                    end
                else
                    if cb then
                        cb(false, resp.body.code, resp.body.message or '')
                    end
                    player_log.call_api_async_callback(player_log_util.header(), TAG, 'player_change_server', player_log.LOG_LEVEL.LOW, {}, cb, false, resp.body.code, resp.body.message or '')
                end
            else
                --cb(false, resp.status, '')
                if cb then
                    cb(false, resp.status, '')
                end
                player_log.call_api_async_callback(player_log_util.header(), TAG, 'player_change_server', player_log.LOG_LEVEL.LOW, {}, cb, false, resp.status, '')
            end
        end)
    end

    --E.LOG.debug(TAG, "batch_player_change_server, url:"..url..", params >>")

    request_one_batch()
end

function M.get_self_account_info(cb)
    local account_id = EG.user_info().uid
    if not account_id or #account_id == 0 then
        util.safe_call_cb(cb, false, CONSTANTS.PLAYER_ERROR_CODES.CODE_ACCOUNT_ID_MISS, 'account id miss')
        return
    end

    M.get_account_infos({account_id}, function (succ, ...)
        if succ then
            local account_infos = ...
            if #account_infos > 0 then
                local self_account_info = account_infos[1]
                util.replace_empty_table(self_account_info, nil)

                util.safe_call_cb(cb, true, self_account_info)
            else
                util.safe_call_cb(cb, false, CONSTANTS.PLAYER_ERROR_CODES.CODE_ACCOUNT_INFO_MISS, 'account info miss')
            end
        else
            util.safe_call_cb(cb, false, ...)
        end
    end)
end

function M.get_account_infos(account_ids, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.LOW, {}, account_ids, cb)

    local account_infos = {}
    local uncache_account_ids = {}
    for _, account_id in ipairs(account_ids) do
        local cache_account_info = player_cache.get_account_info(account_id)
        if cache_account_info then
            table.insert(account_infos, cache_account_info)
        else
            table.insert(uncache_account_ids, account_id)
        end
    end

    E.LOG.debug(TAG, "get_account_infos uncache_account_ids >>")
    E.log({
        uncache_account_ids = uncache_account_ids
    })

    if #uncache_account_ids > 0 then
        rpc_get_account_infos(uncache_account_ids, function(succ, ...)
            if succ then
                local new_account_infos = ...
                for _, new_account_info in ipairs(new_account_infos) do
                    player_cache.add_account_info(new_account_info.account_id, new_account_info)
                    table.insert(account_infos, new_account_info)
                end

                if cb then
                    cb(true, account_infos)
                end

                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, account_infos)
                --cb(true, account_infos)
            else

                if cb then
                    cb(false, ...)
                end

                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
                --cb(false, ...)
            end
        end)
    else
        if cb then
            cb(true, account_infos)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, account_infos)
        --cb(true, account_infos)
    end
end

function M.get_customer_infos(account_ids, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_customer_infos', player_log.LOG_LEVEL.HIGH, {}, account_ids, cb)

    local customer_infos = {}
    local uncache_account_ids = {}
    for _, account_id in ipairs(account_ids) do
        local cache_account_info = player_cache.get_customer_info(account_id)
        if cache_account_info then
            table.insert(customer_infos, cache_account_info)
        else
            table.insert(uncache_account_ids, account_id)
        end
    end

    E.LOG.debug(TAG, "get_customer_infos uncache_account_ids >>")
    E.log({
        uncache_account_ids = uncache_account_ids
    })

    if #uncache_account_ids > 0 then
        http_get_customer_infos(uncache_account_ids, function(succ, ...)
            if succ then
                local new_customer_infos = ...
                for _, new_customer_info in ipairs(new_customer_infos) do
                    player_cache.add_customer_info(new_customer_info.account_id, new_customer_info)
                    table.insert(customer_infos, new_customer_info)
                end

                --E.LOG.debug(TAG, "get_customer_infos succ >>")
                --E.log(customer_infos)
                --cb(true, customer_infos)

                if cb then
                    cb(true, customer_infos)
                end

                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.HIGH, {}, cb, true, customer_infos)
            else
                local _err_code, _err_msg = ...
                --E.LOG.warn(TAG, "get_customer_infos failed, err_code:"..err_code..", err_msg:"..err_msg)
                --cb(false, ...)

                if cb then
                    cb(false, ...)
                end

                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.HIGH, {}, cb, false, ...)
            end
        end)
    else
        --cb(true, customer_infos)
        if cb then
            cb(true, customer_infos)
        end
        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, customer_infos)
    end
end

function M.get_account_info(account_id, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_account_info', player_log.LOG_LEVEL.LOW, {}, account_id, cb)

    local cache_account_info = player_cache.get_account_info(account_id)
    if cache_account_info then
        cb(true, cache_account_info)
    else
        local account_ids = {}
        table.insert(account_ids, account_id)
        rpc_get_account_infos(account_ids, function(succ, ...)
            if succ then
                local account_infos = ...
                local account_info = account_infos[1]

                player_cache.add_account_info(account_info.account_id, account_info)
                --cb(true, account_info)

                if cb then
                    cb(true, account_info)
                end

                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, account_info)
            else
                --cb(false, ...)
                if cb then
                    cb(false, ...)
                end
                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
            end
        end)
    end
end

-- opts.scene
function M.get_filled_player_account_infos(account_ids, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_filled_player_account_infos', player_log.LOG_LEVEL.LOW, {}, account_ids, opts, cb)

    if type(opts) == 'function' then
        cb = opts
        opts = {}
    end

    if type(opts) ~= 'table' then
        opts = {}
    end

    local result_account_infos = {}
    if #account_ids == 0 then

        if cb then
            cb(true, result_account_infos)
        end

        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_filled_player_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, result_account_infos)
        --cb(true, result_account_infos)
        return
    end

    local player_infos_callback = function(succ, ...)
        if succ then
            local player_infos = ...
            for _, player_info in ipairs(player_infos) do
                local account_id = player_info.account
                if result_account_infos[account_id] and result_account_infos[account_id].official_info then
                    result_account_infos[account_id].official_info.last_login_player = player_info
                end
            end

            if cb then
                cb(true, result_account_infos)
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_filled_player_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, result_account_infos)
            --cb(true, result_account_infos)
        else

            if cb then
                cb(false, ...)
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_filled_player_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
            --cb(false, ...)
        end
    end

    local last_player_ids = {}
    local account_infos_callback = function(succ, ...)
        if succ then
            local account_infos = ...
            for _, account_info in ipairs(account_infos) do
                result_account_infos[account_info.account_id] = account_info
                if account_info.official_info and account_info.official_info.last_login_player then
                    table.insert(last_player_ids, account_info.official_info.last_login_player)
                end
            end

            if #last_player_ids > 0 then
                M.get_player_infos(last_player_ids, opts, player_infos_callback)
            else
                if cb then
                    cb(true, result_account_infos)
                end

                player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_filled_player_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, result_account_infos)
                --cb(true, result_account_infos)
            end
        else
            if cb then
                cb(false, ...)
            end
            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_filled_player_account_infos', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
            --cb(false, ...)
        end
    end
    M.get_account_infos(account_ids, account_infos_callback)
end

function M.get_user_list_account_info(user_list, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_user_list_account_info', player_log.LOG_LEVEL.LOW, {}, user_list, opts, cb)

    if type(opts) == 'function' then
        cb = opts
        opts = {}
    end

    if type(opts) ~= 'table' then
        opts = {}
    end

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
        if cb then
            cb(true, user_list)
        end

        player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_user_list_account_info', player_log.LOG_LEVEL.LOW, {}, cb, true, user_list)
        --cb(true, user_list)
        return
    end

    M.get_filled_player_account_infos(account_ids, opts, function(succ, ...)
        if succ then
            local account_info_map = ...
            for account_id, account_info in pairs(account_info_map) do
                item_maps[account_id].account_info = account_info
            end

            local new_user_list = {}
            for _account_id, mix_item in pairs(item_maps) do
                table.insert(new_user_list, mix_item)
            end

            if cb then
                cb(true, new_user_list)
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_user_list_account_info', player_log.LOG_LEVEL.LOW, {}, cb, true, new_user_list)
            --cb(true, new_user_list)
        else

            if cb then
                cb(false, ...)
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_user_list_account_info', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
            --cb(false, ...)
        end
    end)
end

local function table_unique(t)
    t = t or {}
    local check = {}
    local n = {}
    local idx = 1
    for _k, v in pairs(t) do
        if not check[v] then
            n[idx] = v
            idx = idx + 1
            check[v] = true
        end
    end
    return n
end

function M.batch_get_infos(ids, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'batch_get_infos', player_log.LOG_LEVEL.LOW, {}, ids, opts, cb)

    if type(opts) == 'function' then
        cb = opts
        opts = {}
    end

    local unique_player_ids = table_unique(ids[M.IDS.IDS_PLAYER])
    local unique_account_ids = table_unique(ids[M.IDS.IDS_ACCOUNT])
    local unique_customer_account_ids = table_unique(ids[M.IDS.IDS_CUSTOMER])

    local need_info_types = {}
    need_info_types[M.INFO_TYPES.TYPE_PLAYER_INFOS] = #unique_player_ids > 0
    need_info_types[M.INFO_TYPES.TYPE_ACCOUNT_INFOS] = #unique_account_ids > 0
    need_info_types[M.INFO_TYPES.TYPE_CUSTOMER_INFOS] = #unique_customer_account_ids > 0

    local infos = {}
    if need_info_types[M.INFO_TYPES.TYPE_PLAYER_INFOS] or need_info_types[M.INFO_TYPES.TYPE_ACCOUNT_INFOS]
            or need_info_types[M.INFO_TYPES.TYPE_CUSTOMER_INFOS] then
        player_log.debug(player_log_util.header(), TAG, 'start_batch_get_infos', 'get_player_infos', {}, {})
        --E.LOG.debug(TAG, "batch_get_infos has ids, now get infos")
    else
        --E.LOG.warn(TAG, "batch_get_infos NOT has ids, now return")
        --cb(true, infos)

        if cb then
            cb(true, infos)
        end

        player_log.call_api_async_callback(player_log_util.header(), TAG, 'batch_get_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, infos)
        return
    end

    local has_one_failed = false

    local function merge_infos_handler(succ, ...)
        if has_one_failed then
            --E.LOG.warn(TAG, "batch_get_infos has one failed, so ignore this merge!")
            return
        end

        if succ then
            local type, id_info_map = ...
            id_info_map = id_info_map or {}
            infos[type] = id_info_map

            local is_all_infos_ready = true
            for need_info_type, is_need in pairs(need_info_types) do
                if is_need and infos[need_info_type] == nil then
                    is_all_infos_ready = false
                    break
                end
            end

            if is_all_infos_ready then
                --E.LOG.debug(TAG, "batch_get_infos all complete, now return")
                --cb(true, infos)

                if cb then
                    cb(true, infos)
                end

                player_log.call_api_async_callback(player_log_util.header(), TAG, 'batch_get_infos', player_log.LOG_LEVEL.LOW, {}, cb, true, infos)
            end
        else
            --E.LOG.warn(TAG, "batch_get_infos has one failed, callback failed!")
            has_one_failed = true
            --cb(false, ...)

            if cb then
                cb(false, ...)
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'batch_get_infos', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
        end
    end

    if need_info_types[M.INFO_TYPES.TYPE_PLAYER_INFOS] then
        --E.LOG.debug(TAG, "batch_get_infos, now begin get player infos")
        M.get_player_infos(unique_player_ids, { playerid_to_info = true, scene = opts.scene}, function(succ, ...)
            if succ then
                local new_players = ...
                --E.LOG.debug(TAG, "batch_get_infos get_player_infos succ >>")
                --E.log(new_players)
                merge_infos_handler(true, M.INFO_TYPES.TYPE_PLAYER_INFOS, new_players)
            else
                merge_infos_handler(false, ...)
            end
        end)
    end

    if need_info_types[M.INFO_TYPES.TYPE_ACCOUNT_INFOS] then
        --E.LOG.debug(TAG, "batch_get_infos, now begin get account infos")
        -- 需要把外界的opts传给get_filled_player_account_infos，因为这样才能保证外界的scene参数的传递性
        M.get_filled_player_account_infos(unique_account_ids, opts, function(succ, ...)
            if succ then
                local account_info_map = ...
                --E.LOG.debug(TAG, "batch_get_infos get_filled_player_account_infos succ >>")
                --E.log(account_info_map)
                merge_infos_handler(true, M.INFO_TYPES.TYPE_ACCOUNT_INFOS, account_info_map)
            else
                merge_infos_handler(false, ...)
            end
        end)
    end

    if need_info_types[M.INFO_TYPES.TYPE_CUSTOMER_INFOS] then
        --E.LOG.debug(TAG, "batch_get_infos, now begin get customer infos")
        M.get_customer_infos(unique_customer_account_ids, function(succ, ...)
            if succ then
                local customer_infos = ...
                local customer_info_map = {}
                for _, customer_info in ipairs(customer_infos) do
                    customer_info_map[customer_info.account_id] = customer_info
                end

                --E.LOG.debug(TAG, "batch_get_infos get_customer_infos succ >>")
                --E.log(customer_info_map)
                merge_infos_handler(true, M.INFO_TYPES.TYPE_CUSTOMER_INFOS, customer_info_map)
            else
                merge_infos_handler(false, ...)
            end
        end)
    end
end

function M.get_user_list_player_info(user_list, opts, cb)
    player_log.call_api(player_log_util.header(), TAG, 'get_user_list_player_info', player_log.LOG_LEVEL.LOW, {}, user_list, opts, cb)

    if type(opts) == 'function' then
        cb = opts
        opts = {}
    end

    local player_maps = {}
    local player_ids = {}
    for _, item in ipairs(user_list) do
        local player_id = item.user_id
        item.player_id = player_id
        player_maps[player_id] = item
        table.insert(player_ids, item.user_id)
    end
    M.get_player_infos(player_ids, opts, function(succ, ...)
        if succ then
            local player_infos = ...
            for _, player_info in ipairs(player_infos) do
                player_maps[player_info.player_id].player_info = player_info
            end
            local new_user_list = {}
            for _account_id, mix_item in pairs(player_maps) do
                table.insert(new_user_list, mix_item)
            end
            --cb(true, new_user_list)

            if cb then
                cb(true, new_user_list)
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_user_list_player_info', player_log.LOG_LEVEL.LOW, {}, cb, true, new_user_list)
        else
            --cb(false, ...)

            if cb then
                cb(false, ...)
            end

            player_log.call_api_async_callback(player_log_util.header(), TAG, 'get_user_list_player_info', player_log.LOG_LEVEL.LOW, {}, cb, false, ...)
        end
    end)
end

function M.global_player_search(search_data, opt, cb)
    assert(search_data and search_data ~= '', 'search_data is empty!')
    local url_prefix = E.CONFIG.get_config("search")
    local url = url_prefix .. '/global_player_search'
    --_ejoysdk.log('url ' .. tostring(url))
    local holo = require 'ejoysdk_lua.ejoysdk_holo'
    local player_token = holo.get_player_token()
    if not player_token then
        cb(false, -100, 'no player token')
        return
    end
    local headers = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['moment-Token']= player_token}
    }
    opt = opt or {}
    opt.search_data = search_data
    E.HTTP.post(url, headers, E.HTTP.CT_JSON, opt, function(resp)
        --E.log(resp)
        if resp and resp.status == 200 then
            local body = resp.body
            if body.code == 0 then
                local search_id = body.search_id
                local region_count = body.region_count
                cb(true, search_id, region_count)
            else
                cb(false, body.code, body.message or '')
            end
        else
            cb(false, resp.status, '')
        end
    end)
end

function M.player_search(search_data, opt, cb)
    assert(search_data and search_data ~= '', 'search_data is empty!')
    local url_prefix = E.CONFIG.get_config("search")
    local url = url_prefix .. '/player_search'
    --_ejoysdk.log('player search url: ' .. tostring(url))
    local holo = require 'ejoysdk_lua.ejoysdk_holo'
    local player_token = holo.get_player_token()
    if not player_token then
        cb(false, CONSTANTS.PLAYER_ERROR_CODES.CODE_PLAYER_TOKEN_MISS, 'no player token')
        return
    end
    local headers = {
        acceptable = E.HTTP.CT_JSON,
        headers = {['moment-Token']= player_token}
    }
    opt = opt or {}
    opt.search_data = search_data
    --local params = {
    --    search_data = search_data,
    --    search_type = opt.search_type, -- 0(server default) player_id+name,1 player_id,2 name
    --    page_num = opt.page_num,
    --    search_range = opt.search_range
    --}
    E.HTTP.post(url, headers, E.HTTP.CT_JSON, opt, function(resp)
        --E.log(resp)
        if resp and resp.status == 200 then
            local body = resp.body
            if body.code == 0 then
                cb(true, body.player_info_list or {})
            else
                cb(false, body.code, body.message or '')
            end
        else
            cb(false, resp.status, '')
        end
    end)
end

local function gangplank_logout_handler()
    -- logout， cache要清理一下
    player_cache.clear()
end

local function player_offline_handler()
    player_cache.clear()
end

function M.init()
    player_log.call_api(player_log_util.header(), TAG, 'init', player_log.LOG_LEVEL.HIGH, {})

    if module_inited then
        --E.LOG.debug(TAG, 'already init and return')
        return
    end

    module_inited = true

    -- 账号登出，把player_info的缓存清除一下
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, player_offline_handler)

    -- 聊天断开连接 或者 聊天遇到错误时，需要把player_info的缓存清除一下
    ET.subscribe(ET.chat.UPDATE_STATE, function(state)
        if state == STATES.DISCONNECT or state == STATES.ERROR then
            player_cache.clear()
        end
    end)
end

return M
