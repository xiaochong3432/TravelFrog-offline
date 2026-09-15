local E = require 'ejoysdk_lua.ejoysdk'
local EH = require 'ejoysdk_lua.ejoysdk_holo'
local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
local Vendor = require "ejoysdk_lua.vendors.vendor"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local UNI = require "ejoysdk_lua.vendors.unisdk"
local push_event = require 'ejoysdk_lua.push.ejoysdk_push_event'
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local EM = require "ejoysdk_lua.ejoysdk_module"
local log_mgr = require 'ejoysdk_lua.ejoysdk_log_mgr'
local ECO = require 'ejoysdk_lua.ejoysdk_community'
local ECC = require 'ejoysdk_lua.ejoysdk_config_center'

--[[
    阿里云JF打点说明：
    receive_notification_inapp 应用在前台时，收到推送
    open_notification 用户点击通知横幅拉起应用
    receive_notification 应用在后台时，收到推送
    receive_message 收到message的打点，可忽略，一般不用message

    场景举例：
    1.应用进程被杀，收到推送，点击图标：这4个打点，都不会上报
    2.应用进程被杀，收到推送，点击通知横幅：open_notification有上报
    3.应用在后台，收到推送，点击图标：receive_notification有上报
    4.应用在后台，收到推送，点击通知横幅：receive_notification、open_notification有上报
    5.应用在前台，收到推送：receive_notification_inapp有上报
    场景2、4的open_notification可以通过上报参数的launch_time区分，距离上报时间近的，视为场景2；反之视为场景4

    计算到达率： open_notification(场景2) + receive_notification(场景3、4) + receive_notification_inapp(场景5) / push_server的总推送量
    push_server的总推送量的获取, 可以参见阿里云官方文档：https://help.aliyun.com/document_detail/434650.html?spm=a2c4g.434651.0.0.3bb5266deSP2AP
--]]

local HTTP = E.HTTP

local VENDOR_NAME = 'PUSH'
local TAG = EM.MODULE.VENDORS.PUSH

local CAST_LUA_INIT_FINISH = "CAST_LUA_INIT_FINISH"
local CAST_TURN_ON_PUSH = "CAST_TURN_ON_PUSH"
local CAST_TURN_OFF_PUSH = "CAST_TURN_OFF_PUSH"
local CAST_ADD_LOCAL_NOTIFICATION = "CAST_ADD_LOCAL_NOTIFICATION"
local CAST_REMOVE_LOCAL_NOTIFICATION = "CAST_REMOVE_LOCAL_NOTIFICATION"
--local CLEAR_LOCAL_NOTIFICATION = "CLEAR_LOCAL_NOTIFICATION"

--local ASYNC_CHECK_CHANNEL_STATUS = "ASYNC_CHECK_CHANNEL_STATUS"
local ASYNC_BIND_ACCOUNT = "ASYNC_BIND_ACCOUNT"
local ASYNC_UNBIND_ACCOUNT = "ASYNC_UNBIND_ACCOUNT"
local ASYNC_ADD_ALIAS = "ASYNC_ADD_ALIAS"
local ASYNC_REMOVE_ALIAS = "ASYNC_REMOVE_ALIAS"
--local ASYNC_LIST_ALIASES = "ASYNC_LIST_ALIASES"
local ASYNC_BIND_TAG = "ASYNC_BIND_TAG"
local ASYNC_UNBIND_TAG = "ASYNC_UNBIND_TAG"
--local ASYNC_LIST_TAGS = "ASYNC_LIST_TAGS"

local EVT_ON_SERVER_MESSAGE = "EVT_ON_SERVER_MESSAGE"
local EVT_ON_SERVER_NOTIFICATION = "EVT_ON_SERVER_NOTIFICATION"
local EVT_ON_SERVER_NOTIFICATION_OPEN = "EVT_ON_SERVER_NOTIFICATION_OPEN"
--local EVT_ON_SERVER_NOTIFICATION_REMOVED = "EVT_ON_SERVER_NOTIFICATION_REMOVED"
--local EVT_ON_SERVER_NOTIFICATION_CLICKED_WITH_NOACTION = "EVT_ON_SERVER_NOTIFICATION_CLICKED_WITH_NOACTION"
local EVT_ON_SERVER_NOTIFICATION_RECEIVED_INAPP = "EVT_ON_SERVER_NOTIFICATION_RECEIVED_INAPP"
local EVT_ON_LOCAL_NOTIFICATION = "EVT_ON_LOCAL_NOTIFICATION"
local EVT_ON_LOCAL_NOTIFICATION_OPEN = "EVT_ON_LOCAL_NOTIFICATION_OPEN"
local EVT_ON_LOCAL_NOTIFICATION_RECEIVE_INAPP = "EVT_ON_LOCAL_NOTIFICATION_RECEIVE_INAPP"

local PUSH_LAST_PLAYER_ID = E.LazyKeyStore:New('PUSH_LAST_PLAYER_ID', false, false, false)
local PUSH_LAST_PLAYER_ID_TIME = E.LazyKeyStore:New('PUSH_LAST_PLAYER_ID_TIME', false, false, false)
local PUSH_LAST_ACCOUNT_ID = E.LazyKeyStore:New('PUSH_LAST_ACCOUNT_ID', false, false, false)
local PUSH_LAST_ACCOUNT_ID_TIME = E.LazyKeyStore:New('PUSH_LAST_ACCOUNT_ID_TIME', false, false, false)
local PUSH_LAST_SERVER_ID = E.LazyKeyStore:New('PUSH_LAST_SERVER_ID', false, false, false)
local PUSH_LAST_SERVER_ID_ON_DEVICE = E.LazyKeyStore:New('PUSH_LAST_SERVER_ID_ON_DEVICE', false, false, false)
local SAVE_ENTER_GAME_TAG = E.LazyKeyStore:New('SAVE_ENTER_GAME_TAG', false, false, false)
local PUSH_TOPIC_STORE = E.LazyKeyStore:New('PUSH_TOPIC_STORE', false, true, false)
local PUSH_BIND_CACHE_EXPIRY_DURATION = 24 * 3600 -- 有效期1天，单位秒
local PUSH_LAST_SDK_VERSION = E.LazyKeyStore:New('PUSH_LAST_SDK_VERSION', false, false, false)
local PUSH_LAST_PLATFORM = E.LazyKeyStore:New('PUSH_LAST_PLATFORM', false, false, false)

