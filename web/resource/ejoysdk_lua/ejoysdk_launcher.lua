local E = require "ejoysdk_lua.ejoysdk"
local EC = require "ejoysdk_lua.ejoysdk_config"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EI = require 'ejoysdk_lua.ejoysdk_init'
local ES = require 'ejoysdk_lua.ejoysdk_stat'
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local EM = require "ejoysdk_lua.ejoysdk_module"
local CONSTANTS = require "ejoysdk_lua.ejoysdk_constants"
local _utils = require "ejoysdk_lua.ejoysdk_utils"
local QL = require "ejoysdk_lua.ejoysdk_qualitylog"
local ANNS_BADGE = nil

local M = {}
M.TRACE_EVENT = 'trace_event'

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'ejoysdk_launcher'
local vendor_cache
local inited = false

local SERVICE = {
    PARTNER = 'partner',
    BOOT = 'boot',
    LOG = 'log',
    TICKET = 'ticket',
    TICKET_POST = 'ticket_post',
    TICKETS = 'tickets',
    TICKETS_POST = 'tickets_post',
    DETAIL = 'detail',
    SERVER_LIST_TICKET = 'server_list_ticket',
    SERVER_LIST_DETAIL = 'server_list_detail'
}

local url_items = {
    [SERVICE.PARTNER] = 'trace/partner',
    [SERVICE.BOOT] = 'trace/boot',
    [SERVICE.LOG] = 'trace/tracelog',
    [SERVICE.TICKET] = 'ann/v2/ticket/',
    [SERVICE.TICKET_POST] = 'ann/v2/ticket_post/',
    [SERVICE.TICKETS] = 'ann/v2/tickets/',
    [SERVICE.TICKETS_POST] = 'ann/v2/tickets_post/',
    [SERVICE.DETAIL] = 'ann/v2/detail/',
    [SERVICE.SERVER_LIST_TICKET] = 'ann/realm/ticket',
    [SERVICE.SERVER_LIST_DETAIL] = 'ann/realm/detail/',
}

local function get_launcher_url_base(service)
    local url_prefix = E.CONFIG.get_config("launcher") .. '/'
    local service_path = url_items[service]
    return url_prefix .. service_path
end


local KS_VENDERS_KEY = 'VENDERS'
local function get_vendors_stored()
    local v = E.KeyStore.get(KS_VENDERS_KEY)
    if v then
        return E.Utils.split_string(v, ':')
    end
end

local function save_vendors(vendors)
    if #vendors > 0 then
        local v = table.concat(vendors, ':')
        E.KeyStore.set(KS_VENDERS_KEY, v)
    end
end

local KS_LAST_ENTER_SERVER_ID_FOR_LAUNCHER = 'LAST_ENTER_SERVER_ID_FOR_LAUNCHER'
local login_handler = function(user_info)
    if user_info and user_info.uid then
        E.KeyStore.set(KS_LAST_ENTER_SERVER_ID_FOR_LAUNCHER, user_info.server or '')
    end
end

local logout_handler = function(_user_info)
    -- bugfix：切换账号时，要把服务器列表的上次调用get_my_server_info的接口的缓存，做清除操作
    local launcher_ext = require 'ejoysdk_lua.ejoysdk_launcher_ext'
    launcher_ext.reset_last_server_data()
end

--[[
-- opt 是一个table，有各种开关
-- vendor: true 向服务器同步自己的idfa，获取广告渠道
--]]
function M.init(opt)
    if inited then
        E.LOG.debug(TAG, 'already init and return')
        return
    end

    opt = opt or {}

    if opt.vendor then
        local vendors = get_vendors_stored()
        if not vendors then
            M.get_vendors(function(succ)
                if succ then
                    inited = true
                    ET.publish(EI.SUBSCRIBE_LAUNCHER_INITED, true)
                end
            end)
        else
            inited = true
            ET.publish(EI.SUBSCRIBE_LAUNCHER_INITED, true)
            vendor_cache = vendors
        end
    else
        inited = true
        ET.publish(EI.SUBSCRIBE_LAUNCHER_INITED, true)
    end

    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, logout_handler)

    ANNS_BADGE = require 'ejoysdk_lua.badge.ejoysdk_badge_anns'
    ANNS_BADGE.init()
end

