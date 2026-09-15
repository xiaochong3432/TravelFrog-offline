local E = require 'ejoysdk_lua.ejoysdk'
local BASE_API = require 'ejoysdk_lua.libs.base_api'
local user_info_api = BASE_API:New('user-info')
local EM = require "ejoysdk_lua.ejoysdk_module"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local M = {}

local HTTP = E.HTTP

local TAG =  EM.MODULE.SERVER_API .. 'user_info'

local ALGORITHM_TYPE_DH1 = "dh1"

function M.get_punishment(cb)
    local holo = require 'ejoysdk_lua.ejoysdk_holo'
    local player_token = holo.get_player_token()
    if player_token == nil then
        cb(false, -1, 'player token is nil')
        return
    end

    E.LOG.debug(TAG, 'get_punishment')

    local opt = { use_moment_token = true, trace = true }
    local url = '/player_api/get_punishments'
    user_info_api:post(url, {}, {}, opt, function(succ, ...)
        if succ then
            local resp = ...
            --E.log({resp=resp})
            cb(true, resp.punishments)
        else
            cb(false, ...)
        end
    end)
end

-- 获取本帐号下的处罚列表
-- https://yuque.antfin-inc.com/ejoy-platform/user_guide/daxqlh#get_punishment_details
function M.get_punishment_details(player_id_list, cb)

    local body = {}
    local body_json_str
    local id_list = player_id_list
    -- 空table默认处理成array
    local JSON = require 'ejoysdk_lua.ejoysdk_json'
    if id_list and next(id_list) == nil then
        body.player_id_list = JSON.newArray()
        body_json_str = JSON.encode_with_option(body, { encode_empty_array = true })
    else
        body.player_id_list = id_list
        body_json_str = JSON.encode(body)
    end

    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:post('/client_api/get_punishment_details', {}, body_json_str, opt, function(succ, ...)
        if succ then
            local result = ...
            cb(true, result.players_punishment_details)
        else
            cb(false, ...)
        end
    end)
end

local function get_player_token_http_inner(player_id, cb)

    E.LOG.debug(TAG, 'get_player_token_http')

    -- 密钥交换参数 secret_exchange_data
    local client_private = _ejoysdk_crypt.randomkey()
    local client_public = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.dhexchange(client_private))

    local body = {
        player_id = player_id,
        secret_exchange_data = { algorithm_type = ALGORITHM_TYPE_DH1, public_key = client_public }
    }
    local opt = {use_ejoy_token = true, trace = true}
    local url = '/client_api/get_player_token'

    local http_finish = false
    local time_out = false
    E.Timer.once(30, function ()
        time_out = true
        if not http_finish then
            E.LOG.error(TAG, 'get_player_token, succ=false, time out')
            cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_REQUEST_TIMEOUT, 'time out')
        end
    end)

    user_info_api:post(url, {}, body, opt, function(succ, ...)

        http_finish = true
        if time_out then
            return
        end

        if succ then
            local resp = ...
            if resp and resp.moment_token and #(resp.moment_token) > 0 then

                -- 密钥交换结果处理
                user_info_api:save_secret(client_private, resp.moment_token, resp.secret_exchange_data, resp.signature_versions)

                cb(true, resp)
                return
            end
        end

        local gangplank = require 'ejoysdk_lua.ejoysdk_gangplank'
        E.LOG.debug(TAG, '获取 player token 失败，失败 player id: ' .. tostring(player_id) .. ' ,uid: ' .. (gangplank.user_info().uid or ''))
        --E.log(body)
        --E.LOG.debug(TAG, 'get player token url: ' .. url)
        local code, msg = ...
        cb(false, code, msg)
    end)

end

function M.get_player_token_http(player_id, cb)

    -- 获取player_token前，确保已经同步了服务器时间，否则先同步服务器时间再进行请求
    if not E.did_sync_sever_time() then
        E.LOG.debug(TAG, 'get_server_time is not ready, will request get_server_time')
        local EGK = require 'ejoysdk_lua.ejoysdk_gangplank'
        EGK.sync_server_time(function (succ, ...)
            -- 无论成功失败都不卡获取mtoken流程，因为本地时间基本也是准确的
            if not succ then 
                local status, body = ...
                local full_msg = 'status:' .. tostring(status) .. ', code:' .. tostring(body and body.code) .. ", msg:" .. tostring(body and body.message)
                E.LOG.debug(TAG, 'get_server_time request fail,' .. tostring(full_msg))
                -- cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_PLAYER_TOKEN_GET_FAILED, tostring(full_msg))
            end
            get_player_token_http_inner(player_id, cb)
        end)
    else 
        get_player_token_http_inner(player_id, cb)
    end
end

-- 接口废弃
-- 本方法用于替换gangplank_ex的get_players2的方法
function M.get_players2(cb)
    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:get('/client_api/get_players', {}, {}, opt ,function(succ, ...)
        if succ then
            local result = ...
            cb(true, result.players)
        else
            cb(succ, ...)
        end
    end)
end

