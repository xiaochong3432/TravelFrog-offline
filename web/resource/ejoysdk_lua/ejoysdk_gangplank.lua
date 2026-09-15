--
-- User: sean
-- Date: 15-12-1
-- Time: 下午3:45
-- API 尽量多的检查参数错误， 给用户更多方便
--

local E = require "ejoysdk_lua.ejoysdk"
local EV = require "ejoysdk_lua.ejoysdk_vendors"
local ER = require "ejoysdk_lua.ejoysdk_resource"
local ET = require "ejoysdk_lua.ejoysdk_topic"
local EM = require "ejoysdk_lua.ejoysdk_module"
local EI = require 'ejoysdk_lua.ejoysdk_init'

local UNI = require 'ejoysdk_lua.vendors.unisdk'
local VC = require 'ejoysdk_lua.ejoysdk_version_check'

local UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local QL = require "ejoysdk_lua.ejoysdk_qualitylog"
local AGREEMENT = require "ejoysdk_lua.agreement.ejoysdk_agreement"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local JSON = require 'ejoysdk_lua.ejoysdk_json'
local AEGIS = require "ejoysdk_lua.aegis.ejoysdk_aegis"
local POPUP = require "ejoysdk_lua.realname.ejoysdk_popup_handler"
local ACPOPUP = require "ejoysdk_lua.activedcode.ejoysdk_activecode"
local REALNAME_INFO = require "ejoysdk_lua.realname.realname_info"
local UIM = require "ejoysdk_lua.user_info_manager"
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local CM = require 'ejoysdk_lua.ejoysdk_channel_manager'
local EGC = require 'ejoysdk_lua.ejoysdk_gangplank_config'
local OFFICIAL = require 'ejoysdk_lua.vendors.official'
local LANG = require 'ejoysdk_lua.ejoysdk_lang'
local ETAGS = require 'ejoysdk_lua.opentracing.ejoysdk_tags'
local GDP = require "ejoysdk_lua.gangplank_data_provider"
local HTTP = E.HTTP

local M = {}

local LOGINID = math.random(1000, 9999)

local function gen_login_id()
    LOGINID = LOGINID + 1
    return LOGINID
end

local login_listener = nil
local logout_listener = nil
local switch_listener = nil
local pay_listener = nil
local bind_listener = nil
local queue_listener = nil
local exit_listener = nil
local acquire_listener = nil

local game_listeners = nil

local pending_product_infos = {}

local set_player_info_cb

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'gangplank'

function M.player_info()
    return GDP.PLAYER_INFO.clone()
end

function M.async_player_info(cb)
    if cb then
        cb(M.player_info())
    end
end

local EJOY_TOKEN = E.LazyKeyStore:New('EJOY_TOKEN')
local VENDOR_LOGIN = E.LazyKeyStore:New('VENDOR_LOGIN', false, true) -- 记录登录成功的信息
local LOGIN_INFO = E.LazyKeyStore:New("LOGIN_INFO", true, true) -- 记录准备登录的信息
local LAST_VENDOR_AUTH = E.LazyKeyStore:New("LAST_LOGIN", false, false, false)

local acquire_token_params = {}
local token_callback_for_acquire = nil

local CURRENT_QUEUE_LOOP = nil

--全球同服支持的地区列表
local global_region_token_cache = {}

local inited = false

-- 官方灵犀渠道登录的账号是否为游客，默认为false
local is_magic_guest = false

local last_pay_invoke_time = 0
local login_queue_rules_data

function M.login_info()
    return LOGIN_INFO
end

-- 返回灵犀账号是否为游客
function M.is_magic_guest()
    return is_magic_guest
end

local function gangplank_url_base(api, ver, url_base)
    local product = E.CONFIG.get_config('product'):lower()

    if ver then
        api = '/v' .. tostring(ver) .. api
    end

    return url_base .. '/gp/' .. product .. api
end

function M.gangplank_url(api, ver)
    local url_base = E.CONFIG.get_config('gangplank')
    if string.sub(api, 1, 1) ~= '/' then
        api = '/' .. api
    end
    return gangplank_url_base(api, ver, url_base)
end


local function gangplank_logined_url_base(api, ver, url_base)
    local product = E.CONFIG.get_config('product'):lower()

    if ver then
        api = '/logined/v' .. tostring(ver) .. api
    end

    return url_base .. '/gp/' .. product .. api
end

function M.gangplank_logined_url(api, ver)
    local url_base = E.CONFIG.get_config('gangplank')
    return gangplank_logined_url_base(api, ver, url_base)
end

local APIS = {
    login = true,
    queue = true,
    queue_dropout = true,
    create_order = true,
    bind = true,
    query = true,
    get_product_infos = true,
    access = true,
    alive_servers = true,
    get_alive_servers = true,
    acquire = true,
    gen_uuid = true,
    validate_uuid = true,
    grant_uuid_access = true,
    get_server_time = true,
    get_global_token = true,
    global_acquire = true,
    get_recommend_servers = true,
    get_ip_location = true,
    get_location = true,
    scene_login = true
}

local GangplankUrl = {
    __index = function(self, key)
        local ver = rawget(self, 'ver')
        local apis = rawget(self, 'apis') or APIS
        assert(apis[key], "api not found: " .. key)
        return M.gangplank_url('/' .. key, ver)
    end,
    new = function(self, ver, apis)
        return setmetatable({
            ver = ver,
            apis = apis,
        }, self)
    end
}

--local url_tbl_v1 = GangplankUrl:new()
local url_tbl_v2 = GangplankUrl:new('2')

local function require_params(token)
    return {
        trace = true,
        acceptable = E.HTTP.CT_JSON,
        headers = { ['Ejoy-Token'] = token }
    }
end

local function require_params_get_options(options)
    local r_params = require_params()
    if options and type(options) == "table" then
        for k, v in pairs(options) do
            r_params[k] = v
        end
    end

    return r_params
end


local GP_OPENTRACING_APIS = {
    acquire = { span_buz = 'login' },
    login = { span_buz = 'login', reference = ETAGS.CHILD_OF },
    get_server_time = { span_buz = 'init', reference = ETAGS.FOLLOWS_FROM },
}

local function gangplank_v2_post(cmd, params, cb, extra_opts)
    local url = url_tbl_v2[cmd]
    assert(url, "gangplank api: " .. cmd .. " not found")
    E.LOG.debug(TAG, 'gangplank post url: ' .. url)



    local config_params = { trace = true, acceptable = HTTP.CT_JSON }
    if GP_OPENTRACING_APIS[cmd] then
        if cmd == 'get_server_time' and not E.did_sync_sever_time() then
            config_params['opentracing'] = GP_OPENTRACING_APIS[cmd]
        else
            config_params['opentracing'] = GP_OPENTRACING_APIS[cmd]
        end
    end

    -- 防重放加签开关
    config_params.enable_sign_headers_for_request = extra_opts and extra_opts.enable_sign_headers_for_request or false
    config_params.enable_sign_headers_for_response = extra_opts and extra_opts.enable_sign_headers_for_response or false

    HTTP.post(url, config_params, HTTP.CT_JSON, params, function(resp)
        if resp.status == 200 then
            if resp.body.code == 0 then
                cb(200, resp.body)
            else
                cb(resp.body.code, resp.body)
            end
        else
            cb(resp.status, resp.body or {})
        end

        -- 针对acquire接口添加加签验签的打点，用于协助分析验签失败的原因
        if cmd == 'acquire' then
            local data = {}
            data.request_params = config_params
            data.request_body = JSON.encode(params)
            data.response_resp = resp
            QL.log_acquire_http_data(data)
        end
    end)
end

local function gangplank_get(cmd, params, cb, options)
    local url = url_tbl_v2[cmd]
    assert(url, "gangplank api: " .. cmd .. " not found")

    local query = HTTP.urlencode2(params)
    if query and query ~= '' then
        url = url .. "?" .. query
    end

    E.LOG.debug(TAG, 'gangplank get url: ' .. url)

    HTTP.get(url, require_params_get_options(options), function(resp)
        E.LOG.debug(TAG, "gangplank_get response >>")
        --E.log(resp)
        if resp.status == 200 then
            if resp.body == nil then
                cb(CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_GET_NULL_BODY, '')
            elseif resp.body.code == 0 then
                cb(200, resp.body)
            else
                cb(resp.body.code, resp.body)
            end
        else
            cb(resp.status, resp.body or {})
        end
    end)
end


local gangplank_post = gangplank_v2_post

function M.check_substitute(resp_body)
    if resp_body and resp_body.substitute and resp_body.substitute.uid then
        local s_title = '替身登录'
        local s_message = '当前为替身登录，替身账号ID:' .. tostring(resp_body.uid) .. '\n员工账号ID:' .. tostring(resp_body.substitute.uid)
        E.LOG.debug(TAG, s_message)
        if _ejoysdk.os() == 'windows' then
            local sdk_version = E.Sdkinfo.getSDKVersionName("EJOYSDK")
            local check_result = VC.compare_versions(sdk_version,'2.5.3.1')
            if _ejoysdk.utf8_to_acp and tonumber(check_result) >= 0 then -- 简易弹窗支持版本
                s_title = _ejoysdk.utf8_to_acp(s_title)
                s_message = _ejoysdk.utf8_to_acp(s_message)
                local s_option = {
                    message = s_message,
                    buttons = {'确认'},
                    type = 'simple'
                }
                E.Modal.open(s_title, s_option, function ()
                end)
            end
        elseif _ejoysdk.os() == 'ios' then
            local sdk_version = E.Sdkinfo.getSDKVersionName("EJOYSDK")
            local check_result = VC.compare_versions(sdk_version,'2.11.0')
            if tonumber(check_result) >= 0 then -- toast需要支持切换到主线程调用的版本
                E.Toast.show(s_message)
                E.Timer.once(2, E.Toast.hide)
            end
        else
            E.Toast.show(s_message)
            E.Timer.once(2, E.Toast.hide)
        end
    end
end

-- 检查灵犀渠道是否是游客
-- pinfo:{ext:{is_magic_guest:true}}
local function check_magic_guest(pinfo)
    local is_guest = false
    if pinfo and pinfo.ext then
        is_guest = pinfo.ext.is_magic_guest or false
    end

    if is_guest then
        E.LOG.debug(TAG, 'check_magic_guest true, lingxi account is guest')
    else
        E.LOG.debug(TAG, 'check_magic_guest false, lingxi account is not guest')
    end

    return is_guest
end

-- 接入文档里，该接口已废弃
local function login_base(server, region, outsource, token, cb)
    assert(type(server) == 'string' and server ~= '', 'server should be string')
    region = region or E.CONFIG.get_config('product')
    assert(type(region) == 'string', 'region should be string')
    assert(type(outsource) == 'table', 'outsource should be table')
    if outsource.platform then
        assert(type(outsource.ptoken) == 'string', 'platform set, outsource.ptoken should be string')
    end
    assert(type(token) == 'string' or token == nil, 'token should be string')
    assert(type(cb) == 'function', 'cb should be function')

    local secret = _ejoysdk_crypt.randomkey()

    local params = {
        secret = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.dhexchange(secret)),
        game = E.CONFIG.get_config('product'),
        server = server,
        region = region,
        token = token,
        platform = outsource.platform,
        ptoken = outsource.ptoken,
        pid = outsource.pid,
        guest = outsource.guest,
        with = outsource.with,
        with_account = outsource.with_account,
        ext = outsource.ext,
        appname = outsource.appname,
        pkg_info = E.get_pkg_info(),
        aegisExt = UIM.get_encrypt_aegis_info()
    }

    E.log(params)

    -- 这里用下发参数控制走不走加签防重放的流程
    -- 为了防止旧游戏还接的是这个接口，所以此处入口也加上标志位
    local opts = {}
    opts.enable_sign_headers_for_request = true
    opts.enable_sign_headers_for_response =  M.check_if_prevent_replay_status_open()

    gangplank_post('login', params, function(status, body)
        M.offline()

        E.LOG.debug(TAG,'ejoysdk log login result')
        E.log({
            status = status,
            body = body
        })

        if status == 200 or status == 413 or status == AGREEMENT.ERR_CODE_REJECT_FOR_AGREEMENT then
            -- 更新USER_INFO
            local uinfo = GDP.USER_INFO.new({
                game = params.game,
                server = params.server,
                region = params.region,
                token = body.token,
                platform = params.platform,
                ptoken = params.ptoken,
                ext = params.ext,
                guest = params.guest,
                uid = body.uid,
                pinfo = body.pinfo,
                pid = body.pinfo.pid,
                with = body.pinfo.with,
                with_account = body.pinfo.with_account
            })

            M.set_user_info(uinfo)

            -- 更新灵犀渠道账号是否游客的状态
            is_magic_guest = check_magic_guest(body.pinfo)
        end

        if status == 200 then
            local server_secret = _ejoysdk_crypt.base64decode(body.server_secret)
            local real_secret = _ejoysdk_crypt.dhsecret(server_secret, secret)
            cb(true, body.token, body.game_token, real_secret, body.pinfo)
        else
            local handled_callback = function(succ, ejoy_token)
                if succ then
                    E.LOG.debug(TAG, " handled success, user operation success, login again")
                    --login again
                    --outsource 需要传空，服务端该接口不支持ejoy_token和ptoken同时有值的情况
                    login_base(server, region, {}, ejoy_token, cb)
                else
                    M.offline()
                    E.LOG.error(TAG, " login_base failed, user declined for agreement!")
                    cb(false, status, body, secret)
                end
            end

            -- 宙斯盾风控拦截
            local aegis_handled = AEGIS.handle_login_reject_error(status, params.ptoken, body.challengeSuggest, function(aegis_succ, aegis_body)
                local aegis_token = nil
                if aegis_body and aegis_body.token then
                    aegis_token = aegis_body.token
                end
                handled_callback(aegis_succ, aegis_token)
            end)

            --用户协议相关处理逻辑
            local agreement_handled = AGREEMENT.handle_login_reject_error(status, body.token, function(agree_succ)
                handled_callback(agree_succ, GDP.USER_INFO.get('token'))
            end)

            --如果需要用户行为拦截，则等待用户处理返回结果
            if aegis_handled or agreement_handled then
                E.LOG.debug(TAG, " login_base failed and wait for user result!")
            else
                E.LOG.error(TAG, " login_base failed for other reason")
                cb(false, status, body, secret)
            end
        end
    end, opts)