function M.event(tag, detail)
    if detail == nil then
        detail = tag
        tag = 'boot'
    end

    local idfa = E.Sysinfo.idfa()
    local env_info = ES.env_info()
    local params = {
        tag = tag,
        uuid=idfa,
        timestamp=os.time(),
        detail = detail,
        envinfo = env_info
    }

    local log_url = get_launcher_url_base(SERVICE.LOG)
    E.LOG.debug(TAG, 'log_url: '..log_url)
    E.HTTP.post(log_url, {acceptable = E.HTTP.CT_JSON}, E.HTTP.CT_JSON, params, function(resp)
        if resp.status ~= 200 or resp.body.code ~= 200 then
            E.log({error='send event error', resp=resp})
        end
    end)
end

-- 可以直接用 topic 来记录 event
ET.subscribe(M.TRACE_EVENT, M.event)

local function get_full_channel()
    --local channel = stat.env_info().chInfo.ch -- 这个chInfo只有国内有,海外读不到
    local pkg_info = E.get_pkg_info()
    local channel = pkg_info.channel_id -- 兼容国内外
    local sub_channel = pkg_info.ds_sub_channel_id -- 海外没有sub_channel, 只需要考虑国内
    channel = channel and tostring(channel)
    if channel and sub_channel and #sub_channel > 0 then
        E.log('channel is '..channel..', and sub_channel is '.. sub_channel)
        --加一个白名单，sub_channel不在白名单内的都是用OTHERS
        local channelTable = {'DG_1', 'DG_2', 'DG_4', 'DG_28'}
        local in_white = false
        for _i, v in pairs(channelTable) do
            if v == sub_channel then
                in_white = true
                break
            end
        end

        if in_white then
            E.log('sub_channel '..sub_channel..'在白名单内，直接拼接就好')
            channel = tostring(channel) .. ',' .. tostring(sub_channel)
        else
            E.log('sub_channel '..sub_channel..'不在白名单内，替换为others')
            channel = tostring(channel) .. ',' .. 'OTHERS'
        end

    end

    -- PC上渠道号用账号渠道号，未登录则为空
    -- 对应产品需求：未登录前只获取默认公告，不获取特定渠道公告；登录后可获取到默认+特定渠道公告
    if E.Sysinfo.os() == 'windows' then
        channel = pkg_info.accountCh or ''
    end

    return channel
end

--[[
-- ann_types 公告类型字符串数组
-- tags: 通过tags字段筛选，多个tags之间取并集
-- server: 区服id
-- ext: 扩展数据，如按地域的公告，则需要填入ext.lbs_info数据
--]]
function M.tickets(ann_types, tags, server, cb, ext)

    local channel = get_full_channel()

    local params = {
        zone=EC.get_config('zone'),
        lang=EC.get_config('lang'),
        server=server,
        channel=channel
    }

    local CSTAT = require "ejoysdk_lua.cloud_game.cloud_stat"
    local pkg_info = E.get_pkg_info()
    if pkg_info.cloud_game_runmode == CSTAT.MOBILE_RUN_MODE.MODE_RUN_CONNECT_REMOTE or pkg_info.cloud_game_runmode == CSTAT.MOBILE_RUN_MODE.MODE_RUN_IN_CLOUD_SIDE then
        params.client_mode='CLOUD'  -- 表示云微端
    else
        params.client_mode='NORMAL'  -- 表示常规包
    end

    local ticket_cb = function(resp)
        local _status = resp and resp.status or CONSTANTS.GLOBAL_GANGPLANK_ERROR_CODE.GLOBAL_GANGPLANK_RESP_BODY_INVALID
        if _status == 200 then
            local body = resp.body
            if body then
                cb(true, body.tickets)
            else
                cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_GET_NULL_BODY, "resp body is nil")
            end
        else
            cb(false, _status)
        end
    end

    if ext and next(ext) then
        params.types = ann_types
        --拼接扩展数据
        for ext_key, ext_value in pairs(ext) do
            params[ext_key] = ext_value
        end
        if type(tags) == 'string' then
            local tag_arr = {}
            table.insert(tag_arr, tags)
            params.tags = tag_arr
        elseif type(tags) == 'table' then
            params.tags = tags
        end
        E.log(params)
        local ticket_post_url = get_launcher_url_base(SERVICE.TICKETS_POST)
        E.HTTP.post(ticket_post_url, {acceptable = E.HTTP.CT_JSON}, E.HTTP.CT_JSON, params, ticket_cb)
    else
        --没有带ext信息
        local tags_str = nil
        if type(tags) == 'table' then
            tags_str = table.concat(tags, ",")
        elseif type(tags) == 'string' then
            tags_str = tags
        end
        params.tags = tags_str
        --对ann_types进行排序，方便命中cache
        table.sort(ann_types)
        local ann_types_str = table.concat(ann_types, ",")
        local ticket_url = get_launcher_url_base(SERVICE.TICKETS)
        E.LOG.debug(TAG, 'ticket_url: '..ticket_url)
        local url = ticket_url .. ann_types_str
        url = E.HTTP.url_query(url, params)
        E.log('ticket full url = '..url)
        E.HTTP.get(url, {acceptable = E.HTTP.CT_JSON}, ticket_cb)
    end
