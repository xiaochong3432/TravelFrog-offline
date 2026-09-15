local E = require "ejoysdk_lua.ejoysdk"
local EH = require "ejoysdk_lua.ejoysdk_holo"
local JSON = require "ejoysdk_lua.ejoysdk_json"
local protocol = require 'ejoysdk_lua.chat.ejoysdk_chat_protocol'
local LZ = _ejoysdk_crypt.zlib
local compat = require 'ejoysdk_lua.compat.ejoysdk_compat'
local string_pack, string_unpack, xpcall = compat.string.pack, compat.string.unpack, compat.xpcall
local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
local EM = require "ejoysdk_lua.ejoysdk_module"
local chat_token = require 'ejoysdk_lua.chat.ejoysdk_chat_token_util'
local chat_log = require 'ejoysdk_lua.ejoysdk_log_mgr'
local chat_log_util = require 'ejoysdk_lua.chat.ejoysdk_chat_log_util'


local TAG = EM.MODULE.CHAT .. 'data_pack'

local M = {}

M.DATA_PARTS = {
    RPC_HEADER = "rpc_header",
    CONTENT_HEADER = "content_header",
    CONTENT_BODY = "content_body"
}

M.ENCODING_TYPES = {
    DEFLATE = 'deflate'
}

local server_deflate_support = false

local rc4_send_key = nil
local rc4_recv_key = nil
-- 解压流对象
local inflate_stream = nil
local deflate_stream = nil

-- 是否首个rpc请求
local is_first_rpc_request = true

function M.init()
    local rc4_init_key = ''

    if chat_token.is_chat_token_valid() then
        chat_token.curr_login_version = chat_token.LOGIN_V2
        rc4_init_key = chat_token.get_chat_token_info_key()
        E.LOG.debug(TAG, '聊天登录协议V2:使用chat_token_key加密连接')
    end

    -- 如果秘钥无效，则使用moment_token加密
    if not rc4_init_key or #rc4_init_key == 0 then
        -- 不能使用V2，就使用V1
        chat_token.curr_login_version = chat_token.LOGIN_V1
        if EH.get_player_token_body() then
            rc4_init_key = EH.get_player_token_body().key
            E.LOG.debug(TAG, '聊天登录协议V1:使用moment_token加密连接')
        else
            E.LOG.debug(TAG, 'ejoy_chat_data_pack_init, ' .. 'token_is_nil')
            ESTAT.stat_error_with_limit(TAG, 'ejoy_chat_data_pack_init_token_is_nil', 'ejoy_chat_data_pack_init_token_is_nil', 'ejoy_chat_token_is_nil')
        end
    end

    rc4_send_key = _ejoysdk_crypt.rc4_key(rc4_init_key)
    rc4_recv_key = _ejoysdk_crypt.rc4_key(rc4_init_key)
end

local function prepare_content_header(content_header)
    if server_deflate_support then
        --E.LOG.debug(TAG, "pack_data server support deflate, now enable client deflate")
        content_header["content_encoding"] = M.ENCODING_TYPES.DEFLATE
    end

    --E.LOG.debug(TAG, "prepare_content_header >>")
    --E.log(content_header)

    local header_chunk = protocol.encode_header(content_header)
    return header_chunk
end

local function get_deflate_stream()
    if deflate_stream == nil then
        deflate_stream = LZ.deflate(LZ.DEFAULT_COMPRESSION, LZ.DEFAULT_WINDOWBITS)
    end

    return deflate_stream
end

local function prepare_content_body(content_body, options)
    local encode_content = JSON.encode_with_option(content_body, options)
    --E.LOG.debug(TAG, "prepare_content_body >>")
    --E.log(encode_content)

    local result_body = encode_content
    if server_deflate_support then
        --E.LOG.debug(TAG, "pack_data server support deflate, now deflate content_body")
        local deflated_content, _shrink_eof = get_deflate_stream()(encode_content, "sync")
        result_body = deflated_content
    end

    return result_body
end

local function append_first_rpc_header(encrypt_pack, rpc_header)
    local pack
    if is_first_rpc_request then
        is_first_rpc_request = false
        --E.LOG.debug(TAG, "append_first_rpc_header is first rpc request, append header")
        pack = string_pack('>s4', (rpc_header .. encrypt_pack))
        -- E.LOG.debug(TAG, '聊天登录协议:第1次发包')
    else
        --E.LOG.debug(TAG, "append_first_rpc_header NOT first rpc request, skip append header")
        pack = string_pack('>s4', encrypt_pack)
        -- E.LOG.debug(TAG, '聊天登录协议:非第1次发包')
    end

    return pack
end

function M.is_support_deflate()
    if _ejoysdk_crypt.zlib then
        --E.LOG.debug(TAG, "is_support_deflate true")
        return true
    else
        --E.LOG.warn(TAG, "is_support_deflate false")
        return false
    end
end

-- data 包含以下header和params信息：
-- rpc_header: rpc 请求的header，第一个请求需要
-- content_header: 应用方自己的header
-- content_body: 应用方参数
function M.pack_data(data, options)
    local rpc_header = data[M.DATA_PARTS.RPC_HEADER] or ''
    local content_header = data[M.DATA_PARTS.CONTENT_HEADER] or {}
    local content_body = data[M.DATA_PARTS.CONTENT_BODY] or {}

    -- prepare content_header
    local header_chunk = prepare_content_header(content_header)
    local prepared_content_body = prepare_content_body(content_body, options)

    local pack_list = {}
    table.insert(pack_list, string_pack('>I2', #header_chunk))
    table.insert(pack_list, header_chunk)
    table.insert(pack_list, prepared_content_body)
    local pack_body = table.concat(pack_list)

    local encrypt_pack = _ejoysdk_crypt.rc4_encrypt(pack_body, rc4_send_key)
    local pack_result = append_first_rpc_header(encrypt_pack, rpc_header)

    return pack_result
end

local function get_inflate_stream()
    if inflate_stream == nil then
        inflate_stream = LZ.inflate(LZ.DEFAULT_WINDOWBITS)
    end

    return inflate_stream
end

local function decrypt_messge(pack)
    pack = _ejoysdk_crypt.rc4_decrypt(pack, rc4_recv_key)
    local header_length = string_unpack('>I2', pack:sub(1,2))
    pack = pack:sub(3)
    local header_chunk = pack:sub(1, header_length)
    local header = protocol.decode_header(header_chunk)
    --local destination = header.destination
    --local session = header.session
    pack = pack:sub(header_length + 1)

    local content_encoding = header["content_encoding"]
    if content_encoding == M.ENCODING_TYPES.DEFLATE then
        --E.LOG.debug(TAG, "decrypt_messge server support deflate, and we init inflate")
        server_deflate_support = true
        pack = get_inflate_stream()(pack)
    end
    local msg = JSON.decode(pack)
    return header, msg
end

function M.unpack_data(pack)
    local ok, header, msg = xpcall(decrypt_messge, function (x)
        chat_log.warn(chat_log_util.header(),
                TAG,
                'decrypt_messge_has_error',
                {
                    lua_error_msg = tostring(x)
                },
                {})
    end, pack)
    return ok, header, msg
end

function M.reset()
    if deflate_stream then
        deflate_stream(nil, "finish")
    end

    if inflate_stream then
        inflate_stream(nil, "finish")
    end

    deflate_stream = nil
    inflate_stream = nil

    -- reset first request state
    is_first_rpc_request = true

    -- reset server deflate support
    server_deflate_support = false

    --E.LOG.debug(TAG, "reset complete!")
end

return M