end

-- @description acquire 请求
-- @params
-- region ：该字段已废弃
local function acquire_base(region, outsource, token, cb)
    region = region or E.CONFIG.get_config('product')
    assert(type(region) == 'string', 'region should be string')
    assert(type(outsource) == 'table', 'outsource should be table')
    if outsource.platform then
        assert(type(outsource.ptoken) == 'string', 'platform set, outsource.ptoken should be string')
    end
    assert(type(token) == 'string' or token == nil, 'token should be string')
    assert(type(cb) == 'function', 'cb should be function')

    local params = {
        game = E.CONFIG.get_config('product'),
        region = region,
        token = token,
        platform = outsource.platform,
        ptoken = outsource.ptoken,
        pid = outsource.pid,
        guest = outsource.guest,
        with = outsource.with,
        with_account = outsource.with_account,
        ext = outsource.ext,
        appname = outsource.appname,
        pkg_info = E.get_pkg_info(),
        aegisExt = UIM.get_encrypt_aegis_info()
    }

    E.log(params)

    -- acquire 调用技术打点
    QL.log_acquire_invoke(outsource.platform)

    -- 这里用下发参数控制走不走加签防重放的流程
    local opts = {}
    opts.enable_sign_headers_for_request = true
    opts.enable_sign_headers_for_response =  M.check_if_prevent_replay_status_open()

    gangplank_post('acquire', params, function(status, body)
        M.offline()

        E.LOG.debug(TAG, 'ejoysdk 打印 acquire_base 返回参数, response status:' .. status)
        E.log(body)

        if body and body.reg == true then
            -- 检测是否注册
            ET.publish(ET.analytics.REGISTER, { uid = body.uid or '' })
        end

        local acquire_response_handler = function(response_body)
            E.LOG.debug(TAG, "acquire_response_handler >>")
            E.log(response_body)

            -- 有登录态
            if response_body.token then
                E.LOG.debug(TAG, "有登录态返回，缓存登录信息")
                --缓存acquire的params
                acquire_token_params[response_body.token] = params

                --缓存USER_INFO
                local uinfo = GDP.USER_INFO.new({
                    game = params.game,
                    region = params.region,
                    platform = params.platform,
                    ptoken = params.ptoken,
                    ext = params.ext,
                    guest = params.guest,
                    token = response_body.token,
                    uid = response_body.uid,
                    pinfo = response_body.pinfo,
                    pid = response_body.pinfo.pid,
                    with = response_body.pinfo.with,
                    with_account = response_body.pinfo.with_account,
                    isPga = outsource.isPga,
                    substitute = response_body.substitute
                })

                M.set_user_info(uinfo)
            end

            -- 获取游客信息
            is_magic_guest = check_magic_guest(response_body.pinfo)

            -- 处理实名制信息
            REALNAME_INFO.handle_body_realname_info(response_body)

            -- 处理替身登录逻辑
            M.check_substitute(response_body)
        end

        -- 处理响应的body信息
        acquire_response_handler(body)

        -- 默认状态码处理
        local default_callback = function()
            if status == 200 then
                E.LOG.debug(TAG, " acquire_base success!")

                cb(true, body.token, body)
                -- acquire 成功
                QL.log_acquire(outsource.platform)

            else
                E.LOG.error(TAG, " acquire_base failed for other reason")
                M.offline()

                cb(false, status, body)
                -- acquire 失败统计
                QL.log_acquire_failed(outsource.platform, status, body.message)
            end
        end

        -- handler callback
        local handler_callback = function(succ)
            if succ then
                E.LOG.debug(TAG, 'receive handler result succ, need recall acquire ')
                acquire_base(region, outsource, body.token, cb)
            else
                E.LOG.error(TAG, " acquire_base failed, user not finished operation!")
                default_callback()
            end
        end

        -- 用户中心实名制&防沉迷拦截
        local is_intercept = false
        if body.pinfo then
            is_intercept = POPUP.handle_login_reject_error(status, body.token, body.pinfo.attach_info, function(result_status)
                -- 1、实名成功，通知发奖；或者实名成功，但触发防沉迷
                -- 2、实名制失败
                if result_status == REALNAME_INFO.REALNAME_RESULT.STATUS_UNCOMPLETE then
                    E.LOG.debug(TAG, 'receive popup handle result STATUS_NEED_LOGOUT')
                    M.logout()
                elseif result_status == REALNAME_INFO.REALNAME_RESULT.STATUS_COMPLETE_BIND_PHONE then
                    E.LOG.debug(TAG, 'receive popup handle result STATUS_COMPLETE_BIND_PHONE')
                    local v_aligames = require "ejoysdk_lua.vendors.aligames"
                    if v_aligames.is_for_lingxi() then
                        UNI.logout('ALIGAMES') -- 绑定手机成功，调用 native 的 logout
                    else
                        M.logout()
                    end
                else
                    local realname_succ = (result_status == REALNAME_INFO.REALNAME_RESULT.STATUS_COMPLETE_WITH_REALNAME_SUCC)
                    handler_callback(realname_succ)
                end
            end)
        end

        if not is_intercept then
            -- 宙斯盾风控拦截
            is_intercept = AEGIS.handle_login_reject_error(status, params.ptoken, body.challengeSuggest, function(succ, hbody)
                -- 宙斯盾有自己的登录结果，所以这里复写handler_callback
                if succ then
                    E.LOG.debug(TAG, " acquire_base success, user finished operation!")
                    acquire_response_handler(hbody)

                    cb(true, hbody.token, hbody)
                    -- acquire succ
                    QL.log_acquire(outsource.platform)
                else
                    E.LOG.error(TAG, " acquire_base failed, user not finished operation!")
                    M.offline()

                    cb(false, status, body)
                    -- acquire failed
                    QL.log_acquire_failed(outsource.platform, status, body.message)
                end
            end)
        end

        if not is_intercept then
            --用户协议相关处理逻辑
            is_intercept = AGREEMENT.handle_login_reject_error(status, body.token, function(succ)
                handler_callback(succ)
            end)
        end

        --如果用户协议处理，则等待用户协议返回处理
        if is_intercept then
            E.LOG.debug(TAG, " acquire_base failed and wait for user result!")
        else
            default_callback()
        end
    end, opts)
end

function M.request_gangplank_acquire(region, outsource, token, cb)
    E.LOG.debug(TAG, "request_gangplank_acquire begin")
    acquire_base(region, outsource, token, cb)
end

local function call_queue_listener(status, ...)
    if queue_listener then
        queue_listener(status, ...)
    end
end

local function get_interval(queue)
    E.LOG.debug(TAG, "get_interval with queue:" .. tostring(queue))
    if login_queue_rules_data and next(login_queue_rules_data) ~= nil then
        local find_interval
        for _, rule in ipairs(login_queue_rules_data) do
            local cnt = rule.cnt
            if queue >= cnt then
                find_interval = rule.interval
                break
            end
        end

        if find_interval then
            E.LOG.debug(TAG, "get_interval find interval in rules:" .. tostring(find_interval))
            return find_interval
        else
            E.LOG.warn(TAG, "get_interval not find in rules data, now use default")
        end
    end

    if queue > 50 then
        return 5
    elseif queue > 5 then
        return 3
    else
        return 1
    end
end

local function update_current_queue_ticket(id, ticket)
    local ticket_id = id or "0"
    CURRENT_QUEUE_LOOP = {
        [ticket_id] = ticket
    }

    E.LOG.debug(TAG, "update_current_queue_ticket:" .. tostring(id) .. ", ticket:" .. tostring(ticket))
end

local function get_queue_ticket(id)
    local ticket_id = id or "0"
    local ticket = nil
    if CURRENT_QUEUE_LOOP then
        ticket = CURRENT_QUEUE_LOOP[ticket_id]
    end

    E.LOG.debug(TAG, "get_queue_ticket:" .. tostring(ticket))
    return ticket
end

local function get_current_queue_ticket()
    if not CURRENT_QUEUE_LOOP then
        return nil
    end

    local current_ticket = nil
    local first_key = next(CURRENT_QUEUE_LOOP)
    if first_key then
        current_ticket = CURRENT_QUEUE_LOOP[first_key]
        E.LOG.debug(TAG, "get_current_queue_ticket:" .. tostring(current_ticket))
    end

    return current_ticket
end

local function clear_current_queue_ticket()
    E.LOG.debug(TAG, "clear_current_queue_ticket")
    CURRENT_QUEUE_LOOP = nil
end

local function queue_loop(ticket, queue, secret, cb, login_cb_id)
    E.LOG.debug(TAG, 'queue_loop login_cb_id:' .. (login_cb_id or 'nil'))

    local interval = get_interval(queue)
    --_ejoysdk.log("queue_loop interval:" .. tostring(interval))
    local timer_cb = function()
        if get_queue_ticket(login_cb_id) == nil then
            return
        end

        if login_cb_id and login_cb_id ~= LOGINID then
            E.LOG.debug(TAG, 'queue_loop 有新的login callback id, 当前循环需要退出, new:' .. LOGINID .. ", old:" .. login_cb_id)
            call_queue_listener('end')
            return
        end

        local params = {
            ticket = ticket,
        }
        gangplank_post('queue', params, function(status, body)
            if get_queue_ticket(login_cb_id) == nil then
                return
            end

            if login_cb_id and login_cb_id ~= LOGINID then
                E.LOG.debug(TAG, 'queue_loop 有新的login callback id, 当前循环需要退出')
                call_queue_listener('end')
                return
            end

            if status == 200 then
                clear_current_queue_ticket()

                local server_secret = _ejoysdk_crypt.base64decode(body.server_secret)
                local real_secret = _ejoysdk_crypt.dhsecret(server_secret, secret)
                cb(true, body.game_token, real_secret, GDP.USER_INFO.get('pid'))
                call_queue_listener('end')
                ET.publish(ET.gangplank.LOGIN, GDP.USER_INFO.get())
                ET.publish(ET.analytics.LOGIN, GDP.USER_INFO.get())
            elseif status == 413 then
                local new_queue_count = body.queue
                -- loop 场景透传服务端body给到游戏
                call_queue_listener('loop', new_queue_count, body)
                queue_loop(ticket, new_queue_count, secret, cb, login_cb_id)
            else
                clear_current_queue_ticket()

                call_queue_listener('end')
                cb(false, status, body.message or '')

                --排队失败，清空USER_INFO
                M.offline()
            end
        end)
    end
    E.Timer.once(interval, timer_cb)
end

local function on_vendor_login_fail(status, last_login_params)
    local outsource = last_login_params.outsource
    local guest = outsource == nil
    if guest then
        return false
    end
    local vendor_name = EV.get_vendor_name(outsource)
    if vendor_name then
        local vendor = EV.get(vendor_name)
        if vendor and vendor.login_fail and vendor.login_fail(status, last_login_params) then
            return true
        end
    end
    return false
end

local function login_callback_builder(server, region, outsource, info, cb)
    local guest = outsource == nil

    local update_token = function(token, pinfo)
        if guest then
            EJOY_TOKEN:set(token)
            info = pinfo
        else
            local vendor_name = EV.get_vendor_name(outsource)
            local vendor = EV.get(vendor_name)
            info = vendor.merge_info(info, pinfo)

            outsource.pid = info.pid
            VENDOR_LOGIN:set({
                server = server,
                region = region,
                token = token,
                outsource = outsource,
                info = info
            })
        end
        return info
    end

    return function(succ, token, game_token, secret, pinfo)
        if succ then
            local updated_info = update_token(token, pinfo)
            ET.publish(ET.gangplank.LOGIN, GDP.USER_INFO.get())
            ET.publish(ET.analytics.LOGIN, GDP.USER_INFO.get())
            cb(true, game_token, secret, updated_info.pid)
        else
            local status = token
            local body = game_token or {} -- 没有网络的时候为 nil

            E.LOG.error(TAG, "login failed " .. tostring(status))

            if status == 401 then
                if guest then
                    EJOY_TOKEN:delete()
                else
                    VENDOR_LOGIN:delete()
                end
            elseif status == 413 then
                -- 排队
                update_token(body.token, body.pinfo)
                local queue = body.queue
                call_queue_listener('start', queue)
                update_current_queue_ticket(nil, body.ticket)
                return queue_loop(body.ticket, queue, secret, cb)
            elseif status == 406 or status == 462 or status == 407 then
                LAST_VENDOR_AUTH:set('')
                VENDOR_LOGIN:delete()
            end
            local last_login_params = {
                outsource = outsource, info = info, update_token = update_token, direct_cb = cb, region = region, server = server, body = body
            }
            if on_vendor_login_fail(status, last_login_params) then
                return
            end
            cb(false, status, body.message or '', body)
        end
    end
end

local function check_acquire_listener_stat(cb)
    local stat_params = {}

    if not acquire_listener then
        E.LOG.warn(TAG, "check_acquire_listener_stat acquire_listener is nil")
        stat_params.acquire_listener_state = "false"
    else
        stat_params.acquire_listener_state = "true"
    end

    if not cb then
        E.LOG.warn(TAG, "check_acquire_listener_stat cb is nil")
        stat_params.cb_listener_state = "false"
    else
        stat_params.cb_listener_state = "true"
    end

    if game_listeners then
        stat_params.game_listeners_state = "true"
        if game_listeners.acquire_listener then
            stat_params.game_listeners_acquire_lis_state = "true"
        else
            stat_params.game_listeners_acquire_lis_state = "false"
        end
    end
    ESTAT.stat_action('acquirelistener_check', nil, true, stat_params)
end