local M = Vendor:Inherit(VENDOR_NAME)

M.DEVICE_TARGET = 1  -- 后续新增的预设标签，请使用DEVICE_TARGET
M.ACCOUNT_TARGET = 2  -- 后续新增的预设标签，请使用DEVICE_TARGET
M.ALIAS_TARGET = 3  -- 后续新增的预设标签，请使用DEVICE_TARGET

local COLLECT_TYPE_ACCOUNT = 'account'
local COLLECT_TYPE_PLAYERID = 'player_id'

local appkey = nil

local url_items = {
    check_tags = '/api/check_tags'
}
local TYPE_LEN_LIMIT = 40
local TYPE_TAG_LIMIT = 80
local PUSH_ERROR_CORE = {
    PUSH_BIND_SUC = 74003001,
    PUSH_ERROR_PARAMS = 74003002, -- 参数错误
    PUSH_BIND_FAIL = 74003003 -- 绑定失败
}

M.FREQUENTLY_EVENTS = {
    ACTIVE = 'active', --激活未注册
    ACCOUNTID_REGISTER = 'accountid_register', --注册未创角
    PLAYER_CREATE = 'player_create', --完成创角
}

local is_bind_use_cache = false

local function require_params()
    return {
        acceptable = E.HTTP.CT_JSON,
        headers = {['moment-Token'] = EH.get_player_token()}
    }
end

local push_post = function(type, params, cb)

    if url_items[type] then

        local product = E.CONFIG.get_config('product'):lower()
        local url_base = E.CONFIG.get_config('pusher')
        -- push服务暂不支持url_base .. url_items[type]这个结构
        local url = url_base .. '/pusher/' .. product .. url_items[type]
        
        E.HTTP.post(url, require_params(), E.HTTP.CT_JSON, params, function(resp)
            if resp and resp.status == 200 then
                if resp.body and resp.body.code == 0 then
                    cb(true, resp and resp.body)
                else
                    local body = resp.body
                    cb(false, body and body.code, body and body.message)
                end
            else
                cb(false, resp and resp.status or -1, 'request error')
            end
        end)
    end
end

local function get_value_from_topic_store(key)
    local store_value = PUSH_TOPIC_STORE:get() or {}
    return store_value[key]
end

local function set_value_to_topic_store(key, value)
    local info = PUSH_TOPIC_STORE:get() or {}
    info[key] = value
    PUSH_TOPIC_STORE:set(info)
end

local function is_bind_use_cache_from_cc()
    -- 从配置中心判断是否使用缓存，用来做功能回滚
    local cc_config = ECC.get_config(ECC.NAMESPACE.EJOYSDK_BIZ)
    local push_config = cc_config and cc_config.config and cc_config.config.push  -- 读取阿里云推送的配置，firebase不用这个key
    if push_config and push_config.is_bind_use_cache then
        return true
    end
    return false
end

local function get_appkey()
    if not appkey then
        if E.Sysinfo.os() == 'android' then
            appkey = tostring(E.Sysinfo.manifest_meta_data('int', 'com.alibaba.app.appkey'))
        elseif E.Sysinfo.os() == 'ios' then
            appkey = tostring(UNI.sync_call(VENDOR_NAME, 'ASYNC_PUSH_GET_APPKEY', {}).value)
        end
    end
    E.LOG.debug(TAG, 'appkey: ' .. tostring(appkey))
    return appkey
end

local server_collect = function(type, value, cb)
    assert(type == COLLECT_TYPE_PLAYERID or type == COLLECT_TYPE_ACCOUNT, 'server collect type wrong')
    cb = cb or function() end
    local product = E.CONFIG.get_config('product'):lower()
    local url_base = E.CONFIG.get_config('pusher')
    local url = url_base .. '/pusher/' .. product .. '/manage/ay/collect'
    local params = {
        type = type,
        value = value,
        appKey = get_appkey()
    }
    local header = {
        acceptable = E.HTTP.CT_JSON,
        _log_config = {log_level = log_mgr.LOG_LEVEL.HIGH}
    }

    -- bugfix: 如果是账号维度的绑定，moment-token就不要传了，否则服务器会优先取moment-token作为鉴权
    if COLLECT_TYPE_ACCOUNT == type then
        header.headers = { ['Ejoy-Token'] = EG.user_info().token }
    else
        header.headers = { ['moment-token']= EH.get_player_token(), ['Ejoy-Token'] = EG.user_info().token }
    end
    HTTP.post(url, header, HTTP.CT_JSON, params, function(resp)
        --E.log(resp)
        if resp.status == 200 then
            if resp.body and resp.body.code == 0 then
                local bind_value = resp.body and resp.body.bind_value
                -- 旧版本服务端这个为nil，新版本正式环境保持不变，测试环境会返回拼接规则
                cb(true, bind_value)
            else
                cb(false)
            end
        else
            cb(false)
        end
    end)
end

local function async_call(type, params, cb)
    UNI.async_call(VENDOR_NAME, type, params, nil, cb)
end

function M.turn_on_push()
    UNI.cast(VENDOR_NAME, CAST_TURN_ON_PUSH, {})
end

function M.turn_off_push()
    UNI.cast(VENDOR_NAME, CAST_TURN_OFF_PUSH, {})
end

local function get_product_env()
    local product = E.CONFIG.get_config('product')
    product = product and product:lower()
    return product or ''
end

