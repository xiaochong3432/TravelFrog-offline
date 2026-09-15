local E = require "ejoysdk_lua.ejoysdk"
local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
local launcher = require 'ejoysdk_lua.ejoysdk_launcher'
local EM = require "ejoysdk_lua.ejoysdk_module"
local utils = require "ejoysdk_lua.ejoysdk_utils"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local QL = require "ejoysdk_lua.ejoysdk_qualitylog"

local M = {}

M.SOURCE_TYPE = {
    LAST_LOGIN = "last_login",
    RECOMMEND = "recommend",
    RANDOM = "random"
}

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'launcher_ext'

local function fill_alive_value(server_list, alive_server_info)
    local alive_server_map = {}
    for _,v in pairs(alive_server_info or {}) do
        alive_server_map[v.name] = v
    end

    for _,v in pairs(server_list) do
        -- 先判断一下服务端数据是否带alive_data_info字段，如果不带，才往数据里加
        if not v.alive_data_info then
            if alive_server_map[tostring(v.name)] then
                v.alive_data_info = alive_server_map[tostring(v.name)]
            else
                v.alive_data_info = {}
            end
        end
    end
end

local function fill_recommend_value(server_list, recommend_list)
    local recommend_server_map = {}
    for _,v in pairs(recommend_list) do
        recommend_server_map[tostring(v)] = true
    end

    for _,v in pairs(server_list) do
        -- 先判断一下服务端数据是否带recommend_data_info字段，如果不带，才往数据里加
        if not v.recommend_data_info then
            if recommend_server_map[tostring(v.server_id)] then
                v.recommend_data_info = true
            else
                v.recommend_data_info = false
            end
        end
    end
end

local function pick_server_id_list(server_list)
    local server_id_map = {}
    if server_list then
        for _,v in pairs(server_list) do
            server_id_map[v.server_id] = true
        end
    end

    local server_id_list = {}
    for k,_ in pairs(server_id_map) do
        table.insert(server_id_list, k)
    end

    return server_id_list
end

local function fetch_server_info(_params, _server_ids, _cb)
    local server_list_params = {}
    server_list_params.tags = _params.tags
    server_list_params.server_groups = _params.server_groups
    server_list_params.fields = _params.fields
    server_list_params.ext = _params.ext
    server_list_params.server_ids = _params.server_ids
    server_list_params.realm_types = _params.realm_types
    if _server_ids and next(_server_ids) ~= nil then
        server_list_params.server_ids = _server_ids
    end

    launcher.server_list_ticket_detail_with_params_v2(function (succ1, ...)
        --[
        -- params table类型，包含以下参数：
        -- tags: table类型，tag标签数组
        -- server_ids: table类型，server_id 数组
        --]
        if succ1 then

            local resp = ...
            resp = resp or {}

            local server_list = resp.anns or {}

            if not next(server_list) then
                utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_SERVER_LIST_IS_EMPTY, 'server list is empty on fetch server info')

                E.LOG.error(TAG, 'server list is empty on fetch server info')
                return
            end

            local alive_params = {}
            if _server_ids and next(_server_ids) ~= nil then
                alive_params.server_ids = _server_ids
            end
            alive_params.tags = server_list_params.tags

            EG.alive_servers_with_params(function (succ2, ...)
                if succ2 then
                    local alive_servers = ...
                    fill_alive_value(server_list, alive_servers)

                    utils.safe_call_cb(_cb, true, server_list)
                else
                    local code, msg = ...
                    local detail = 'code=' .. tostring(code) .. ', msg=' ..tostring(msg)
                    utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_SERVER_ALIVE_ERROR, 'alive api error, ' .. detail)

                    E.LOG.error(TAG, 'alive api error on fetch server info, ' .. detail)
                end
            end, alive_params)
        else
            local code, msg = ...
            local detail = 'code=' .. tostring(code) .. ', msg=' ..tostring(msg)
            utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_SERVER_LIST_V2_ERROR, 'server list v2 error, ' .. detail)

            E.LOG.error(TAG, 'server list v2 error on fetch server info, ' .. detail)
        end
    end, server_list_params)
end

