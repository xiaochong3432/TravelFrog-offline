local E = require 'ejoysdk_lua.ejoysdk'
local JSON = require "ejoysdk_lua.ejoysdk_json"
local CONSTANTS = require 'ejoysdk_lua.ejoysdk_constants'
local ERROR_CODES = CONSTANTS.QRCODE_ERROR_CODES
local EM = require "ejoysdk_lua.ejoysdk_module"
local QL = require "ejoysdk_lua.ejoysdk_qualitylog"

local M = {}

local CODE_DENY_CAMERA_PERMISSION = 74003001

local CODE_PARSE_QRCODE_ERROR = 74003002

local CODE_QRCODE_TYPA_NOT_SUPPORT = 74003003

local TAG = EM.MODULE.QRCODE .. 'ejoysdk_qrcode'

local qr_modules = {}

function M.register_qr_module(qr_type, module)
    qr_modules[qr_type] = module
end

--qr_info = {
--    type = '',
--    uuid = '',
--    product = ''
--}

M.SCAN_TYPE = {
    LOGIN = "login",
    LOGIN_V2 = "login_v2", -- 新版本扫码接口，轮询接口不返回ejoy_token，只返回ptoken，sdk自己做acquire处理
    LOGIN_OLD = "LOGIN", -- 兼容旧版本生成的二维码
    BBS = "bbs",
    OFFICIAL_SCAN_LOGIN = "official_scan_login" -- 海外扫码登录，H5页面来承载
}

do
    M.register_qr_module(M.SCAN_TYPE.LOGIN, require 'ejoysdk_lua.qrcode.login')
    M.register_qr_module(M.SCAN_TYPE.LOGIN_OLD, require 'ejoysdk_lua.qrcode.login') -- 兼容旧版本生成的二维码
    M.register_qr_module(M.SCAN_TYPE.LOGIN_V2, require 'ejoysdk_lua.qrcode.login_v2')
    M.register_qr_module(M.SCAN_TYPE.BBS, require 'ejoysdk_lua.qrcode.bbs')
    M.register_qr_module(M.SCAN_TYPE.OFFICIAL_SCAN_LOGIN, require 'ejoysdk_lua.qrcode.ejoysdk_h5_scan_login')
end

local function check_qr_func_support(type, func_name, cb)
    local qr_module = qr_modules[type]
    local has_module_func = qr_module and qr_module[func_name]
    if not has_module_func then
        if cb then
            cb(false, ERROR_CODES.CODE_NOT_SUPPORT_TYPE, 'not support type')
        end

        return false
    else
        if qr_module.check_support_scan then
            local result = qr_module.check_support_scan()
            if result and not result.is_support and result.fallback_type then
                return true, result.fallback_type
            end
        end

        return true, type
    end
end

local cur_show_qr_info
local cur_scan_qr_info

local function dispatch_qr_info(qr_info, cb)
    -- 如果有 product id，检查 product id 是否正确
    if qr_info.product and qr_info.product:lower() ~= E.CONFIG.get_config('product'):lower() then
        cb(false, ERROR_CODES.CODE_WRONG_PRODUCT, 'wrong product, qr:' .. tostring(qr_info.product) .. ", config:" .. tostring(E.CONFIG.get_config('product')))
        return
    end

    local is_support, qr_type = check_qr_func_support(qr_info.type, 'scan_handler', cb)
    E.LOG.debug(TAG, "dispatch_qr_info check_qr_func_support result:" .. tostring(is_support) .. ", type:" .. tostring(qr_type))
    if not is_support then
        local LANG = require 'ejoysdk_lua.lang.util'
        E.Toast.show(LANG.getString('qrcode_dispatch_fail', 'QR code recognition failed, please check the content of the QR code'), { use_native = true })
        cb(false, CODE_QRCODE_TYPA_NOT_SUPPORT, 'qrcode type not support')
        return
    end

    cur_scan_qr_info = qr_info
    qr_modules[qr_type].scan_handler(qr_info, cb)
end

local function parse_json(content)
    -- 检测是否旧版 JSON
    local decode_succ, result = pcall(JSON.decode, content)
    E.LOG.debug(TAG, 'parse_json succ?: ' .. tostring(decode_succ))
    if decode_succ then
        if type(result) ~= 'table' or not result.uuid or not result.type then
            --cb(false, ERROR_CODES.CODE_WRONG_JSON, 'no result.uuid or no result.type')
            return false, ERROR_CODES.CODE_WRONG_JSON, 'no result.uuid or no result.type'
        else
            local qr_info = {
                type = result.type,
                uuid = result.uuid
            }
            return true, qr_info
        end
    else
        return false
    end