local function acquire_callback_builder(region, outsource, info, cb)
    local guest = outsource == nil

    local update_token = function(token, pinfo)
        if guest then
            EJOY_TOKEN:set(token)
            info = pinfo
        else
            local vendor_name = EV.get_vendor_name(outsource)
            local vendor = EV.get(vendor_name)
            info = vendor.merge_info(info, pinfo)

            outsource.pid = info.pid
            VENDOR_LOGIN:set({
                region = region,
                token = token,
                outsource = outsource,
                info = info
            })
        end
        return info
    end

    return function(succ, ...)
        if succ then
            local token, body = ...
            local pinfo = body.pinfo

            update_token(token, pinfo)

            if cb then
                cb(true, token, body)
            end

            ET.publish(ET.gangplank.ACQUIRE, GDP.USER_INFO.get())

            -- cb stat
            check_acquire_listener_stat(cb)
        else
            local status, body = ...
            body = body or {}
            E.LOG.error(TAG,"acquire failed, status code: " .. tostring(status))

            if status == 401 then
                if guest then
                    EJOY_TOKEN:delete()
                else
                    VENDOR_LOGIN:delete()
                end
            elseif status == 406 or status == 462 or status == 407 then
                LAST_VENDOR_AUTH:set('')
                VENDOR_LOGIN:delete()
            end
            local last_login_params = {
                outsource = outsource, info = info, update_token = update_token, direct_cb = cb, region = region, body = body
            }
            if on_vendor_login_fail(status, last_login_params) then
                return
            end

            local err_msg = body.message or ''
            if cb then
                E.LOG.debug(TAG, "acquire callback, body.ds_code:" .. tostring(body.ds_code) .. ", status:" .. tostring(status) .. ", ds_server_code:" .. tostring(body.ds_server_code))
                cb(false, status, err_msg, body)
            end

            local fail_info = {
                code = status,
                msg = err_msg
            }
            ET.publish(ET.gangplank.ACQUIRE_FAILED, fail_info)
        end
    end
end


function M.logout(manual)
    -- logout时暂停PC的心跳，这里不用判断操作系统这些，其内部来处理
    local PC_HEARTBEAT = require 'ejoysdk_lua.realname.ejoysdk_realname_heartbeat'
    PC_HEARTBEAT.heartbeat_stop()

    local last_login = LAST_VENDOR_AUTH:get()
    E.LOG.debug(TAG, 'logout, last_login:' .. (last_login or 'nil'))
    OFFICIAL.reset_last_official_login()

    local USERCENTER = require 'ejoysdk_lua.user_center.ejoysdk_usercenter'
    USERCENTER.logout()
    if last_login then
        LAST_VENDOR_AUTH:set('')
        if last_login ~= 'guest' then
            local vendor = EV.get(last_login)
            if vendor then
                vendor.logout(manual)
                return
            end
        end
    end

    LOGIN_INFO:delete()
    M.offline()
    ET.publish(ET.gangplank.LOGOUT, GDP.USER_INFO.get())

    if not manual or type(manual) ~= 'boolean' or manual == false then
        logout_listener()
    end
end

function M.clear_user_info()
    GDP.USER_INFO.clear()
    GDP.PLAYER_INFO.clear()
end

function M.get_last_login()
    return LAST_VENDOR_AUTH:get() or ''
end

function M.set_last_login(vendor_name)
    LAST_VENDOR_AUTH:set(vendor_name)
end


--[
-- login 登录游戏
--
-- @param server 要登录的服务器, 名字与在平台监听（mq routing key）的名字相同
-- @param region 账号归属于哪个区域，gangplank 的一个帐号, 在一个 region 下是唯一,
-- 一个游戏建议只设置一个统一的 region, 不设置 region, region 会使用 server
-- @param vendor_name 要用来登录的第三方平台, nil 表示游客登录
--]
-- 接入文档已不推荐游戏使用该接口
function M.login(vendor_name, server, region)
    assert(login_listener, "register login listener first")
    assert(type(server) == 'string', 'server should be string')
    region = region or E.CONFIG.get_config('product')
    assert(type(region) == 'string', 'region should be string')

    --发送登录调用的通知
    ET.publish(ET.gangplank.LOGIN_INVOKE)
    QL.log_login_invoke()

    if vendor_name == 'auto' then
        local login_sdks = EV.get_native_vendors(EV.ABILITY.ACCOUNT)
        vendor_name = login_sdks[1]
    end

    if vendor_name == 'guest' then
        -- 纯游客登录
        local token = EJOY_TOKEN:get()
        -- 游客授权
        LAST_VENDOR_AUTH:set('guest')
        login_base(
                server, region, {}, token,
                login_callback_builder(server, region, nil, nil, login_listener)
        )
    else
        local vendor = EV.get(vendor_name)
        assert(vendor, 'vendor: ' .. tostring(vendor_name) .. 'not found')

        LOGIN_INFO:set({
            type = 'login',
            server = server,
            region = region,
            token = nil,
            vendor = vendor_name,
        })

        vendor.login()

        E.LOG.debug(TAG, "vendor login begin:" .. tostring(vendor_name))
        ET.publish(ET.gangplank.VENDOR_LOGIN_BEGIN, vendor_name)
    end
end

--覆盖后将不回调游戏acquire结果
local function get_acquire_token_listener(ext)
    if ext and ext.override_acquire_listener then
        return ext.override_acquire_listener
    else
        return acquire_listener
    end
end

-- @description 获取ejoy_token接口
-- @params ext 为一个table格式，里面的key定义如下：
-- > override_acquire_listener: Object类型，默认acquire_token结果会回调acquire_listener, 如果不想要回调此接口，可以设置override_acquire_listener
local function acquire_token_base(vendor_name, region, ext)
    --发送登录调用的通知
    ET.publish(ET.gangplank.LOGIN_INVOKE)

    --获取 acquire_token的回调，单独存储，不依赖生命周期更长的LOGIN_INFO
    token_callback_for_acquire = get_acquire_token_listener(ext)

    if vendor_name == 'guest' then
        local token = EJOY_TOKEN:get()
        -- 游客授权
        LAST_VENDOR_AUTH:set('guest')
        local acquire_callback = acquire_callback_builder(region, nil, nil, token_callback_for_acquire)
        acquire_base(region, {}, token, acquire_callback)
    else
        -- 如果是扫码包，直接走ejoy_scan vendor的登录
        if E.is_scan_pkg() then
            E.LOG.debug(TAG, "is a scan pkg, change to : EJOY_SCAN vendor" .. tostring(vendor_name))
            vendor_name = 'EJOY_SCAN'
        end

        local vendor_ret = CM.get_vendor(vendor_name, EV.ABILITY.ACCOUNT)
        vendor_name = vendor_ret.vendor_name
        local vendor = vendor_ret.vendor
        assert(vendor, 'vendor: ' .. tostring(vendor_name) .. 'not found')
        LOGIN_INFO:set({
            type = 'acquire',
            region = region,
            token = nil,
            vendor = vendor_name
        })

        -- 登录 vendor
        CM.login(vendor_name, ext)

        E.LOG.debug(TAG, "vendor login begin:" .. tostring(vendor_name))
        ET.publish(ET.gangplank.VENDOR_LOGIN_BEGIN, vendor_name)

        -- acquire invoke
        QL.log_vendor_login_invoke(vendor_name)
    end
end

-- 全球同服功能已没有人使用，先注释掉
--local function global_acquire_with_local_token(local_ejoy_token, target_region, ext)
--    -- get global token
--    local url_base = E.CONFIG.get_config(E.CONFIG.KEY.LOCAL_GANGPLANK_URL_BASE)
--    local get_global_token_url = gangplank_logined_url_base('/get_global_token', '2', url_base)
--
--    local acquire_token_listener = get_acquire_token_listener(ext)
--
--    local post_params = {}
--    post_params.region = target_region
--    post_params.pkg_info = E.get_pkg_info()
--    E.LOG.debug(TAG, 'global_acquire_with_local_token> begin, url:' .. get_global_token_url)
--    E.log(post_params)
--
--    HTTP.post(get_global_token_url, require_params(local_ejoy_token), HTTP.CT_JSON, post_params, function(resp)
--        local respstatus = resp.status
--        local respbody = resp.body
--        E.LOG.debug(TAG, 'global_acquire_with_local_token> response>')
--        E.log({
--            status = respstatus,
--            body = respbody
--        })
--        if respstatus == 200 then
--            if respbody.code == 0 then
--                local params = {
--                    global_token = respbody.global_token,
--                    pkg_info = E.get_pkg_info()
--                }
--
--                local acquire_params = acquire_token_params[local_ejoy_token]
--                if acquire_params then
--                    params.game = acquire_params.game
--                    params.region = acquire_params.region
--                    params.platform = acquire_params.platform
--                    params.ptoken = acquire_params.ptoken
--                    params.ext = acquire_params.ext
--                    params.guest = acquire_params.guest
--                end
--
--                E.LOG.debug(TAG, 'global_acquire_with_local_token> request global_acquire')
--                gangplank_post('global_acquire', params, function(status, body)
--                    M.offline()
--                    E.LOG.debug(TAG, 'global_acquire_with_local_token>global_acquire response>')
--                    E.log({
--                        status = status,
--                        body = body
--                    })
--
--                    local global_center_login_info = VENDOR_LOGIN:get()
--                    local outsource = {}
--                    local info = nil
--                    if global_center_login_info then
--                        E.LOG.debug(TAG, 'find global_center_login_info!')
--                        outsource = global_center_login_info.outsource
--                        info = global_center_login_info.info
--                    else
--                        E.LOG.error(TAG, 'VENDOR_LOGIN is empty, this should never happen!')
--                    end
--
--                    local acquire_token_listener_wrapper = acquire_callback_builder(target_region, outsource, info, acquire_token_listener)
--
--                    if status == 200 or status == 413 or status == AGREEMENT.ERR_CODE_REJECT_FOR_AGREEMENT then
--                        acquire_token_params[body.token] = params
--
--                        USER_INFO = new_user_info({
--                            game = params.game,
--                            region = params.region,
--                            token = body.token,
--                            platform = params.platform,
--                            ptoken = params.ptoken,
--                            ext = params.ext,
--                            guest = params.guest,
--                            uid = body.uid,
--                            pinfo = body.pinfo,
--                            pid = body.pinfo.pid,
--                            with = body.pinfo.with,
--                            with_account = body.pinfo.with_account
--                        })
--
--                        --清除 global token cache
--                        global_region_token_cache = {}
--
--                        ET.publish(ET.gangplank.USER_INFO_CHANGED, USER_INFO)
--                    end
--
--                    if status == 200 then
--                        acquire_token_listener_wrapper(true, body.token, body.pinfo, body.reg)
--                    else
--                        --用户协议相关处理逻辑
--                        local agreement_handled = AGREEMENT.handle_login_reject_error(status, body.token, function(succ)
--                            if succ then
--                                E.LOG.debug(TAG, " global_acquire success, user accept for agreement!")
--                                acquire_token_listener_wrapper(true, body.token, body.pinfo, body.reg)
--                            else
--                                E.LOG.error(TAG, " global_acquire failed, user declined for agreement!")
--                                acquire_token_listener_wrapper(false, status, body)
--
--                                --登录失败，用户下线，需要重新登录
--                                M.offline()
--                            end
--                        end)
--
--                        --如果用户协议处理，则等待用户协议返回处理
--                        if agreement_handled then
--                            E.LOG.debug(TAG, 'global_acquire failed and wait for user agreement result!')
--                        else
--                            E.LOG.error(TAG, " global_acquire failed for other reason")
--                            acquire_token_listener_wrapper(false, status, body)
--                        end
--                    end
--                end)
--            else
--                acquire_token_listener(false, respbody.code, respbody.message)
--            end
--        else
--            acquire_token_listener(false, respstatus, 'request url:' .. get_global_token_url .. " failed")
--        end
--    end)
--end

-- @description: acquire 接口分发。详细如下：
-- login_global_center 为全球同服的第一步，会调用acquire_token_global。然后第二步会调用acquire_token 走之前的接口协议逻辑，正确获取角色地区的ejoy_token。
-- 这两步都会调用到acquire_token_global方法，不同的是他们的地区可能不同
-- 1. 如果未开启全球同服开关，则走默认的acquire_token_base逻辑
-- 2. 如果开启了全球同服开关，第一步acquire(没有缓存)，则直接走acquire_token_base，获得本地地区的ejoy_token，我们这里缓存，给第二步acquire_token 获取
-- 3. 如果开启了全球同服开关，第二步acquire(有第一步的缓存)，此时判断如果第二步登录的地区信息和第一步一致，则返回第一步的token缓存；如果地区不一致，则获取第一步的token缓存去global_acquire获得第二步地区的ejoy_token
-- 4. 如果开启了全球同服开关, 第二步acquire(无第一步的缓存)，代表游戏跳过了第一步直接走第二步（游戏需要保证此前在本地地区gangplank已经创建了账号，否则直接登录可能会在其它地区会重新创建角色），那么用此时的region走默认的acquire_token_base逻辑
function M._acquire_token_global(vendor_name, region, ext)
    region = region or E.CONFIG.get_config('product') -- 现在基本不用region字段了，默认赋值product
    assert(type(region) == 'string', 'region or product should be string')
    local acquire_token_listener = get_acquire_token_listener(ext)
    if not inited then
        E.LOG.error(TAG, "acquire failed, not init")
        acquire_token_listener(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_NOT_INIT, "not init")
        return
    end

    local global_gangplank_enabled = E.CONFIG.get_config('global_gangplank_enabled')
    if not global_gangplank_enabled then
        E.LOG.debug(TAG, "acquire_token_global > global gangplank not enabled, directly request gangplank")
        acquire_token_base(vendor_name, region, ext)
    else
        -- 尝试从 global center 缓存读取
        E.LOG.debug(TAG, "acquire_token_global > now try get from cache")
        region = E.CONFIG.get_config(E.CONFIG.KEY.REGION)
        assert(region, 'region should not be nil in global gangplank')


        local return_cached_token = function(ejoy_token)
            acquire_token_listener(true, ejoy_token)
            -- remove global region token cache
            global_region_token_cache = {}
        end

        local region_token_cache = global_region_token_cache[region]
        if region_token_cache then
            E.LOG.debug(TAG, "acquire_token_global > return ejoy_token from cache")
            return_cached_token(region_token_cache)
        else
            E.LOG.debug(TAG, "acquire_token_global > no token cache for region, try process from local region cache")
            local local_region = E.CONFIG.get_config(E.CONFIG.KEY.LOCAL_GANGPLANK_REGION)
            if local_region then
                E.LOG.debug(TAG, "acquire_token_global > try get local region token cache")
                local local_region_token_cache = global_region_token_cache[local_region]
                if local_region_token_cache then
                    E.LOG.debug(TAG, "acquire_token_global > exists local region cache, do global_acquire")
                    -- global_acquire
                    -- 该函数执行不到了，先注释
                    --global_acquire_with_local_token(local_region_token_cache, region, ext)
                else
                    E.LOG.debug(TAG, "acquire_token_global > no token cache for local region, do acquire_token_base")
                    acquire_token_base(vendor_name, region, ext)
                end
            else
                E.LOG.debug(TAG, "acquire_token_global > unknown local region, do acquire_token_base")
                acquire_token_base(vendor_name, region, ext)
            end
        end
    end
