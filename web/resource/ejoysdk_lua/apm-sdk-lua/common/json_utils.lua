-------------------------------------------------------------------------------
-- Created Date: 2021.12.22
-- Author: 三傻
-- Desc:   json库二次封装 支持注册cjson库
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"

local M = {}
M.__index = M

local LOGGER = "apm_json_utils"

local _cjson_lib_path

-- 设置cjson解析库的链接
function M.set_cjson_lib_path(cjson_lib_path)
    if type(cjson_lib_path) == "string" and cjson_lib_path ~= "" then
        _cjson_lib_path = cjson_lib_path
        M.init()
    end
end

function M.init()
    local JSON
    if _cjson_lib_path then
        local ok, module = pcall(require, _cjson_lib_path)
        if ok and module and module.decode and module.encode then
            E.LOG.debug(LOGGER,"using cjson as json-parser, cjson_lib_path:" .. _cjson_lib_path)
            JSON = module
        end
    end
    if not JSON then
        E.LOG.debug(LOGGER,"using ejoysdk_json as json-parser")
        JSON = require "ejoysdk_lua.ejoysdk_json"
    end

    -- 经过测试，encode函数对不同类型的入参，都不会抛出异常，故不用加pcall  <-- 该注释引自EJOYSDK
    M["encode"] = JSON.encode

    local decodeFunction = function(json_str, ...)
        if json_str == "" then
            return nil
        else
            local ok, result = pcall(JSON.decode, json_str, ...)
            if ok then
                return result
            else
                return nil
            end
        end
    end

    M["safe_decode"] = decodeFunction
    M["decode"] = decodeFunction
end

return M