end

--解析扫码的url里的业务信息
local function generate_qr_info_by_url_business(path, query)
    local params = E.Utils.split_string(path, '/')

    --扫码登录业务解析
    if params[1] == 'user' and params[2] == 'login' then
        local uid = query.uid
        if uid == nil or uid == '' then
            return false
        end
        local qr_info = {
            type = 'official_scan_login',
            uuid = uid
        }
        return qr_info
    end

    local params_size = #params
    -- 新的扫码协议的格式为 https://domain/<param1>/<product_code>/<params3>?u=<uuid>
    -- path里面：
    -- params1+ productcode + params3 代表一个服务
    -- params1 和 param3之间的是product_code
    -- query里面 u 为uuid
    if params_size >= 3 then
        local _product = params[2]
        local _uuid = query.u

        local qr_info = {
            uuid = _uuid,
            product = _product
        }

        if params[1] == "gangplank" and params[3] == "login" then
            local qr_type = M.SCAN_TYPE.LOGIN_V2
            qr_info.type = qr_type

            return qr_info
        end
    end

    --兼容旧版本行为
    local qr_type = params[1]
    local product = params[2]
    local uuid = query.u
    if not qr_type or not product or not uuid then
        return nil
    end
    local qr_info = {
        type = qr_type,
        uuid = uuid,
        product = product
    }
    return qr_info
end

local function parse_url(content)
    -- 尝试按 http url，解析扫码 content
    E.LOG.debug(TAG, 'parse_url, content: ' .. tostring(content))
    local url_info = E.HTTP.parse(content)
    E.LOG.debug(TAG, 'parse_url, url_info')
    E.LOG.debug(TAG, url_info)
    if url_info == nil or url_info.host == nil or url_info.path == nil or url_info.query == nil then
        return false, ERROR_CODES.CODE_WRONG_URL, 'wrong url'
    end
    --local host = url_info.host -- 校验 host
    local query = url_info.query
    local path = url_info.path
    local qr_info = generate_qr_info_by_url_business(path, query)
    if not qr_info then
        return false, ERROR_CODES.CODE_WRONG_URL_PARAMS, 'wrong url params'
    end
    return true, qr_info
end



local function parse_qrcode(content)
    -- 检测是否旧版 JSON
    local parse_succ, qr_info = parse_json(content)
    E.LOG.debug(TAG, '扫码解析 json 成功？' .. tostring(parse_succ))
    if parse_succ then
        return true, qr_info
    end

    -- 尝试按 http url，解析扫码 content
    return parse_url(content)
end

--for游戏，调用扫码, 带隐私合规权限申请流程
function M.qrcode_scan_with_permission_dialog(cb)
    M.detect_camera_permission(function(succ)
        if succ then
            --相机授权成功，调用扫码
            M.qrcode_scan(cb)
        else
            --授权失败
            cb(false, CODE_DENY_CAMERA_PERMISSION, 'has no camera permission!')
        end
    end)
end

--h5用户中心调用扫码功能
function M.h5_qrcode_scan()
    --关闭webview再调扫码，ios不支持在webview界面存在时拉起扫码
    E.WebView.close()
    M.detect_camera_permission(function(succ)
        --授权成功才打开扫码功能
        if succ then
            M.qrcode_scan(function(scan_succ, ...)
                if scan_succ then
                    E.LOG.debug(TAG, 'scan qrcode succ, now start grant')
                    M.grant_qrcode(function(grant_succ, ...)
                        if grant_succ then
                            E.LOG.debug(TAG, 'qrcode grant succ')
                        else
                            local error_code, error_msg = ...
                            E.LOG.debug(TAG, 'error_code: ' .. tostring(error_code) .. ' ,error_msg: ' .. tostring(error_msg))
                        end
                    end)
                end
            end)
        end
    end)
end

function M.detect_camera_permission(cb)
    if (E.Permission.support_compliance_check()) then
        local permissions_android = {
            ["android.permission.CAMERA"] = {}
        }

        local permissions_ios = {
            ['NSCameraUsageDescription']={}
        }
        local permissions = permissions_android;
        if _ejoysdk.os() == "ios" then
            permissions = permissions_ios
        end
        local options = {
            ['permissions'] = permissions
        }
        E.Permission.check_permission_v3(options,function(succ)
            -- 点击按钮回调
            if succ then
                -- 授权成功，可以继续调用接口
                cb(true)
            else
                -- 授权失败
                cb(false)
            end
        end)
    else
        --不支持调用授权检测的api，直接调用扫码功能
        cb(true)
    end
