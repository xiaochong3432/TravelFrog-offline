local E = require 'ejoysdk_lua.ejoysdk'
local Class = require "ejoysdk_lua.ejoysdk_class"
local EM = require "ejoysdk_lua.ejoysdk_module"
local EJ_SIGN = require "ejoysdk_lua.libs.signature"

-- 支持功能
-- 1. GET、POST 请求
-- 2. 自定义 header、params
-- 3. 使用 ejoy-token、moment-token
local M = Class:Inherit('SERVER_BASE_API')
local HTTP = E.HTTP

local TAG = EM.MODULE.LIBS .. 'base_api'

M.CT_URLENCODED = HTTP.CT_URLENCODED
M.CT_JSON = HTTP.CT_JSON
M.CT_FORMDATA = HTTP.CT_FORMDATA

local default_content_type = M.CT_JSON -- SDK 默认的 content-type，如需修改，通过 headers 参数传入
local default_acceptable = M.CT_JSON -- SDK 默认支持的服务端返回 content-type，目前只支持 application/json，服务器也只会返回 JSON
local CONTENT_TYPE = 'Content-Type'

local function create_http_params(headers, opt)
    local params = {
        trace = opt.trace,
        headers = headers
    }
    params.headers[CONTENT_TYPE] = headers[CONTENT_TYPE] or default_content_type
    if opt.use_ejoy_token then
        local EG = require 'ejoysdk_lua.ejoysdk_gangplank'
        params.headers['Ejoy-Token']= EG.user_info().token
    end
    if opt.use_moment_token then
        local HOLO = require 'ejoysdk_lua.ejoysdk_holo'
        local m_token = HOLO.get_player_token()
        params.headers['moment-Token'] = m_token

        -- rpc调用底层会检测是否需要加签
    end

    params.enable_sign_headers_for_request = opt and opt.enable_sign_headers_for_request or false
    params.enable_sign_headers_for_response = opt and opt.enable_sign_headers_for_response or false

    params.acceptable = default_acceptable
    return params
end

local function create_http_resp_handler(cb)
    return function(resp)
        --E.LOG.debug(TAG, resp)
        if resp.status == 200 then -- HTTP code
            if (resp.body and resp.body.code == 0) or (resp.body and resp.body.code == 200) then -- 平台 code，0 和 200 可视为成功
                cb(true, resp.body)
            else
                -- 服务接口层，需要拿到完整的body
                cb(false, resp.body and resp.body.code, resp.body and resp.body.message, resp.body)
            end
        else
            cb(false, resp.status, 'HTTP error')
        end
    end
end

-- api : 接口 api 路径
-- headers : HTTP headers : table 类型
-- params : HTTP post body : table 类型
-- opt : 拓展设置，目前支持:
--  opt.use_ejoy_token : boolean 类型，是否使用 ejoy-token
--  opt.use_moment_token : boolean 类型，是否使用 moment-token
--  opt.trace : boolean 类型，是否经分日志跟踪
--  opt.acceptable : SDK 支持的解析类型，目前只有 CT_JSON
function M:post(api, headers, body, opt, cb)
    assert(api, 'base server post request, api is nil!')
    local url = E.CONFIG.get_config(self.service) .. api
    headers = headers or {}
    body = body or {}
    opt = opt or {}

    local params = create_http_params(headers, opt)
    local handler = create_http_resp_handler(cb)
    
    --底层HTTP打印了
    --E.LOG.debug(TAG, 'post url: ' .. tostring(url))
    --E.LOG.debug(TAG,'log headers: \n')
    E.LOG.debug(TAG, params.headers)
    --E.LOG.debug(TAG,'log body: \n')
    --E.LOG.debug(TAG, body)
    HTTP.post(url, params, params.headers[CONTENT_TYPE], body, handler)
end

-- api : 接口 api 路径
-- headers : HTTP headers, table 类型
-- query : HTTP get query, table 类型
-- opt : 拓展设置，目前支持:
--  opt.use_ejoy_token : boolean 类型，是否使用 ejoy-token
--  opt.use_moment_token : boolean 类型，是否使用 moment-token
--  opt.trace : boolean 类型，是否经分日志跟踪
--  opt.acceptable : SDK 支持的解析类型，目前只有 CT_JSON
function M:get(api, headers, query, opt, cb)
    assert(api, 'base server get request, api is nil!')
    local url = E.CONFIG.get_config(self.service) .. api
    headers = headers or {}
    query = query or {}
    opt = opt or {}
    local url_query = HTTP.urlencode2(query)
    if url_query and url_query ~= '' then
        url = url .. "?" .. url_query
    end

    local params = create_http_params(headers, opt)
    local handler = create_http_resp_handler(cb)
    --底层HTTP打印了
    --E.LOG.debug(TAG, 'get url: ' .. tostring(url))
    --E.LOG.debug(TAG, 'log headers: \n')
    --E.LOG.debug(TAG, params.headers)
    HTTP.get(url, params, handler)
end

function M:save_secret(client_private, m_token, exchange_data, signature_versions)
    EJ_SIGN.save_secret(client_private, m_token, exchange_data, signature_versions)
end

function M:_init(service_name)
    assert(service_name, 'service_name empty!')
    self.service = service_name
    local CONFIG = require 'ejoysdk_lua.ejoysdk_config'
    CONFIG.register_service(self.service)
end

return M