end

function M.acquire_token(vendor_name, region)
    M._acquire_token_global(vendor_name, region, nil)
end

function M.open_user_center(vendor_name)
    -- 判断是否已经登录，没登录不允许打开
    local USERCENTER = require 'ejoysdk_lua.user_center.ejoysdk_usercenter'
    local usercenter_userinfo = USERCENTER.user_info()
    local user_info = M.user_info()
    if (user_info and user_info.token and string.len(user_info.token) > 0) or -- 国内需要校验这个
            (usercenter_userinfo and usercenter_userinfo.token and string.len(usercenter_userinfo.token) > 0) then -- 用户中心已经登录了也能打开
        local vendor_ret = CM.get_vendor(vendor_name, EV.ABILITY.ACCOUNT)
        CM.open_user_center(vendor_ret.vendor_name)
    else
        E.LOG.error(TAG, "open user_center fail, not login yet")
    end
end

function M.open_userinfo_completion(vendor_name, cb)
    -- 判断是否已经登录，没登录不允许打开
    local user_info = M.user_info()
    if user_info and user_info.token and string.len(user_info.token) > 0 then
        local vendor_ret = CM.get_vendor(vendor_name, EV.ABILITY.ACCOUNT)
        CM.open_userinfo_completion(vendor_ret.vendor_name, cb)
    else
        E.LOG.error(TAG, "open userinfo completion page fail, not login yet")
    end
end

local function do_login_with_token(server, token, cbid, login_opts)
    E.LOG.debug(TAG, 'do_login_with_token cbid:' .. (cbid or 'nil') .. ', server:' .. (server or 'nil'))
    assert(type(server) == 'string' and server ~= '', 'server should be string')
    assert(type(token) == 'string' or token == nil, 'token should be string')
    QL.log_login_invoke()

    local secret = _ejoysdk_crypt.randomkey()
    local params = {
        secret = _ejoysdk_crypt.base64encode(_ejoysdk_crypt.dhexchange(secret)),
        game = E.CONFIG.get_config('product'),
        server = server,
        token = token,
        pkg_info = E.get_pkg_info()
    }

    local acquire_params = acquire_token_params[token]
    if acquire_params then
        params.platform = acquire_params.platform
        params.with = acquire_params.with
    end

    E.LOG.debug(TAG, 'do_login_with_token params:>>')
    E.log(params)

    local login_api_name = 'login'
    if login_opts and login_opts.login_api then
        login_api_name = login_opts.login_api
        E.LOG.debug(TAG, 'login_with_token api:' .. tostring(login_api_name))
    end

    -- 这里用下发参数控制走不走加签防重放的流程
    local opts = {}
    opts.enable_sign_headers_for_request = true
    opts.enable_sign_headers_for_response =  M.check_if_prevent_replay_status_open()

    gangplank_post(login_api_name, params, function(status, body)
        E.LOG.debug(TAG, 'current cbid:' .. (cbid or 'nil') .. ', loginId:' .. LOGINID)
        if cbid ~= LOGINID then
            E.LOG.debug(TAG, '已有最新的请求调用，该请求不处理，当前callback_id:' .. (cbid or 'nil') .. ', 最新callback_id:' .. (LOGINID or 'nil'))
            return
        end

        E.LOG.debug(TAG, 'ejoysdk 打印 login_with_token 返回参数')
        E.log(body)

        local handled_callback = function(succ)
            if succ then
                E.LOG.debug(TAG, " login_with_token success,  login again")
                --login again
                do_login_with_token(server, token, cbid, login_opts)
            else
                E.LOG.error(TAG, " login_with_token failed")
                VENDOR_LOGIN:delete()
                login_listener(false, status, body.message or '', body)
            end
        end

        if status == 200 then
            E.LOG.debug(TAG, 'do_login_with_token 成功！')
            GDP.USER_INFO.update(GDP.USER_UPDATE_TYPE.LOGIN, server, body)

            -- 以下字段并没有项目在使用
            local server_secret = _ejoysdk_crypt.base64decode(body.server_secret)
            local real_secret = _ejoysdk_crypt.dhsecret(server_secret, secret) -- 这是个二进制，跨lua传递时注意

            ET.publish(ET.gangplank.LOGIN, GDP.USER_INFO.get())
            ET.publish(ET.analytics.LOGIN, GDP.USER_INFO.get())
            login_listener(true, body.game_token, real_secret, body.pinfo.pid)
        elseif status == 413 then
            -- 排队
            E.LOG.debug(TAG, 'do_login_with_token 排队！')
            GDP.USER_INFO.update(GDP.USER_UPDATE_TYPE.LOGIN, server, body)

            local queue = body.queue
            call_queue_listener('start', queue)
            update_current_queue_ticket(cbid, body.ticket)

            return queue_loop(body.ticket, queue, secret, login_listener, cbid)
        elseif status == 10421 then
            -- 激活码
            E.LOG.debug(TAG, 'do_login_with_token activat-code required')
            local popup_info = {
                ejoy_token = GDP.USER_INFO.get('token'),
                config_url = body.active_code_url,
                server_id = server
            }

            ACPOPUP.handle_login_interrupt_info(status, popup_info, function(code, msg)
                handled_callback(code == ACPOPUP.ACTIVE_STATUS.ACTIVED)
            end)

        else
            -- 这里不需要拦截宙斯盾风控，因为acquire_token已经处理完成

            -- 用户协议相关处理逻辑
            local agreement_handled = AGREEMENT.handle_login_reject_error(status, body.token, handled_callback)

            --如果用户协议处理，则等待用户协议返回处理
            if agreement_handled then
                E.LOG.debug(TAG, " login_with_token failed and wait for user agreement result!")
            else
                E.LOG.error(TAG, "login_with_token failed for other reason")
                VENDOR_LOGIN:delete()
                login_listener(false, status, body.message or '', body)
            end
        end
    end, opts)
end

function M.login_with_token(server, token)
    local cbid = gen_login_id()
    E.LOG.debug(TAG, '收到新的请求调用，callback_id:' .. cbid)
    do_login_with_token(server, token, cbid)
end

function M.scene_login_with_token(server, token)
    local cbid = gen_login_id()
    E.LOG.debug(TAG, 'scene_login_with_token: 收到新的请求调用，callback_id:' .. tostring(cbid))
    local opts = { login_api = 'scene_login' }
    do_login_with_token(server, token, cbid, opts)
end

--[[
设置排队的等待规则
@param rules, table, k-v结构。
 k 为number类型，代表大于这个排队数；v为number类型，代表等待间隔时间，单位为秒
 示例：
 local rules = {
        [50] = 5,
        [30] = 3,
        [5] = 2
        [1] = 1
    }
 代表 >= 50时等待时间为5秒; >= 30 且 < 50 等待3秒; >=5 且 < 30 等待2秒; >= 1 且 < 5 等待为1秒
--]]
function M.set_queue_interval_rules(rules)
    if not rules then
        E.LOG.warn(TAG, "set_queque_interval_rules skip, rules is nil")
        return
    end

    local rules_data = {}
    for cnt, interval in pairs(rules) do
        local data = {}
        data.cnt = cnt
        data.interval = interval
        table.insert(rules_data, data)
    end

    table.sort(rules_data, function(data1, data2)
        return data1.cnt > data2.cnt
    end)

    E.LOG.debug(TAG, "set_queue_interval_rules >")
    E.log(rules_data)
    login_queue_rules_data = rules_data
end

local has_set_player_info = false -- 确保每次登录，sdk 内部只 publish 一次 player_info

local function login_handler()
    has_set_player_info = false
end

local function logout_hanlder()
    has_set_player_info = false
    GDP.PLAYER_INFO.clear()
end

local function get_player_token_succ_handler(moment_token)
    if set_player_info_cb then
        set_player_info_cb(true, {type=M.SET_PLAYER_INFO_CALLBACK_EVENT.GET_PLAYER_TOKEN_SUCC})
    end

    GDP.PLAYER_INFO.update(GDP.PLAYER_UPDATE_TYPE.MOMENT_TOKEN, moment_token)
end

local function get_player_token_fail_handler(ret)
    local code = ret.code
    local msg = ret.msg
    if set_player_info_cb then
        set_player_info_cb(false, {type=M.SET_PLAYER_INFO_CALLBACK_EVENT.GET_PLAYER_TOKEN_FAIL, code=code, msg=msg})
    end
end

local function pc_heartbeat_check(type)

    if 'enterGame' == type then
        local PC_HEARTBEAT = require 'ejoysdk_lua.realname.ejoysdk_realname_heartbeat'
        PC_HEARTBEAT.heartbeat_start()
    elseif 'exitGame' == type then
        local PC_HEARTBEAT = require 'ejoysdk_lua.realname.ejoysdk_realname_heartbeat'
        PC_HEARTBEAT.heartbeat_stop()
    end
end

M.SET_PLAYER_INFO_CALLBACK_EVENT = {
    GET_PLAYER_TOKEN_SUCC = 'GET_PLAYER_TOKEN_SUCC',
    GET_PLAYER_TOKEN_FAIL = 'GET_PLAYER_TOKEN_FAIL'
}

-- 选择角色，进入游戏时，必须调用
function M.set_player_info(player_info, player_info_type, cb)
    assert(player_info, 'player_info can not be nil')
    assert(player_info.server_id, 'server_id can not be nil')
    assert(type(player_info.server_id) == 'string', 'server_id should be string')
    assert(player_info.player_id, 'player_id can not be nil')
    assert(player_info.player_name, 'player_name can not be nil')

    player_info.player_id = tostring(player_info.player_id) -- 避免游戏传入数值id

    set_player_info_cb = cb

    local current_player_id = GDP.PLAYER_INFO.get('player_id')
    -- update player_info
    GDP.PLAYER_INFO.set(player_info)

    -- 1.有新的player_id到来时，发布消息
    -- 2.SET_PLAYER_INFO 事件是 lua sdk 内部使用，关注点在有新的角色信息发布，发布一次即可
    local clone_player_info = GDP.PLAYER_INFO.clone()
    if not has_set_player_info or player_info.player_id ~= current_player_id then
        E.LOG.debug(TAG, "set_player_info player change, cur:" .. tostring(current_player_id) .. ", new:" .. tostring(player_info.player_id))
        ET.publish(ET.gangplank.SET_PLAYER_INFO, clone_player_info)
        has_set_player_info = true
    end

    local stat_params = {
        new_player_id = player_info.player_id,
        old_player_id = current_player_id
    }
    ESTAT.stat_action("ejoy_set_player_info_invoke", player_info_type, nil, stat_params)

    if player_info_type then
        E.LOG.debug(TAG, "set_player_info with type, player_info_type:" .. tostring(player_info_type))
        ET.publish(ET.gangplank.SET_PLAYER_INFO_WITH_TYPE, clone_player_info, player_info_type) -- 渠道需要的 player_info，才有 TYPE
        pc_heartbeat_check(player_info_type) -- 后续考虑抽出去放到一个Windows的lua文件里
    end

end

-- 登出角色时，必须调用
function M.player_offline()
    has_set_player_info = false
    GDP.PLAYER_INFO.clear()

    ET.publish(ET.holo.CLEAR_PLAYER_TOKEN) -- 先让Holo那边把token清除，用通知的方式避免gangplank和holo有耦合

    ET.publish(ET.gangplank.PLAYER_OFFLINE)  -- 再通知各个模块，角色已登出
end

function M.cancel_queue()
    local current_ticket = get_current_queue_ticket()
    if current_ticket then
        local params = {
            ticket = current_ticket,
        }
        gangplank_post('queue_dropout', params, function()
        end)
        call_queue_listener('end')
        clear_current_queue_ticket()
    end
end

-- gagnplank的bind接口是历史业务，现在绑定第三方渠道已经转移到小宁哥这边的账号服务了，gagnplank不再做这类业务，该类接口已过期
local function bind_base(token, outsource, force, cb)
    local _server = GDP.USER_INFO.get('server')
    local _region = GDP.USER_INFO.get('region')
    local params = {
        token = token, -- 选择绑定的平台token
        game = E.CONFIG.get_config('product'),
        server = _server,
        region = _region,
        platform = outsource.platform,
        ptoken = outsource.ptoken,
        pid = outsource.pid,
        ext = outsource.ext,
        force = force,
        with = outsource.with,
        with_account = outsource.with_account,
        appname = outsource.appname,

    }

    gangplank_post('bind', params, function(status, body)
        E.LOG.debug(TAG,'ejoysdk log bind result')
        E.log({
            body = body,
            status = status
        })
        if status == 200 then
            cb.success(body)
        elseif status == 403 then
            cb.conflict(body.conflict)
        else
            cb.error(status)
        end
    end)
end