end

function M.qrcode_scan(cb)
    QL.commit_action_main('ej_qrcode_scan')
    E.qrcode_scan(function(succ, ...)
        if succ then
            QL.commit_action_main('ej_qrcode_scan_result', nil, true)
            local content = ...
            E.LOG.debug(TAG, '扫码 info: ' .. tostring(content))
            if content == nil or content == '' then
                cb(false, CONSTANTS.QRCODE_ERROR_CODES.CODE_EMPTY_CONTENT, 'empty qrcode content')
                return
            end

            local parse_succ, qr_info, msg = parse_qrcode(content)
            if parse_succ then
                dispatch_qr_info(qr_info, cb)
            else
                local LANG = require 'ejoysdk_lua.lang.util'
                E.Toast.show(LANG.getString('qrcode_dispatch_fail', 'QR code recognition failed, please check the content of the QR code'), { use_native = true })
                cb(false, CODE_PARSE_QRCODE_ERROR, msg, content)
            end
        else
            local error_code, error_msg = ...
            error_code = error_code or CONSTANTS.QRCODE_ERROR_CODES.CODE_SCAN_ERROR
            error_msg = error_msg or ''
            E.LOG.debug(TAG, 'qrcode scan fail: ' .. tostring(-error_code) .. tostring(error_msg))
            local params = {
                code = error_code,
                msg = error_msg
            }
            QL.commit_action_main('ej_qrcode_scan_result', nil, false, params)
            cb(false, -error_code, error_msg, '')
        end
    end)
end

function M.grant_qrcode(cb)
    if not cur_scan_qr_info then
        cb(false, ERROR_CODES.CODE_NO_SCAN, 'no qr info')
        return
    end

    local is_support, qr_type = check_qr_func_support(cur_scan_qr_info.type, 'grant_qrcode', cb)
    E.LOG.debug(TAG, "grant_qrcode check_qr_func_support result:" .. tostring(is_support) .. ", type:" .. tostring(qr_type))
    if not is_support then
        E.LOG.warn(TAG, "grant_qrcode not support")
        return
    end

    qr_modules[qr_type].grant_qrcode(cur_scan_qr_info.uuid, cb)
end

function M.query_status(cb)
    if not cur_show_qr_info then
        cb(false, ERROR_CODES.CODE_NO_QRCODE, 'no qr code')
        return
    end

    local is_support, qr_type = check_qr_func_support(cur_show_qr_info.type, 'query_status', cb)
    E.LOG.debug(TAG, "query_status check_qr_func_support result:" .. tostring(is_support) .. ", type:" .. tostring(qr_type))
    if not is_support then
        E.LOG.warn(TAG, "query_status is not support")
        return
    end

    qr_modules[qr_type].query_status(cur_show_qr_info.uuid, cb)
end

function M.cancel_query_status()
    if not cur_show_qr_info then
        return
    end

    local is_support, qr_type = check_qr_func_support(cur_show_qr_info.type, 'cancel_query_status')
    E.LOG.debug(TAG, "cancel_query_status check_qr_func_support result:" .. tostring(is_support) .. ", type:" .. tostring(qr_type))
    if not is_support then
        E.LOG.warn(TAG, "cancel_query_status not support")
        return
    end

    qr_modules[qr_type].cancel_query_status()
    cur_show_qr_info = nil
end

function M.show_qrcode(content)
    E.invoke('SHOW_QRCODE', {content = content})
end

function M.gen_qrcode_bmp(content)
    return E.QRCode.gen_bmp(content)
end

function M.get_qrcode(type, cb)
    local is_support, qr_type = check_qr_func_support(type, 'get_qrcode', cb)
    E.LOG.debug(TAG, "get_qrcode check_qr_func_support result:" .. tostring(is_support) .. ", type:" .. tostring(qr_type))
    if not is_support then
        E.LOG.warn(TAG, "get_qrcode failed, not support")
        return
    end

    qr_modules[qr_type].get_qrcode(function(succ, ...)
        if succ then
            local content = ...
            local parse_succ, qr_info, msg = parse_qrcode(content)
            if parse_succ then
                cur_show_qr_info = qr_info -- 记录 qr_info，用于 query_status
                E.LOG.debug(TAG, 'cur_show_qr_info')
                E.LOG.debug(TAG, cur_show_qr_info)
                cb(true, content) -- callback qrcode_content
            else
                local error_code = qr_info
                cb(false, error_code, msg)
            end
        else
            cb(false, ...)
        end
    end)
end

return M