-------------------------------------------------------------------------------
-- Created Date: 2021.08.13
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local E_UTILS = require "ejoysdk_lua.ejoysdk_utils"
local TBUtils = require "ejoysdk_lua.apm-sdk-lua.common.tb_utils"

local LOGGER = "apm_utils"

local M = {}
M.__index = M

function M.table_tostring(...)
    return E_UTILS.log_util.table_tostring(...)
end

function M.table_size(data)
    local count = 0
    for _, _ in pairs(data) do
        count = count + 1
    end
    return count
end

-- 合并两个table，如果replacing为true，则直接覆盖base，否则生成一个新的table
function M.merge_table(base, advanced, replacing)
    if base == nil then
        return advanced
    end
    if advanced == nil then
        return base
    end

    local t = replacing and base or E_UTILS.deepcopy(base)
    for k, v in pairs(advanced) do
        if t[k] == nil then
            t[k] = v
        elseif type(v) ~= type(t[k]) then
            -- 类型不匹配，保留base配置
            E.LOG.error(LOGGER, string.format("table merging error: types of %s are %s and %s", k, type(v), type(t[k])))
        elseif type(v) == "table" then
            -- 递归
            t[k] = M.merge_table(t[k], v)
        elseif t[k] ~= v then
            t[k] = v
        end
    end
    return t
end

local pack_fn = table.pack or function(...)
        return {...}
    end
local unpack_fn = table.unpack or unpack

function M.exec(func, args)
    if func == nil then
        return
    end
    local ret = nil
    xpcall(
        function()
            if args == nil then
                ret = pack_fn(func())
            elseif type(args) == "table" and #args > 0 then
                -- 参数列表，非key/map，需要展开
                ret = pack_fn(func(unpack_fn(args)))
            else
                ret = pack_fn(func(args))
            end
        end,
        function(err)
            E.LOG.error(
                LOGGER,
                string.format(
                    "Executing function error. Args: %s. Error: %s. Traceback:\n%s",
                    M.table_tostring(args),
                    err,
                    TBUtils.get_traceback_info()
                )
            )
        end
    )
    if ret ~= nil then
        return unpack_fn(ret)
    end
    return nil
end

local function quick_determine(actual, expected, marginForAlmostEqual)
    if actual == expected then
        return true, true
    end

    local type_a, type_e = type(actual), type(expected)

    if type_a ~= type_e then
        return true, false -- different types won't match
    end

    if type_a == "number" then
        if marginForAlmostEqual ~= nil and type(marginForAlmostEqual) == "number" and marginForAlmostEqual >= 0 then
            return true, math.abs(expected - actual) <= marginForAlmostEqual
        else
            return true, actual == expected
        end
    elseif type_a ~= "table" then
        -- other types compare directly
        return true, actual == expected
    end
    return false, false
end

-- inspired by luaunit
function M:is_table_equals(actual, expected, cycleDetectTable, marginForAlmostEqual)
    local ok, result = quick_determine(actual, expected, marginForAlmostEqual)
    if ok then
        return result
    end
    cycleDetectTable = cycleDetectTable or {actual = {}, expected = {}}
    if cycleDetectTable.actual[actual] then
        -- oh, we hit a cycle in actual
        if cycleDetectTable.expected[expected] then
            -- uh, we hit a cycle at the same time in expected
            -- so the two tables have similar structure
            return true
        end

        -- cycle was hit only in actual, the structure differs from expected
        return false
    end

    if cycleDetectTable.expected[expected] then
        -- no cycle in actual, but cycle in expected
        -- the structure differ
        return false
    end

    -- at this point, no table cycle detected, we are
    -- seeing this table for the first time

    -- mark the cycle detection
    cycleDetectTable.actual[actual] = true
    cycleDetectTable.expected[expected] = true

    local actualKeysMatched = {}
    for k, v in pairs(actual) do
        actualKeysMatched[k] = true -- Keep track of matched keys
        if not self:is_table_equals(v, expected[k], cycleDetectTable, marginForAlmostEqual) then
            -- table differs on this key
            -- clear the cycle detection before returning
            cycleDetectTable.actual[actual] = nil
            cycleDetectTable.expected[expected] = nil
            return false
        end
    end

    for k, _ in pairs(expected) do
        if not actualKeysMatched[k] then
            -- Found a key that we did not see in "actual" -> mismatch
            -- clear the cycle detection before returning
            cycleDetectTable.actual[actual] = nil
            cycleDetectTable.expected[expected] = nil
            return false
        end
        -- Otherwise actual[k] was already matched against v = expected[k].
    end

    -- all key match, we have a match !
    cycleDetectTable.actual[actual] = nil
    cycleDetectTable.expected[expected] = nil
    return true
end

-- https://prometheus.io/docs/concepts/data_model/  参考prometheus的正则要求
local metric_type_regex = "^[a-zA-Z_:][a-zA-Z0-9_:]*$"

-- metric_name 需要符合prometheus的正则要求
function M.is_metric_name_valid(name)
    if type(name) ~= "string" then
        return false
    end
    local ret = string.match(name, metric_type_regex)
    return ret ~= nil
end

return M