local function bind_callback_builder(outsource, info)
    local platform = GDP.USER_INFO.get('platform')
    local guest = platform == nil

    local token
    if guest then
        token = EJOY_TOKEN:get()
    else
        token = VENDOR_LOGIN:get().token
    end

    local cb = {
        success = function(body)
            if guest then
                EJOY_TOKEN:delete()
            end

            local _region = GDP.USER_INFO.get('region')
            VENDOR_LOGIN:set({
                region = _region,
                token = body.token,
                outsource = outsource,
                info = info
            })
            bind_listener("succ", body.token)
        end,
        error = function(status)
            if status == 401 then
                if guest then
                    EJOY_TOKEN:delete()
                else
                    VENDOR_LOGIN:delete()
                end
            end
            local last_login_params = {
                outsource = outsource, info = info
            }
            if on_vendor_login_fail(status, last_login_params) then
                return
            end
            bind_listener("error", status)
        end,
        conflict = function(conflict)
            local continure_bind = function(selected_token)
                if selected_token == token then
                    bind_base(
                            token, outsource, true,
                            bind_callback_builder(outsource, info))
                end
            end
            bind_listener("conflict", conflict, continure_bind)
        end
    }
    return cb
end

local function bind(vendor_name)
    local vendor = EV.get(vendor_name)
    assert(vendor, 'vendor: ' .. tostring(vendor_name) .. 'not found')

    local _token = GDP.USER_INFO.get('token')
    LOGIN_INFO:set({
        type = 'bind',
        token = _token,
        vendor = vendor_name,
    })

    vendor.login()
end

-- 该接口跟bind接口一样是历史业务，现在已不再使用
local function query(server, region, outsource, cb)
    assert(type(server) == 'string' and server ~= '', 'server should be string')
    assert(type(region) == 'string' or region == nil, 'region should be string or nil')
    assert(type(outsource.platform) == 'string', 'outsource.platform should be string')
    assert(type(outsource.ptoken) == 'string', 'outsource.ptoken should be string')
    assert(type(outsource.pid) == 'string' or outsource.pid == nil, 'outsource.pid should be string or nil')

    assert(type(cb.success) == 'function', 'cb.success should be function')
    assert(type(cb.error) == 'function', 'cb.error should be function')

    local params = {
        game = E.CONFIG.get_config('product'),
        server = server,
        region = region,
        platform = outsource.platform,
        ptoken = outsource.ptoken,
        pid = outsource.pid,
        ext = outsource.ext,
    }

    gangplank_post('query', params, function(status, body)
        if status == 200 then
            cb.success(body.tokens)
        else
            cb.error(status)
        end
    end)
end

ET.subscribe("app_on_stop", function()
    if LOGIN_INFO:get() then
        LOGIN_INFO:save()
    end
end)

local function create_order_base(type_, amount, channel, outsource, cb, override)
    assert(type(type_) == 'string' and type_ ~= '', 'type should be string')
    assert(type(amount) == 'number' and amount > 0, 'amount should be number and larger then 0')
    assert(type(cb) == 'function', 'cb should be function')
    local _token = GDP.USER_INFO.get('token')
    assert(_token, "need login")

    local user_server_id = GDP.USER_INFO.get('server')
    local player_server_id = GDP.PLAYER_INFO.get('server_id')
    local current_server_id = user_server_id
    if player_server_id then
        E.LOG.debug(TAG, '已经设置了player_info，server_id:' .. player_server_id)
        if current_server_id ~= player_server_id then
            E.LOG.debug(TAG, '[warning]当前登录的角色和进入游戏的角色不一致，登录角色区服ID:' .. tostring(user_server_id) .. ', 进入游戏角色区服ID：' .. tostring(player_server_id))
            current_server_id = player_server_id
        end
    else
        E.LOG.debug(TAG, '没有设置player_info，使用 user_info 的 server_id:' .. tostring(user_server_id))
    end

    --server_id 不同时的技术打点
    local ql_params
    if user_server_id ~= player_server_id then
        local login_server_id_str = user_server_id or 'nil'
        local player_server_id_str = player_server_id or 'nil'
        ql_params = {
            login_server_id = login_server_id_str,
            player_server_id = player_server_id_str
        }

        E.LOG.debug(TAG, 'server_id inconsistent, login_server_id:' .. login_server_id_str .. ', player_server_id:' .. player_server_id_str)
    end
    QL.commit_event(QL.EVENT_NAMES.SDK_PAY_CREATE_ORDER_INVOKE, ql_params, true)

    local _player_info = GDP.PLAYER_INFO.get()
    local params = {
        ["type"] = type_,
        amount = amount,
        platform = outsource.platform,
        ptoken = outsource.ptoken,
        pid = outsource.pid,
        with = outsource.with,
        with_account = outsource.with_account,
        ext = outsource.ext,
        channel = channel,
        game = E.CONFIG.get_config('product'),
        server = current_server_id,
        token = _token,
        pkg_info = E.get_pkg_info(),
        player_info = _player_info,
        money_type = outsource.money_type
    }

    E.LOG.debug(TAG, "create_order_base params >>")
    E.log(params)
    E.log(override)

    if override then
        for k, v in pairs(override) do
            if (type(v) ~= 'function') then
                params[k] = v
            end
        end
    end

    gangplank_post('create_order', params, function(status, body)
        if status == 200 then
            cb(true, body.order_id, body)
        else
            E.log(body)
            cb(false, body.code, body.message)
        end
    end)
end

local function check_realname_before_pay(cb)
    -- 是否是国内独代渠道
    local v_aligames = require "ejoysdk_lua.vendors.aligames"
    -- 注意：
    -- 1. 国内灵犀渠道才需要支持lua的方式在支付前检查实名制
    -- 2. 由于android灵犀渠道的支付SDK已经支持支付前实名，所以为了不冲突，这里只需处理IOS的场景
    if v_aligames.is_for_lingxi() and E.Sysinfo.os() == 'ios' then
        E.LOG.debug(TAG, 'its lingxi channel and is ios system, so need check realname before pay')
        -- check switch from server
        local realname_enabled = false
        local pinfo = GDP.USER_INFO.get('pinfo', {})
        local attach_info = pinfo.attach_info
        if attach_info and attach_info.payRealNameSwitch then
            realname_enabled = true
        end

        if not realname_enabled then
            E.LOG.debug(TAG, 'aligames realname not enabled cb success')
            cb(true)
            return
        end

        local function check_realname_callback(status)
            E.LOG.debug(TAG, 'check_callback, status:' .. status)
            -- 实名制成功可以支付
            if status == REALNAME_INFO.REALNAME_RESULT.STATUS_COMPLETE_WITH_REALNAME_SUCC then
                E.LOG.debug(TAG, 'check before create order complete, realname success, and do create order now!')
                cb(true)
            else
                E.LOG.warn(TAG, 'check before create order uncomplete, and could not do create order')
                cb(false, { code = -10003, msg = '支付前实名失败', platform = 'ALIGAMES' })
            end
        end

        local function check_bind_callback(status)
            E.LOG.debug(TAG, 'check_bind_callback, status:' .. status)
            -- 绑定手机成功需要登出
            if status == REALNAME_INFO.REALNAME_RESULT.STATUS_COMPLETE_BIND_PHONE then
                E.LOG.warn(TAG, 'check bind before create order , bind succ, and need logout!')
                UNI.logout('ALIGAMES')
                cb(false, { code = -10004, msg = '支付前绑定手机成功', platform = 'ALIGAMES' })
            else
                E.LOG.warn(TAG, 'check bind before create order uncomplete, and could not do create order')
                cb(false, { code = -10005, msg = '支付前绑定手机失败', platform = 'ALIGAMES' })
            end
        end

        local realname_status = REALNAME_INFO.get_realname_status()
        -- check if guest then bind & realname
        if is_magic_guest then
            E.LOG.debug(TAG, '支付前是游客状态，拉起绑定手机')
            -- show bind and process bind callback then logout
            POPUP.handle_realname_pages(POPUP.REALNAME_PAGE_TYPE.BIND_URL, POPUP.SCENE_TYPE.SCENE_BEFORE_CREATE_ORDER, true, check_bind_callback)
        else
            if realname_status ~= REALNAME_INFO.REALNAME_STATUS.SUCCESS then
                E.LOG.debug(TAG, '支付前未实名，拉起实名认证')
                -- realname
                POPUP.handle_realname_pages(POPUP.REALNAME_PAGE_TYPE.REALNAME_URL, POPUP.SCENE_TYPE.SCENE_BEFORE_CREATE_ORDER, true, check_realname_callback)
            else
                E.LOG.debug(TAG, '支付前已实名，可以继续下单操作')
                cb(true)
            end
        end
    else
        E.LOG.debug(TAG, 'not aligames vendor lingxi channel, and not ios system, so could create order')
        cb(true)
    end
end

local function pay_base(vendor_name, product_id, count, override)
    local vendor_ret = CM.get_vendor(vendor_name, EV.ABILITY.PAY)
    vendor_name = vendor_ret.vendor_name
    local vendor = vendor_ret.vendor

    if vendor == nil then
        ET.publish('purchased', false, ER.order.CANT_PURCHASE)
        ET.publish(ET.gangplank.PAY_FAILED, { can_pay = false, })
        pay_listener(false, '', CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_PAY_NOT_SUPPORT, 'not support', {})
        return
    end

    if not vendor.can_pay() then
        ET.publish('purchased', false, ER.order.CANT_PURCHASE)
        ET.publish(ET.gangplank.PAY_FAILED, { can_pay = false, })
        pay_listener(false, '', CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_CAN_NOT_PAY, 'can not pay', {})
        return
    end

    --assert(vendor.product_list()[product_id], "product " .. product_id .. " not found")
    local product_info = vendor.product_list()[product_id]

    if not product_info then
        pay_listener(false, '', -1, "product " .. product_id .. " not found")
        return
    end

    local _platform = GDP.USER_INFO.get('platform')
    local _ptoken = GDP.USER_INFO.get('ptoken')
    local _pid = GDP.USER_INFO.get('pid')
    local _with = GDP.USER_INFO.get('with')
    local _with_account = GDP.USER_INFO.get('with_account')
    local _ext = GDP.USER_INFO.get('ext')
    local outsource = {
        platform = _platform,
        ptoken = _ptoken,
        pid = _pid,
        with = _with,
        with_account = _with_account,
        ext = _ext,
        money_type = product_info.money_type
    }

    local pay_channel = vendor_name
    if vendor and vendor.vendor_channel then
        pay_channel = vendor.vendor_channel()
    end

    -- 这里补充一下注释：
    -- 国内传的vendor_name是ALIGAMES，user_info.with是ALIGAMES，platform是998233，所以得到的vendor_name是nil，对应到下单时的channel是nil，这样下单会成功
    -- 国外传的vendor_name是OFFICIAL_PAY, user_info.with是OFFICIAL, platform是具体的登录方式（例如：AIRELINE）, 此时vendor_name这里的逻辑判断后是OFFICIAL_PAY，在最后下单时的channel为OFFICIAL
    --local channel_target = USER_INFO.with or USER_INFO.platform
    --if vendor_name == channel_target then
    --    vendor_name = nil
    --end
    if pay_channel == "ALIGAMES" then
        pay_channel = nil
    end

    E.LOG.debug(TAG,'before create_order_base, pay_channel:' .. tostring(pay_channel))
    if vendor and vendor.skip_gp_order and vendor.skip_gp_order() then
        vendor.pay(product_id, count, '', {}, override)
    else
        create_order_base(product_id, count, pay_channel, outsource, function(succ, ...)
            if succ then
                local order_id, body = ...
                E.LOG.debug(TAG,'before create_order_base success ' .. tostring(order_id))
                pending_product_infos.order_id = product_info
                ET.publish(ET.analytics.CREATE_ORDER, order_id, product_info)
                vendor.pay(product_id, count, order_id, body, override)
            else
                E.LOG.error(TAG,'before create_order_base failure')
                local code, msg = ...
                local param = {
                    can_pay = true,
                    code = code,
                    msg = msg,
                }
                ET.publish(ET.gangplank.PAY_FAILED, param)
                pay_listener(false, '', code, msg, {})
            end
        end, override)
    end
end

function M.pay(vendor_name, product_id, count, override)
    assert(pay_listener, "register pay listener first")
    ET.publish(ET.gangplank.PAY_INVOKE)

    local token = GDP.USER_INFO.get('token')
    if not token then
        pay_listener(false, '', 1, 'need login!', {})
        return
    end

    local cur_time = os.time()
    if cur_time - last_pay_invoke_time < 1 then
        E.LOG.debug(TAG,'频繁调用充值！')
        return
    else
        last_pay_invoke_time = cur_time
    end

    check_realname_before_pay(function(succ, ...)
        if succ then
            E.LOG.debug(TAG, 'check before create order succ, now do create order!')
            pay_base(vendor_name, product_id, count, override)
        else
            E.LOG.error(TAG, 'before create_order_base failure, check realname failed!')
            local params = {}
            params.order_id = ''
            params.code = 1
            params.msg = '充值失败'
            local ext = ...
            params.ext = ext or {}
            ET.publish(ET.gangplank.PAY_FAILED, params)
            pay_listener(false, '', params.code, params.msg, params.ext)
        end
    end)
end

local function product_infos_base(channel, cb)
    local params = {
        game = E.CONFIG.get_config("product"),
        channel = channel,
        tags = E.CONFIG.get_config("pay_tags"),
        area = E.CONFIG.get_config('district'),
        language = LANG.get_startup_lang(),
        device_platforms = { E.Sysinfo.os() }
    }

    E.log("product_infos request params>>")
    E.log(params)
    gangplank_get('get_product_infos', params, function(status, body)
        if status == 200 then
            local product_infos = {}

            for _, v in ipairs(body.product_infos) do
                product_infos[v.product_id] = v
            end

            cb(true, product_infos)
        else
            cb(false, status)
        end
    end)
end

-- 不需要传channel入参的接口
function M.get_product_list_v2(cb)
    return M.get_product_list(nil, cb)
end