end

--[[
-- ann_type 公告类型
-- tags: 通过tags字段筛选，多个tags之间取并集
-- server: 区服id
-- ext: 扩展数据，如按地域的公告，则需要填入ext.lbs_info数据
--]]
function M.ticket(ann_type, tags, server, cb, ext)

    local channel = get_full_channel()

    local params = {
        zone=EC.get_config('zone'),
        lang=EC.get_config('lang'),
        server=server,
        channel=channel
    }

    local CSTAT = require "ejoysdk_lua.cloud_game.cloud_stat"
    local pkg_info = E.get_pkg_info()
    if pkg_info.cloud_game_runmode == CSTAT.MOBILE_RUN_MODE.MODE_RUN_CONNECT_REMOTE or pkg_info.cloud_game_runmode == CSTAT.MOBILE_RUN_MODE.MODE_RUN_IN_CLOUD_SIDE then
        params.client_mode='CLOUD'  -- 表示云微端
    else
        params.client_mode='NORMAL'  -- 表示常规包
    end

    local ticket_cb = function(resp)
        local _status = resp and resp.status or CONSTANTS.GLOBAL_GANGPLANK_ERROR_CODE.GLOBAL_GANGPLANK_RESP_BODY_INVALID
        if _status == 200 then
            local body = resp.body
            if body and body.code ~= CONSTANTS.EJOYSDK_ERROR_CODES.HTTP_REQUEST_BODY_NIL then
                cb(true, body.hash, body.time)
            else
                cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_GET_NULL_BODY, "resp body is nil")
            end
        else
            cb(false, _status)
        end
    end
    
    if ext and next(ext) then
        params.type = ann_type
        --拼接扩展数据
        for ext_key, ext_value in pairs(ext) do
            params[ext_key] = ext_value
        end
        if type(tags) == 'string' then
            local tag_arr = {}
            table.insert(tag_arr, tags)
            params.tags = tag_arr
        elseif type(tags) == 'table' then
            params.tags = tags
        end
        E.log(params)
        local ticket_post_url = get_launcher_url_base(SERVICE.TICKET_POST)
        E.HTTP.post(ticket_post_url, {acceptable = E.HTTP.CT_JSON}, E.HTTP.CT_JSON, params, ticket_cb)
    else
        --没有带ext信息
        local tags_str = nil
        if type(tags) == 'table' then
            tags_str = table.concat(tags, ",")
        elseif type(tags) == 'string' then
            tags_str = tags
        end
        params.tags = tags_str
        local ticket_url = get_launcher_url_base(SERVICE.TICKET)
        E.LOG.debug(TAG, 'ticket_url: '..ticket_url)
        local url = ticket_url .. ann_type
        url = E.HTTP.url_query(url, params)
        E.log('ticket full url = '..url)
        E.HTTP.get(url, {acceptable = E.HTTP.CT_JSON}, ticket_cb)
    end
end

function M.detail(ticket, cb)
    local detail_url = get_launcher_url_base(SERVICE.DETAIL)
    local url = tostring(detail_url) .. tostring(ticket)
    E.LOG.debug(TAG, 'detail_url: '..url)

    E.HTTP.get(url, {raw_body=true}, function(resp)
        if resp.status == 200 then
            cb(true, resp.body, ticket)
        else
            cb(false, resp.status, "get detail failed")
        end
    end)
end

-- 依据hash来获取本地缓存，避免重复请求
local ticket_cache_format =  "%s_ticket_cache"
function M.get_ticket_cache(type,hash)
    if hash and ''~=hash  then
        local fn = string.format(ticket_cache_format, type)
        local cache = E.File.readfile(fn)
        if cache ~= nil then
            local data = JSON.safe_decode(cache)
            if data and data.hash == hash then
                return data
            else
                E.log('ticket_detail  decode cache failed')
            end
        end
    end
    return nil
end

local function save_ticket_cache(type,data)
    local fn = string.format(ticket_cache_format, type)
    local json_str = JSON.encode(data)
    E.File.writefile(fn, json_str)
end

