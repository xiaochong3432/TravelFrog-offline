local M = {}

function M.bxor(a,b)
    return a ~ b
end

-- 注意：not 方法无法做到统一，lua 5.3 使用 64 位取反，lua 5.1 只能使用 32 位
--function M.bnot(a)
--    return ~a
--end

function M.band(a,b)
    if type(a) == 'number' and type(b) == 'number' then
        return a & b
    end
    return 0
end

function M.bor(a,b)
    if type(a) == 'number' and type(b) == 'number' then
        return a | b
    end
    return 0
end

function M.rshift(a,disp) -- Lua5.2 insipred
    if type(a) == 'number' and type(disp) == 'number' then
        return a >> disp
    end
    return 0
end

function M.lshift(a,disp) -- Lua5.2 inspired
    if type(a) == 'number' and type(disp) == 'number' then
        return a << disp
    end
    return 0
end

return M