function M.get_product_list(channel, cb)
    if cb == nil then
        return
    end

    E.LOG.debug(TAG, "get_product_list begin")
    local vendor = EV.get(channel)
    if channel == nil or channel == '' or channel == 'auto'  then
        local vendor_ret = CM.get_vendor(nil, EV.ABILITY.PAY)
        if vendor_ret and vendor_ret.vendor then
            vendor = vendor_ret.vendor
        end
    end

    if vendor and vendor.vendor_channel then
        channel = vendor.vendor_channel()
    end

    if channel == nil or channel == '' then
        -- 未传入channel内部也找不到pay这个ability的情况，填充默认值
        local is_oversea = E.CONFIG.get_config(E.CONFIG.KEY.MULTI_REGIONS_ENABLED)
        if is_oversea then
            channel = 'OFFICIAL'
        else
            channel = 'ALIGAMES'
        end

        -- 游戏不接支付插件时，则以默认的vendor为准
        if not vendor then
            vendor = EV.get(channel)
        end
    end

    E.LOG.debug(TAG, "get_product_list from channel: "..(channel or 'nil'))

    if vendor then

        -- 如果vendor有自定义的异步获取商品列表方法，则使用vendor的
        -- vendore的自定义异步方法，返回参数必须是（boolean, table）的格式
        if vendor.get_product_list then
            vendor.get_product_list(cb)
            return
        end

        local product_list = nil
        if vendor.product_list then
            local ok, result = pcall(vendor.product_list)
            if ok then
                product_list = result
            end
        end

        if product_list and next(product_list) then
            E.LOG.debug(TAG,'get product from cache')
            cb(true, product_list)
        else
            M.product_infos_base(channel, cb)
        end
    else
        cb(false, -10)
    end
end

M.VENDOR_LOGIN_ERROR = -1

-- 所有的base接口，都是不负责和第三方sdk通讯的接口
-- 不带base的接口，都是打算以后做一站式服务的接口.

M.login_base = login_base
M.bind_base = bind_base
M.product_infos_base = product_infos_base
M.create_order_base = create_order_base

-- 尽量不用这些接口 begin:
function M.set_user_info(info)
    GDP.USER_INFO.set(info)
end

M.get_ejoy_token = function()
    return EJOY_TOKEN:get()
end
-- end

M.get_vendor_auth_info = function()
    return VENDOR_LOGIN:get()
end

-- 用户下线
-- 用户授权成功后在gangplank校验失败（例如：用户协议未签署、排队失败、风控处理失败时），之前的授权信息需要清空
M.offline = function()
    GDP.USER_INFO.clear()
end
M.bind = bind
M.query = query

function M.user_info()
    return GDP.USER_INFO.clone()
end

function M.async_user_info(cb)
    UTILS.safe_call_cb(cb, M.user_info());
end

function M.access(cb)
    local params = {
        token = GDP.USER_INFO.get('token'),
    }
    gangplank_post('access', params, function(status, body)
        if (status == 200) then
            cb(true, body)
        else
            cb(false, body)
        end
    end)
end

function M.exit(_vendor_name)
    local last_login = LAST_VENDOR_AUTH:get()
    if last_login and last_login ~= 'guest' then
        local vendor = EV.get(last_login)
        if vendor and vendor.exit then
            vendor.exit()
            return
        end
    end
    exit_listener(true)
    ET.publish(ET.gangplank.EXIT)
end

local function bind_listener_wrapper(listener) -- luacheck: ignore
    return function(succ, ...)
        LOGIN_INFO:delete()
        if listener then
            listener(succ, ...)
        end
    end
end

local function login_listener_wrapper(listener) -- luacheck: ignore
    return function(succ, ...)
        LOGIN_INFO:delete()
        if listener then
            listener(succ, ...)
        end
    end
end

local function acquire_listener_wrapper(listener) -- luacheck: ignore
    return function(succ, ...)
        LOGIN_INFO:delete()
        if listener then
            listener(succ, ...)
        end
    end
end

local function login_listener_modify(listener)
    return function(success, ...)
        if listener then
            listener(success, ...)
        end
        if success then
            QL.log_login(...)
        else
            ET.publish(ET.gangplank.LOGIN_FAILED, ...)
            QL.log_login_failed(...)
        end
    end
end

local function pay_listener_modify(listener)
    return function(succ, ...)
        if listener then
            listener(succ, ...)
        end
        local param = {
            can_pay = true,
        }
        if succ then
            local order_id, ext = ...
            param.order_id = order_id
            param.ext = ext or nil
            ET.publish(ET.gangplank.PAY, param)
        else
            local order_id, code, msg, ext = ...
            param.order_id = order_id
            param.code = code
            param.msg = msg
            param.ext = ext
            ET.publish(ET.gangplank.PAY_FAILED, param)
        end
    end
end

function M.get_global_cdn_config()
    return EGC.get_global_cdn_config()
end

local function get_cutout_info_from_cc()
    local CC = require 'ejoysdk_lua.ejoysdk_config_center'
    local biz_config = CC.get_config(CC.NAMESPACE.EJOYSDK_BIZ)
    if biz_config and biz_config.config then
        local cc_cutout_infos = biz_config.config.cutout_infos
        local model_str = E.Sysinfo.model() or ''
        if cc_cutout_infos and type(model_str) == 'string' and #model_str ~= 0 then
            local cutout_info = cc_cutout_infos[model_str]
            if cutout_info then
                E.LOG.debug(TAG,'get cutout from config_center')
                return { [model_str] = cutout_info } -- 兼容旧版本的格式
            end
        end
    end

    return nil
end

local function init_all_channel(opts, cb)
    local function vendor_init_callback(succ, ...)
        if succ then
            E.LOG.debug(TAG, 'vendor_init_callback success, now begin init native side')
            local ALL_CHANNEL = 'ALL'
            UNI.register_init_listener(ALL_CHANNEL, function(succ2, msg)
                if succ2 then
                    E.LOG.debug(TAG, 'all channel init success!')
                    cb(true)
                else
                    E.LOG.error(TAG, 'all channel init failed, msg:' .. (msg or 'nil'))
                    cb(false, CONSTANTS.CHANNEL_ERROR_CODE.CHANNEL_NATIVE_INIT_FAILED, msg)
                end
            end)
            local params = {}
            if _ejoysdk.os then
                -- 实际只有android native需要承接这个数据
                -- 优先使用配置中心的下发的数据
                local cutout_info = get_cutout_info_from_cc()
                if cutout_info then
                    params['cutout_info'] = cutout_info
                else
                    params['cutout_info'] = (require 'ejoysdk_lua.consts.cutout_info')[_ejoysdk.os() or '']
                end
            end
            UNI.init(ALL_CHANNEL, params)
        else
            local code, msg = ...
            E.LOG.error(TAG, 'vendor_init_callback failed, now callback init failed, code:' .. code .. ', msg:' .. (msg or 'nil'))
            cb(false, code, msg)
        end
    end

    -- 先初始化lua，再初始化Java层。这样lua才能收到Java层的初始化回调
    CM.init(opts, {
        --outsource 在各个vendor的register_login_listener回调中拼接
        auth_listener = function(vendor, succ, outsource, info)
            local login_info = LOGIN_INFO:get()
            if login_info and vendor == login_info.vendor then

                if login_info.type == 'login' then
                    if succ then
                        -- vendor 授权成功，更新LAST_VENDOR_AUTH
                        E.LOG.debug(TAG, 'auth_listener result succ, the login_info type is login, now set LAST_VENDOR_AUTH:' .. vendor)
                        LAST_VENDOR_AUTH:set(vendor)

                        local region = login_info.region
                        login_base(
                                login_info.server, region, outsource, login_info.token,
                                login_callback_builder(login_info.server, region, outsource, info, login_listener)
                        )

                        QL.log_vendor_login(vendor)
                    else
                        VENDOR_LOGIN:delete()
                        local login_fail_info = outsource or {}
                        login_fail_info.type = 'vendor_login_failed'
                        login_fail_info.vendor = vendor
                        ET.publish('trace_event', 'boot', login_fail_info)
                        local err_code = login_fail_info.code or M.VENDOR_LOGIN_ERROR
                        local err_msg = login_fail_info.msg or ''
                        login_listener(false, err_code, err_msg)

                        QL.log_vendor_login_failed(vendor, err_code, err_msg)
                    end

                    -- vendor login end
                    ET.publish(ET.gangplank.VENDOR_LOGIN_END, succ, outsource or {})
                elseif login_info.type == 'bind' then
                    if succ then
                        bind_base(
                                login_info.token, outsource, false,
                                bind_callback_builder(outsource, info)
                        )
                    else
                        bind_listener("error", M.VENDOR_LOGIN_ERROR, outsource)
                    end
                elseif login_info.type == 'acquire' then
                    if succ then
                        -- vendor 授权成功，更新LAST_VENDOR_AUTH
                        E.LOG.debug(TAG, 'auth_listener result succ, the login_info type is acquire, now set LAST_VENDOR_AUTH:' .. vendor)
                        LAST_VENDOR_AUTH:set(vendor)

                        local userinfo = M.user_info() or {}
                        userinfo.ptoken = outsource.ptoken
                        userinfo.platform = outsource.platform -- 注意三方登录,要用vendor_name
                        userinfo.uid = outsource.openId
                        userinfo.with = outsource.with
                        ET.publish(ET.gangplank.AUTH_SUCC,userinfo) -- 提前通知账号登录成功，保存登录历史，海外限定

                        local region = login_info.region
                        local token = login_info.token

                        local acquire_callback = acquire_callback_builder(region, outsource, info, token_callback_for_acquire)
                        acquire_base(region, outsource, token, acquire_callback)

                        -- vendor 登录技术打点
                        QL.log_vendor_login(vendor)
                    else
                        local login_fail_info = outsource or {}
                        login_fail_info.type = 'vendor_login_failed'
                        login_fail_info.vendor = vendor
                        local err_msg = login_fail_info.msg or ''
                        login_fail_info.message = err_msg
                        ET.publish('trace_event', 'boot', login_fail_info)

                        local err_code = login_fail_info.code or M.VENDOR_LOGIN_ERROR
                        local region = login_info.region
                        acquire_callback_builder(region, outsource, info, token_callback_for_acquire)(false, err_code, outsource or {})
                        --token_callback_for_acquire(false, login_fail_info.code or M.VENDOR_LOGIN_ERROR, login_fail_info.msg or '', outsource or {})

                        -- vendor 登录技术打点
                        QL.log_vendor_login_failed(vendor, err_code, err_msg)
                    end

                    -- vendor login end
                    ET.publish(ET.gangplank.VENDOR_LOGIN_END, succ, outsource or {})
                end

            else
                E.log('vendor not equal to login_info.vendor')
            end
        end,
        pay_listener = function(vendor, succ, ...)
            if succ then
                local order_id, ext = ...
                local product_info = pending_product_infos.order_id
                ET.publish(ET.analytics.PURCHASE_SUCC, order_id, product_info)
                pending_product_infos.order_id = nil
                pay_listener(true, order_id, ext or {})
            else
                local order_id, value = ...
                local ext = value.ext or {}
                ext.platform = vendor
                pay_listener(false, order_id, value.code or ext.code or CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_PAY_FAILED_DEFAULT_CODE, value.msg or ext.msg or '', ext)
            end
        end,
        switch_listener = function(_vendor, outsource, info)
            -- 参数格式和auth_listener相比少了succ，其他一样
            local vendor_login = VENDOR_LOGIN:get()
            if vendor_login then
                login_base(
                        vendor_login.server, vendor_login.region, outsource, vendor_login.token,
                        login_callback_builder(vendor_login.server, vendor_login.region, outsource, info, switch_listener)
                )
            end
        end,
        logout_listener = function(_vendor, _ext)
            LOGIN_INFO:delete()
            VENDOR_LOGIN:delete()
            M.offline()
            ET.publish(ET.gangplank.LOGOUT, GDP.USER_INFO.get())
            logout_listener()
        end,
        exit_listener = function(_vendor, succ)
            exit_listener(succ)
            if succ then
                ET.publish(ET.gangplank.EXIT)
                ET.publish(ET.analytics.EXIT)
            end
        end
    }, vendor_init_callback)
end

local function check_init_opts(opts)
    if type(opts) == 'string' and opts == 'auto' then
        local login_sdks = EV.get_native_vendors(EV.ABILITY.ACCOUNT)
        local pay_sdks = EV.get_native_vendors(EV.ABILITY.PAY)
        opts = {}
        for _, sdk in pairs(login_sdks) do
            opts[sdk] = {}
        end
        for _, sdk in pairs(pay_sdks) do
            opts[sdk] = {}
        end
    else
        opts = opts or {}
    end

    E.LOG.debug(TAG, 'check init opts before >>')
    --E.log(opts) -- opts 可能传入 function，不打印

    -- get sdk_config sdk infos
    local sdk_infos = UNI.get_sdk_infos()
    -- st登录作为official的一部分, 默认捆绑配置
    if sdk_infos and sdk_infos['OFFICIAL'] then
        local st_login_name = 'ST_LOGIN'
        sdk_infos[st_login_name] = {
            name = st_login_name,
            lua_vendor = true,
            ability = { 'ACCOUNT' }
        }
    end

    E.LOG.debug(TAG, 'check init opts sdk_infos >>')
    E.log(sdk_infos)

    for sdk_name, sdk_info in pairs(sdk_infos) do
        sdk_info = sdk_info or {}
        if sdk_info.lua_vendor and EV.get(string.upper(sdk_name)) then
            -- 目前lua插件名字全部都为大写，加入此条件后不会影响现有逻辑
            -- 修改背景：越南的travlet支付打包officialpay使用纯lua的新版本插件，但officialpay以前名字都是使用小写的，并从native获取名字，使用纯lua后就不能从native获取名字了，需要纠正
            sdk_name = string.upper(sdk_name)
        end

        if opts[sdk_name] == nil then
            E.LOG.debug(TAG, 'opts add native sdk: ' .. tostring(sdk_name))
            local meta_info = sdk_info.meta or {}
            opts[sdk_name] = meta_info
        end
    end

    -- check disable opts
    for vendor_name, options in pairs(opts) do
        if options._disable then
            E.LOG.debug(TAG, "vendor is disable, so remove it from opts:" .. vendor_name)
            opts[vendor_name] = nil
        end
    end

    E.LOG.debug(TAG, "check_init_opts opts after >>")
    E.log(opts)
    return opts
end