local function commit_action_succ_main_before_enter_game(action, type, params)
    local eg = require "ejoysdk_lua.ejoysdk_gangplank"
    local player_info = eg.player_info()

    if not player_info then
        E.LOG.debug(TAG, "commit_action_succ_main_before_enter_game begin:" .. tostring(action) .. ", type:" .. tostring(type))
        QL.commit_action_succ_main(action, type, params)
    end
end

local function commit_action_fail_main_before_enter_game(action, action_type, code, msg, params)
    local eg = require "ejoysdk_lua.ejoysdk_gangplank"
    local player_info = eg.player_info()

    if not player_info then
        E.LOG.debug(TAG, "commit_action_fail_main_before_enter_game begin:" .. tostring(action) .. ", type:" .. tostring(action_type))
        QL.commit_action_fail_main(action, action_type, code, msg, params)
    end
end

-- 获取原始服务端公告数据
function M.ticket_detail(ann_type,tags,server,cb,ext)
    local cb_wrapper = function(succ, ...)
        if cb then
            cb(succ, ...)
        end

        if succ then
            E.LOG.debug(TAG, "ticket_detail succ")
            -- stat
            local _stat_params = {
                p1 = server
            }
            commit_action_succ_main_before_enter_game("ejoy_ticket_detail_end", ann_type, _stat_params)
        else
            local _code, _msg = ...
            E.LOG.warn(TAG, "ticket_detail failed, code:" .. tostring(_code) .. ", msg:" .. tostring(_msg))
            local _stat_params = {
                p1 = server
            }
            commit_action_fail_main_before_enter_game("ejoy_ticket_detail_end", ann_type, _code, _msg, _stat_params)
        end
    end

    M.ticket(ann_type, tags, server, function(succ, ...)
        if succ then

            local hash, _time = ...
            local data = M.get_ticket_cache(ann_type,hash)
            if data~= nil then
                cb_wrapper(true, data.body, data.ticket, hash)
                return
            end

            M.detail(hash, function (ok, ...)
                if ok then
                    local body, ticket = ...
                    local cb_data =
                    {
                        hash = hash,
                        ticket = ticket,
                        body = body,
                    }
                    save_ticket_cache(ann_type, cb_data)
                    --_ejoysdk.log("[ann] get form server")
                    cb_wrapper(true, body, ticket, hash)
                else
                    local _code, _msg = ...
                    cb_wrapper(false, _code, _msg)
                end
            end)
        else
            local _code, _msg = ...
            cb_wrapper(false, _code, _msg)
        end
    end, ext)
end

function M.tickets_details(ann_types, tags, server, cb, ext)
    local cb_wrapper = function(succ, ...)
        if cb then
            cb(succ, ...)
        end
        --对ann_types进行排序,转string作为action_type参数
        table.sort(ann_types)
        local ann_types_str = table.concat(ann_types, ",")
        if succ then
            E.LOG.debug(TAG, "tickets_details succ")
            -- stat
            local _stat_params = {
                p1 = server
            }
            commit_action_succ_main_before_enter_game("ejoy_tickets_details_end", ann_types_str, _stat_params)
        else
            local _code, _msg = ...
            E.LOG.warn(TAG, "tickets_details failed, code:" .. tostring(_code) .. ", msg:" .. tostring(_msg))
            local _stat_params = {
                p1 = server
            }
            commit_action_fail_main_before_enter_game("ejoy_tickets_details_end", ann_types_str, _code, _msg, _stat_params)
        end
    end
    M.tickets(ann_types, tags, server, function(succ, ...)
        if succ then
            local tickets = ...
            local ticket_size = 0
            if tickets then
                ticket_size = #tickets
            end
            if tickets == nil or ticket_size == 0 then
                cb_wrapper(true, {})
                return
            end
            local get_detail_size = 0
            local detail_datas = {}
            for _, ticket in pairs(tickets) do
                local ann_type = ticket.type
                local hash = ticket.hash
                local time = ticket.time
                local ticket_detail_data = {
                    ann_type = ann_type,
                    time = time,
                    hash = hash
                }
                local data = M.get_ticket_cache(ann_type, hash)
                if data ~= nil then
                    ticket_detail_data.detail = data.body
                    --补充上成功的code
                    ticket_detail_data.code = 200
                    table.insert(detail_datas, ticket_detail_data)
                    get_detail_size = get_detail_size + 1
                    if get_detail_size == ticket_size then
                        cb_wrapper(true, detail_datas)
                    end
                else
                    M.detail(hash, function(detail_succ, ...)
                        if detail_succ then
                            local body, ticket_hash = ...
                            local cache_data =
                            {
                                hash = hash,
                                ticket = ticket_hash,
                                body = body,
                            }
                            save_ticket_cache(ann_type, cache_data)
                            ticket_detail_data.detail = body
                            ticket_detail_data.code = 200
                        else
                            local code, msg = ...
                            ticket_detail_data.code = code
                            ticket_detail_data.msg = msg
                        end
                        table.insert(detail_datas, ticket_detail_data)
                        get_detail_size = get_detail_size + 1
                        if get_detail_size == ticket_size then
                            cb_wrapper(true, detail_datas)
                        end
                    end)
                end
            end
        else
            cb_wrapper(false, ...)
        end
    end, ext)