function M.sort_player_list(players_list)
    -- 按上次登录时间降序排序，最近时间登录的排在前面
    table.sort(players_list, function (a, b)
        local value
        if a.official_info and a.official_info.last_login_time and b.official_info and b.official_info.last_login_time then
            if a.official_info.last_login_time > b.official_info.last_login_time then
                value = -1
            elseif a.official_info.last_login_time == b.official_info.last_login_time then
                value = 0
            else
                value = 1
            end
        elseif a.official_info and a.official_info.last_login_time then
            -- 有字段的，要排在前面
            value = -1
        elseif b.official_info and b.official_info.last_login_time then
            -- 有字段的，要排在前面
            value = 1
        else
            value = 0
        end

        if value < 0 then
            return true
        else
            return false
        end
    end)
end

local function get_last_login_player(cb)
    if not EG.user_info() or not EG.user_info().uid then
        utils.safe_call_cb(cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_LAST_ENTER_SERVER_UID_MISS, 'uid miss for get last enter server')

        E.LOG.error(TAG, 'uid miss for get last enter server')
        return
    end

    if EG.user_info().token then
        EG.get_players(nil, function (succ, ...)
            if succ then
                local players_list = ...
                players_list = players_list or {}
                M.sort_player_list(players_list)

                -- 取第一个，就是最近登录的角色
                local last_login_player = players_list[1]
                if last_login_player and last_login_player.server_id and last_login_player.official_info and last_login_player.official_info.last_login_time then
                    utils.safe_call_cb(cb, true, last_login_player.server_id)
                else
                    utils.safe_call_cb(cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_LAST_ENTER_SERVER_LAST_LOGIN_PLAYER_INFO_EMPTY, 'last login player empty for get last enter server')

                    E.LOG.error(TAG, 'last login player empty for get last enter server >>')
                    E.LOG.error(TAG, last_login_player)
                end
            else
                local code, msg = ...
                local detail = 'code=' .. tostring(code) .. ', msg=' ..tostring(msg)
                utils.safe_call_cb(cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_LAST_ENTER_SERVER_ACCOUNT_INFO_FAIL, 'players info fetch fail for get last enter server, ' .. detail)

                E.LOG.error(TAG, 'players info fetch fail for get last enter server, ' .. detail)
            end
        end)
    else
        utils.safe_call_cb(cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_CODE_EJOY_TOKEN_INVALID, 'ejoy token miss for get last enter server')
        E.LOG.error(TAG, 'ejoy token miss for get last enter server')
    end
end

-- 上次调用get_my_server_info，接口返回的server_id
local last_server_id
local last_server_source_type
local last_server_recommend_data_info = false
local recommend_servers_cache

local function get_recommend_servers(cb)
    if recommend_servers_cache then
        utils.safe_call_cb(cb, true, utils.deepcopy(recommend_servers_cache))
        return
    end

    -- params {} 预留查询扩展参数, 传空table即可
    EG.get_recommend_servers({}, function (succ, ...)
        if succ then
            local recommend_servers = ...

            if recommend_servers and next(recommend_servers) ~= nil then
                recommend_servers_cache = recommend_servers

                utils.safe_call_cb(cb, true, utils.deepcopy(recommend_servers_cache))
            else
                utils.safe_call_cb(cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_GET_RECOMMEND_EMPTY, 'get recommend servers empty')

                E.LOG.error(TAG, 'get recommend servers empty')
            end
        else
            local code, msg = ...
            local detail = 'code=' .. tostring(code) .. ', msg=' .. tostring(msg)
            utils.safe_call_cb(cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_GET_RECOMMEND_FAIL, 'get recommend servers fail, ' .. detail)

            E.LOG.error(TAG, 'get recommend servers fail, ' .. detail)
        end
    end)
end

local function classify_server_info_list_by_alive(server_info_list)
    local alive_list = {}
    local un_alive_list = {}

    for _, v in pairs(server_info_list) do
        if v.alive_data_info.alive == true then
            table.insert(alive_list, v)
        else
            table.insert(un_alive_list, v)
        end
    end

    return {alive_list=alive_list, un_alive_list=un_alive_list}
end

