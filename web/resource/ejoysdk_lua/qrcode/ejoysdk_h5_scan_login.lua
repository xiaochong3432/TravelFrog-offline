-- 海外扫码登录，H5页面承载，PC端用H5来生成展示二维码、轮询二维码授权状态，移动端用H5来授权登录，但移动端扫描二维码后校验二维码是否有效是lua的接口
local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"
local AEGIS_DATA = require 'ejoysdk_lua.aegis.aegis_collect_data'

local M = {}

local TAG = EM.MODULE.OFFICIAL_SCAN_LOGIN

local CODE_VERIFY_CODE_INVALID_RESP = 4001199
local CODE_GRANT_QRCODE_ERROR = 4001198

local grant_succ = false
local scan_qrcode_callback

function M.get_qrcode(_cb)
    E.LOG.debug(TAG, 'not support generate qrcode')
end

function M.cancel_query_status()
    E.LOG.debug(TAG, 'not support cancel_query_status')
end

function M.query_status()
    E.LOG.debug(TAG, 'not support query_status')
end

function M.grant_qrcode(_uuid, _cb)
    --扫码后前端页面处理
    E.LOG.debug(TAG, 'not support grant_qrcode')
end

local on_close_callback = function()
    --授权不成功的情况下关闭授权页，回调失败
    if not grant_succ and scan_qrcode_callback then
        scan_qrcode_callback(false, CODE_GRANT_QRCODE_ERROR, 'qrcode grant not succ and close grant page')
    end
end
-- 用于展示授权登录页面，会有一些文案和授权按钮
local function open_webview(url, append_start_up_data)
    local host = E.HTTP.parse(url).host
    local local_start_up_data = {
        aegis_data = AEGIS_DATA.get_encrypt_data(),
        ejoysdk_ver = E.get_sdk_version_name('EJOYSDK')
    }
    if append_start_up_data then
        for start_up_data_key, start_up_data_data in pairs(append_start_up_data) do
            local_start_up_data[start_up_data_key] = start_up_data_data
        end
    end
    --打开授权页
    grant_succ = false
    E.WebView.open(url, {[host] = { startupData = local_start_up_data, transparent = true }}, {
        compactMode= true,
        use_fragment = true,
        hide_close_btn = true
    }, nil, on_close_callback)
end

--拼装url的方式使用聚合页的方式
local function get_api_url(api)
    local OFFICIAL = require 'ejoysdk_lua.vendors.official'
    return OFFICIAL.get_api_url(api)
end

--生成request_id
local function get_request_id()
    math.randomseed(os.time())
    local random_mills = math.random(1, 1000)
    local sys_clock = os.time() * 1000
    local random_time_in_mills = sys_clock + random_mills
    E.LOG.debug(TAG, 'get_request_id :'.. tostring(random_time_in_mills) .. ', sys_clock:'.. tostring(sys_clock) ..', random_mills:' .. tostring(random_mills))
    return random_time_in_mills
end

local function verify_uid(uid, cb)
    local api = 'apiOfficial/user/scanQrCode'
    local url = get_api_url(api)
    local id = tostring(get_request_id())
    local param = {
        id = id,
        data = {
            code = uid
        }
    }
    E.LOG.debug(TAG, 'param is >>')
    E.log(param)
    E.HTTP.post(url, {}, E.HTTP.CT_JSON, param, function(resp)
        local LANG = require 'ejoysdk_lua.lang.util'
        if resp.status == 200 then
            if resp.body and resp.body.state and resp.body.state.code then
                E.LOG.debug(TAG, 'resp is >> ')
                E.log(resp)
                local resp_code = resp.body.state.code
                local msg = resp.body.state.msg
                if resp_code == 2000000 then
                    --服务端校验码后返回的数据
                    local data = resp.body.data
                    cb(true, data)
                else
                    if resp_code == 4001107 then
                        --二维码已失效
                        E.Toast.show(LANG.getString('qrcode_invalid', 'Qrcode Invalid'), { use_native = true })
                    else
                        --其他異常
                        E.Toast.show(LANG.getString('qrcode_server_exception', 'Qrcode Service Exception'), { use_native = true })
                    end
                    cb(false, resp_code, msg)
                end
            else
                E.Toast.show(LANG.getString('qrcode_server_exception', 'Qrcode Service Exception'), { use_native = true })
                cb(false, CODE_VERIFY_CODE_INVALID_RESP, 'response invalid')
            end
        else
            E.Toast.show(LANG.getString('qrcode_server_exception', 'Qrcode Service Exception'), { use_native = true })
            cb(false, resp.status, 'http error')
        end
    end)
end

--h5调用授权成功后调用
function M.h5_callback_grant_finish()
    grant_succ = true
    if scan_qrcode_callback then
        scan_qrcode_callback(true)
    end
end

--扫码后调用的方法
function M.scan_handler(qr_info, cb)
    --保存起来回调，等h5授权成功后返回
    scan_qrcode_callback = cb
    local uid = qr_info.uuid
    E.LOG.debug(TAG, 'qrcode scan uid is ' .. tostring(uid))
    --校验uid
    verify_uid(uid, function(succ, ...)
        if succ then
            E.LOG.debug(TAG, "qrcode login, verify uid succ")
            --校验成功，打开页面
            local api = 'm#/qrcode/login'
            local url = get_api_url(api)
            E.LOG.debug(TAG, 'qrcode login, grant page url is ' .. tostring(url))
            local data = ...
            local scan_data = {
                qr_server_data = data,
                uid = uid
            }
            --这里要h5授权后才回调
            open_webview(url, {scan_data = scan_data})
        else
            local code, msg = ...
            cb(false, code, msg)
            E.LOG.debug(TAG, 'qrcode login, verify uid fail, code is ' .. tostring(code) .. ', msg is ' .. tostring(msg))
        end
    end)
end

return M