function M.get_players(token, cb)
    E.LOG.debug(TAG, 'get_players token : ' .. tostring(token))
    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:get('/client_api/get_players', {}, {}, opt, function(succ, ...)
        --E.LOG.debug(TAG, 'get_players receive resp, succ=' .. tostring(succ))

        if succ then
            local resp = ...
            --E.log(resp)
            cb(true, resp.players)
            return
        end

        local code, msg = ...
        --E.LOG.debug(TAG, 'get_players receive resp fail, code=' .. code .. ', msg=' .. msg)
        cb(false, code, msg)
    end)
end

-- get players接口 post方式请求
-- params = {
--  获取处罚信息
--  with_punishment = true
--  ...以后扩展
--}
function M.get_players_v2(params, cb)
    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:post('/client_api/get_players', {}, params, opt, function(succ, ...)
        if succ then
            local resp = ...
            cb(true, resp.players)
            return
        end

        local code, msg = ...
        cb(false, code, msg)
    end)
end


-- 参考 get_players 扩展
-- 增一个通用接口 get_players_with_query 支持query参数
-- 支持query参数 = {
--         with_punishment = true,
--         ... --以后扩展
-- }
function M.get_players_with_query(query, cb)
    local url = '/client_api/get_players'

    query = query or {}
    local url_query = HTTP.urlencode2(query)
    if url_query and url_query ~= '' then
        url = url .. "?" .. url_query
    end

    E.LOG.debug(TAG, 'get_players_with_query url : ' .. tostring(url))
    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:get(url, {}, {}, opt, function(succ, ...)
        --E.LOG.debug(TAG, 'get_players_with_query receive resp, succ=' .. tostring(succ))

        if succ then
            local resp = ...
            --E.log(resp)
            cb(true, resp.players)
            return
        end

        local code, msg = ...
        --E.LOG.debug(TAG, 'get_players_with_query receive resp fail, code=' .. code .. ', msg=' .. msg)
        cb(false, code, msg)
    end)
end

-- 获取全球同服角色对应的地区列表
function M.get_global_players(cb)
    local ejoysdk_gangplank = require 'ejoysdk_lua.ejoysdk_gangplank'
    assert(ejoysdk_gangplank.user_info().token, 'need login')

    local url = '/client_api/get_global_players'
    E.LOG.debug(TAG, 'get_global_players request url:' .. url)
    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:get(url, {}, {}, opt, function(succ, ...)
        --E.LOG.debug(TAG, 'get_global_players receive resp, succ=' .. tostring(succ))

        if succ then
            local resp = ...
            --E.log(resp)
            cb(true, resp.players)
            return
        end

        local code, msg = ...
        --E.LOG.debug(TAG, 'get_global_players receive resp fail, code=' .. code .. ', msg=' .. msg)
        cb(false, code, msg)
    end)
end

--https://yuque.antfin-inc.com/ejoy-platform/user_guide/daxqlh#db5adecf
--设置标签
--[[
@param
    params : table
    支持参数duration，非必填，设置标签持续时间，单位：秒。已调接口传递参数为准，如不传，则默认为admin后台标签设定时间，整数类型
    支持参数label_id，必填，标签id，需在admin后台先设置，字符串类型
    支持参数label，必填，标签值，字符串类型
    支持参数user_id，非必填，角色ID，不填则为给账号打标，设置了值则是给角色打标
    支持参数ext_oper，自定义参数，非必填，需在admin后台先设置参数名称及类型，支持set（设置值）、inc（值累加）、append（用于数组值的尾部添加元素）操作，示例:
    ext_oper = {
        hide = {
            mode = "set",
            value = true
        },
        count = {
            mode = "inc",
            value = 3
        },
        labels = {
            mode = "append",
            value = "a"
        }
    }
]]
function M.set_label(params, cb)
    local url = '/client_api/set_label'
    E.LOG.debug(TAG, 'set_label request url: ' .. url)
    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:post(url, {}, params, opt, function(succ, ...)
        if succ then
            cb(true, ...)
        else
            local code, msg = ...
            cb(false, code, msg)
        end
    end)
end

--https://yuque.antfin-inc.com/ejoy-platform/user_guide/daxqlh#2f8eaa0f
--设置玩家标签扩展信息
--[[
@param
    params : table
    支持参数label_id，必填，标签id，必须先设置标签
    支持参数user_id，非必填，角色ID，不填则为给账号的标签设置，设置了值则是给对应角色标签设置
    支持参数ext_oper，自定义参数，非必填，需在admin后台先设置参数名称及类型，支持set（设置值）、inc（值累加）、append（用于数组值的尾部添加元素）操作，示例:
    ext_oper = {
        hide = {
            mode = "set",
            value = true
        },
        count = {
            mode = "inc",
            value = 3
        },
        labels = {
            mode = "append",
            value = "a"
        }
    }
]]
function M.set_label_ext_info(params, cb)
    local url = '/client_api/set_label_ext_info'
    E.LOG.debug(TAG, 'set_label_ext_info request url: ' .. url)
    local opt = {use_ejoy_token = true, trace = true}
    user_info_api:post(url, {}, params, opt, function(succ, ...)
        if succ then
            cb(true, ...)
        else
            local code, msg = ...
            cb(false, code, msg)
        end
    end)
end

return M