function M._sort_server_info_list(server_info_list)
    if not server_info_list or next(server_info_list) == nil then
        return
    end

    table.sort(server_info_list, function (a, b)
        local value

        if a.alive_data_info.crow_propertion and b.alive_data_info.crow_propertion then
            if a.alive_data_info.crow_propertion == b.alive_data_info.crow_propertion then
                value = 0
            elseif a.alive_data_info.crow_propertion < b.alive_data_info.crow_propertion then
                value = -1
            else
                value = 1
            end
        elseif a.alive_data_info.crow_propertion then
            -- a有crow_propertion字段，b没crow_propertion字段，有字段的，要排在前面
            value = -1
        elseif b.alive_data_info.crow_propertion then
            -- a没crow_propertion字段，b有crow_propertion字段，有字段的，要排在前面
            value = 1
        else
            value = 0
        end

        if value < 0 then
            return true
        else
            return false
        end
    end)

    local front = {}
    local mid = math.ceil(#server_info_list / 2)
    for k, v in pairs(server_info_list) do
        if k <= mid then
            table.insert(front, v)
        end
    end

    table.sort(front, function (a, b)
        local value

        if a.alive_data_info.load_propertion and b.alive_data_info.load_propertion then
            if a.alive_data_info.load_propertion == b.alive_data_info.load_propertion then
                value = 0
            elseif a.alive_data_info.load_propertion < b.alive_data_info.load_propertion then
                value = -1
            else
                value = 1
            end
        elseif a.alive_data_info.load_propertion then
            value = -1
        elseif b.alive_data_info.load_propertion then
            value = 1
        else
            value = 0
        end

        if value < 0 then
            return true
        else
            return false
        end
    end)

    for k, v in pairs(front) do
        server_info_list[k] = v
    end
end

local function get_my_server_info_for_last_login(params, _cb)
    if last_server_source_type == M.SOURCE_TYPE.LAST_LOGIN and last_server_id then
        fetch_server_info(params, {last_server_id}, function (succ, ...)
            if not succ then
                utils.safe_call_cb(_cb, false, ...)
                return
            end

            local server_info_list = ...
            local ret = utils.safe_get_array_item(server_info_list, 1)
            if not ret then
                utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_TARGET_SERVER_NOT_FOUND, 'target server not found')
                return
            end

            ret.source_type = last_server_source_type
            ret.recommend_data_info = last_server_recommend_data_info
            utils.safe_call_cb(_cb, true, ret)
        end)

        return
    end

    local function real_get_last_login_server(final_last_login_server_id)
        fetch_server_info(params, {final_last_login_server_id}, function (succ2, ...)
            if not succ2 then
                utils.safe_call_cb(_cb, false, ...)
                return
            end

            local server_info_list = ...
            local ret = utils.safe_get_array_item(server_info_list, 1)

            if not ret then
                utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_TARGET_SERVER_NOT_FOUND, 'target server not found')
                return
            end

            get_recommend_servers(function (succ3, ...)

                if succ3 then
                    local recommend_server_ids = ...
                    fill_recommend_value({ret}, recommend_server_ids)
                end

                ret.source_type = M.SOURCE_TYPE.LAST_LOGIN
                ret.recommend_data_info = ret.recommend_data_info or false

                last_server_id = ret.server_id
                last_server_source_type = ret.source_type
                last_server_recommend_data_info = ret.recommend_data_info

                utils.safe_call_cb(_cb, true, ret)
            end)
        end)
    end

    get_last_login_player(function (succ, ...)
        if not succ then
            utils.safe_call_cb(_cb, false, ...)
            return
        end

        local last_login_player_server_id = ...

        real_get_last_login_server(last_login_player_server_id)
    end)
end