end

-- 客户端合并公告数据+红点数据
function M.ticket_detail_with_badge(ann_type, tags, server, cb, ext)
    local cb_wrapper = function(succ, ...)
        -- 公告数据添加红点标识
        if succ then
            local body_str,ticket,hash = ...
            -- 获取公告红点树
            ANNS_BADGE.get_notice_badge_tree_imm(ann_type,tags,server,function(ann_badge_data)
                local body_data = JSON.safe_decode(body_str)
                local anns = (body_data or {}).anns or {}
                -- 公告添加强弹标识（只要子数据有至少一个是强弹那就是强弹）
                local anns_badge = {}

                -- 公告红点树
                local children = ((ann_badge_data or {}).tree_info or {}).children or {}
                for _,badge in pairs(children) do
                    anns_badge[badge.node_id] = badge.is_activated or false
                end

                local is_force_popup = false -- 强弹一定有红点，反之不一定, 而红点会受频率开关等控制
                for _, ann in pairs(anns) do
                    ann.has_read = anns_badge[ann._uuid] == false
                    is_force_popup = is_force_popup or (not ann.has_read and ann._badge_config and ann._badge_config.is_force_popup == true)
                end

                body_data.force_popup = is_force_popup

                local body = JSON.encode(body_data)
                cb(true,body,ticket,hash)

                -- stat ticket_detail_with_badge succ
                local _stat_params = {
                    p1 = server
                }
                commit_action_succ_main_before_enter_game("ejoy_ticket_detail_badge_end", ann_type, _stat_params)
            end)
        else
            local _code, _msg = ...
             cb(false, _code, _msg)

            -- stat ticket_detail_with_badge failed
            local _stat_params = {
                p1 = server
            }
            commit_action_fail_main_before_enter_game("ejoy_ticket_detail_badge_end", ann_type, _code, _msg, _stat_params)
        end
    end

    -- 获取原始公告数据
    M.ticket_detail(ann_type,tags,server,cb_wrapper,ext)
end

function M.vendors()
    return vendor_cache
end

-- internal
--
local function update_vendor_cache(vendors)
    save_vendors(vendors)
    vendor_cache = vendors
end

function M.get_vendors(cb)
    local idfa = E.Sysinfo.idfa()
    local timestamp = os.time()
    local params = {
        product = E.CONFIG.get_config("product"),
        idfa = idfa;
        timestamp = timestamp
    }

    local partner_url = get_launcher_url_base(SERVICE.PARTNER)
    E.LOG.debug(TAG, 'partner_url: '.. partner_url)

    E.HTTP.post(partner_url, {acceptable = E.HTTP.CT_JSON}, E.HTTP.CT_URLENCODED, params, function(resp)
        if resp.status == 200 then
            if resp.body.code == 200 then
                E.log(resp.body)
                update_vendor_cache(resp.body.data)
                cb(true, resp.body.data)
                return
            end
        end
        cb(false)
    end)
end

