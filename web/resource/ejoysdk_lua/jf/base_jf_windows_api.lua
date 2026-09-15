--负责上报经分消息
local E = require 'ejoysdk_lua.ejoysdk'
local JF_WINDOWS_CONFIG = require 'ejoysdk_lua.jf.jf_windows_config'
local JSON = require "ejoysdk_lua.ejoysdk_json"
local LZ = _ejoysdk_crypt.zlib
local EM = require "ejoysdk_lua.ejoysdk_module"
local TAG = EM.MODULE.JF .. "BASE_JF_WINDOWS_API"

local HTTP = E.HTTP

local M = {}

local function prepare_content_body(event_arr)
    local log_count = #event_arr
    E.LOG.debug(TAG, "jf_windows log count is " .. tostring(log_count))
    local encode_content = ''
    for index, event_log in ipairs(event_arr) do
        if index == log_count then
            encode_content = encode_content .. JSON.encode(event_log)
        else
            encode_content = encode_content .. JSON.encode(event_log) .. '\n'
        end
    end
    E.LOG.debug(TAG, "prepare_content_body >>")
    E.LOG.debug(TAG, encode_content)
    --gzip压缩
    local deflated_content, _shrink_eof = LZ.deflate(5, 31)(encode_content, "finish")
    return deflated_content
end

local function create_http_resp_handler(cb)
    return function(resp)
        -- 底层HTTP统一打印了
        --E.LOG.debug(TAG, resp)
        if resp.status == 200 then -- HTTP code
            local is_body_json_str = type(resp.body) == "string"
            local resp_body_obj = resp.body
            if is_body_json_str then
                resp_body_obj = JSON.safe_decode(resp.body)
            end
            if resp_body_obj and resp_body_obj.code == 0 then -- code=0为成功
                cb(true, resp.body)
            else
                -- 服务接口层，需要拿到完整的body
                local safe_resp_body_obj = resp_body_obj or {}
                cb(false, safe_resp_body_obj.code or -1, 'upload error')

                E.LOG.warn(TAG, "upload error")
            end
        else
            cb(false, resp.status, 'HTTP error')

            E.LOG.warn(TAG, "http error")
        end
    end
end

function M.upload(event_arr, cb)
    local api_server = JF_WINDOWS_CONFIG.get_api_server()
    if api_server then
        local content = prepare_content_body(event_arr)
        local form_data = E.HTTP.FormData.New()
        form_data:add_part('data', content, 'binary/octet-stream', false, 'xdata-log')
        local headers = {}
        headers['User-Agent'] = 'AGA'
        local params = {
            headers = headers
        }
        HTTP.post(api_server, params, form_data:content_type(), form_data:build(), create_http_resp_handler(cb))
    else
        E.LOG.warn(TAG, "jf api server is nil")
    end
end

return M