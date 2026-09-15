local BASE_API = require 'ejoysdk_lua.libs.base_api'
local gangplank_api = BASE_API:New('gangplank')
local user_info_api = require "ejoysdk_lua.server_api.ejoysdk_user_info"
local E = require 'ejoysdk_lua.ejoysdk'
local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.SERVER_API .. 'gangplank_ex'

local M = {}

local function gangplank_v2_api(api)
    local product = E.CONFIG.get_config('product'):lower()

    api = '/v2' .. api

    return '/gp/' .. product .. api
end

-- 请直接使用user_info_api的get_players2接口
-- 之所以保留gangplank_ex的get_players2接口，是为了兼容旧版本
M['get_players2'] = user_info_api.get_players2;

function M.validate_qrcode_uuid_http(uuid, extra_params, cb)
    local body = {
        uuid = uuid
    }
    for key, value in pairs(extra_params) do
        body[key] = value
    end

    -- 这里用下发参数控制走不走加签的流程
    local opt = {}
    opt.enable_sign_headers_for_request = true -- request的加签默认开启
    opt.enable_sign_headers_for_response = EG.check_if_prevent_replay_status_open()


    gangplank_api:post(gangplank_v2_api('/validate_uuid'), {}, body, opt, cb)
end

-- 扫码登录状态轮询接口, 服务端接口协议：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/srq4v3
function M.validate_qrcode_uuid_http_v2(uuid, extra_params, cb)
    local body = {
        uuid = uuid
    }

    for key, value in pairs(extra_params) do
        body[key] = value
    end

    -- 这里用下发参数控制走不走加签的流程
    local opt = {}
    opt.enable_sign_headers_for_request = true -- request的加签默认开启
    opt.enable_sign_headers_for_response = EG.check_if_prevent_replay_status_open()

    gangplank_api:post(gangplank_v2_api('/qrcode/login/query'), {}, body, opt, function(succ, ...)
        local _body
        local code
        local msg
        if succ then
            E.LOG.debug(TAG, "validate_qrcode_uuid_http_v2 succ")
            _body = ...
        else
            code, msg, _body = ...
            E.LOG.debug(TAG, "validate_qrcode_uuid_http_v2 failed, code:" .. tostring(code) .. ", msg:" .. tostring(msg))
        end

        _body = _body or {}
        -- 这里添加scan_type是为了和login v1对齐。ios的demo使用了body里面的scan_type，但是login v2没有此字段。考虑到服务端新的协议不和旧的兼容，同时不影响游戏接入代码，这里在body添加了scan_type
        _body.scan_type = "login_v2"
        if succ then
            cb(true, _body)
        else
            cb(false, code, msg, _body)
        end
    end)
end

function M.get_login_qrcode_http(cb)
    local body = {
        game_code = E.CONFIG.get_config('product'),
        scan_type = 'LOGIN'
    }
    gangplank_api:post(gangplank_v2_api('/gen_uuid'), {}, body, {}, cb)
end

-- 获取扫码二维码(uuid)数据，服务端接口协议：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/gdh7te
function M.get_login_qrcode_http_v2(cb)
    E.LOG.debug(TAG, "get_login_qrcode_http_v2 begin")
    local body = {
        pkg_info = E.get_pkg_info()
    }
    gangplank_api:post(gangplank_v2_api('/qrcode/login/acquire'), {}, body, {}, cb)
end

function M.grant_login_uuid_http(uuid, cb)
    E.LOG.debug(TAG, 'grant_login_uuid_http')

    local body = {}
    body.uuid = uuid
    body.grant_type = 'LOGIN'
    body.token = EG.user_info().token
    body.game = E.CONFIG.get_config('product')
    local tempExt = {}
    tempExt.ptoken = EG.user_info().ptoken or ''
    body.ext = tempExt
    --E.log(body)

    -- 这里用下发参数控制走不走加签的流程
    local opt = {}
    opt.enable_sign_headers_for_request = true -- request的加签默认开启
    opt.enable_sign_headers_for_response = EG.check_if_prevent_replay_status_open()


    gangplank_api:post(gangplank_v2_api('/grant_uuid_access'), {}, body, opt,  cb)
end

-- 扫码登录授权（移动端扫码授权）,服务端接口文档：https://yuque.antfin-inc.com/ejoy-platform/ejoy-platform/skgbpm
function M.grant_login_uuid_http_v2(uuid, cb)
    E.LOG.debug(TAG, 'grant_login_uuid_http_v2')

    local body = {}
    body.uuid = uuid

    local user_info = EG.user_info()
    body.token = user_info.token

    local authorized_infos = {
        with = user_info.with,
        region = user_info.region,
        ptoken = user_info.ptoken,
        platform = user_info.platform,
        guest = user_info.guest,
        game = user_info.game,
        pid = user_info.pid,
        ext = user_info.ext,
        appname = E.Sysinfo.app_name(),
        client_params = "ext info"
    }

    body.authorized_infos = authorized_infos

    E.LOG.debug(TAG, "before grant >>")
    E.log(authorized_infos)

    --E.log(body)
    -- 这里用下发参数控制走不走加签的流程
    local opt = {}
    opt.enable_sign_headers_for_request = true -- request的加签默认开启
    opt.enable_sign_headers_for_response = EG.check_if_prevent_replay_status_open()

    gangplank_api:post(gangplank_v2_api('/qrcode/login/authorize'), {}, body, opt,  cb)
end

return M