local function get_my_server_info_for_recommend(params, _cb)
    if last_server_source_type == M.SOURCE_TYPE.RECOMMEND and last_server_id then
        -- 获取上次进入游戏的server_id
        fetch_server_info(params, {last_server_id}, function (succ, ...)
            if not succ then
                utils.safe_call_cb(_cb, false, ...)
                return
            end

            local server_info_list = ...
            local ret = utils.safe_get_array_item(server_info_list, 1)

            if not ret then
                utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_TARGET_SERVER_NOT_FOUND, 'target server not found')
                return
            end

            ret.source_type = last_server_source_type
            ret.recommend_data_info = last_server_recommend_data_info
            utils.safe_call_cb(_cb, true, ret)
        end)

        return
    end

    get_recommend_servers(function (succ2, ...)

        if not succ2 then
            utils.safe_call_cb(_cb, false, ...)
            return
        end

        local recommend_server_ids = ...

        fetch_server_info(params, recommend_server_ids, function (succ3, ...)
            if not succ3 then
                utils.safe_call_cb(_cb, false, ...)
                return
            end

            local server_info_list = ...

            local classify_info = classify_server_info_list_by_alive(server_info_list)
            local alive_list = classify_info.alive_list
            local un_alive_list = classify_info.un_alive_list

            local ret

            if alive_list and next(alive_list) ~= nil then
                M._sort_server_info_list(alive_list)
                local index = math.random(1, math.ceil(#alive_list / 4))
                ret = utils.safe_get_array_item(alive_list, index)
            elseif un_alive_list and next(un_alive_list) ~= nil then
                M._sort_server_info_list(un_alive_list)
                local index = math.random(1, math.ceil(#un_alive_list / 4))
                ret = utils.safe_get_array_item(un_alive_list, index)
            end

            if not ret then
                utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_TARGET_SERVER_NOT_FOUND, 'target server not found')
                return
            end

            ret.source_type = M.SOURCE_TYPE.RECOMMEND
            ret.recommend_data_info = true

            last_server_id = ret.server_id
            last_server_source_type = ret.source_type
            last_server_recommend_data_info = ret.recommend_data_info

            utils.safe_call_cb(_cb, true, ret)
        end)
    end)
end

local function get_my_server_info_for_random(params, _cb)
    if last_server_source_type == M.SOURCE_TYPE.RANDOM and last_server_id then
        fetch_server_info(params, {last_server_id}, function (succ, ...)
            if not succ then
                utils.safe_call_cb(_cb, false, ...)
                return
            end

            local server_info_list = ...
            local ret = utils.safe_get_array_item(server_info_list, 1)

            if not ret then
                utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_TARGET_SERVER_NOT_FOUND, 'target server not found')
                return
            end

            ret.source_type = last_server_source_type
            ret.recommend_data_info = last_server_recommend_data_info

            utils.safe_call_cb(_cb, true, ret)
        end)

        return
    end

    -- 获取上次进入游戏的server_id
    fetch_server_info(params, nil, function (succ, ...)
        if not succ then
            utils.safe_call_cb(_cb, false, ...)
            return
        end

        local server_info_list = ...

        local classify_info = classify_server_info_list_by_alive(server_info_list)
        local alive_list = classify_info.alive_list
        local un_alive_list = classify_info.un_alive_list

        local ret

        if alive_list and next(alive_list) ~= nil then
            M._sort_server_info_list(alive_list)
            local index = math.random(1, math.ceil(#alive_list / 4))
            ret = utils.safe_get_array_item(alive_list, index)
        elseif un_alive_list and next(un_alive_list) ~= nil then
            M._sort_server_info_list(un_alive_list)
            local index = math.random(1, math.ceil(#un_alive_list / 4))
            ret = utils.safe_get_array_item(un_alive_list, index)
        end

        if not ret then
            utils.safe_call_cb(_cb, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_TARGET_SERVER_NOT_FOUND, 'target server not found')
            return
        end

        get_recommend_servers(function (succ2, ...)

            if succ2 then
                local recommend_server_ids = ...
                fill_recommend_value({ret}, recommend_server_ids)
            end

            ret.source_type = M.SOURCE_TYPE.RANDOM
            ret.recommend_data_info = ret.recommend_data_info or false

            last_server_id = ret.server_id
            last_server_source_type = ret.source_type
            last_server_recommend_data_info = ret.recommend_data_info

            utils.safe_call_cb(_cb, true, ret)
        end)
    end)
end

local function get_my_server_info_for_pipeline(params, _cb)
    get_my_server_info_for_last_login(params, function (succ, ...)
        if succ then
            utils.safe_call_cb(_cb, true, ...)
            return
        end

        get_my_server_info_for_recommend(params, function (succ2, ...)
            if succ2 then
                utils.safe_call_cb(_cb, true, ...)
                return
            end

            get_my_server_info_for_random(params, _cb)
        end)
    end)
end

--[
-- params table类型，包含以下参数：
-- tags: table类型，tag标签数组
-- server_groups：服务器id, 用逗号分隔, 可以获得传入服务器分组下的所有服务器. 与上述筛选条件互为与逻辑.
-- fields: 获取的字段, 用逗号分隔, 若没有传入, 可以获得所有字段, 若传入, 只获得希望获得的字段.
-- ext: table类型，作为扩展字段。
-- source_type: string类型, last_login\recommend\random
--]
function M.get_my_server_info(params, _cb)
    params = params or {}

    local type = params.source_type or 'pipeline'
    params.source_type = nil

    local _cb_wrapper = function(succ, ...)
        utils.safe_call_cb(_cb, succ, ...)

        if succ then
            E.LOG.debug(TAG, "get_my_server_info succ")
            QL.commit_action_succ_main("ejoy_my_server_info_end")
        else
            local _code, _msg = ...
            E.LOG.debug(TAG, "get_my_server_info failed, code:" .. tostring(_code) .. ", msg:" .. tostring(_msg))
            QL.commit_action_fail_main("ejoy_my_server_info_end", nil, _code, _msg)
        end
    end

    if type == M.SOURCE_TYPE.LAST_LOGIN then
        get_my_server_info_for_last_login(params, _cb_wrapper)
    elseif type == M.SOURCE_TYPE.RECOMMEND then
        get_my_server_info_for_recommend(params, _cb_wrapper)
    elseif type == M.SOURCE_TYPE.RANDOM then
        get_my_server_info_for_random(params, _cb_wrapper)
    elseif type == 'pipeline' then
        get_my_server_info_for_pipeline(params, _cb_wrapper)
    else
        local err_msg = 'source_type of params is invalid'
        QL.commit_action_fail_main("ejoy_my_server_info_end", nil, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_SERVER_INFO_SOURCE_TYPE_INVALID, err_msg)
        assert(false, err_msg)
    end
end

--[
-- params table类型，包含以下参数：
-- tags: table类型，tag标签数组
-- server_ids: table类型，server_id 数组
-- server_groups：服务器id, 用逗号分隔, 可以获得传入服务器分组下的所有服务器. 与上述筛选条件互为与逻辑.
-- fields: 获取的字段, 用逗号分隔, 若没有传入, 可以获得所有字段, 若传入, 只获得希望获得的字段.
-- ext: table类型，作为扩展字段。
-- realm_types: table类型，realm_type的数组
--]
function M.get_server_info_list(params, _cb)

    local _cb_wrapper = function(_succ, ...)
        utils.safe_call_cb(_cb, _succ, ...)

        if _succ then
            E.LOG.debug(TAG, "get_server_info_list succ")
            QL.commit_action_succ_main("ejoy_server_info_list_end")
        else
            local _code, _msg = ...
            E.LOG.debug(TAG, "get_server_info_list failed, code:" .. tostring(_code) .. ", msg:" .. tostring(_msg))
            QL.commit_action_fail_main("ejoy_server_info_list_end", nil, _code, _msg)
        end
    end

    launcher.server_list_ticket_detail_with_params_v2(function (succ1, ...)

        if succ1 then

            local resp = ...
            local server_list = resp.anns

            -- 从结果中抽取出server_id_list
            local server_id_list = pick_server_id_list(server_list)

            local alive_finish = false
            local recommend_finish = false
            local get_players_finish = false
            local players_list

            local total_cb = function()
                if not alive_finish then
                    return
                end

                if not recommend_finish then
                    return
                end

                if not get_players_finish then
                    return
                end

                local ret = {players_list = players_list, server_list = server_list}
                utils.safe_call_cb(_cb_wrapper, true, ret)
            end

            --[
            -- params table类型，包含以下参数：
            -- tags: table类型，tag标签数组
            -- server_ids: table类型，server_id 数组
            --]

            local alive_params = {server_ids=server_id_list}
            alive_params.tags = params.tags

            EG.alive_servers_with_params(function (succ2, ...)
                alive_finish = true

                if succ2 then

                    local alive_server_info = ...

                    fill_alive_value(server_list, alive_server_info)

                    total_cb()
                else
                    local code, msg = ...
                    utils.safe_call_cb(_cb_wrapper, false, code, msg)
                end
            end, alive_params)

            -- _params, 预留参数，传空table即可
            get_recommend_servers(function (succ3, ...)
                recommend_finish = true

                if succ3 then
                    local recommend_servers = ...
                    fill_recommend_value(server_list, recommend_servers)
                end

                total_cb()
            end)

            if EG.user_info().token then

                EG.get_players(nil, function (succ4, ...)
                    get_players_finish = true

                    if succ4 then
                        players_list = ...
                        total_cb()
                    else
                        local code, msg = ...
                        E.LOG.warn(TAG, 'player_id_list fail, code=' .. tostring(code) .. ', msg=' .. tostring(msg))
                        total_cb()
                    end
                end)

            else
                get_players_finish = true
                total_cb()
            end
        else
            local code, msg = ...
            utils.safe_call_cb(_cb_wrapper, false, code, msg)
        end
    end, params)
end

-- 重置 上次调用get_my_server_info接口返回的server_id
function M.reset_last_server_data()
    last_server_id = nil
    last_server_source_type = nil
    last_server_recommend_data_info = false
end

return M
