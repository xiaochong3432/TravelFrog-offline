local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.init"

local Bucket = require "ejoysdk_lua.apm-sdk-lua.log.bucket.init"
local Vconfig = require "ejoysdk_lua.apm-sdk-lua.log.vconfig"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local StringUtils = require "ejoysdk_lua.apm-sdk-lua.common.string_utils"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"

local assert = assert
local error = error
local type = type
local pairs = pairs
local tostring = tostring
local getmetatable = getmetatable
local select = select
local setmetatable = setmetatable
local next = next

local sformat = string.format
local sgsub = string.gsub
local smatch = string.match
local srep = string.rep
local tconcat = table.concat
local tunpack = table.unpack or unpack

-- 单 vm 内 SERVICE_NAME 作为全局变量读取。
local appname = SERVICE_NAME or "app" --luacheck: ignore SERVICE_NAME

-- level priority
local DEBUG = Global.LogLevelEnum.DEBUG
local INFO = Global.LogLevelEnum.INFO
local WARNING = Global.LogLevelEnum.WARNING
local ERROR = Global.LogLevelEnum.ERROR
local CRITICAL = Global.LogLevelEnum.CRITICAL

local LOG_LEVEL = {
    ["DEBUG"] = DEBUG,
    ["INFO"] = INFO,
    ["WARNING"] = WARNING,
    ["ERROR"] = ERROR,
    ["CRITICAL"] = CRITICAL
}

local VERBOSE = {}
for i = 0, Vconfig.max_level do
    VERBOSE[i] = i
end

-- log 统计信息，不同级别日志统计信息/tb统计。
-- 所有 logger 对象共享。
local stats = {level = {}, traceback_cnt = 0}
for _, l in pairs(LOG_LEVEL) do
    stats.level[l] = 0
end

local prefered_bucket, default_bucket

local function get_bucket()
    -- cloud_bucket = cloud_bucket or Bucket.new("file","/tmp/game_$Y$m$d_$H$M$S.log?split=line&maxline=10000")
    -- cloud_bucket = cloud_bucket or Bucket.new("buffer","?format=simple_text&color=true")
    -- cloud_bucket = cloud_bucket or Bucket.new("buffer","?format=text&color=false")
    prefered_bucket = prefered_bucket or Bucket.new("cloud", "?format=text&color=false")

    if prefered_bucket then
        return prefered_bucket
    end

    default_bucket = default_bucket or Bucket.get_default()
    return default_bucket
end

local function set_bucket(bucket)
    local old = get_bucket()
    prefered_bucket = bucket
    return old
end

local supported_bucket = {
    console = true,
    file = true,
    cloud = true
}

local function get_default_bucket_list()
    default_bucket = default_bucket or Bucket.get_default()
    return {default_bucket}
end

local used_bucket_list
local function get_bucket_list()
    if used_bucket_list and next(used_bucket_list) then
        return used_bucket_list
    end
    local bucket_list_str = Cfg.get_log_bucket()
    local bucket_list = StringUtils.split(bucket_list_str, "|")
    if not next(bucket_list) then
        return get_default_bucket_list()
    end
    local custom_bucket_num = 0
    used_bucket_list = {}
    local bucket_conf = Cfg.get_log_bucket_conf()
    for _, bucket_name in ipairs(bucket_list) do
        if supported_bucket[bucket_name] then
            custom_bucket_num = custom_bucket_num + 1
            local params = bucket_conf and bucket_conf[bucket_name] or nil
            table.insert(used_bucket_list, Bucket.new(bucket_name, params))
        end
    end

    if custom_bucket_num == 0 then
        return get_default_bucket_list()
    end

    return used_bucket_list
end

local MAX_LOG_SRC_LEN = 256
local g_record = {}
-- catalog: 记录类型, 目前可行值如下
--  log: 普通日志
--  metrics: 指标
local function save_to_buckets(catalog, modname, level, timestamp, src, tags, msg, values)
    local bucket_list = get_bucket_list()
    g_record.module = modname
    g_record.level = level
    g_record.timestamp = timestamp
    g_record.line = StringUtils.truncate(src, MAX_LOG_SRC_LEN)
    g_record.tags = tags
    g_record.msg = msg
    g_record.values = values
    for _, bucket in ipairs(bucket_list) do
        bucket:put(catalog, g_record)
    end
    return g_record
end

-- 以@开头 或以.lua 结尾,则认为source来源于文件
local function is_source_come_from_file(src)
    local len = #src
    if len > 1 and string.sub(src, 1, 2) == "@" then
        return true
    end

    if #src > 4 and string.sub(src, len - 4 + 1, len) == ".lua" then
        return true
    end
    return false
