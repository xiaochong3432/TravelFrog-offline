-- 无状态，提供协议相关定义，如错误码，关键字，编解码Header的方法等
local assert = assert
local error = error
local string = string
local table = table
local tostring = tostring
local compat = require 'ejoysdk_lua.compat.ejoysdk_compat'
local bitutil = compat.bitutil
local compat_string = compat.string
local EM = require "ejoysdk_lua.ejoysdk_module"

local _TAG = EM.MODULE.CHAT .. 'protocol'

local M = {}

M.StatusSucceed                = 0
M.StatusUnknown                = 1
M.StatusCanceled               = 2
M.StatusBadRequest             = 40
M.StatusMethodNotFound         = 41
M.StatusCodecNotSupported      = 42
M.StatusInternalServerError    = 50


local ktt = {} -- key type table
ktt[1] = "codec";        ktt["codec"]           = 1
ktt[2] = "method";       ktt["method"]          = 2
ktt[3] = "session";      ktt["session"]         = 3
ktt[4] = "code";         ktt["code"]            = 4
ktt[5] = "error";        ktt["error"]           = 5
ktt[6] = "timestamp";    ktt["timestamp"]       = 6
ktt[7] = "trace";        ktt["trace"]           = 7
ktt[8] = "destination";       ktt["destination"]      = 8
ktt[9] = "source";            ktt["source"]           = 9
ktt[10] = "fragment";    ktt["fragment"] = 10
ktt[11] = "content_encoding"; ktt["content_encoding"] = 11

local vtt = {} -- value type table
vtt[1] = "json";         vtt["json"]            = 1
vtt[2] = "sproto";       vtt["sproto"]          = 2
vtt[3] = "protobuf";     vtt["protobuf"]        = 3
vtt[4] = "raw";          vtt["raw"]             = 4
vtt[5] = "0";            vtt["0"]               = 5
vtt[6] = "deflate";      vtt["deflate"]         = 6

local function encode_key(k)
    k = tostring(k)
    local kt = ktt[k]
    if kt then
        return compat_string.pack("B", bitutil.bor(0x80, kt))
    else
        local lenk = #k
        assert(lenk < 0x7f, "key length larger than 127: ".. k)
        return compat_string.pack(">s1", k)
    end
end

local function encode_value(v)
    v = tostring(v)
    local vt = vtt[v]
    if vt then
        return compat_string.pack("B", bitutil.bor(0x80, vt))
    else
        local lenv = #v
        if lenv < 0x40 then
            return compat_string.pack(">s1", v)
        elseif lenv < 0x4000 then
            return compat_string.pack(string.format(">BBc%s", lenv), bitutil.bor(0x40, bitutil.rshift(lenv, 8)), bitutil.band(lenv, 0xff), v)
        else
            error(string.format("Not supported string length, %s", v))
        end
    end
end

function M.encode_header(header)
    local packlist = {}
    for k, v in pairs(header) do
        table.insert(packlist, encode_key(k))
        table.insert(packlist, encode_value(v))
    end
    return table.concat(packlist)
end

local function decode_key(chunk, pos)
    local key, byte, _
    byte, _ = compat_string.unpack("B", chunk, pos)
    if bitutil.band(byte, 0x80) == 0 then -- string
        key, pos = compat_string.unpack(">s1", chunk, pos)
    elseif bitutil.band(byte, 0x80) == 0x80 then -- static table
        byte, pos = compat_string.unpack("B", chunk, pos)
        key = ktt[bitutil.band(byte, 0x7f) ]
    else
        error "not supported key format"
    end
    return key, pos
end

local function decode_value(chunk, pos)

    -- https://yuque.antfin-inc.com/gserver/srpc/afxis0#4a1b3912 srpc协议解析
    local len, value, byte, _
    byte, _ = compat_string.unpack("B", chunk, pos)
    if bitutil.band(byte, 0xc0) == 0 then
        len, pos = compat_string.unpack("B", chunk, pos)
        -- bugfix: 兼容lua 5.1, 5.1不支持c0的unpack
        if len == 0 then
            value = ''
        else
            value, pos = compat_string.unpack(string.format(">c%s", len), chunk, pos)
        end
    elseif bitutil.band(byte,  0xc0)  == 0x40 then
        local i1, i2
        i1, i2, pos = compat_string.unpack("BB", chunk, pos)
        len  = bitutil.lshift(bitutil.band(i1, 0x3f), 8) + i2
        value, pos = compat_string.unpack(string.format(">c%s", len), chunk, pos)
    elseif bitutil.band(byte, 0x80) == 0x80 then
        byte, pos = compat_string.unpack("B", chunk, pos)
        value = vtt[bitutil.band(byte, 0x7f) ]
    else
        error "not supported value format"
    end
    return value, pos
end

function M.decode_header(chunk)
    local header = {}
    local pos = 1
    while pos < #chunk do
        local key, value
        key, pos = decode_key(chunk, pos)
        value, pos = decode_value(chunk, pos)
        header[key] = value
    end
    return header
end

return M