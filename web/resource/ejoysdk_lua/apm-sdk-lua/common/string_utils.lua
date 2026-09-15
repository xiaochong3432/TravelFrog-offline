-------------------------------------------------------------------------------
-- Created Date: 2021.11.04
-- Author: 三傻
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local M = {}
M.__index = M

-- inspired by http://lua-users.org/wiki/SimpleStringBuffer
local string_buffer = {}
string_buffer.__index = string_buffer

function string_buffer.new()
    local obj = {
        buf = {}
    }
    return setmetatable(obj, string_buffer)
end

function string_buffer:append(rune)
    table.insert(self.buf, rune)
end

function string_buffer:to_string()
    return table.concat(self.buf, "")
end

function M.new_string_buffer()
    return string_buffer.new()
end

-- quoted from luatricks

local magic_chars = "^$()%.[]*+-?"
local magic_chars_pattern = "[" .. string.gsub(magic_chars, ".", "%%%1") .. "]"

-- 按分隔符切割字符串
-- str: string
-- sep: 分隔符, 默认为空格字符
-- return：table
function M.split(str, sep)
    if not sep or sep == "" then
        sep = "%s"
    else
        sep = string.gsub(sep, magic_chars_pattern, "%%%1")
    end

    local result = {}
    for i in string.gmatch(str, string.format("([^%s]*)", sep)) do
        table.insert(result, i)
    end
    return result
end

-- 截断字符串
function M.truncate(str, max_length)
    if type(max_length) ~= "number" or max_length < 0 then
        return str
    end
    local fixed_max_length = math.ceil(max_length)
    if type(str) == "string" and #str > fixed_max_length then
        return string.sub(str, 1, fixed_max_length)
    end
    return str
end

return M
