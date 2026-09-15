local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'ejoysdk_json'

local M = {}
local JSON

-- cjson非这里实现，而是ejoysdk_cjson.lua, 参考ejoysdk_lua_cjson, 如果需要全局使用cjson，可以使用 enable_cjson(true)方法
-- 注意替换_ejoysdk_lua_cjson时留意 { [0] = 0 } 的特殊使用地方都需要考虑是否修改

-- 项目组在初始化前调用ejoysdk_json方法，会报lua异常，所以需要判断一下_ejoysdk and _ejoysdk.log 是否存在
if _ejoysdk and _ejoysdk.log then
    _ejoysdk.log(TAG .. "#using lunajson as json-parser")
end
JSON = require 'ejoysdk_lua.libs.lunajson'
M['newArray'] = function()
    return { [0] = 0 }
end
M['is_cjson'] = false

local cjsonEncodeEmptyTableAsArray = function(json_, ...)
    
    if JSON.encode_empty_table_as_array then
        JSON.encode_empty_table_as_array(true)
    end

    local ok, result = pcall(JSON.encode, json_, ...)

    if JSON.encode_empty_table_as_array then
        JSON.encode_empty_table_as_array(false)
    end

    if ok then
        return result
    else
        return nil
    end
end

local encodeWithOptionFunction = function(json_, opts, ...)

    if M['is_cjson'] and opts and opts.encode_empty_array then
        return cjsonEncodeEmptyTableAsArray(json_, ...)
    end

    local ok, result = pcall(JSON.encode, json_, ...)
    if ok then
        return result
    else
        return nil
    end
end

local encodeFunction = function(json_, ...)
    local ok, result = pcall(JSON.encode, json_, ...)
    if ok then
        return result
    else
        return nil
    end
end

M['encode'] = encodeFunction
M['safe_encode'] = encodeFunction

local decodeFunction = function(json_, ...)
    if json_ == '' then
        return nil
    else
        local ok, result = pcall(JSON.decode, json_, ...)
        if ok then
            return result
        else
            return nil
        end
    end
end

M['safe_decode'] = decodeFunction
M['decode'] = decodeFunction

-- 支持空table encode成数组
-- eg:
-- local _json = JSON.newArray()
-- local encode_str = JSON.encode_with_option(_json, { encode_empty_array = true })
M['encode_with_option'] = encodeWithOptionFunction

-- 是否全局使用cjson
function M.enable_cjson(_enable)

    local version_support = false
    if _ejoysdk_lua_cjson and _ejoysdk_lua_cjson.is_support_global then -- luacheck: ignore
        version_support = _ejoysdk_lua_cjson.is_support_global() -- luacheck: ignore
    end
        
    if not version_support then
        if _ejoysdk and _ejoysdk.log then
            _ejoysdk.log(TAG .. "#native version not support global cjson")
        end
        -- 全局cjson需要解决和luajson统一输出的问题，需要更新到支持版本
        return
    end

    if _ejoysdk and _ejoysdk.os and _ejoysdk.os() == 'android' then
        local E = require "ejoysdk_lua.ejoysdk"
        local os_version = E.Sysinfo.os_version() or ''
        local os_version_number = tonumber(os_version) or 20 -- 如拿不到就默认支持
        if os_version_number <= 19 then -- Android 4.4 兼容问题不适用
            _enable = false
        end
    end

    if _enable and _ejoysdk_lua_cjson then -- luacheck: ignore
        JSON = _ejoysdk_lua_cjson -- luacheck: ignore
        M['newArray'] = function()
            return {}
        end
        M['is_cjson'] = true
        
        if _ejoysdk and _ejoysdk.log then
            _ejoysdk.log(TAG .. "#using cjson as json-parser")
        end
    else
        JSON = require 'ejoysdk_lua.libs.lunajson'
        M['newArray'] = function()
            return { [0] = 0 }
        end
        M['is_cjson'] = false
    end

    -- 重新赋值一下
    M['encode'] = encodeFunction
    M['safe_encode'] = encodeFunction
    M['safe_decode'] = decodeFunction
    M['decode'] = decodeFunction
    M['encode_with_option'] = encodeWithOptionFunction
end

return M