-- 接口描述：获取过滤服务器列表对应的hash值
-- params table类型，包含以下参数：
-- tags: table类型，tag标签数组
-- server_ids: table类型，server_id 数组
-- server_groups：服务器id, 用逗号分隔, 可以获得传入服务器分组下的所有服务器. 与上述筛选条件互为与逻辑.
-- fields: 获取的字段, 用逗号分隔, 若没有传入, 可以获得所有字段, 若传入, 只获得希望获得的字段.
-- ext: table类型，作为扩展字段。
-- realm_types: table类型，realm_type的数组
function M.server_list_ticket_with_params(cb, params)
    params = params or {}

    local tags_str = nil
    if params.tags then
        tags_str = table.concat(params.tags, ',')
    end

    local server_ids_str = nil
    if params.server_ids then
        server_ids_str = table.concat(params.server_ids, ',')
    end

    local server_groups_str = nil
    if params.server_groups then
        server_groups_str = table.concat(params.server_groups, ',')
    end

    local fields_str = nil
    if params.fields then
        fields_str = table.concat(params.fields, ',')
    end

    local realm_types_str = nil
    if params.realm_types and next(params.realm_types) ~= nil then
        realm_types_str = table.concat(params.realm_types, ',')
    end

    local server_list_ticket_url = get_launcher_url_base(SERVICE.SERVER_LIST_TICKET)
    local url = server_list_ticket_url
    E.LOG.debug(TAG, 'server_list_ticket_url, url:'..url)

    local channel = get_full_channel()

    local params2 = {
        zone=EC.get_config('zone'),
        lang=EC.get_config('lang'),
        tags = tags_str,
        server_ids = server_ids_str,
        server_groups = server_groups_str,
        fields = fields_str,
        channel=channel,
        realm_types=realm_types_str
    }

    url = E.HTTP.url_query(url, params2)

    if params.ext and type(params.ext) == 'table' then
        -- 添加ext=true，标记后续参数是追加的自定义参数
        url = url .. '&ext=true&' .. E.HTTP.urlencode(params.ext)
    end

    _ejoysdk.log('server list ticket url: ' .. tostring(url))
    E.HTTP.get(url, {trace = true, acceptable = E.HTTP.CT_JSON}, function(resp)
        if resp.status == 200 then
            local body = resp.body
            if body and body.hash then
                E.LOG.debug(TAG, "server_list_ticket_with_params resp succ, hash:"..body.hash)
                cb(true, body.hash, body.time)
            else
                E.LOG.warn(TAG, "server_list_ticket_with_params resp failed, resp body or hash is invalid")
                cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_TICKET_HASH_INVALID, "ticket hash invalid")
            end
        else
            E.LOG.warn(TAG, "server_list_ticket_with_params resp failed, resp status >>")
            E.log(resp)
            cb(false, resp.status, "get failed")
        end
    end)
end

function M.server_list_ticket(tags, cb)
    local params = {}
    if type(tags) == 'function' then
        cb = tags
        params.tags = nil
    else
        params.tags = tags
    end

    M.server_list_ticket_with_params(cb, params)
end

function M.server_list_detail(ticket, cb)
    local server_list_detail_url = get_launcher_url_base(SERVICE.SERVER_LIST_DETAIL)
    local url = server_list_detail_url .. ticket
    E.LOG.debug(TAG, 'server_list_detail, url:'..url)

    local params = {
        zone=EC.get_config('zone'),
        lang=EC.get_config('lang'),
    }
    url = E.HTTP.url_query(url, params)
    E.HTTP.get(url, {trace = true, raw_body=true}, function(resp)
        if resp.status == 200 then
            cb(true, resp.body)
        else
            cb(false, resp.status)
        end
    end)
end

-- 接口描述：获取服务器详细信息列表
-- params table类型，包含以下参数：
-- tags: table类型，tag标签数组
-- server_ids: table类型，server_id 数组
-- server_groups：服务器id, 用逗号分隔, 可以获得传入服务器分组下的所有服务器. 与上述筛选条件互为与逻辑.
-- fields: 获取的字段, 用逗号分隔, 若没有传入, 可以获得所有字段, 若传入, 只获得希望获得的字段.
-- ext: table类型，作为扩展字段。
-- realm_types: table类型，realm_type的数组
-- 详细协议参考文档：https://yuque.antfin.com/ejoy-platform/user_guide/mfddqk
function M.server_list_ticket_detail_with_params(cb, params)
    local cb_wrapper = function(succ, ...)
        if cb then
            cb(succ, ...)
        end

        -- stat ticket detail
        if succ then
            E.LOG.debug(TAG, "server_list_ticket_detail_with_params succ")

            -- stat ticket detail failed
            QL.commit_action_succ_main("ejoy_server_info_list_end")
        else
            local _code, _msg = ...
            E.LOG.warn(TAG, "server_list_ticket_detail_with_params failed, code:" .. tostring(_code) .. ", msg:" .. tostring(_msg))

            -- stat ticket detail failed
            QL.commit_action_fail_main("ejoy_server_info_list_end", nil, _code, _msg)
        end
    end

    local inner_cb = function(succ, ...)
        if succ then
            local hash, _time = ...
            local fn = string.format("%s_sl_cache", hash)

            local cache = E.File.readfile(fn)
            if cache ~= nil then
                local data = JSON.safe_decode(cache)
                if data and data.detail then
                    local result = JSON.safe_decode(data.detail)
                    if result then
                        E.LOG.debug(TAG,"get_server_list_ticket_detail get from cache >>")
                        E.log(data.detail)
                        cb_wrapper(true, data.detail)
                        return
                    end
                end
            end

            M.server_list_detail(hash,
                    function(succ2, ...)
                        if succ2 then
                            local detail = ...
                            local result = JSON.safe_decode(detail)
                            if result then
                                E.log('server_list_detail HTTP response data right，and ready to cache it')
                                local data =
                                {
                                    hash = hash,
                                    detail = detail,
                                }
                                local json_str = JSON.encode(data)
                                E.LOG.debug(TAG, "server_list_detail response >>")
                                E.log(json_str)
                                E.File.writefile(fn, json_str)
                                --_ejoysdk.log("[server_list] get from server")
                                cb_wrapper(true, detail)
                            else
                                E.log('server_list_detail HTTP response get wrong response data, please retry it')
                                cb_wrapper(false, CONSTANTS.GLOBAL_GANGPLANK_ERROR_CODE.GLOBAL_GANGPLANK_JSON_DECODE_ERROR, "detail decode failed")
                            end
                        else
                            local status = ...
                            cb_wrapper(false, status)
                        end
                    end
            )
        else
            local _code, _msg = ...
            cb_wrapper(false, _code, _msg)
        end
    end

    M.server_list_ticket_with_params(inner_cb, params)