-- 需要对外暴露给加签模块，确保加签前同步过server_time
-- 不带重试参数则只请求一次
M.sync_server_time = function(cb, _retry_times, _retry_timer_interval)
    local start = os.time()
    local start_clock = E.system_clock()
    gangplank_post('get_server_time', {}, function(status, body)
        if status == 200 then
            -- E.LOG.debug(TAG, 'get_server_time resp:' .. tostring(body.server_time_ms))
            local now = os.time()
            local rtt = (start - now) / 2
            local diff = body.server_time_ms / 1000 + rtt - now

            local end_clock = E.system_clock()
            local clock_rtt = end_clock - start_clock
            local server_ms = body.server_time_ms + (clock_rtt / 2)

            E.set_time_diff(diff)

            -- E.LOG.debug(TAG, 'end_clock:' .. tostring(end_clock) .. ' start_clock:' .. tostring(start_clock) .. ', clock: ' .. tostring(clock_rtt))
            
            -- 同步服务器时间
            -- 如果tick结果回来发现超过了 4min（加签过期时间 5min + 请求超时时间，单位ms） 这个结果用于加签是不可靠的旧服务器时间，需要丢弃
            if clock_rtt < 4 * 60 * 1000 and clock_rtt > 0 then
                E.set_server_ms(server_ms)
                if cb then
                    cb(true)
                end
            else
                E.LOG.debug(TAG, 'tick sync_server_time time out')
                if cb then
                    cb(false, 0, { code = 0, message = 'sync_server_time time out' })
                end
            end
        else
            local retry_times = _retry_times or 0
            local retry_timer_interval = _retry_timer_interval or 1
            -- 保护一下
            if retry_timer_interval <= 0 then
                retry_timer_interval = 600
            end
            if retry_times > 0 then
                -- 如果失败了，retry_timer_interval会按照1,2,4,8,16,32,*** 的指数间隔重试
                E.Timer.once(retry_timer_interval, function ()
                    M.sync_server_time(cb, retry_times - 1, retry_timer_interval * 2)
                end)
            else -- 默认不重试
                if cb then
                    cb(false, status, body)
                end
            end
        end
    end)
end

local DEFAULT_LOOP_SYNC_SERVER_TIME = 60 * 60 * 12 -- 对时间隔，理论不需要，这里是解决长期挂机卡顿导致时间不准的情况
local did_start_loop_sync_timer = false
local function loop_sync_server_timer()
    E.Timer.once(DEFAULT_LOOP_SYNC_SERVER_TIME, function ()
        M.sync_server_time()
        loop_sync_server_timer()
    end)
end

--[
-- 有一些SDK会在程序启动的时候直接推送消息给我们的程序，告知登录信息，
-- 只能用如此复杂的登录/付费流程
--
-- @param opts: 一个 table，以 VENDOR 名字为key， 比如 EJOY, WEIXIN,
-- 值为一个 table， 会传递给对应的 VENDOR 作为初始化参数, 比如
-- {EJOY = {hide_email_login = true}}, 没有出现的 VENDOR 不会被初始化
--
-- @param listeners: 一个 table， 包含四个 key, auth_listener, pay_listener, bind_listener, queue_listener
--]

function M.init(opts, listeners)
    if inited then
        E.LOG.debug(TAG, 'gangplank already inited, just notify init success and return')
        ET.publish(EI.SUBSCRIBE_GANGPLANK_INITED, true)
        return
    end

    ET.publish(EI.SUBSCRIBE_GANGPLANK_INITSTART)

    opts = check_init_opts(opts)

    -- vendor 准备好了，在初始化前校验vendor和ejoy的最低版本要求
    local check_result = VC.check_sdk_version(opts)
    if not check_result.result then
        local check_fail_msg = "[error]version check failed! sdk_name:" .. check_result.sdk_name .. ", current version is " .. check_result.current_sdk_version .. ", min sdk required is:" .. check_result.sdk_min_version
        E.LOG.warn(TAG, check_fail_msg)
        ET.publish(EI.SUBSCRIBE_GANGPLANK_INITED, false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_CHECK_SDK_VERSIONS_FAILED, check_fail_msg)
        return ;
    end

    M.set_listener(listeners)

    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, logout_hanlder)

    ET.subscribe(ET.holo.GET_PLAYER_TOKEN, get_player_token_succ_handler)
    ET.subscribe(ET.holo.GET_PLAYER_TOKEN_FAIL, get_player_token_fail_handler)

    local publish_init_success = function()
        --mark inited
        inited = true

        ET.publish(EI.SUBSCRIBE_GANGPLANK_INITED, true)
    end

    local publish_init_failed = function(status, message)
        E.LOG.error(TAG, 'init failed, status:' .. (status or 'nil') .. ', msg:' .. (message or nil))
        ET.publish(EI.SUBSCRIBE_GANGPLANK_INITED, false, status, message)
    end

    E.LOG.debug(TAG, "gangplank init begin, bin_ver:" .. tostring(E.Sysinfo.bin_version()))
    EGC.init_config(function(succ, ...)
        if succ then
            E.LOG.debug(TAG, "init_config succ >>")
            --初始化本地时间
            
            --服务器对时：同步服务器时间，这里是异步的请求
            -- 立刻调用一次，失败会重试10次
            M.sync_server_time(function (_time_succ, ...)
                if _time_succ then
                    E.LOG.debug(TAG, "sync_server_server succ")
                    QL.commit_action_succ_main("ejoy_get_server_time_end")
                else
                    local _status = ...
                    E.LOG.warn(TAG, "sync_server_server failed:" .. tostring(_status))
                    QL.commit_action_fail_main("ejoy_get_server_time_end", nil, _status)
                end
            end, 10)

            if not did_start_loop_sync_timer then
                loop_sync_server_timer()
                -- 避免开启多个timer
                did_start_loop_sync_timer = true
            end
            
            -- 后台配置中心，2021-08 APM 一期不需要卡初始化流程
            local config_center = require 'ejoysdk_lua.ejoysdk_config_center'
            local aligames_config = require 'ejoysdk_lua.vendors.aligames_config'
            config_center.set_url_base(aligames_config.get_config_center_base_url())
            config_center.init()

            local ejoy_res = require 'ejoysdk_lua.res.ejoysdk_res'
            ejoy_res.init() -- 提前初始化资源

            local ejoy_lightboat = require 'ejoysdk_lua.res.lightboat.ejoysdk_lightboat'
            ejoy_lightboat.init()

            E.LOG.debug(TAG, "init_all_channel begin")
            --初始化所有渠道
            init_all_channel(opts, function(succ2, ...)
                -- 继续回调的代码抽出来

                local status, message = ...
                if not succ2 then
                    E.LOG.error(TAG, "init_all_channel failed, status: " .. tostring(status) .. ", msg:" .. tostring(message))
                    publish_init_failed(status, message)
                    return
                end

                E.LOG.debug(TAG, "init_all_channel succ received")
                local temp_callback_function = function(_succ, ...)
                    if _succ then
                        if succ2 then
                            publish_init_success()
                        else
                            publish_init_failed(status, message)
                        end
                    else
                        local code, msg = ...
                        E.LOG.error(TAG, "gangplank init failed, code: " .. tostring(code) .. ", msg:" .. tostring(msg))
                        publish_init_failed(code, msg)
                    end
                end

                -- 游戏设置了需要强更，才去请求接口检查是否有版本需要更新
                if (E.CONFIG.get_config(E.CONFIG.KEY.APP_VERSION_UPDATE_CHECK) == true) then
                    local APP_Update = require("ejoysdk_lua.app_update.app_update")
                    APP_Update.check_update_app_version(function(_succ, ...)
                        -- 当需要强制更新，则不会再回调到这里
                        temp_callback_function(_succ, ...)
                    end)
                else
                    temp_callback_function(succ2, ...)
                end
            end)

            -- stat global config succ
            QL.commit_action_succ_main("ejoy_gp_config_end")
        else
            local status, message = ...
            E.LOG.error(TAG, "init_config failed, status:" .. (status or 'nil') .. ", message:" .. (message or 'nil'))
            publish_init_failed(status, message)

            -- stat global config failed
            QL.commit_action_fail_main("ejoy_gp_config_end", nil, status, message)
        end
    end)

end

function M.is_inited()
    return inited
end

function M._test_reset_init()
    inited = false
end

function M.set_listener(listeners)
    login_listener = login_listener_modify(listeners.auth_listener)
    logout_listener = listeners.logout_listener
    switch_listener = listeners.switch_listener
    pay_listener = pay_listener_modify(listeners.pay_listener)
    bind_listener = listeners.bind_listener
    queue_listener = listeners.queue_listener
    exit_listener = listeners.exit_listener
    acquire_listener = listeners.acquire_listener

    game_listeners = listeners
end

function M.get_listener()
    return game_listeners
end

-- 接口描述：获取服务器详细信息列表，get请求方式
-- params table类型，包含以下参数：
-- tags: table类型，tag标签数组
-- server_ids: table类型，server_id 数组
-- options 传递到请求库的配置项目前，支持 {use_url_connection = true}用于规避一些请求库的问题，仅限于频繁的轮询请求
function M.alive_servers_with_params(cb, params, options)
    E.LOG.debug(TAG, "alive_servers_with_params params >>")
    E.log(params)

    gangplank_get('get_alive_servers', params, function(status, body)
        if status == 200 then
            for _, server in pairs(body.servers) do
                -- 以前gangplank设计的realm是一个数组，用于记录服务器的一连串地址。
                -- 现在用不到数组，直接取数组第一个元素返回
                server.realm = server.realm[1] or ''
            end
            cb(true, body.servers)

            --stat alive_servers result
            QL.commit_action_succ_main("ejoy_alive_servers_end")
        else
            local msg = body and body.message or ''
            cb(false, status, msg)

            --stat alive_servers result
            QL.commit_action_fail_main("ejoy_alive_servers_end", nil, status, msg)
        end

    end, options)
end

function M.alive_servers(tags, cb)
    E.LOG.debug(TAG, "alive_servers begin >>")
    if type(tags) == 'function' then
        cb = tags
        tags = {}
    end

    if tags and #tags == 0 then
        tags = nil
    end

    local params = {
        tags = tags,
    }

    M.alive_servers_with_params(cb, params)
end

-- 接口描述：获取服务器详细信息列表，带登录态
-- params table类型，包含以下参数：
-- tags: table类型，tag标签数组
-- server_ids: table类型，server_id 数组
function M.alive_servers_auth_with_params(cb, params)
    E.LOG.debug(TAG, "alive_servers_auth_with_params params >>")
    E.log(params)

    local url = M.gangplank_logined_url('/alive_servers', '2')
    local token = M.user_info().token
    E.HTTP.post(url, require_params(token), HTTP.CT_JSON, params, function(resp)
        E.log({ resp = resp })
        local status = resp.status
        local body = resp.body
        if status == 200 then
            for _, server in pairs(body.servers) do
                --与alive_servers保持一致
                server.realm = server.realm[1] or ''
            end
            cb(true, body.servers)

            --stat alive_servers result
            QL.commit_action_succ_main("ejoy_alive_servers_auth_end")
        else
            local _msg = body and body.message or ''
            cb(false, status, _msg)

            --stat alive_servers result
            QL.commit_action_fail_main("ejoy_alive_servers_auth_end", nil, status, _msg)
        end
    end)
end

-- 传入tags数组
-- 需要有登录态才能调用
function M.alive_servers_with_auth(tags, cb)
    if tags and #tags == 0 then
        tags = nil
    end
    local params = {
        tags = tags,
    }

    M.alive_servers_auth_with_params(cb, params)
end

-- 接口描述：只查询推荐服务器，且推荐服务器一定为alive状态服务器，get请求方式
-- params {} 预留查询扩展参数
function M.get_recommend_servers(_params, cb)
    local params = _params or {}
    E.LOG.debug(TAG, "get_recommend_servers params >>")
    E.log(params)

    gangplank_get('get_recommend_servers', params, function(status, body)
        if status == 200 then
            cb(true, body.servers)
        else
            cb(false, status, body and body.message or '')
        end

    end)
end

-- 用户地址内存缓存
local gplbs_config
-- 接口描述：从服务端接口获取用户地址
-- _params 扩展参数
local function get_ip_location_from_server(_params, cb)
    local params = _params or {}

    gangplank_post('get_location', params, function(status, body)
        if status == 200 then
            local result = body and body.data
            if result then
                gplbs_config = result
            end
            if cb then
                cb(true, result or {})
            end
        else
            if cb then
                cb(false, status, body and body.message or '')
            end
        end
    end)
end

-- 获取用户地址，外部接口，调用时机游戏决定
-- 优先从本地获取，如果没有则走服务端接口
function M.get_ip_location_async(cb)
    if gplbs_config then
        if cb then
            cb(true, gplbs_config)
        end
    else
        get_ip_location_from_server({}, cb)
    end
end

-- 为了兼容保留该方法
-- 后续需要调用get_players，请使用user_info_api的get_players方法
function M.get_players(token, cb)
    local user_info_api = require "ejoysdk_lua.server_api.ejoysdk_user_info"
    user_info_api.get_players(token, cb)
end

-- 为了兼容保留该方法
-- 后续需要调用get_players_with_query，请使用user_info_api的get_players_with_query方法
function M.get_players_with_query(_query, cb)
    local user_info_api = require "ejoysdk_lua.server_api.ejoysdk_user_info"
    user_info_api.get_players_with_query(_query, cb)
end

function M.get_players_from_gs(cb)
    local url = M.gangplank_logined_url('/get_players', '2')
    E.LOG.debug(TAG,'get_players_from_gs url : ' .. tostring(url))
    local token = M.user_info().token
    HTTP.post(url, require_params(token), HTTP.CT_JSON, {}, function(resp)
        local status = resp.status
        local body = resp.body
        E.log({
            status = status,
            body = body
        })
        if status == 200 then
            if body.code == 0 then
                cb(true, body.result)
            else
                cb(false, body.code)
            end
        else
            cb(false, status)
        end
    end)
end

-- 获取全球同服角色对应的地区列表
local function get_global_players(cb)
    local user_info_api = require "ejoysdk_lua.server_api.ejoysdk_user_info"
    user_info_api.get_global_players(cb)
end

-- 用于单元测试，请勿调用
function M.get_global_players_for_unittest(cb)
    get_global_players(cb)