end

local function get_log_src(level)
    if not Cfg.should_collect_line_info() then
        return nil
    end

    local info = debug.getinfo(level + 1, "Sl")
    if info == nil then
        return nil
    end

    local src = info.source

    -- source - where the function was defined.
    -- If in a file, it is the file name prefixed by "@".
    -- If the function was defined in a string (through loadstring) then "source" is this string.
    -- If the function was defined interactively (through the lua.exe program) then source will be "stdin".
    -- If the function was defined in a C program, then source will be "[C]".
    if not is_source_come_from_file(src) then
        -- 如果调用方不是lua file,是拿不到具体的文件信息的 这里直接返回nil
        return nil
    end

    return sformat("%s:%s", src, info.currentline)
end

local function table_serialize(root)
    local cache = {}
    local function _dump(t, space, name)
        if cache[t] then
            return cache[t]
        end
        if type(t) ~= "table" then
            return sformat(" [%s]", tostring(t))
        end
        local mt = getmetatable(t)
        if mt and mt.__tostring then
            return sformat(" {%s}", tostring(t))
        end
        cache[t] = sformat(" {%s}", t == root and "." or name)
        local temp = {}
        for k, v in pairs(t) do
            local key = tostring(k)
            local next_space = sformat("%s|%s", space, srep(" ", #key))
            local next_name = sformat("%s.%s", name, key)
            temp[#temp + 1] = sformat("+%s%s", key, _dump(v, next_space, next_name))
        end
        return tconcat(temp, sformat("\n%s", space))
    end
    return _dump(root, "", "")
end

-- 如遇table 不展开table 只打印table的地址
local function simple_serialize(_, s)
    return tostring(s)
end

local function strict_serialize(_, s)
    if type(s) == "table" then
        return table_serialize(s)
    else
        return tostring(s)
    end
end

local function serialize(level, s)
    if level < INFO and type(s) == "table" then
        return table_serialize(s)
    end
    return tostring(s)
end

local function simple_string_format(_, _, format, ...)
    return sformat(format, ...)
end

local function strict_string_format(seri, level, format, ...)
    local n = select("#", ...)
    local t = {...}
    for i = 1, n do
        t[i] = seri(level, t[i])
    end
    return sformat(format, tunpack(t, 1, n))
end

local function string_format(seri, level, format, ...)
    if level < INFO then
        return strict_string_format(seri, level, format, ...)
    else
        return sformat(format, ...)
    end
end

--
-- end log helper fun
--

-- logger object
local logger = {}
logger.__index = logger

-- priority
logger.DEBUG = DEBUG
logger.INFO = INFO
logger.WARNING = WARNING
logger.ERROR = ERROR
logger.CRITICAL = CRITICAL

local concat_buffer = {}
-- luacheck: ignore
function logger:stats()
    return stats
end

local function readonly(record)
    return setmetatable(
        {},
        {
            __index = record,
            __newindex = error,
            __pairs = function(_)
                return pairs(record)
            end
        }
    )
end

function logger:ilog(level, ...)
    local seri = self.serialize
    local n = select("#", ...)
    for i = 1, n do
        concat_buffer[i] = seri(level, select(i, ...))
    end
    return tconcat(concat_buffer, " ", 1, n)
end

function logger:flog(level, format, ...)
    return self.string_format(self.serialize, level, format, ...)
end

--  结构化日志
function logger:slog(level, structure, ...)
    local n = select("#", ...)
    local values = {...}
    local seri = self.serialize
    for i = 1, n do
        values[i] = seri(level, values[i])
    end

    return structure, values
end

function logger:log(level, format_type, stack_depth, ...)
    -- 过滤掉信息的条件：level高于log_level
    if level > self.log_level then
        return
    end

    -- apus sdk 初始化完 才能打log
    if not Global.is_apus_sdk_initialized() then
        return
    end

    stats.level[level] = stats.level[level] + 1

    local timestamp = Time.now()
    local src = self.log_src and get_log_src(self.stack_level + stack_depth)
    local modname = self.module_name or appname
    local tags = self:get_tag()

    local record = save_to_buckets("log", modname, level, timestamp, src, tags, self[format_type](self, level, ...))

    if self.callback and level <= self.callback_level then
        -- 这里不做保护, 有异常直接报错, 建议不要修改record
        return self.callback("log", record)
    end
end

function logger:manual_log(level, log_src, log_time, format_type, stack_depth, ...)
    -- 过滤掉信息的条件：level高于log_level
    if level > self.log_level then
        return
    end

    -- apus sdk 初始化完 才能打log
    if not Global.is_apus_sdk_initialized() then
        return
    end

    stats.level[level] = stats.level[level] + 1

    local timestamp = log_time or Time.now()
    local src
    if self.log_src then
        src = log_src or get_log_src(self.stack_level + stack_depth)
    end
    local modname = self.module_name or appname
    local tags = self:get_tag()

    local record = save_to_buckets("log", modname, level, timestamp, src, tags, self[format_type](self, level, ...))

    if self.callback and level <= self.callback_level then
        -- 这里不做保护, 有异常直接报错, 建议不要修改record
        return self.callback("log", record)
    end
end

--
-- public interface
--
local ExtStackDepth = 1

-- level: 日志级别 可取值 1:cri 2:err 3:warn 4:info 5:debug
-- log_src: 打印日志的文件+行号
-- log_time: 日志打印的时间戳 精确到秒 可以有小数点 小数点前三位将会变计算为毫秒
function logger:ManualLog(level, log_src, log_time, ...)
    return self:manual_log(level, log_src, log_time, "ilog", ExtStackDepth, ...)
end

function logger:ManualLogS(level, log_src, log_time, ...)
    return self:manual_log(level, log_src, log_time, "slog", ExtStackDepth, ...)
end

function logger:ManualLogf(level, log_src, log_time, ...)
    return self:manual_log(level, log_src, log_time, "flog", ExtStackDepth, ...)
end

function logger:Debug(...)
    return self:log(DEBUG, "ilog", ExtStackDepth, ...)
end

function logger:Debugf(...)
    return self:log(DEBUG, "flog", ExtStackDepth, ...)
end

function logger:DebugS(...)
    return self:log(DEBUG, "slog", ExtStackDepth, ...)
end

function logger:Info(...)
    return self:log(INFO, "ilog", ExtStackDepth, ...)
end

function logger:Infof(...)
    return self:log(INFO, "flog", ExtStackDepth, ...)
end

function logger:InfoS(...)
    return self:log(INFO, "slog", ExtStackDepth, ...)
end

function logger:Warning(...)
    return self:log(WARNING, "ilog", ExtStackDepth, ...)
end

function logger:Warningf(...)
    return self:log(WARNING, "flog", ExtStackDepth, ...)
end

function logger:WarningS(...)
    return self:log(WARNING, "slog", ExtStackDepth, ...)
end

function logger:Error(...)
    return self:log(ERROR, "ilog", ExtStackDepth, ...)
end

function logger:Errorf(...)
    return self:log(ERROR, "flog", ExtStackDepth, ...)
end

function logger:ErrorS(...)
    return self:log(ERROR, "slog", ExtStackDepth, ...)
end

function logger:Critical(...)
    return self:log(CRITICAL, "ilog", ExtStackDepth, ...)
end

function logger:Criticalf(...)
    return self:log(CRITICAL, "flog", ExtStackDepth, ...)
end

function logger:CriticalS(...)
    return self:log(CRITICAL, "slog", ExtStackDepth, ...)
end

function logger:set_module(module_name)
    self.module_name = module_name
end

function logger:set_log_level(log_level)
    self.log_level = log_level
end

local function get_perror_level(self, level)
    local pcalls = self.pcalls
    if next(pcalls) then
        while true do
            level = level + 1
            local info = debug.getinfo(level, "f")
            if not info then
                break
            end
            local func = info.func
            if pcalls[func] then
                return pcalls[func]
            end
        end
    end
    return CRITICAL
end

local function slog_unescape(msg)
    return sgsub(msg, "([{}])", "%0%0")
end

local function separate_traceback(msg, tcb)
    local msg_message, msg_stack = smatch(msg, "^([^\n]*)\n?(stack traceback:\n.*)$")
    if msg_stack then
        msg = msg_message
        tcb = sformat("%s\n%s", msg_stack, tcb)
    end
    return msg, tcb
end

local function log_traceback(self, log_lv, err_type, err_msg, stack_depth)
    local msg, tcb = separate_traceback(slog_unescape(tostring(err_msg)), debug.traceback(nil, stack_depth + 1))
    return self:log(log_lv, "slog", stack_depth, sformat("<%s> %s {traceback}", err_type, msg), tcb)
end

-- debug.traceback 与 error 的 level 参数含义不同
local DoErrorStackDepth = 2
local function do_error(self, err_type, err_msg, err_lv)
    stats.traceback_cnt = stats.traceback_cnt + 1

    local log_lv = get_perror_level(self, DoErrorStackDepth)
    log_traceback(self, log_lv, err_type, err_msg, DoErrorStackDepth)

    return error(err_msg, err_lv)
end

local DefAssertMsg = "assertion failed!"
local AssertErrLv = 2
function logger:Assert(v, ...)
    if v then
        return v, ...
    end
    local message = select("#", ...) > 0 and ... or DefAssertMsg

    return do_error(self, "assert", message, AssertErrLv)
end

function logger:SError(message, level)
    level = level or 1
    if level > 0 then
        level = level + 1
    end

    return do_error(self, "error", message, level)
end

local XpcallMsghStackDepth = 1
function logger:xpcall_msgh(msg)
    return log_traceback(self, CRITICAL, "error", msg, XpcallMsghStackDepth)
end

local tags = {} -- 复用 tags 表
function logger:get_tag()
    local del = next(tags)
    while del do -- tags 往往很少
        tags[del] = nil
        del = next(tags)
    end
    local static_tags = self.static_tags
    local dynamic_tags = self.dynamic_tags
    if static_tags then
        for k, v in pairs(static_tags) do
            tags[k] = v
        end
    end
    if dynamic_tags then
        for k, v in pairs(dynamic_tags) do
            local tv = v()
            if tv then
                tags[k] = tostring(tv)
            end
        end
    end
    if static_tags or dynamic_tags then
        return tags
    else
        return nil
    end
end

-- value为function，则为动态tag，值在打印日志时计算
function logger:tag(key, value)
    if type(value) == "function" then
        if not self.dynamic_tags then
            self.dynamic_tags = {}
        end
        self.dynamic_tags[key] = value
    else
        if not self.static_tags then
            self.static_tags = {}
        end
        self.static_tags[key] = tostring(value)
    end
end

function logger:untag(key)
    local dynamic_tags = self.dynamic_tags
    if dynamic_tags and dynamic_tags[key] then
        dynamic_tags[key] = nil
        if next(dynamic_tags) == nil then
            self.dynamic_tags = nil
        end
    end

    local static_tags = self.static_tags
    if static_tags and static_tags[key] then
        static_tags[key] = nil
        if next(static_tags) == nil then
            self.static_tags = nil
        end
    end
end

-- 配置字段类型约束，如果 type 为 table，则为 table 映射值。
local config_constraint = {
    product = {type = "boolean"},
    use_simple_serialize = {type = "boolean"},
    name = {type = "string", field = "module_name"},
    level = {type = LOG_LEVEL, field = "log_level"},
    verbose = {type = VERBOSE},
    log_src = {type = "boolean"},
    log_table = {type = "boolean"},
    stack_level = {type = "number"},
    callback_level = {type = LOG_LEVEL},
    callback = {type = "function"}
}

function logger:config(t)
    -- 检查配置字段约束
    for f, v in pairs(t) do
        local c = assert(config_constraint[f], f)
        local ct = c.type
        if type(ct) == "table" then
            v = assert(ct[v], v)
        else -- lua types
            if type(v) ~= ct then
                error("type mismatch for field: " .. f)
            end
        end
        self[c.field or f] = v
    end

    -- 根据配置信息修改已有信息
    -- 优先设置simple_serialize
    if self.use_simple_serialize then
        self.serialize = simple_serialize
        self.string_format = simple_string_format
    elseif not self.product or self.log_table then
        self.serialize = strict_serialize
        self.string_format = strict_string_format
    else
        self.serialize = serialize
        self.string_format = string_format
    end
end

function logger:add_pcall(pcall, level)
    assert(type(pcall) == "function", pcall)
    assert(stats.level[level], sformat("log level not found:%s", level))
    self.pcalls[pcall] = level
end

function logger.new(module_name)
    -- private field
    local obj = {}
    obj.module_name = module_name

    -- 初始的日志级别与配置文件的对齐 以ERROR级别兜底
    obj.log_level = Cfg.get(Cfg.CATEGORY_LOG, "level", ERROR)
    obj.verbose = Vconfig.max_level

    obj.log_src = true

    -- 回溯栈的深度
    obj.stack_level = 1

    -- tags
    obj.static_tags = nil
    obj.dynamic_tags = nil
    obj.tags = ""

    -- 日志回调
    obj.callback_level = ERROR
    obj.callback = nil

    obj.serialize = strict_serialize
    obj.string_format = strict_string_format

    obj.pcalls = {}

    return setmetatable(obj, logger)
end

logger.set_bucket = set_bucket
logger.get_bucket = get_bucket

return logger