local function bind_account_use_cache_flag(account)
    local last_account = PUSH_LAST_ACCOUNT_ID:get()
    local last_account_time = PUSH_LAST_ACCOUNT_ID_TIME:get() or 0
    local now = E.time()  -- 服务器时间, 单位秒

    -- 账号变了 或者 超过缓存标记有效期(1天)，就重新绑定
    if last_account ~= account or now -  last_account_time >= PUSH_BIND_CACHE_EXPIRY_DURATION  then

        server_collect(COLLECT_TYPE_ACCOUNT, account, function(succ2, bind_value)
            if succ2 then

                local account_tag = account
                if bind_value ~= nil then
                    -- 以服务端规则为准，否则照旧
                    account_tag = bind_value
                end

                async_call(ASYNC_BIND_ACCOUNT, { account = account_tag }, function(succ, ...)
                    if succ then
                        E.LOG.d(TAG, 'bind_account_use_cache_flag:' .. tostring(account_tag) .. ' succ')
                    else
                        PUSH_LAST_ACCOUNT_ID:set('')
                        PUSH_LAST_ACCOUNT_ID_TIME:set(0)
        
                        local log_params = {account=tostring(account),
                                            last_account=tostring(last_account),
                                            last_account_time=tostring(last_account_time),
                                            cause='async_call_bind_account_fail'}
                        log_mgr.warn({}, TAG, 'push_bind_account_fail', log_params, {})
                        ESTAT.stat_action('push', 'bind_account', false, log_params)
                    end
                end)

                PUSH_LAST_ACCOUNT_ID:set(account)
                PUSH_LAST_ACCOUNT_ID_TIME:set(E.time())

                local log_params = {account=tostring(account),
                                    last_account=tostring(last_account),
                                    last_account_time=tostring(last_account_time)}
                log_mgr.debug({}, TAG, 'push_bind_account_succ', 'bind_account', log_params, {})  

            else
                PUSH_LAST_ACCOUNT_ID:set('')
                PUSH_LAST_ACCOUNT_ID_TIME:set(0)

                M.unbind_account(account)

                local log_params = {account=tostring(account),
                                    last_account=tostring(last_account),
                                    last_account_time=tostring(last_account_time),
                                    cause='server_collect_fail'}
                log_mgr.warn({}, TAG, 'push_bind_account_fail', log_params, {})
                ESTAT.stat_action('push', 'bind_account', false, log_params)
            end
        end)        
    else
        local log_params = {account=tostring(account),
                            last_account=tostring(last_account),
                            last_account_time=tostring(last_account_time)}
        log_mgr.debug({}, TAG, 'push_bind_account_succ_already', 'bind_account', log_params, {})
    end
end

function M.bind_account(account)
    local last_account = PUSH_LAST_ACCOUNT_ID:get()
    local last_account_time = PUSH_LAST_ACCOUNT_ID_TIME:get() or 0

    local log_params_start = {last_account=tostring(last_account),
                        last_account_time=tostring(last_account_time),
                        account=tostring(account)}
    log_mgr.debug({}, TAG, 'push_bind_account_start', 'bind_account', log_params_start, {})

    if is_bind_use_cache then
        bind_account_use_cache_flag(account)
    else
        -- bugfix: 不判断 last_account 和 account，直接每次账号登录，都重新绑定账号，解决玩家在多设备之间切换账号，导致旧设备不能收到推送的问题

        server_collect(COLLECT_TYPE_ACCOUNT, account, function(succ2, bind_value)
            if succ2 then

                local account_tag = account
                if bind_value ~= nil then
                    -- 以服务端规则为准，否则照旧
                    account_tag = bind_value
                end

                async_call(ASYNC_BIND_ACCOUNT, { account = account_tag }, function(succ, ...)
                    if succ then
                        E.LOG.d(TAG, 'bind_account:' .. tostring(account_tag) .. ' succ')
                    else
                        PUSH_LAST_ACCOUNT_ID:set('')
                        PUSH_LAST_ACCOUNT_ID_TIME:set(0)
        
                        local log_params = {account=tostring(account),
                                            last_account=tostring(last_account),
                                            last_account_time=tostring(last_account_time),
                                            cause='async_call_bind_account_fail'}
                        log_mgr.warn({}, TAG, 'push_bind_account_fail', log_params, {})
                        ESTAT.stat_action('push', 'bind_account', false, log_params)
                    end
                end)

                PUSH_LAST_ACCOUNT_ID:set(account)
                PUSH_LAST_ACCOUNT_ID_TIME:set(E.time())

                local log_params = {account=tostring(account),
                                    last_account=tostring(last_account),
                                    last_account_time=tostring(last_account_time),
                                    cause='bind_account_succ'}
                log_mgr.debug({}, TAG, 'push', 'bind_account', log_params, {})
            else
                PUSH_LAST_ACCOUNT_ID:set('')
                PUSH_LAST_ACCOUNT_ID_TIME:set(0)

                M.unbind_account(account)

                local log_params = {account=tostring(account),
                                    last_account=tostring(last_account),
                                    last_account_time=tostring(last_account_time),
                                    cause='server_collect_fail'}
                log_mgr.warn({}, TAG, 'push_bind_account_fail', log_params, {})
                ESTAT.stat_action('push', 'bind_account', false, log_params)
            end
        end)
    end
end

