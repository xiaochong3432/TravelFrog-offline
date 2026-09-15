local M = {}

local is503 = (string.pack ~= nil)
local compat_string = {} -- string.pack 5.1 compat
local compat_math = {}
local bitutil -- bit math 5.1 compat
local compat_utf8 -- utf8 5.1 compat
local compat_xpcall -- xpcall 5.1 compat
local compat_table_move

if is503 then
    -- string
    compat_string.pack = string.pack
    compat_string.unpack = string.unpack
    -- bit
    bitutil = require 'ejoysdk_lua.compat.bitutil_503'
    -- utf8
    compat_utf8 = utf8
    compat_xpcall = xpcall
    compat_table_move = table.move
    --math
    compat_math.type = math.type
else
    -- string
    local LUA501 = require 'ejoysdk_lua.compat.string_pack_501'
    compat_string.pack = LUA501.pack
    compat_string.unpack = LUA501.unpack
    -- bit
    bitutil = require 'ejoysdk_lua.compat.bitutil_501'
    -- utf8
    compat_utf8 = _ejoysdk.utf8

    local LUA501_xpcall = require 'ejoysdk_lua.compat.xpcall_501'
    compat_xpcall = LUA501_xpcall.xpcall

    local LUA501_table_move = require 'ejoysdk_lua.compat.table_move_501'
    compat_table_move = LUA501_table_move.table_move

    --math
    compat_math.type = function(number)
        -- ref: https://www.lua.org/manual/5.3/manual.html#math.type
        if type(number) ~= 'number' then
            -- not a number
            return nil
        end

        -- lua51没有整形，都是用浮点数保存，为避免msgpack加工后其他端读取异常，尽量保证判断准确
        if math.floor(number) == number then
            -- 在浮点数与最大整数相等时，有两种情况
            -- 1. 原数据是如1，2，3这样子的整数
            -- 2. 原数据是如1.0这样子的数，也会被识别成整形，实际上数值上也是相等
            return 'integer'
        else
            return 'float'
        end
    end
end

M.string = compat_string
M.bitutil = bitutil
M.utf8 = compat_utf8
M.xpcall = compat_xpcall
M.table_move = compat_table_move
M.math = compat_math

return M