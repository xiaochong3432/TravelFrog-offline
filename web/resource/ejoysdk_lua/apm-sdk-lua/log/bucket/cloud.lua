-- -- 一般情况下，用于对接 aliyun sls 或 fluentbit 等云原生日志系统
-- -- return require "ejoysdk_lua.apm-sdk-lua.log.bucket.console"
-- return require "ejoysdk_lua.apm-sdk-lua.log.bucket.console"

-- 输出到云端
local Formatter = require "ejoysdk_lua.apm-sdk-lua.log.formatter"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local Ratelimit = require "ejoysdk_lua.apm-sdk-lua.common.ratelimit"
local CollectFilter = require "ejoysdk_lua.apm-sdk-lua.common.collect_filter"
local E = require "ejoysdk_lua.ejoysdk"
local Store = require "ejoysdk_lua.apm-sdk-lua.store.store"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local EjoysdkUtils = require "ejoysdk_lua.apm-sdk-lua.common.ejoysdk_utils"

local sformat = string.format
local sgsub = string.gsub
local ssub = string.sub
local slog_fmt = "({+)([%w_]*)(}+)"

local LOGGER = "apm_bucket_cloud"

local cloud = {handle = io.stdout}

local structured_keys = {} --复用
local function build_args(values, msg)
    if values == nil or #values == 0 then
        return nil
    end
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
    sgsub(msg, slog_fmt, fargs)
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

-- 最大单条日志长度8k
local MAX_LOG_LENGTH = 8192

local function truncate_msg(msg)
    if #msg >= MAX_LOG_LENGTH then
        msg = string.sub(msg, 1, MAX_LOG_LENGTH)
    end
    return msg
end

local log_to_file_fns = {
    [Global.LogLevelEnum.DEBUG] = E.LOG.debugt,
    [Global.LogLevelEnum.INFO] = E.LOG.infot,
    [Global.LogLevelEnum.WARNING] = E.LOG.warnt,
    [Global.LogLevelEnum.ERROR] = E.LOG.errort,
    [Global.LogLevelEnum.CRITICAL] = E.LOG.errort
}

local function get_level_desc(level)
    local desc = Formatter.level_desc[level]
    local level_desc = desc and desc.name or tostring(level)
    return level_desc
end

local function should_send_log_through_file()
    return EjoysdkUtils.has_upgrade_log_file_native() and Cfg.should_send_log_to_cloud_through_file()
end

local nano_time_counter = 0
-- timeUnixNano 总共19位 前10位将被SLS存储为"__time__"字段，后六位用于保证同一毫秒内的采集记录的有序性
local function cvt_to_time_unix_nano(timeMill)
    nano_time_counter = nano_time_counter + 1
    if nano_time_counter >= 1e7 then
        nano_time_counter = 1
    end
    return string.format("%d%06d", timeMill, nano_time_counter)
end

function cloud:put(catalog, record)
    if not Cfg.is_log_enabled() then
        return
    end

    -- 限流
    if cloud.ratelimiter ~= nil and not cloud.ratelimiter:allow() then
        E.LOG.debug(LOGGER, "cloud log put is rejected by ratelimiter")
        return
    end

    local event_name = "pure_log"
    if record.values ~= nil and next(record.values) then
        event_name = record.msg
    end

    -- 处于黑名单列表的 event_name 不上报云端
    if CollectFilter.is_in_log_blacklist(event_name) then
        return
    end

    local msg = self.formatter(catalog, record)
    local level_desc = get_level_desc(record.level)
    if should_send_log_through_file() then
        -- key的缩写遵循 https://yuque.antfin.com/gserver/evpg3z/arwxsl#m0wU5 的约定
        local log = {
            e = event_name,
            m = truncate_msg(msg),
            ln = record.line,
            -- 服务器端接收的是毫秒级别时间戳
            ti = math.floor(record.timestamp * 1000),
            -- 上传 time_unix_nano, 用于日志内容排序 record.timestamp 单位是秒，float类型
            tn = cvt_to_time_unix_nano(record.timestamp * 1000),
            mo = record.module,
            tags = record.tags,
            args = build_args(record.values, record.msg),
            lv = level_desc
        }
        local log_to_file_fn = log_to_file_fns[record.level] or E.LOG.debugt
        -- 与ejoysdk log级别隔离，优先使用E.LOG.ignore_level打印日志
        if type(E.LOG.ignore_level) == "function" then
            log_to_file_fn = E.LOG.ignore_level
        end
        log_to_file_fn(log)
        return true
    end
    -- 以下的逻辑是通过原有方式上传日志: 直接上传到云端 不通过file
    local log = {
        event_name = event_name,
        trace_id = nil,
        message = truncate_msg(msg),
        line = record.line,
        timestamp = Formatter.format_time(record.timestamp),
        module = record.module,
        tags = record.tags,
        args = build_args(record.values, record.msg),
        level = level_desc,
        stats = nil
    }
    Store.submit_log(log)
    return true
end

-- luacheck: ignore
function cloud:close()
end

cloud.default_params = {format = "text", color = false}
-- console+?color=false     关闭颜色输出
function cloud.new(_, params)
    local rate_limit = Cfg.get(Cfg.CATEGORY_LOG, "rate_limit", 10)
    local burst = Cfg.get(Cfg.CATEGORY_LOG, "burst", 100)
    local err
    cloud.ratelimiter, err = Ratelimit.new_limiter(rate_limit, burst, "cloud_log")
    if err ~= nil then
        E.LOG.error(LOGGER, "new limiter err:" .. err)
    else
        E.LOG.debug(LOGGER, "new limiter succ")
    end
    cloud.formatter = Formatter.get_formatter(params.format, params.color)
    return cloud
end

return cloud