function M.unbind_account(account, cb)
    log_mgr.call_api({}, TAG, 'unbind_account', log_mgr.LOG_LEVEL.HIGH, {}, account, cb)

    async_call(ASYNC_UNBIND_ACCOUNT, {account = account}, function (...)
        if cb then
            cb(...)
        end

        log_mgr.call_api_async_callback({}, TAG, 'unbind_account', log_mgr.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.add_alias(alias, cb)
    log_mgr.call_api({}, TAG, 'add_alias', log_mgr.LOG_LEVEL.HIGH, {}, alias, cb)

    async_call(ASYNC_ADD_ALIAS, {alias = alias}, function (...)
        if cb then
            cb(...)
        end

        log_mgr.call_api_async_callback({}, TAG, 'add_alias', log_mgr.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

-- 如果 alias 为 nil，则 remove 权限 alias
function M.remove_alias(alias, cb)
    log_mgr.call_api({}, TAG, 'remove_alias', log_mgr.LOG_LEVEL.HIGH, {}, alias, cb)

    async_call(ASYNC_REMOVE_ALIAS, {alias = alias}, function(...)
        if cb then
            cb(...)
        end

        log_mgr.call_api_async_callback({}, TAG, 'remove_alias', log_mgr.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.bind_tag(target, tags, alias, cb)
    log_mgr.call_api({}, TAG, 'bind_tag', log_mgr.LOG_LEVEL.HIGH, {}, target, tags, alias, cb)

    async_call(ASYNC_BIND_TAG, {target = target, tags = tags, alias = alias}, function(...)
        if cb then
            cb(...)
        end

        log_mgr.call_api_async_callback({}, TAG, 'bind_tag', log_mgr.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.unbind_tag(target, tags, alias, cb)
    log_mgr.call_api({}, TAG, 'unbind_tag', log_mgr.LOG_LEVEL.HIGH, {}, target, tags, alias, cb)

    async_call(ASYNC_UNBIND_TAG, {target = target, tags = tags, alias = alias}, function(...)
        if cb then
            cb(...)
        end

        log_mgr.call_api_async_callback({}, TAG, 'unbind_tag', log_mgr.LOG_LEVEL.HIGH, {}, cb, ...)
    end)
end

function M.add_local_notification(title, content, calendar, ext, config)
    log_mgr.call_api({}, TAG, 'add_local_notification', log_mgr.LOG_LEVEL.LOW, {}, title, content, calendar, ext, config)

    UNI.cast(VENDOR_NAME, CAST_ADD_LOCAL_NOTIFICATION,
            {title = title,
                    content = content,
                    calendar = calendar,
                    ext = ext,
                    config = config}
    )
end

function M.remove_local_notification(notify_id)
    log_mgr.call_api({}, TAG, 'remove_local_notification', log_mgr.LOG_LEVEL.LOW, {}, notify_id)

    UNI.cast(VENDOR_NAME, CAST_REMOVE_LOCAL_NOTIFICATION, {notify_id = notify_id})
end

local push_handlers = nil

function M.set_handlers(handlers)
    log_mgr.call_api({}, TAG, 'set_handlers', log_mgr.LOG_LEVEL.LOW, {}, handlers)

    push_handlers = handlers
end

-- bind_player_id_alias_func是实际开始绑定的action
local function bind_player_use_cache_flag(player_id, bind_player_id_alias_func)
    local last_player_id = PUSH_LAST_PLAYER_ID:get()
    local last_player_id_time = PUSH_LAST_PLAYER_ID_TIME:get() or 0
    local now = E.time()  -- 服务器时间, 单位秒

    -- 绑定的角色变了，或者缓存超过有效期(1天)
    if last_player_id ~= player_id or now - last_player_id_time >= PUSH_BIND_CACHE_EXPIRY_DURATION then
        M.remove_alias(nil, function(succ)
            if succ then
                PUSH_LAST_PLAYER_ID:set('') -- remove_alias 后，本地也清空 LAST_PLAYER_ID
                PUSH_LAST_PLAYER_ID_TIME:set(0)

                if bind_player_id_alias_func then
                    bind_player_id_alias_func()
                end
            else
                local log_params = {player_id=tostring(player_id),
                                    last_player_id=tostring(last_player_id),
                                    last_player_id_time=tostring(last_player_id_time),
                                    cause='remove_alias_fail'}
                log_mgr.warn({}, TAG, 'push_bind_player_fail', log_params, {})
                ESTAT.stat_action('push', 'bind_player', false, log_params)
            end
        end)
    else
        local log_params = {player_id=tostring(player_id),
                            last_player_id=tostring(last_player_id),
                            last_player_id_time=tostring(last_player_id_time),
                            cause='bind_player_succ_already'}
        log_mgr.debug({}, TAG, 'push', 'bind_player', log_params, {})
    end
end

function M.bind_player_id(player_id)
    local last_player_id = PUSH_LAST_PLAYER_ID:get()
    local last_player_id_time = PUSH_LAST_PLAYER_ID_TIME:get() or 0

    local function bind_player_id_alias_func()
        server_collect(COLLECT_TYPE_PLAYERID, player_id, function(succ2, bind_value)
            if succ2 then

                local player_id_alias = player_id
                if bind_value ~= nil then
                    -- 以服务端规则为准，否则照旧
                    player_id_alias = bind_value
                end

                M.add_alias(player_id_alias, function(succ, ...)
                    if succ then
                        E.LOG.d(TAG, 'add_alias:' .. tostring(player_id_alias) .. ' succ')
                    else
                        local log_params = {player_id=tostring(player_id),
                                            last_player_id=tostring(last_player_id),
                                            last_player_id_time=tostring(last_player_id_time),
                                            cause='add_alias_fail'}
                        log_mgr.warn({}, TAG, 'push_bind_player_fail', log_params, {})
                        ESTAT.stat_action('push', 'bind_player', false, log_params)
                    end
                end)

                PUSH_LAST_PLAYER_ID:set(player_id)
                PUSH_LAST_PLAYER_ID_TIME:set(E.time())

                local log_params = {player_id=tostring(player_id),
                                    last_player_id=tostring(last_player_id),
                                    last_player_id_time=tostring(last_player_id_time),
                                    cause='bind_player_succ'}
                log_mgr.debug({}, TAG, 'push', 'bind_player', log_params, {})
            else
                PUSH_LAST_PLAYER_ID:set('')
                PUSH_LAST_PLAYER_ID_TIME:set(0)
                M.remove_alias(nil)

                local log_params = {player_id=tostring(player_id),
                                    last_player_id=tostring(last_player_id),
                                    last_player_id_time=tostring(last_player_id_time),
                                    cause='server_collect_fail'}
                log_mgr.warn({}, TAG, 'push_bind_player_fail', log_params, {})
                ESTAT.stat_action('push', 'bind_player', false, log_params)
            end
        end)
    end

    local log_params_start = {player_id=tostring(player_id),
                        last_player_id=tostring(last_player_id),
                        last_player_id_time=tostring(last_player_id_time),
                        cause='bind_player_start'}
    log_mgr.debug({}, TAG, 'push', 'bind_player', log_params_start, {})

    if is_bind_use_cache then
        bind_player_use_cache_flag(player_id, bind_player_id_alias_func)
    else
        -- bugfix: 不判断 last_player_id 和 player_id，直接每次选角进入游戏，都重新绑定别名，解决玩家在多设备之间切换账号，导致旧设备不能收到推送的问题
        M.remove_alias(nil, function(succ)
            if succ then
                PUSH_LAST_PLAYER_ID:set('') -- remove_alias 后，本地也清空 LAST_PLAYER_ID
                PUSH_LAST_PLAYER_ID_TIME:set(0)
                bind_player_id_alias_func()
            else
                local log_params = {player_id=tostring(player_id),
                                    last_player_id=tostring(last_player_id),
                                    last_player_id_time=tostring(last_player_id_time),
                                    cause='remove_alias_fail'}
                log_mgr.warn({}, TAG, 'push_bind_player_fail', log_params, {})
                ESTAT.stat_action('push', 'bind_player', false, log_params)
            end
        end)
    end
end

function M.bind_server_id(server_id)
    local last_account = PUSH_LAST_ACCOUNT_ID:get()
    local user_info = EG.user_info()
    local account = user_info.uid

    log_mgr.debug({}, TAG, 'push_bind_server_start', 'bind_server', {last_account=last_account, account=account}, {})

    if last_account ~= account then
        log_mgr.warn({}, TAG, 'push_bind_server_fail', {last_account=last_account, account=account, cause='current_account_bind_fail'}, {})
        -- 说明 account 没有绑定成功，这时不能 bind_tag，因为我们的 bind_tag 是绑定在阿里云账号上面
        return
    end
    local last_server_id = PUSH_LAST_SERVER_ID:get()
    local function bind_server_id_tag()
        local server_tag = 'server:' .. server_id
        M.bind_tag(M.ACCOUNT_TARGET, {server_tag}, nil, function(succ)
            if succ then
                log_mgr.debug({}, TAG, 'push_bind_server_succ', 'bind_server', {server_tag=server_tag}, {})
                PUSH_LAST_SERVER_ID:set(server_id)
            else
                log_mgr.warn({}, TAG, 'push_bind_server_fail', {server_tag=server_tag, cause='bind_tag_fail'}, {})
                PUSH_LAST_SERVER_ID:set('')
            end
        end)
    end

    log_mgr.debug({}, TAG, 'push_check_server_id', 'bind_server', {server_id=server_id, last_server_id=last_server_id}, {})

    if last_server_id == nil or #last_server_id == 0 then
        bind_server_id_tag()
    elseif last_server_id ~= server_id then
        local last_server_tag = 'server:' .. last_server_id
        M.unbind_tag(M.ACCOUNT_TARGET, {last_server_tag}, nil, function(succ)
            if succ then
                PUSH_LAST_SERVER_ID:set('')
                bind_server_id_tag()
            else
                log_mgr.warn({}, TAG, 'push_bind_server_fail', {last_server_tag=last_server_tag, cause='unbind_tag_fail'}, {})
            end
        end)
    else
        log_mgr.debug({}, TAG, 'push_bind_server_succ_already', 'bind_server', {server_id=server_id, last_server_id=last_server_id}, {})
    end
end

function M.bind_server_id_on_device(server_id)
    if not server_id or type(server_id) ~= 'string' or #server_id == 0 then
        return
    end

    local last_server_id = PUSH_LAST_SERVER_ID_ON_DEVICE:get()

    local function bind_server_id_tag()
        local server_tag = 'server:' .. server_id
        M.bind_tag(M.DEVICE_TARGET, {server_tag}, nil, function(succ)
            if succ then
                log_mgr.debug({}, TAG, 'push_bind_server_succ', 'bind_server_on_device', {server_tag=server_tag}, {})
                PUSH_LAST_SERVER_ID_ON_DEVICE:set(server_id)
            else
                log_mgr.warn({}, TAG, 'push_bind_server_fail_on_device', {server_tag=server_tag, cause='bind_tag_fail'}, {})
            end
        end)
    end

    log_mgr.debug({}, TAG, 'push_check_server_id', 'bind_server_on_device', {server_id=server_id, last_server_id=last_server_id}, {})

    if last_server_id == nil or #last_server_id == 0 then
        bind_server_id_tag()
    elseif last_server_id ~= server_id then
        local last_server_tag = 'server:' .. last_server_id
        M.unbind_tag(M.DEVICE_TARGET, {last_server_tag}, nil, function(succ)
            if succ then
                PUSH_LAST_SERVER_ID_ON_DEVICE:set('')
                bind_server_id_tag()
            else
                log_mgr.warn({}, TAG, 'push_bind_server_fail_on_device', {last_server_tag=last_server_tag, cause='unbind_tag_fail'}, {})
            end
        end)
    else
        log_mgr.debug({}, TAG, 'push_bind_server_succ_already', 'bind_server_on_device', {server_id=server_id, last_server_id=last_server_id}, {})
    end
end

local clear_push_data_for_last_account = function()
    local last_account = PUSH_LAST_ACCOUNT_ID:get()
    if last_account and #last_account > 0 then
        PUSH_LAST_ACCOUNT_ID:set('')
        PUSH_LAST_ACCOUNT_ID_TIME:set(0)
        M.unbind_account(last_account, function(succ, ...)
            E.LOG.debug(TAG, 'aliyun logout unbind account: ' .. tostring(last_account) .. ', result:' .. tostring(succ))
            if not succ then
                local error_code, error_msg = ...
                E.LOG.debug(TAG, 'error code: ' .. tostring(error_code) .. ', error msg: ' .. tostring(error_msg))
            end
        end)
    end
end

local clear_push_data_for_last_player_id = function ()
    local last_player_id = PUSH_LAST_PLAYER_ID:get()
    if last_player_id and #last_player_id > 0 then
        PUSH_LAST_PLAYER_ID:set('')
        PUSH_LAST_PLAYER_ID_TIME:set(0)
        M.remove_alias(nil, function(succ, ...)
            E.LOG.debug(TAG, 'aliyun logout unbind player_id: ' .. tostring(last_player_id) .. ', result: '.. tostring(succ))
            if not succ then
                local error_code, error_msg = ...
                E.LOG.debug(TAG, 'error code: ' .. tostring(error_code) .. ', error msg: ' .. tostring(error_msg))
            end
        end)
    end
end

local clear_push_data_for_last_server_id = function()
    local last_server_id = PUSH_LAST_SERVER_ID:get()
    if last_server_id and #last_server_id > 0 then
        local last_server_tag = 'server:' .. last_server_id
        M.unbind_tag(M.ACCOUNT_TARGET, {last_server_tag}, nil, function(succ, ...)
            E.LOG.debug(TAG, 'aliyun logout unbind server_id: ' .. tostring(last_server_id) .. ', result: ' .. tostring(succ))
            if succ then
                PUSH_LAST_SERVER_ID:set('')
            else
                local error_code, error_msg = ...
                E.LOG.debug(TAG, 'error code: ' .. tostring(error_code) .. ', error msg: ' .. tostring(error_msg))
            end
        end)
    end
end

local clear_push_data_for_last_server_id_on_device = function()
    local last_server_id_on_device = PUSH_LAST_SERVER_ID_ON_DEVICE:get()
    if last_server_id_on_device and #last_server_id_on_device > 0 then
        local last_server_tag = 'server:' .. last_server_id_on_device
        M.unbind_tag(M.DEVICE_TARGET, {last_server_tag}, nil, function(succ, ...)
            E.LOG.debug(TAG, 'aliyun logout unbind server_id on device: ' .. tostring(last_server_id_on_device) .. ', result: ' .. tostring(succ))
            if succ then
                PUSH_LAST_SERVER_ID_ON_DEVICE:set('')
            else
                local error_code, error_msg = ...
                E.LOG.debug(TAG, 'error code: ' .. tostring(error_code) .. ', error msg: ' .. tostring(error_msg))
            end
        end)
    end
end

function M.clear_push_data_on_player_offline()
    clear_push_data_for_last_player_id()
    clear_push_data_for_last_server_id()
    clear_push_data_for_last_server_id_on_device()
end

function M.clear_push_data()
    clear_push_data_for_last_account()
    clear_push_data_for_last_player_id()
    clear_push_data_for_last_server_id()
    clear_push_data_for_last_server_id_on_device()
end

local function callback(push_handler_name, ...)
    if push_handlers then
        local push_handler = push_handlers[push_handler_name]
        if push_handler then
            push_handler(...)
        end
    end
end

local function open_community_page(notification_body)
    local is_community_notification = false
    local biz_data
    if not notification_body.ext or not notification_body.ext.platform_payload then
        return
    end

    local platform_payload = notification_body.ext.platform_payload
    if type(platform_payload) == 'string' then
        E.LOG.d(TAG, 'platform_payload data type is string')
        -- 安卓，传过来的是json string, ios传来的table
        platform_payload = JSON.safe_decode(platform_payload)
    end

    if type(platform_payload) ~= 'table' then
        return
    end

    if platform_payload.biz_data and platform_payload.biz_data.platform then
        local ESW = require "ejoysdk_lua.shortcut.ejoysdk_shortcut_webview"
        if ESW.Type.Community == platform_payload.biz_data.platform then
            is_community_notification = true
            biz_data = platform_payload.biz_data
        end
    end

    if not is_community_notification then
        return false
    end

    -- 在这里判断，是否为微社区推送，如果是，则拉起微社区页面
    local ESW = require "ejoysdk_lua.shortcut.ejoysdk_shortcut_webview"

    local sc_params = ESW.get_config_from_cc_h5res('community')
    if not sc_params then
        return false
    end

    -- 配置中心侧，已经禁用了推送拉起微社区
    if sc_params.disable_notification_open ~= nil and sc_params.disable_notification_open == true then
        return false
    end

    local HOLO = require "ejoysdk_lua.ejoysdk_holo"
    if not HOLO.get_player_token() then
        E.LOG.d(TAG, 'player not login, not launch community')
        return false
    end

    local params = {
        ['local_params'] = {
            ['from_source'] = 'community'  -- 这个打开路径，说明游戏已经启动，所以from_source的值是community
        }
    }

    if biz_data and type(biz_data) == 'table' and next(biz_data) ~= nil then
        params.from_source_data = {}
        params.from_source_data.biz_data = biz_data  -- 根据前端的要求，填充from_source_data
    end

    ECO.notification_open(params)

    return true
end

local EVT_HANDLERS = {}

EVT_HANDLERS[EVT_ON_SERVER_MESSAGE] = function(body)
    callback(push_event.ON_SERVER_MESSAGE, body.title, body.content, body.ext or {})
    ESTAT.stat_action('push', 'receive_message', true, {})
end

EVT_HANDLERS[EVT_ON_SERVER_NOTIFICATION] = function(body)
    callback(push_event.ON_SERVER_NOTIFICATION, body.title, body.content, body.ext or {})
    ESTAT.stat_action('push', 'receive_notification', true, {})
end

EVT_HANDLERS[EVT_ON_SERVER_NOTIFICATION_OPEN] = function(body)
    callback(push_event.ON_SERVER_NOTIFICATION_OPEN, body.title, body.content, body.ext or {})

    -- 将通知数据，按urlopen的链路透传给游戏
    E.LOG.debug('url_open', '[v2]receive aliyun:' .. JSON.encode(body))
    local notification_body = body or {}
    ET.publish('urlopen_v2', 'notification', notification_body)

    -- TODO： 后面优化下，这个逻辑应该写在微社区模块，让微社区模块监听urlopen_v2的广播
    open_community_page(notification_body)

    -- 通过launch_time去区分打开通知前，游戏进程在后台还是已被kill，launch_time和打点时间较近的是进程已被kill，反之在后台
    local launch_time = E.Sysinfo.launch_time() / 1000  -- E.Sysinfo.launch_time()的单位是毫秒，需要转成秒
    ESTAT.stat_action('push', 'open_notification', launch_time, notification_body)
end

EVT_HANDLERS[EVT_ON_SERVER_NOTIFICATION_RECEIVED_INAPP] = function(body)
    callback(push_event.ON_SERVER_NOTIFICATION_IN_APP, body.title, body.content, body.ext or {})
    ESTAT.stat_action('push', 'receive_notification_inapp', true, {})
end

EVT_HANDLERS[EVT_ON_LOCAL_NOTIFICATION] = function(body)
    callback(push_event.ON_LOCAL_NOTIFICATION, body.title, body.content, body.ext or {})
end

EVT_HANDLERS[EVT_ON_LOCAL_NOTIFICATION_OPEN] = function(body)
    callback(push_event.ON_LOCAL_NOTIFICATION_OPEN, body.title, body.content, body.ext or {})
end

EVT_HANDLERS[EVT_ON_LOCAL_NOTIFICATION_RECEIVE_INAPP] = function(body)
    callback(push_event.ON_LOCAL_NOTIFICATION_IN_APP, body.title, body.content, body.ext or {})
end

-- 为当前设备绑定包名
local function bind_package_name_topic()
    local package_name = E.Sysinfo.package_name()

    local subscrib_cb = function(succ)
        if succ then
            E.LOG.debug(TAG, 'bind package_name: ' .. tostring(package_name) .. ' success!')
        else
            E.LOG.debug(TAG, 'bind package_name: ' .. tostring(package_name) .. ' failed!')
        end
    end

    E.LOG.debug(TAG, 'bind_package_name_topic, package_name: ' .. tostring(package_name))

    local package_name_topic = 'package_name:' .. package_name

    M.bind_tag(M.DEVICE_TARGET, { package_name_topic }, nil, subscrib_cb)
end


local function bind_os_topic()

    local os_name = _ejoysdk.os()

    local subscrib_cb = function(succ)
        if succ then
            E.LOG.debug(TAG, 'bind os: ' .. tostring(os_name) .. ' success!')
        else
            E.LOG.debug(TAG, 'bind os: ' .. tostring(os_name) .. ' failed!')
        end
    end

    E.LOG.debug(TAG, 'bind_os_topic, os: ' .. tostring(os_name))

    local os_topic = 'os:' .. os_name
    
    M.bind_tag(M.DEVICE_TARGET, { os_topic }, nil, subscrib_cb)
end


local function bind_sdk_version_topic()
    local ejoy = require("ejoysdk_lua.ejoysdk")
    local ejoysdk_version = ejoy.get_sdk_version_name('EJOYSDK')

    if not ejoysdk_version then
        E.log('bind_sdk_version_topic, but ejoysdk_version is nil')
        return
    end

    local last_sdk_version = PUSH_LAST_SDK_VERSION:get()
    if last_sdk_version and #last_sdk_version > 0 and last_sdk_version ~= ejoysdk_version then
        local last_sdk_version_topic = 'sdk_version:' .. last_sdk_version
        M.unbind_tag(M.DEVICE_TARGET, { last_sdk_version_topic }, nil, function(succ)
            if succ then
                PUSH_LAST_SDK_VERSION:set('')
                E.LOG.debug(TAG, 'unbind sdk_version: ' .. tostring(last_sdk_version) .. ' success!')
            else
                E.LOG.debug(TAG, 'unbind sdk_version: ' .. tostring(last_sdk_version) .. ' failed!')
            end
        end)
    end

    local subscrib_cb = function(succ)
        if succ then
            PUSH_LAST_SDK_VERSION:set(ejoysdk_version)
            E.LOG.debug(TAG, 'bind sdk_version: ' .. tostring(ejoysdk_version) .. ' success!')
        else
            E.LOG.debug(TAG, 'bind sdk_version: ' .. tostring(ejoysdk_version) .. ' failed!')
        end
    end

    E.LOG.debug(TAG, 'bind_sdk_version_topic, sdk_version: ' .. tostring(ejoysdk_version))

    local sdk_version_topic = 'sdk_version:' .. ejoysdk_version

    M.bind_tag(M.DEVICE_TARGET, { sdk_version_topic }, nil, subscrib_cb)
end

local function bind_platform_topic()
    local product = get_product_env()
    if product and #product > 0 then

        local last_platform = PUSH_LAST_PLATFORM:get()
        if last_platform and #last_platform > 0 and last_platform ~= product then
            local last_sdk_product_topic = 'platform:' .. last_platform
            M.unbind_tag(M.DEVICE_TARGET, { last_sdk_product_topic }, nil, function(succ)
                if succ then
                    PUSH_LAST_PLATFORM:set('')
                    E.LOG.debug(TAG, 'unbind platform: ' .. tostring(last_platform) .. ' success!')
                else
                    E.LOG.debug(TAG, 'unbind platform: ' .. tostring(last_platform) .. ' failed!')
                end
            end)
        end

        local sdk_product_topic = 'platform:' .. product
        local subscrib_cb = function(succ)
            if succ then
                PUSH_LAST_PLATFORM:set(product)
                E.LOG.debug(TAG, 'bind platform: ' .. tostring(product) .. ' success!')
            else
                E.LOG.debug(TAG, 'bind platform: ' .. tostring(product) .. ' failed!')
            end
        end
        M.bind_tag(M.DEVICE_TARGET, { sdk_product_topic }, nil, subscrib_cb)
    end
end

local function bind_frequently_events_topic(event_name)
    if not event_name then
        E.log('bind_frequently_events_topic, event_name is nil')
        return
    end

    E.log('bind_frequently_events_topic, event_name: ' .. tostring(event_name))

    local old_event_name = get_value_from_topic_store(event_name)
    if old_event_name then
        E.log('already bind this event_name before, can only bind once, event_name = '.. tostring(event_name))
        if M.FREQUENTLY_EVENTS.ACCOUNTID_REGISTER == event_name then
            local last_event_topic = 'frequently_events:' .. M.FREQUENTLY_EVENTS.ACTIVE
            -- unsubscrib_topic(last_event_topic, nil)
            M.unbind_tag(M.DEVICE_TARGET, { last_event_topic }, nil, function(_succ)
            end)
        elseif M.FREQUENTLY_EVENTS.PLAYER_CREATE == event_name then
            -- 取消前面两个步骤订阅的topic
            local last_event_topic1 = 'frequently_events:' .. M.FREQUENTLY_EVENTS.ACTIVE
            local last_event_topic2 = 'frequently_events:' .. M.FREQUENTLY_EVENTS.ACCOUNTID_REGISTER
            M.unbind_tag(M.DEVICE_TARGET, { last_event_topic1, last_event_topic2 }, nil, function(_succ) end)
        end
        return
    end

    local subscrib_frequently_events_cb = function(succ)
        if succ then
            set_value_to_topic_store(event_name, event_name)
            E.log('bind frequently_events_topic success, event_name = ' .. tostring(event_name))
        else
            E.log('bind frequently_events_topic failed, event_name = ' .. tostring(event_name))
        end
    end

    --整个APP安装后的生命周期，这三个事件都只能绑定一次
    local event_topic = 'frequently_events:' .. event_name
    if M.FREQUENTLY_EVENTS.ACTIVE == event_name then
        M.bind_tag(M.DEVICE_TARGET, { event_topic }, nil, subscrib_frequently_events_cb)
    elseif M.FREQUENTLY_EVENTS.ACCOUNTID_REGISTER == event_name then
        -- 取消绑定第一个事件
        local last_region_topic = 'frequently_events:' .. M.FREQUENTLY_EVENTS.ACTIVE
        M.unbind_tag(M.DEVICE_TARGET, { last_region_topic }, nil, function(_succ)
        end)
        M.bind_tag(M.DEVICE_TARGET, { event_topic }, nil, subscrib_frequently_events_cb)
    elseif M.FREQUENTLY_EVENTS.PLAYER_CREATE == event_name then
        -- 取消第一个绑定事件
        local last_event_topic1 = 'frequently_events:' .. M.FREQUENTLY_EVENTS.ACTIVE
        -- 取消第二个绑定事件
        local last_event_topic2 = 'frequently_events:' .. M.FREQUENTLY_EVENTS.ACCOUNTID_REGISTER
        M.unbind_tag(M.DEVICE_TARGET, { last_event_topic1, last_event_topic2 }, nil, function(_succ)
        end)
        M.bind_tag(M.DEVICE_TARGET, { event_topic }, nil, subscrib_frequently_events_cb)
    end
end

local function _check_custom_tag_parmas(type, tag, cb)
    if not type or not tag then 
        cb(false, PUSH_ERROR_CORE.FIREBASE_ERROR_PARAMS, 'type or tag should not be nil')
        return false
    end

    if #type > TYPE_LEN_LIMIT or #tag > TYPE_TAG_LIMIT then 
        cb(false, PUSH_ERROR_CORE.FIREBASE_ERROR_PARAMS, 'the length is not supported.(need: #type <= 40 and #tag <= 80)')
        return false
    end

    return true
end

-- 先请求push服务判断是否已配置了自定义标签
-- 返回成功后再绑定到三方的标签
-- 标签名type长度不能超过40，tag长度不能超过80 (总长度不能超过128)
function M.bind_custom_tag(type, tag, cb)

    if not _check_custom_tag_parmas(type, tag, cb) then 
        return
    end

    local custom_topic = tostring(type) .. ':' .. tostring(tag)

    local tag_params = { key = type, value = tag }

    -- 请求push服务
    push_post('check_tags', { tag_list = { tag_params } } , function (succ, ...)
        if succ then
            M.bind_tag(M.DEVICE_TARGET, { custom_topic }, nil, function(succ_topic)
                if succ_topic then
                    E.LOG.debug(TAG, 'bind custom_tag success, tag = ' .. tostring(custom_topic))
                    cb(true, tostring(custom_topic))
                else
                    E.LOG.debug(TAG, 'bind custom_tag fail, tag = ' .. tostring(custom_topic))
                    cb(false, PUSH_ERROR_CORE.FIREBASE_BIND_FAIL, 'bind custom_tag fail, tag = ' .. tostring(custom_topic))
                end
            end)
        else
            cb(false, ...)
        end
    end)
end

function M.unbind_custom_tag(type, tag, cb)

    if not _check_custom_tag_parmas(type, tag, cb) then 
        return
    end

    local custom_topic = tostring(type) .. ':' .. tostring(tag)
    M.unbind_tag(M.DEVICE_TARGET, { custom_topic }, nil, function(succ)
        if succ then
            E.LOG.debug(TAG, 'unbind custom_tag success, tag = ' .. tostring(custom_topic))
            cb(true, tostring(custom_topic))
        else
            E.LOG.debug(TAG, 'unbind custom_tag fail, tag = ' .. tostring(custom_topic))
            cb(false, PUSH_ERROR_CORE.FIREBASE_BIND_FAIL, 'unbind custom_tag fail, tag = ' .. tostring(custom_topic))
        end
    end)
end

-- 注册未创角
local function register_handler()
    bind_frequently_events_topic(M.FREQUENTLY_EVENTS.ACCOUNTID_REGISTER)
end

 -- 完成创建角色
local function get_player_info_handler(_player_info)
    bind_frequently_events_topic(M.FREQUENTLY_EVENTS.PLAYER_CREATE)
end

local function get_player_token_handler()

    local player_info = EG.player_info()
    -- 场景服等特殊角色的场景，不需要重新绑定推送
    if (not player_info) or (player_info and player_info.is_valid == false) then
        E.LOG.debug(TAG, 'player_info = nil or player_info.is_valid = false, ignore bind player')
        return
    end

    M.bind_player_id(player_info.player_id)
    M.bind_server_id(player_info.server_id)
    M.bind_server_id_on_device(player_info.server_id)
end

local function acquire_succ_handler()

    local user_info = EG.user_info()
    M.bind_account(user_info.uid)
end

local function do_init()
    log_mgr.debug({}, TAG, 'push_init_finish', 'push_init_finish', {}, {})

    ET.unsubscribe(ET.push.INITED, do_init)
    local ejoysdk_push = require 'ejoysdk_lua.push.ejoysdk_push'
    ejoysdk_push.set_push_vendor(M)
    UNI.register_event_cb(VENDOR_NAME, function(type, body)
        local handler = EVT_HANDLERS[type]
        if handler then
            handler(body)
        end
    end)
    UNI.cast(VENDOR_NAME, CAST_LUA_INIT_FINISH, {})

    local entered_game = SAVE_ENTER_GAME_TAG:get()
    if entered_game ~= 'true' then
        --已打开游戏（但未进入游戏）标签
        M.bind_tag(M.DEVICE_TARGET, {"user:not_logined"}, nil, function() end)
    end
end

local function enter_tag_handler(...)
    --已打开游戏（但未进入游戏）标签需要更新为：已进入游戏
    local entered_game = SAVE_ENTER_GAME_TAG:get()

    if entered_game ~= 'true' then
        M.unbind_tag(M.DEVICE_TARGET, {"user:not_logined"}, nil, function()
            M.bind_tag(M.DEVICE_TARGET, {"user:logined"}, nil, function() 
                SAVE_ENTER_GAME_TAG:set('true')
            end)
        end)
    end
end

function M.init(_opt, cb)
    E.LOG.tips(TAG, 'If you get a push error')
    log_mgr.call_api({}, TAG, 'init', log_mgr.LOG_LEVEL.HIGH, {}, _opt, cb)
    local ejoysdk_push = require 'ejoysdk_lua.push.ejoysdk_push'
    if ejoysdk_push.inited then
        do_init()
    else
        ET.subscribe(ET.push.INITED, do_init)
    end

    is_bind_use_cache = is_bind_use_cache_from_cc()
    ESTAT.stat_action('push', 'read_config_center', is_bind_use_cache, {})

    ET.subscribe(ET.gangplank.PLAYER_ONLINE, get_player_token_handler)
    ET.subscribe(ET.gangplank.PLAYER_OFFLINE, M.clear_push_data_on_player_offline)
    ET.subscribe(ET.gangplank.ACQUIRE, acquire_succ_handler)
    ET.subscribe(ET.gangplank.LOGIN, enter_tag_handler)
    ET.subscribe(ET.gangplank.LOGOUT, M.clear_push_data)
    ET.subscribe(ET.analytics.REGISTER, register_handler) -- 注册事件
    ET.subscribe(ET.gangplank.SET_PLAYER_INFO, get_player_info_handler)

    bind_package_name_topic()
    bind_os_topic()
    bind_sdk_version_topic()
    bind_platform_topic()

    -- 激活未注册
    bind_frequently_events_topic(M.FREQUENTLY_EVENTS.ACTIVE)
    
    -- callback init success
    cb(true)
end

M:is_implemented({"PUSH"})

return M