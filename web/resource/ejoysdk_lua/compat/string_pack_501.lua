local unpack = table.unpack or unpack
local struct = _ejoysdk_struct

local M = {}

local format_param_len = {
    ['>'] = 0, -- >
    ['<'] = 0, -- <
    ['B'] = 1, -- B
    ['b'] = 1, -- b
    ['x'] = 1, -- x
    ['H'] = 1, -- H
    ['h'] = 1, -- h
    ['L'] = 1, -- L
    ['l'] = 1, -- l
    ['T'] = 1, -- T
    ['i'] = 1, -- i // struct 库最多只支持 32 位
    ['I'] = 1, -- I
    ['f'] = 1, -- f
    ['d'] = 1, -- d
    ['c'] = 1,
    ['s'] = 1
}

local pack_format_filter = {
    ['c'] = function(fmt_item)
        if type(fmt_item.p) ~= 'string' then
            return false, 'option \'s\' param is not string!'
        end
        -- c 可以不带参数
        if fmt_item.n and fmt_item.n > #fmt_item.p then
            local diff = fmt_item.n - #fmt_item.p
            for _i = 1, diff do
                fmt_item.p = fmt_item.p .. string.char(0x00)
            end
        end
        if fmt_item.n then
            fmt_item.fmt = 'c' .. tostring(fmt_item.n)
        end
        return true
    end,
    ['s'] = function(fmt_item)
        if type(fmt_item.p) ~= 'string' then
            return false, 'option \'s\' param is not string!'
        end
        if fmt_item.n == nil then
            fmt_item.n = 4
        elseif fmt_item.n == 0 then
            return false, 'option \'s\' 0 length'
        end
        fmt_item.fmt = 'I' .. tostring(fmt_item.n) .. 'c0'
        local p = {}
        table.insert(p, #fmt_item.p)
        table.insert(p, fmt_item.p)
        fmt_item.p =  p
        return true
    end
}

local unpack_format_filter = {
    ['s'] = function(fmt_item)
        if fmt_item.n == nil then
            fmt_item.n = 4
        elseif fmt_item.n == 0 then
            return false, 'option \'s\' 0 length'
        end
        fmt_item.fmt = 'I' .. tostring(fmt_item.n) .. 'c0'
        return true
    end
}

local function filter_pack_fmt_item(fmt_item)
    local filter = pack_format_filter[fmt_item.fmt]
    if not filter then
        if fmt_item.n then
            fmt_item.fmt = fmt_item.fmt .. tostring(fmt_item.n)
        end
        return true
    else
        return filter(fmt_item)
    end
end

local function filter_unpack_fmt_item(fmt_item)
    local filter = unpack_format_filter[fmt_item.fmt]
    if not filter then
        if fmt_item.n then
            fmt_item.fmt = fmt_item.fmt .. tostring(fmt_item.n)
        end
        return true
    else
        return filter(fmt_item)
    end
end

local function pack_format(format, ...)
    assert(format, 'pack format is nil!')
    assert(type(format) == 'string', 'pack format is not a string!')
    local len = #format
    local fmts = {string.byte(format, 1, len)}
    local need_filter = false
    for i = 1, len do
        fmts[i] = string.char(fmts[i])
        if pack_format_filter[fmts[i]] ~= nil then
            need_filter = true
        end
    end

    if not need_filter then -- 没有特殊字符，直接调用
        return struct.pack(format, ...)
    end

    local params = {...}
    local fmt_items = {}

    local n = 0
    local idx = 1
    local param_idx = 1
    local fmt_item
    while idx <= len do
        local fmt = fmts[idx]
        if fmt >= '0' and fmt < '9' then
            n = n * 10 + tonumber(fmt)
            if fmt_item == nil then
                error('wrong number berfore string option!')
            end
            fmt_item.n = n
        else
            local val = format_param_len[fmt]
            if val == nil then
                error('invalid format option \'' .. tostring(fmt) .. '\'')
            end
            n = 0
            fmt_item = {fmt = fmt}
            if val == 1 then
                local param = params[param_idx]
                if param == nil then
                    error('format longer than params')
                end
                fmt_item.p = param
                param_idx = param_idx + 1
            end
            table.insert(fmt_items, fmt_item)
        end
        idx = idx + 1
    end

    local new_format = ''
    local new_params = {}
    for _, _fmt_item in ipairs(fmt_items) do
        local succ, msg = filter_pack_fmt_item(_fmt_item)
        if not succ then
            error( msg or 'filiter failed, format option \' ' .. tostring(_fmt_item.fmt) .. ' \'')
        end
        new_format = new_format .. _fmt_item.fmt
        if _fmt_item.p ~= nil then
            if type(_fmt_item.p) == 'table' then
                for _, p in ipairs(_fmt_item.p) do
                    table.insert(new_params, p)
                end
            else
                table.insert(new_params, _fmt_item.p)
            end
        end
    end

    --log({
    --    func = 'pack',
    --    new_format = new_format,
    --})
    return struct.pack(new_format, unpack(new_params))
end

local function unpack_format(format, ...)
    assert(format, 'unpack format is nil!')
    assert(type(format) == 'string', 'unpack format is not a string!')
    local len = #format
    local fmts = {string.byte(format, 1, len)}
    local need_filter = false
    for i = 1, len do
        fmts[i] = string.char(fmts[i])
        if pack_format_filter[fmts[i]] ~= nil then
            need_filter = true
        end
    end

    if not need_filter then -- 没有特殊字符，直接调用
        return struct.unpack(format, ...)
    end

    local fmt_items = {}

    local n = 0
    local idx = 1
    local fmt_item

    while idx <= len do
        local fmt = fmts[idx]
        if fmt >= '0' and fmt < '9' then
            n = n * 10 + tonumber(fmt)
            if fmt_item == nil then
                error('wrong number berfore string option!')
            end
            fmt_item.n = n
        else
            local val = format_param_len[fmt]
            if val == nil then
                error('invalid format option \'' .. tostring(fmt) .. '\'')
            end
            n = 0
            fmt_item = {fmt = fmt}
            table.insert(fmt_items, fmt_item)
        end
        idx = idx + 1
    end

    local new_format = ''
    for _, _fmt_item in ipairs(fmt_items) do
        local succ, msg = filter_unpack_fmt_item(_fmt_item)
        if not succ then
            error('filiter failed, format option \' ' .. tostring(_fmt_item.fmt) .. ' \' ,msg: ' .. tostring(msg))
        end
        new_format = new_format .. _fmt_item.fmt
    end
    --log({
    --    func = 'unpack',
    --    new_format = new_format,
    --})
    return struct.unpack(new_format, ...)
end

function M.pack(format, ...)
    if struct then
        return pack_format(format, ...)
    else
        error('struct not implemented')
    end
end

function M.unpack(format, ...)
    if struct then
        return unpack_format(format, ...)
    else
        error('struct not implemented')
    end
end

return M