end

-- 优化server_list_ticket_detail_with_params方法，获取缓存时多次decode问题，返回值改为table，调用方无需再decode
-- 接口描述：获取服务器详细信息列表
-- params table类型，包含以下参数：
-- tags: table类型，tag标签数组
-- server_ids: table类型，server_id 数组
-- server_groups：服务器id, 用逗号分隔, 可以获得传入服务器分组下的所有服务器. 与上述筛选条件互为与逻辑.
-- fields: 获取的字段, 用逗号分隔, 若没有传入, 可以获得所有字段, 若传入, 只获得希望获得的字段.
-- ext: table类型，作为扩展字段。
-- realm_types: table类型，realm_type的数组
-- 详细协议参考文档：https://yuque.antfin.com/ejoy-platform/user_guide/mfddqk
function M.server_list_ticket_detail_with_params_v2(cb, params)
    local cb_wrapper = function(succ, ...)
        if cb then
            cb(succ, ...)
        end

        -- stat ticket detail
        if succ then
            E.LOG.debug(TAG, "server_list_ticket_detail_with_params_v2 succ")

            -- stat ticket detail failed
            QL.commit_action_succ_main("ejoy_server_info_list_end")
        else
            local _code, _msg = ...
            E.LOG.warn(TAG, "server_list_ticket_detail_with_params_v2 failed, code:" .. tostring(_code) .. ", msg:" .. tostring(_msg))

            -- stat ticket detail failed
            QL.commit_action_fail_main("ejoy_server_info_list_end", nil, _code, _msg)
        end
    end

    local inner_cb = function(succ, ...)
        if succ then
            local hash, _time = ...
            local fn = string.format("%s_sl_cache_v2", hash)
            local cache = E.File.readfile(fn)
            if cache ~= nil then
                local detail = JSON.safe_decode(cache)
                if detail then
                    E.LOG.debug(TAG,"get_server_list_ticket_detail_table get from cache >>")
                    E.log(detail)
                    cb_wrapper(true, detail)
                    return
                end
            end

            M.server_list_detail(hash,
                    function(succ2, ...)
                        if succ2 then
                            local detail = ...
                            local result = JSON.safe_decode(detail)
                            if result then
                                E.log('server_list_detail_table HTTP response data right，and ready to cache it')
                                E.LOG.debug(TAG, "server_list_detail_table response >>")
                                E.log(detail)
                                E.File.writefile(fn, detail)
                                cb_wrapper(true, result)
                            else
                                E.log('server_list_detail_table HTTP response get wrong response data, please retry it')
                                cb_wrapper(false, CONSTANTS.GLOBAL_GANGPLANK_ERROR_CODE.GLOBAL_GANGPLANK_JSON_DECODE_ERROR, "detail decode failed")
                            end
                        else
                            local status = ...
                            cb_wrapper(false, status)
                        end
                    end
            )
        else
            local _code, _msg = ...
            cb_wrapper(false, _code, _msg)
        end
    end

    M.server_list_ticket_with_params(inner_cb, params)
end

--修复server_list_ticket_detail方法，返回table
function M.server_list_ticket_detail_v2(tags, cb)
    local no_tags = false

    --为了兼容server_list_ticket的写法
    if type(tags) == 'function' then
        cb = tags
        no_tags = true
    else
        if not tags then
            no_tags = true
        end
    end

    local params = {}
    if not no_tags then
        params.tags = tags
    end

    M.server_list_ticket_detail_with_params_v2(cb, params)