end

-- @description 登录进入国际大厅
-- @params vendor_name: 登录使用的插件名称
-- @return 返回全球的角色对应地区信息，和全球同服地区列表
-- 返回示例：
-- {
--   "global_players":[
--      {
--         "account": "xxxx",
--         "player_id":"123",
--         "region":"HK"
--      },
--      {
--        "account": "xxxx",
--         "player_id":"1234",
--         "region":"US"
--      }
--   ],
--   "gangplank_config":[
--        {
--            "area": "HK",
--            "region": "HK",
--            "ext": "中国",
--            "default": true
--        },
--        {
--            "area": "SG",
--            "region": "HK",
--            "ext": "东南亚",
--            "default": false
--        }
--    ]
-- }
function M.login_global_center(vendor_name, cb)
    local global_gangplank_enabled = E.CONFIG.get_config(E.CONFIG.KEY.GLOBAL_GANGPLANK_ENABLED)
    if not global_gangplank_enabled then
        local err_msg = 'login_global_center failed, global gangplank not enabled!'
        E.LOG.error(TAG, err_msg)
        cb(false, CONSTANTS.GLOBAL_GANGPLANK_ERROR_CODE.GLOBAL_GANGPLANK_NOT_ENABLED, err_msg)
        return
    end

    local login_global_center_callback = function(succ, ...)
        if succ then
            local players = ...

            local global_result = {}
            global_result.global_players = players
            global_result.gangplank_config = EGC.get_global_gangplank_configs()
            cb(true, global_result)
        else
            local status, message = ...
            E.LOG.error(TAG, 'get_global_players failed:' .. status)
            cb(false, status, message or 'login global center failed!')
        end
    end

    local acquire_token_callback = function(succ, ...)
        if succ then
            local token = ...
            E.LOG.debug(TAG, 'login_global_center get ejoy_token succ:' .. token)
            local region = E.CONFIG.get_config(E.CONFIG.KEY.REGION)
            global_region_token_cache[region] = token
            E.LOG.debug(TAG, 'login_global_center update token cache, region:' .. region .. ', token:' .. token)
            -- 2. 获取全球角色对应地区列表
            get_global_players(function(succ2, ...)
                if succ2 then
                    local players = ...
                    E.LOG.debug(TAG, 'get_global_players succ:')
                    E.log(players)

                    login_global_center_callback(true, players)
                else
                    local status = ...
                    E.LOG.error(TAG, 'get_global_players failed:' .. status)
                    login_global_center_callback(false, status, 'get global players failed!')
                end
            end)
        else
            local code, message = ...
            E.LOG.error(TAG, 'login_global_center get ejoy_token failed, code: ' .. code .. ' ,message: ' .. message)
            login_global_center_callback(false, code, message)
        end
    end

    local ext = {
        override_acquire_listener = acquire_token_callback
    }

    -- 1. 清除global_region_token_cache
    global_region_token_cache = {}
    -- 2. 获取gangplank的ejoy_token
    M._acquire_token_global(vendor_name, nil, ext)
end


-- For PC

local cur_login_qrcode_uuid = nil

function M.get_login_qrcode(cb)
    local params = {
        game_code = E.CONFIG.get_config('product'),
        scan_type = 'LOGIN'
    }
    gangplank_post('gen_uuid', params, function(status, body)
        E.log('get login qr status: ' .. tostring(status))
        E.log(body)
        if status == 200 then
            if body.code == 0 then
                local result = {}
                result.uuid = body.uuid
                cur_login_qrcode_uuid = body.uuid
                result.type = 'LOGIN'
                cb(true, JSON.encode(result))
            else
                cb(false, body.code, body.message or '')
            end
        else
            cb(false, status, '')
        end
    end)
end

function M.check_if_prevent_replay_status_open()

    local CC = require 'ejoysdk_lua.ejoysdk_config_center'
    local core_config = CC.get_config(CC.NAMESPACE.EJOYSDK_CORE)
    if core_config and core_config.config then
        local value = core_config.config.enable_sign_headers_for_response
        if value then
            return true
        end
    end

    return false
end

function M.validate_qrcode_uuid(uuid, extra_params, cb)
    local params = {
        uuid = uuid
    }
    for key, value in pairs(extra_params) do
        params[key] = value
    end

    -- 这里用下发参数控制走不走加签防重放的流程
    local opts = {}
    opts.enable_sign_headers_for_request = true
    opts.enable_sign_headers_for_response =  M.check_if_prevent_replay_status_open()

    gangplank_post('validate_uuid', params, function(status, body)
        E.log({
            status = status, body = body
        })
        if status == 200 then
            if body.code == 0 then
                cb(true, body)
            else
                cb(false, body.code, body.message)
            end
        else
            cb(false, status, '')
        end
    end, opts)
end

function M.cancel_query_qrcode_login()
    cur_login_qrcode_uuid = nil
end

function M.query_qrcode_login_status(cb)
    if not cur_login_qrcode_uuid then
        return
    end

    E.LOG.debug(TAG, "query_qrcode_login_status, uuid:" .. cur_login_qrcode_uuid)
    local extra_params = { return_all = true }
    M.validate_qrcode_uuid(cur_login_qrcode_uuid, extra_params, function(succ, ...)
        if succ then
            local body = ...
            local status = body.status
            local _ptoken = ''
            local ext = body.ext
            if ext and ext.ptoken then
                _ptoken = ext.ptoken
            end
            if status == 1 then
                cur_login_qrcode_uuid = nil
                E.LOG.debug(TAG,'query qrcode logined!')
                local game = E.CONFIG.get_config('product')
                local region = game
                local login_data = body.login_data
                local pinfo = login_data.pinfo or {}
                local uifo = GDP.USER_INFO.new({
                    game = game,
                    region = region,
                    token = login_data.token,
                    uid = login_data.uid,
                    pinfo = pinfo,
                    pid = pinfo.pid,
                    with = pinfo.with,
                    with_account = pinfo.with_account,
                    platform = pinfo.platform,
                    ptoken = _ptoken
                })

                M.set_user_info(uifo)
                cb(true, login_data.token, login_data)

                ET.publish(ET.gangplank.SCAN_LOGIN, GDP.USER_INFO.get())
            else
                E.LOG.debug(TAG,'query qrcode not login, query again')
                E.Timer.once(3, function()
                    M.query_qrcode_login_status(cb)
                end)
            end
        else
            E.LOG.debug(TAG,'query qrcode other error')
            cb(false, ...)
        end
    end)
end

function M.grant_login_uuid(uuid, cb)
    local params = {}
    params.uuid = uuid
    params.grant_type = 'LOGIN'
    params.token = M.user_info().token
    params.game = E.CONFIG.get_config('product')
    params.ext = {
        ptoken = M.user_info().ptoken or ''
    }

    -- 这里用下发参数控制走不走加签的流程
    local opts = {}
    opts.enable_sign_headers_for_request = true
    opts.enable_sign_headers_for_response =  M.check_if_prevent_replay_status_open()

    E.log(params)
    gangplank_post('grant_uuid_access', params, function(status, body)
        E.log({
            status = status, body = body
        })
        if status == 200 then
            if body.code == 0 then
                cb(true)
            else
                cb(false, body.code, body.message)
            end
        else
            cb(false, status, '')
        end
    end, opts)
end

-- For phone
function M.qrcode_scan(cb)
    local qr_realname_stat = function(is_realname_open, realname_status, adult_status, is_qrcode_start)
        local params = {
            is_realname_open = is_realname_open,
            realname_status = realname_status,
            adult_status = adult_status,
            is_qrcode_start = is_qrcode_start
        }
        QL.commit_event(QL.EVENT_NAMES.SDK_REALNAME_QRSCAN, params)
    end

    local is_realname_open = REALNAME_INFO.is_realname_open()
    if is_realname_open then
        -- 检查服务端是否有拦截，注意：这里应该是实名制开启开关，但服务端暂时么有该开关，所以直接禁止。

        E.LOG.debug(TAG, 'realname is open, so check realname and adult status')
        local realname_status = REALNAME_INFO.get_realname_status()
        E.LOG.debug(TAG, 'qrcode_scan realname_status:' .. realname_status)
        if realname_status ~= REALNAME_INFO.REALNAME_STATUS.SUCCESS then
            E.LOG.warn(TAG, 'qrcode_scan user has not realname success, should not scan for windows login')
            cb(false, REALNAME_INFO.ERR_CODE_QRCODE_NEED_REALNAME_ADULT, '用户未实名')
            qr_realname_stat(true, REALNAME_INFO.REALNAME_STATUS.UNKNOWN, REALNAME_INFO.REALNAME_AGE_STATUS.UNKNOWN, false)
            return
        else
            local adult_status = REALNAME_INFO.get_adult_status()
            E.LOG.debug(TAG, 'qrcode_scan adult status:' .. adult_status)
            if adult_status ~= REALNAME_INFO.REALNAME_AGE_STATUS.ADULT then
                E.LOG.warn(TAG, 'qrcode_scan user is not adult, should not scan for windows login')
                cb(false, REALNAME_INFO.ERR_CODE_QRCODE_NEED_REALNAME_ADULT, '用户未成年')
                qr_realname_stat(true, REALNAME_INFO.REALNAME_STATUS.SUCCESS, adult_status, false)
                return
            end
        end
    else
        E.LOG.debug(TAG, 'realname not open, skip and start scan')
    end

    qr_realname_stat(is_realname_open, REALNAME_INFO.get_realname_status(), REALNAME_INFO.get_adult_status(), true)
    E.LOG.debug(TAG, 'qrcode_scan now start qrcode scan')

    QL.commit_action_main('ej_qrcode_scan')
    E.qrcode_scan(function(succ, ...)
        if succ then
            QL.commit_action_main('ej_qrcode_scan_result', nil, true)
            local content = ...
            E.log('qrcode scan info: ' .. content)

            local decode_succ, result = pcall(JSON.decode, content)

            if not decode_succ or type(result) ~= "table" or not result.uuid or not result.type then
                -- -999 表示json解析失败
                cb(false, -999, '')
                return
            end

            local uuid = result.uuid
            local uuid_type = result.type
            M.validate_qrcode_uuid(uuid, {}, function(succ2, ...)
                if succ2 then
                    local body = ...
                    cb(true, uuid, uuid_type, body)
                else
                    cb(false, ...)
                end
            end)
        else
            local error_code, error_msg = ...
            error_code = error_code or 1
            error_msg = error_msg or ''
            E.LOG.error(TAG,'qrcode scan fail: ' .. tostring(-error_code) .. tostring(error_msg))
            local params = {
                code = error_code,
                msg = error_msg
            }
            QL.commit_action_main('ej_qrcode_scan_result', nil, false, params)
            cb(false, -error_code, error_msg)
        end
    end)
end

-- 为了兼容旧版本，保留gangplank的get_punishment方法
-- 后续要使用get_punishment，请直接使用user_info_api的get_punishment
function M.get_punishment(cb)
    local user_info_api = require "ejoysdk_lua.server_api.ejoysdk_user_info"
    user_info_api.get_punishment(cb)
end

function M.unfreeze_player_product(player_id, cb)
    if not GDP.USER_INFO.get('token') or GDP.USER_INFO.get('token') == '' then
        E.LOG.error(TAG, 'unfreeze_player_product failed, ejoy token is nil')
        cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_CODE_EJOY_TOKEN_INVALID, 'ejoy token is nil')
        return
    end

    local playerid = player_id
    E.LOG.debug(TAG, 'unfreeze_player_product, game set with player_id:' .. (playerid or 'nil'))
    if not playerid or playerid == '' then
        -- 解除绑定需要对应的角色ID
        local player_info = M.player_info()
        playerid = (player_info and player_info.player_id) or nil
        E.LOG.debug(TAG, 'unfreeze_player_product, game NOT set with player_id, now use current player_id:' .. (playerid or 'nil'))
    end

    if not playerid or playerid == '' then
        E.LOG.error(TAG, 'unfreeze_player_product failed, player id is nil')
        cb(false, CONSTANTS.GANGPLANK_ERROR_CODE.GANGPLANK_ERROR_CODE_PLAYER_ID_INVALID, 'player id is nil')
        return
    end

    local params = {
        player_id = tostring(playerid)
    }

    E.LOG.debug(TAG, 'unfreeze_player_product player_id:' .. (playerid or 'nil'))
    E.log(params)

    -- 服务端解除角色商品冻结接口
    local token = GDP.USER_INFO.get('token')
    HTTP.post(M.gangplank_logined_url('/unfreeze_player_product', 2), require_params(token), E.HTTP.CT_JSON, params, function(resp)
        E.log({ resp = resp })

        local status = (resp and resp.status) or -1
        if status == 200 then
            local result_code = resp and resp.body and resp.body.code
            if result_code == 0 then
                cb(true)
            else
                local msg = resp and resp.body and resp.body.message
                cb(false, result_code, msg or 'request failed')
            end
        else
            cb(false, status, 'request failed, status:' .. status)
        end

    end)
end

-- 接口描述：查询是否在白名单，主要是涉及 ip/账号/渠道账号 的黑白名单检查
-- 使用场景：star游戏有维护公告，普通玩家会被拦截，但是白名单用户可以正常进入游戏
function M.check_white_black(cb)
    local url = M.gangplank_logined_url('/check_white_black', '2')
    local token = M.user_info().token

    E.HTTP.post(url, require_params(token), HTTP.CT_JSON, {}, function(resp)
        E.LOG.debug(TAG, "check_white_black resp >>")
        E.log({ resp = resp })
        local status = resp.status
        local body = resp.body
        if status == 200 then
            local code = body.code
            local msg = body.message
            if code == 0 then
                E.LOG.debug(TAG, "check_white_black succ")
                cb(true, body)
            else
                E.LOG.error(TAG, "check_white_black failed, code:" .. code .. ", msg:" .. msg)
                cb(false, code, msg)
            end
        else
            local err_msg = body and body.message or ''
            E.LOG.error(TAG, "check_white_black failed, status:" .. status .. ", msg:" .. err_msg)
            cb(false, status, err_msg)
        end
    end)
end

return M
