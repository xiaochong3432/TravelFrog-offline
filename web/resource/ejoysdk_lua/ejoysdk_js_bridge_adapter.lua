local E = require 'ejoysdk_lua.ejoysdk'
local EM = require "ejoysdk_lua.ejoysdk_module"
local unpack = table.unpack or unpack

--对接notifyLua#lua_call
local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'js_bridge_adapter'

local M = {}
M.VER = {
    V1 = 'v1', -- 直接调用并返回所有结果
    V2 = 'v2'  -- 直接调用并封装成table { succ = s, body = {}}
}

local function get_module(module_name)
    if module_name then
        if not( E.Utils.start_with(module_name,'sdk_test') or E.Utils.start_with(module_name,'ejoysdk_lua')) then
            module_name = 'ejoysdk_lua.' .. tostring(module_name)
        end
        return require(tostring(module_name))
    else
        return nil
    end

end

local _id_to_function = {}



local function callback_function(func_id, callback_params, use_output2)
    if use_output2 then
        if M.output2 then
            --E.log(callback_params)
            M.output2(func_id, callback_params)
        end
    else
        if M.output then
            M.output(func_id, callback_params)
        end
    end
end

local function return_function(func_id, return_params, use_output2)
    return callback_function(func_id, return_params, use_output2)
end

local function create_callback_function(_module, _func, func_id, use_output2)
    local callback = function(...)
        local ret = ... -- 有可能是一个table（对接js的协议），有可能是多个参数（普通任意调用）
        if (type(ret) ~= 'table' or  ret.ver ~= M.VER.V2) then
            ret = { ... }
        end
        callback_function(func_id, ret, use_output2)
    end
    return callback
end

-- TODO: param 的 key 是 function 格式
local function parse_function_param(module_name, func_name, param, use_output2)
    local param_type = type(param)
    if param_type == 'table' then
        local func_id = param._func_id
        if func_id then
            local callback_func = create_callback_function(module_name, func_name, func_id, use_output2)
            _id_to_function[func_id] = callback_func
            param = callback_func
        else
            for key, value in pairs(param) do
                param[key] = parse_function_param(module_name, func_name, value, use_output2)
            end
        end
    end
    return param
end

local function parse_function(module_name, body, use_output2)
    local module = get_module(module_name)
    local func_name = body['function']

    if func_name and module then
        local invoke_fun = module
        string.gsub(func_name, '[^\\.]+', function(w)
            invoke_fun = invoke_fun[w]
        end)

        if invoke_fun and type(invoke_fun) == 'function' then
            local params = body['params'] or {}
            local sync_call = body['syncCall'] or false

            -- 对 JSON 协议的参数做转化，把函数类型参数解析出来
            -- func_params 才是调用 lua 的真正参数
            local func_params = {}
            for i, param in ipairs(params) do
                if type(param) == 'table' then
                    func_params[i] = parse_function_param(module_name, func_name, param, use_output2)
                else
                    func_params[i] = param
                end
            end

            local call_result = { pcall(invoke_fun, unpack(func_params)) }
            local ok = call_result[1]
            local result = {}

            if ok then
                if sync_call then
                    local func_id = params['_func_id'] or ''
                    for _, param in ipairs(params) do
                        if type(param) == 'table' and param._func_id then
                            func_id=param._func_id
                        end
                    end
                    if #call_result > 1 then
                        for i = 2, #call_result do
                            table.insert(result, call_result[i])
                        end
                        E.LOG.debug(TAG, 'return params count: ' .. tostring(#result))
                    end
                    return_function(func_id, result, use_output2)
                end
            else
                E.LOG.warn(TAG, '调用函数失败, module: ' .. tostring(module_name) .. ', function: ' .. tostring(func_name) .. ', error: ' .. tostring(call_result[2]))
            end
        end
    end
end

-- 判断顺序如下
-- 1. module
-- 2. function(params)
-- 3. variable
local function parse_call(body, use_output2)
    E.LOG.debug(TAG, 'lua adapter input(plain): ' .. tostring(body))
    if not body or type(body) ~= 'table' then
        return
    else
        local module_name = body['module']
        -- module 可以按 ejoysdk_lua.${module}.ejoysdk_${moudle} 的格式搜索
        if not module_name or not get_module(module_name) then
            return
        end
        parse_function(module_name, body, use_output2)
        --parse_variable(module_name, body)
    end
end

local function parse_call2(body)
    parse_call(body, true)
end

M.input = parse_call
M.output = nil
M.input2 = parse_call2
M.output2 = nil

return M
