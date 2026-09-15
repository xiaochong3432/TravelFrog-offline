local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.init"

local Logger = require "ejoysdk_lua.apm-sdk-lua.log.logger"

local pairs = pairs
local type = type

local tconcat = table.concat
local sformat = string.format
local sgsub = string.gsub
local ssub = string.sub

local colors = {
    Black = 30,
    Red = 31,
    Green = 32,
    Yellow = 33,
    Blue = 34,
    Magenta = 91,
    Cyan = 36,
    Default = 39, -- 默认颜色
    LightRed = 91,
    White = 97
}

local slog_fmt = "({+)([%w_]*)(}+)"

local function color_seq(color)
    return sformat("\x1b[%dm", color)
end

local color_reset = color_seq(0)

local level_desc = {
    [Logger.CRITICAL] = {name = "CRI", color = color_seq(colors.LightRed)},
    [Logger.ERROR] = {name = "ERR", color = color_seq(colors.Red)},
    [Logger.WARNING] = {name = "WAR", color = color_seq(colors.Yellow)},
    [Logger.INFO] = {name = "INF", color = ""},
    [Logger.DEBUG] = {name = "DBG", color = color_seq(colors.Cyan)}
}

local M = {}

-- export to use
M.level_desc = level_desc

local structured_keys = {}
local function get_structured_str(msg, values)
    local idx, n = 0, #values

    local fargs = function(left, mid, right)
        local lnum, rnum = #left, #right
        local parity = lnum % 2
        if rnum % 2 ~= parity then
            error("mismatched parentheses")
        end
        left = ssub(left, 1, math.floor(lnum / 2))
        right = ssub(right, 1, math.floor(rnum / 2))
        if parity == 1 then
            idx = idx + 1
            if idx > n then
                error(sformat("no value to %s (%s#%d)", msg, mid, idx))
            end
            structured_keys[idx] = mid
            structured_keys[idx + 1] = nil
            return sformat("%s%s:%s%s", left, mid, values[idx], right)
        end
        return sformat("%s%s%s", left, mid, right)
    end
    return sgsub(msg, slog_fmt, fargs)
end

-- 把record.msg转换成字符串
-- msg的可能类型为string或包含一层kv值的table
local m2s_tbl = {}
local function msg_to_str(msg, values)
    if values then
        return get_structured_str(msg, values)
    end
    if type(msg) == "table" then
        local n = 0
        for k, v in pairs(msg) do
            n = n + 1
            m2s_tbl[n] = sformat("%s:%s", k, v)
        end
        return tconcat(m2s_tbl, ",", 1, n)
    end
    return msg
end

local last_time, last_time_str
local function format_time(timestamp)
    local sec = math.floor(timestamp)
    local ms = math.floor(timestamp * 1000 % 1000)

    local f
    if sec == last_time then
        f = last_time_str
    else
        f = Time.format(sec)
        last_time_str = f
        last_time = sec
    end
    return sformat("%s.%03d", f, ms)
end

-- export to use
M.format_time = format_time

local function level_to_string(level)
    local desc = level_desc[level]
    return desc.name
end

local function build_args(values)
    if values == nil or #values == 0 then
        return nil
    end
    local args = {}
    for i = 1, #values do
        local key = structured_keys[i]
        if not key then
            return nil
        end
        if #key == 0 or args[key] then
            key = sformat("%s#%d", key, i)
        end
        args[key] = values[i]
    end
    return args
end

local json_encoder
local grecord = {}
local function format_record(catalog, record)
    local rec
    if catalog == "log" then
        local msg = record.msg
        local values = record.values
        rec = grecord
        rec.tag = "apus.log"
        rec.module = record.module
        rec.level = level_to_string(record.level)
        rec.line = record.line
        rec.tags = record.tags
        if values then
            rec.msg = get_structured_str(msg, values)
            rec.args = build_args(values)
            record.args = rec.args
            rec.event = msg
        else
            rec.msg = msg
            rec.args = nil
            rec.event = nil
        end
    else
        -- metrics
        rec = record.msg
        rec.tag = "apus.metrics"
    end

    -- fluent only
    rec.product = record.product
    rec.group = record.group
    rec.node = record.node

    rec.time = format_time(record.timestamp)
    return json_encoder(rec)
end

local F = {}

function F.json(_, catalog, record)
    json_encoder = json_encoder or require("ejoysdk_lua.apm-sdk-lua.common.json_utils").encode
    return format_record(catalog, record)
end

local tagbuf = {}
function F.text(_, _, record)
    local msg = msg_to_str(record.msg, record.values)
    local desc = level_desc[record.level]
    if not desc then
        error("log level not exist, level: " .. record.level)
    end
    -- record.line 有可能为空 lua5.1 sformat 不接受nil占位符
    record.line = record.line or ""
    if record.tags then
        local n = 0
        for k, v in pairs(record.tags) do
            n = n + 1
            tagbuf[n] = sformat("%s:%s", k, v)
        end
        local tagstr = tconcat(tagbuf, ",", 1, n)
        return sformat(
            "[%s %s *%s*]%s:[%s] %s",
            format_time(record.timestamp),
            desc.name,
            record.module,
            record.line,
            tagstr,
            msg
        )
    end
    return sformat("[%s %s *%s*]%s: %s", format_time(record.timestamp), desc.name, record.module, record.line, msg)
end

local simple_tag_buf = {}
-- 当与ejoysdk log一起使用时，ejoysdk log以封装了时间戳信息，本log省去时间戳信息
function F.simple_text(_, _, record)
    local msg = msg_to_str(record.msg, record.values)
    local desc = level_desc[record.level]
    if not desc then
        error("log level not exist, level: " .. record.level)
    end
    -- record.line 有可能为空 lua5.1 sformat 不接受nil占位符
    record.line = record.line or ""
    if record.tags then
        local n = 0
        for k, v in pairs(record.tags) do
            n = n + 1
            simple_tag_buf[n] = sformat("%s:%s", k, v)
        end
        local tagstr = tconcat(simple_tag_buf, ",", 1, n)
        return sformat("%s:[%s] %s", record.line, tagstr, msg)
    else
        return sformat("%s: %s", record.line, msg)
    end
end

-- 上传到云端的log，只需要替换模板后的日志信息即可
function F.cloud_text(_, _, record)
    local msg = msg_to_str(record.msg, record.values)
    return msg
end

local function colorify(msg, _, record)
    local desc = level_desc[record.level]
    if not desc then
        error("log level not exist, level: " .. record.level)
    end
    local color_beg = desc.color
    local color_end = color_reset
    if color_beg == "" then
        color_end = ""
    end
    return sformat("%s%s%s", color_beg, msg, color_end)
end

-- formatter 组合多个形式的 format，format 形式 format(msg, catalog, record)
function M.get_formatter(format, color)
    format = format or "text"
    local logfmt = assert(F[format], format)

    return function(catalog, record)
        local msg = logfmt(nil, catalog, record)
        if color then
            return colorify(msg, catalog, record)
        else
            return msg
        end
    end
end

return M
