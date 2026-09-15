-- 这个是海外扫码用的vendor，用H5来展示账号中心的二维码，PC上被扫码成功后H5给把ptoken给到lua来进行acquire流程
local E = require 'ejoysdk_lua.ejoysdk'
local HTTP = E.HTTP
local Vendor = require 'ejoysdk_lua.vendors.vendor'
local ET = require 'ejoysdk_lua.ejoysdk_topic'
local EM = require "ejoysdk_lua.ejoysdk_module"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local QR_LOGIN_VENDOR_NAME = 'QR_LOGIN'
local QR_LOGIN = Vendor:Inherit(QR_LOGIN_VENDOR_NAME)

local TAG = EM.MODULE.VENDORS.QR_LOGIN_ACC

local cb_handler_info = {}

local function is_type_for_qr_login(url)
    local ret = HTTP.parse(url)
    E.LOG.debug(TAG, ret)
    if ret.query and ret.query.type then
        local type = ret.query.type
        if type ~= 'qr_login' then
            return false
        end
    end
    return true
end

local function cb_handler(succ, token, new_nonce, _new_state, login_type)
    local nonce = cb_handler_info.nonce

    -- browser 下，可能游戏退出了，导致nonce变成了初始化的nil
    if not succ then
        local error_info = token
        QR_LOGIN.opt.auth_listener(false, error_info)
    elseif (nonce and new_nonce ~= nonce) then
        E.LOG.debug(TAG,'nonce: ' .. tostring(nonce) .. ' nonce cb: ' .. tostring(new_nonce))
        QR_LOGIN.opt.auth_listener(false, {code = CONSTANTS.QR_LOGIN_ERROR_CODES.CODE_NONCE_ERROR, msg = 'nonce error'})
    else
        QR_LOGIN.opt.auth_listener(true, {ptoken = token,platform = QR_LOGIN_VENDOR_NAME, ext = {thirdparty_type = login_type}}, {})
    end
end

local function on_url(url)
    local ret = HTTP.parse(url)
    if ret.host == 'sdk.ejoy.com' and ret.query then
        local query = ret.query
        if query.access_token and query.nonce and query.state then
            --登录成功回调
            cb_handler(true, query.access_token, query.nonce, query.state, query.login_type)
        else
            E.LOG.warn(TAG, 'query error')
            cb_handler(false, {code = CONSTANTS.QR_LOGIN_ERROR_CODES.CODE_OAUTH_FAILED, msg = 'ouath error callback url'})
        end
    end
end

local function on_login_done(value)
    E.LOG.debug(TAG, 'h5 on_login_done---')
    E.log(value)

    if not is_type_for_qr_login(value.args.uri) then
        E.LOG.debug(TAG, 'type 不是 qr_login，直接返回')
        return
    end
    --校验登录后返回的信息
    on_url(value.args.uri)
end

function QR_LOGIN.init(opt, cb)
    QR_LOGIN.opt = opt

    ET.subscribe('logindone', on_login_done)

    -- callback init success
    cb(true)
end

function QR_LOGIN.login()
    E.LOG.debug(TAG, 'call qrcode login')
end

function QR_LOGIN.check_token(_outsource, _info)
    QR_LOGIN.login()
end

function QR_LOGIN.logout()
    QR_LOGIN.opt.logout_listener({})
end

function QR_LOGIN.merge_info(info, pinfo)
    return QR_LOGIN.merge_helper(info, pinfo)
end

function QR_LOGIN.simple_token()
    return false
end

QR_LOGIN:is_implemented({'ACCOUNT'})


return QR_LOGIN