end

function M.server_list_ticket_detail(tags, cb)
    local no_tags = false

    --为了兼容server_list_ticket的写法
    if type(tags) == 'function' then
        cb = tags
        no_tags = true
    else
        if not tags then
            no_tags = true
        end
    end

    local params = {}
    if not no_tags then
        params.tags = tags
    end

    M.server_list_ticket_detail_with_params(cb, params)
end

M.SHOW_TICKET_DETAIL_CODE = {
    ERR_GET_DETAIL = -1,
    ERR_EMPTY_LIST = -2,
    ERR_NOT_RENDER_WITH_H5 = -3
}

function M.show_ticket_detail(ann_type, tags, server, cb, ext)
    cb = cb or {}
    M.ticket_detail(ann_type,tags,server,function(succ,body_str,ticket,hash)
        local err_code = M.SHOW_TICKET_DETAIL_CODE.ERR_GET_DETAIL
        local err_msg = "获取公告失败"

        if succ then
            local body_data = JSON.safe_decode(body_str)
            local anns = body_data.anns
            if anns and next(anns)  then
                local body = anns[1] -- 取任意一个即可

                local _ann_type = body._ann_type -- 0：非阻断公告 1:阻断公告
                local _render_type = body._render_type -- 0:客户端渲染 1：h5渲染
                local _server_name = body._ann_param or ''-- 当render_type 为1时会携带公告的url

                if _render_type == 1  and _server_name and ''~=_server_name then
                    E.log('show announcement in SDK')

                    local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
                    local gangplank_config = EGC.get_current_cdn_config()
                    local url = 'https://game-notice.ejoy.com' -- 国内默认RELEASE
                    if gangplank_config and gangplank_config.render_center and gangplank_config.render_center.game_notice and ''~= gangplank_config.render_center.game_notice then
                        url = gangplank_config.render_center.game_notice
                    else
                        local CC = require 'ejoysdk_lua.ejoysdk_config_center'
                        local env = CC.get_env()
                        if env ~= CC.ENV.RELEASE then
                            url = 'https://ieu-render-raven.alibaba.net/p/r_dev'
                        end
                    end

                    if url.sub(url, -1) ~= "/" then
                        url = url .. "/"
                    end

                    url = url .. _server_name

                    local channel = get_full_channel()
                    local tags_str = tags
                    if type(tags) == 'table' then
                        tags_str = table.concat(tags, ",")
                    elseif type(tags) == 'string' then
                        tags_str = tags
                    end

                    -- 公告可能会跳转到外部，此时就需要使用传递的参数由前端自己去获取公告
                    local query_params = {
                        zone=EC.get_config('zone'),
                        lang=EC.get_config('lang'),
                        product_code=EC.get_config('product'),
                        tags=tags_str,
                        server=server,
                        channel=channel,
                        type=ann_type,
                        hash=hash -- 给前端可以直接获取缓存
                    }

                    url = E.HTTP.url_query(url, query_params) -- 拼接参数

                    local host = E.HTTP.parse(url).host
                    E.LOG.debug(TAG,"notice url: "..url)

                    E.WebView.open(url,
                            {[host] = { startupData = {}, transparent = true }},
                            { compactMode = true, use_fragment = true, hide_close_btn = true, use_cutout = true},
                            nil,
                            function(_value)
                                cb(true,  body_str, ticket, _ann_type) -- 与原来的接口相比多了一个_ann_type，表示阻断类型
                            end)

                    -- stat show ticket detail succ
                    local stat_params = {
                        p1 = server
                    }
                    commit_action_succ_main_before_enter_game("ejoy_ticket_detail_show_end", ann_type, stat_params)
                    return
                else
                    E.log('show announcement in game')
                    err_code = M.SHOW_TICKET_DETAIL_CODE.ERR_NOT_RENDER_WITH_H5
                    err_msg = "公告非H5渲染"
                end
            else
                err_code = M.SHOW_TICKET_DETAIL_CODE.ERR_EMPTY_LIST
                err_msg = "公告列表为空"
            end
        end

        cb(false,err_code,err_msg)

        -- stat show_ticket_detail failed
        local stat_params = {
            p1 = server
        }
        commit_action_fail_main_before_enter_game("ejoy_ticket_detail_show_end", ann_type, err_code, err_msg, stat_params)
    end, ext)
end

return M
