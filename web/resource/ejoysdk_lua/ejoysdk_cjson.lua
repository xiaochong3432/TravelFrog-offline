local EM = require "ejoysdk_lua.ejoysdk_module"

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'ejoysdk_cjson'

local M = {}
local JSON

if _ejoysdk_lua_cjson then -- luacheck: ignore
    JSON = _ejoysdk_lua_cjson -- luacheck: ignore
    M['newArray'] = function()
        return {}
    end
    M['is_cjson'] = true

    -- 暂不暴露避免全局影响API
    -- M['encode_sparse_array'] = JSON.encode_sparse_array
else
    -- 兼容旧版本
    _ejoysdk.log(TAG .. "#inner using lunajson as cjson-parser")
    JSON = require 'ejoysdk_lua.libs.lunajson'
    M['newArray'] = function()
        return { [0] = 0 }
    end
    M['is_cjson'] = false
end

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

local encodeFunction = function(json_, ...)
    local ok, result = pcall(JSON.encode, json_, ...)
    if ok then
        return result
    else
        return nil
    end
end

local encodeEmptyTableAsArray = function(json_, ...)
    
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

local prepareFunction = function()
    if _ejoysdk.os() == 'android' then
        local E = require "ejoysdk_lua.ejoysdk"
        local os_version = E.Sysinfo.os_version() or ''
        local os_version_number = tonumber(os_version) or 20 -- 如拿不到就默认支持
        -- Android 4.4 上cjson 有偶现崩溃，需要规避
        if os_version_number <= 19 then
            -- 兼容旧版本
            _ejoysdk.log(TAG .. "#inner using lunajson as cjson-parser (Android: " .. tostring(os_version_number) .. "<= 19)")
            JSON = require 'ejoysdk_lua.libs.lunajson'
            M['newArray'] = function()
                return { [0] = 0 }
            end
        end
    end
end

M['safe_decode'] = decodeFunction
M['safe_encode'] = encodeFunction
M['encode'] = encodeFunction
M['decode'] = decodeFunction
M['prepare'] = prepareFunction
M['encode_as_array'] = encodeEmptyTableAsArray

return M
