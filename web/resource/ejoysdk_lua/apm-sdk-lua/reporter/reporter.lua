-------------------------------------------------------------------------------
-- APM埋点数据的上报模块
--
-- Created Date: 2021.08.03
-- Author: 十影
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"

local Labeler = require "ejoysdk_lua.apm-sdk-lua.label.labeler"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local apm_stats = require "ejoysdk_lua.apm-sdk-lua.stats.apm_stats"
local Store = require "ejoysdk_lua.apm-sdk-lua.store.store"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.init"
local ErrUtils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"
local ELOG = require "ejoysdk_lua.ejoysdk_log_file"
local EjoysdkUtils = require "ejoysdk_lua.apm-sdk-lua.common.ejoysdk_utils"

local CFG_INTERVAL = "report_interval"
local CFG_SERVER = "ingester_server"
local CFG_SERVER_FORMAL_DOMAIN = "formal_domain"
local CFG_SERVER_TEST_DOMAIN = "test_domain"
local CFG_SERVER_IS_FORMAL_ENV = "is_formal_env"
local CFG_SKIP_AUTH = "skip_auth"

local CFG_TRANSPORT = "transport"

local STATS_TYPE = Global.DataTypeEnum.STATS_TYPE
local EVENT_TYPE = Global.DataTypeEnum.EVENT_TYPE
local LOG_TYPE = Global.DataTypeEnum.LOG_TYPE
local TRACE_TYPE = Global.DataTypeEnum.TRACE_TYPE
local FILE_TYPE = Global.DataTypeEnum.FILE_TYPE

local stopping = true

local skip_auth = false

-- reporter总执行耗时
local reporter_cost = apm_stats:new_counter("reporter_cost_ms")

-- reporter总执行次数
local report_times = apm_stats:new_counter("report_times")

-- 组装协议数据总耗时
local encapsulate_cost = apm_stats:new_counter("encapsulate_cost_ms")

-- 发送协议数据到native层总耗时
local http_post_cost = apm_stats:new_counter("http_post_cost_ms")

-- 上传一批次的日志文件总耗时
local file_reort_cost = apm_stats:new_counter("file_reort_cost_ms")

local LOGGER = "apm_reporter"

-- Reporter 基类
local Reporter = {
    __name = "Reporter",
    data_type = 0, -- 数据类型，跟store模块的数据类型对应
    ingester_url = "",
    type_name = "",
    api_name = "",
    report_size_counter = nil, --各种数据上报大小 counter
    report_failure_counter = nil, --上报错误数 counter
    encapsulate_func = nil --封装协议的函数
}

Reporter.__index = Reporter

local reporter_full_list = {}

function Reporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    -- 判断是否已存在
    if reporter_full_list[data_type] ~= nil then
        E.LOG.error(LOGGER, "data_type already exists: " .. data_type)
        return nil
    end
    local obj = {
        data_type = data_type,
        type_name = type_name,
        api_name = api_name,
        report_size_counter = report_size_counter,
        report_failure_counter = report_failure_counter,
        encapsulate_func = nil
    }
    local result = setmetatable(obj, Reporter)
    reporter_full_list[data_type] = result
    return result
end

function Reporter:set_encapsulate_func(encapsulate_func)
    self.encapsulate_func = encapsulate_func
end

function Reporter:set_ingester_url(ingester_server, env)
    self.ingester_url = string.format("%s/%s%s", ingester_server, env, self.api_name)
end

local function should_send()
    local token = Labeler.get_resource("token") or ""
    if token == "" and not skip_auth then
        return false
    end
    return true
end

function Reporter:send(data, cb)
    if not should_send() then
        E.LOG.error(LOGGER, "token unset,won't send")
        return
    end
    if not data then
        E.LOG.error(LOGGER, "data is nil,won't send")
        return
    end
    local url = self.ingester_url
    local log_module = LOGGER .. "," .. self.type_name
    if cb == nil then
        cb = function(resp)
            if not resp then
                self.report_failure_counter:inc(1)
                return
            end
            local status = tostring(resp.status)
            E.LOG.debug(log_module, "url=" .. url .. ", status=" .. status)
            if resp.status ~= 200 then
                self.report_failure_counter:inc(1)
                E.LOG.error(log_module, "error sending " .. self.type_name .. ",status:" .. status)
                E.LOG.error(log_module, resp.body)
            end
        end
    end
    E.HTTP.post(url, {use_gzip = true}, E.HTTP.CT_JSON, data, cb)
    self.report_size_counter:inc(#data)
end

function Reporter:report(resource)
    local data = Store.retrieve_data(self.data_type) or {}
    if #data > 0 then
        local start = Time.system_clock()

        local output = Utils.exec(self.encapsulate_func, {resource, data})

        local elapsed_encapsulate = Time.system_clock() - start
        if elapsed_encapsulate > 0 then
            encapsulate_cost:inc(elapsed_encapsulate)
        end

        self:send(output)

        local elapsed_send = Time.system_clock() - start - elapsed_encapsulate
        if elapsed_send > 0 then
            http_post_cost:inc(elapsed_send)
        end
    end
end

-----------------------------
-- StatsReporter类
-----------------------------
local StatsReporter = {__name = "StatsReporter"}
setmetatable(StatsReporter, Reporter)
StatsReporter.__index = StatsReporter

function StatsReporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    local obj = Reporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    if obj == nil then
        return nil
    end
    return setmetatable(obj, StatsReporter)
end

-----------------------------
-- EventReporter类
-----------------------------
local EventReporter = {__name = "EventReporter"}
setmetatable(EventReporter, Reporter)
EventReporter.__index = EventReporter

function EventReporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    local obj = Reporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    if obj == nil then
        return nil
    end
    return setmetatable(obj, EventReporter)
end

-----------------------------
-- LogReporter类
-----------------------------
local LogReporter = {__name = "LogReporter"}
setmetatable(LogReporter, Reporter)
LogReporter.__index = LogReporter

function LogReporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    local obj = Reporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    if obj == nil then
        return nil
    end
    return setmetatable(obj, LogReporter)
end

-----------------------------
-- TraceReporter类
-----------------------------
local TraceReporter = {__name = "TraceReporter"}
setmetatable(TraceReporter, Reporter)
TraceReporter.__index = TraceReporter

function TraceReporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    local obj = Reporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    if obj == nil then
        return nil
    end
    return setmetatable(obj, TraceReporter)
end

-----------------------------
-- FileReporter类
-----------------------------
local FileReporter = {
    __name = "FileReporter",
    -- upload_to_server_fail_counter 上传文件到服务器失败计数器，超过 MAX_UPLOAD_TO_SERVER_FAIL_COUNTER，就终止上传，防止游戏客户端卡顿
    upload_to_server_fail_counter = 0,
    -- reupload_to_server_ticker 当终止文件上传时，需求每tick一段时间（2interval），再尝试文件上传，以便文件服务器恢复时可以及时把文件上传到云端
    reupload_to_server_ticker = 0
}
setmetatable(FileReporter, Reporter)
FileReporter.__index = FileReporter
function FileReporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    local obj = Reporter.New(data_type, type_name, api_name, report_size_counter, report_failure_counter)
    if obj == nil then
        return nil
    end
    return setmetatable(obj, FileReporter)
end

-- MAX_UPLOAD_TO_SERVER_FAIL_COUNTER 允许的最大上传失败次数
local MAX_UPLOAD_TO_SERVER_FAIL_COUNTER = 8
-- MAX_REUPLOAD_TO_SERVER_TICKER 计数器到达MAX_RELOAD_TO_SERVER_TICKER 次时，可以补偿上传一次
local MAX_REUPLOAD_TO_SERVER_TICKER = 5

local function is_file_list_valid(file_list)
    if file_list == nil then
        return false
    end
    if not file_list.data then
        return false
    end

    return true
end

-- 升级了结构化日志的native代码，且配置文件渠道采集日志，才开启file reporter
local function should_collect_log_via_file()
    return EjoysdkUtils.has_upgrade_log_file_native() and Cfg.should_send_log_to_cloud_through_file()
end

local default_params = {}
-- FileReporter 重载Reporter 的report 方法
function FileReporter:report(resource)
    if not should_collect_log_via_file() then
        return
    end
    E.LOG.debug(
        LOGGER,
        "upload_to_server_fail_counter:" ..
            tostring(self.upload_to_server_fail_counter) ..
                ",reupload_to_server_ticker:" .. tostring(self.reupload_to_server_ticker)
    )

    if self.upload_to_server_fail_counter >= MAX_UPLOAD_TO_SERVER_FAIL_COUNTER then
        self.reupload_to_server_ticker = self.reupload_to_server_ticker + 1
    end

    local start = Time.system_clock()
    E.get_log_file_infos(
        default_params,
        function(...)
            local file_list = ...
            if not is_file_list_valid(file_list) then
                return
            end
            for _, file in ipairs(file_list.data) do
                local file_size = tonumber(file.sizes or 0)
                if file and file.file_path and file.file_name and file_size > 0 then
                    self.report_size_counter:inc(file_size)
                    self:upload_log_file(resource, file.file_path, file.file_name)
                else
                    -- 参数无效 记一次失败
                    self.report_failure_counter:inc(1)
                end
            end
            local elapsed = Time.system_clock() - start
            if elapsed > 0 and file_reort_cost then
                file_reort_cost:inc(elapsed)
            end
        end
    )
end

local reported_log_files = {}

-- delete_after_upload表示上传成功后需要删除
local default_opts = {delete_after_upload = true}
function FileReporter:upload_log_file(resource, file_path, file_name)
    if not file_path or not file_name then
        return
    end

    local minimised_resource = Labeler.minimise_resource(resource)

    local cached_key = file_path .. file_name
    if reported_log_files[cached_key] then
        E.LOG.warn(LOGGER, "file already successfully reported,ignore,cached_key:" .. cached_key)
        return
    end

    -- 持续MAX_UPLOAD_TO_SERVER_FAIL_COUNTER次上传失败，终止上传，保护服务器，也保护客户端
    if
        self.upload_to_server_fail_counter >= MAX_UPLOAD_TO_SERVER_FAIL_COUNTER and
            self.reupload_to_server_ticker <= MAX_REUPLOAD_TO_SERVER_TICKER
     then
        E.LOG.warn(LOGGER, "upload file to server failed too frequently, ignore upload...")
        return
    end

    -- 上传日志文件到天燕
    ELOG.upload_log_to_apus(
        self.ingester_url,
        {form_header = minimised_resource},
        file_path,
        file_name,
        default_opts,
        function(succ, ...)
            if succ then
                reported_log_files[cached_key] = true
                E.LOG.debug(LOGGER, "upload_file_to_apus:" .. tostring(succ))
                self.upload_to_server_fail_counter = 0
                self.reupload_to_server_ticker = 0
            else
                local code, msg = ...
                E.LOG.warn(
                    LOGGER,
                    "upload_file_to_apus:" .. tostring(succ) .. ",code:" .. tostring(code) .. tostring(msg)
                )
                self.report_failure_counter:inc(1)
                self.upload_to_server_fail_counter = self.upload_to_server_fail_counter + 1
                -- 无论是正常的上传失败 还是补偿的上传失败 都置空reupload_to_server_ticker，需要等待2interval，才能激活补偿上传
                self.reupload_to_server_ticker = 0
            end
        end
    )
end

local M = {
    stats_reporter = StatsReporter.New(
        STATS_TYPE,
        "stats",
        "/v1/stats",
        apm_stats:new_counter("size_stats", true),
        apm_stats:new_counter("failure_stats", true)
    ),
    -- 目前event类型的数据会拆分为log和stats俩种类型的数据，所以event类型的queue目前不会有数据，
    -- /v1/events 这个接口不会被调用到，此处是为未来预留能力
    event_reporter = EventReporter.New(EVENT_TYPE, "event", "/v1/events"),
    log_reporter = LogReporter.New(
        LOG_TYPE,
        "log",
        "/v1/logs",
        apm_stats:new_counter("size_log", true),
        apm_stats:new_counter("failure_log", true)
    ),
    trace_reporter = TraceReporter.New(
        TRACE_TYPE,
        "trace",
        "/v1/traces",
        apm_stats:new_counter("size_trace", true),
        apm_stats:new_counter("failure_trace", true)
    ),
    file_reporter = FileReporter.New(
        FILE_TYPE,
        "file",
        "/v1/files",
        apm_stats:new_counter("size_file", true),
        apm_stats:new_counter("failure_file", true)
    )
}
M.__index = M

local function run()
    if not stopping then
        E.Timer.once(M.interval, run)
    end
    xpcall(M.report, ErrUtils.handle_err)
end

local handler_fns = {
    [Cfg.KEY_ENABLED] = function(value)
        if value == true and stopping == true then
            M.start()
        elseif value == false and stopping == false then
            M.stop()
        end
    end,
    [CFG_INTERVAL] = function(value)
        -- 下次生效
        if type(value) == "number" then
            E.LOG.debug(LOGGER, string.format("report interval is changed from %d to %d seconds", M.interval, value))
            M.interval = value
        end
    end,
    [CFG_SERVER] = function(value)
        E.LOG.debug(LOGGER, "ingester server is changed to " .. tostring(value))
        M.set_ingester_server(value)
    end,
    [CFG_SKIP_AUTH] = function(value)
        if type(value) == "boolean" then
            E.LOG.debug(LOGGER, "skip_auth is changed to " .. tostring(value))
            skip_auth = value
        end
    end
}

local function handle_config_update(key, value)
    local handler_fn = handler_fns[key]
    if handler_fn ~= nil then
        handler_fn(value)
    else
        E.LOG.error(LOGGER, "invalid config change of report: " .. key)
    end
end

function M.init()
    ErrUtils.set_report_stopper(M.stop)

    M.set_ingester_server(Cfg.get(Cfg.CATEGORY_REPORT, CFG_SERVER))

    local interval = Cfg.get(Cfg.CATEGORY_REPORT, CFG_INTERVAL, 60)

    -- 数据传输协议，目前实现了OTLP的HTTP方式
    local transport = Cfg.get(Cfg.CATEGORY_REPORT, CFG_TRANSPORT, "http")
    M.set_encapsulator(transport)

    skip_auth = Cfg.get(Cfg.CATEGORY_REPORT, CFG_SKIP_AUTH, false)

    local enabled = Cfg.get(Cfg.CATEGORY_REPORT, Cfg.KEY_ENABLED, true)
    if enabled then
        M.start(interval)
        E.LOG.debug(LOGGER, "Reporter initialized with interval " .. tostring(M.interval))
    end
    Cfg.set_update_callback(Cfg.CATEGORY_REPORT, handle_config_update)

    Store.set_report_by_bufsize_fn(M.report_by_bufsize)
end

local function get_env()
    local env = E.CONFIG and E.CONFIG.get_config("product") or ""
    if env == nil or env == "" then
        env = "default"
    end
    return env
end

local function update_ingester_url(ingester_server, env)
    for _, reporter in ipairs(reporter_full_list) do
        reporter:set_ingester_url(ingester_server, env)
    end
end

function M.set_ingester_server(server_cfg)
    local env = get_env()
    if type(server_cfg) == "string" then
        update_ingester_url(server_cfg, env)
    elseif type(server_cfg) == "table" then
        local server = server_cfg[CFG_SERVER_FORMAL_DOMAIN]
        local is_formal_env = server_cfg[CFG_SERVER_IS_FORMAL_ENV]
        if not is_formal_env then
            server = server_cfg[CFG_SERVER_TEST_DOMAIN]
        end
        update_ingester_url(server, env)
    else
        E.LOG.error(LOGGER, "Error getting ingester from config:" .. tostring(server_cfg))
    end
end

function M.set_encapsulator(transport)
    -- 目前只实现了http/json，以后会支持gRPC
    if transport == "http" then
        M.encapsulator = require "ejoysdk_lua.apm-sdk-lua.reporter.otlp_http"
    else
        E.LOG.error(LOGGER, "unsupported transport " .. transport)
        return
    end
    M.stats_reporter:set_encapsulate_func(M.encapsulator.build_otlp_logs_v2)
    M.log_reporter:set_encapsulate_func(M.encapsulator.build_otlp_logs_v2)
    M.trace_reporter:set_encapsulate_func(M.encapsulator.build_otlp_spans_v2)
end

function M.start(interval)
    if interval ~= nil then
        M.interval = interval
    end
    if stopping == true then
        stopping = false
        -- 延后1秒以便在stats collector之后运行
        E.Timer.once(M.interval + 1, run)
        E.LOG.debug(LOGGER, "reporter started")
    end
end

function M.stop()
    -- E.Timer没有cancel方法，还会跑最后一次
    stopping = true
    E.LOG.debug(LOGGER, "reporter is stopping")
end

function M.set_interval(v)
    M.interval = v
end

-- 对指定埋点数据异步发送到Ingester服务器 由bufsize触发
function M.report_by_bufsize(dtype)
    E.LOG.debug(LOGGER, "reporter is invoked.triggered by bufsize")

    local reporter = reporter_full_list[dtype]
    if not reporter then
        E.LOG.error(LOGGER, "could not retrieve reporter,dtype:" .. tostring(dtype))
        return
    end

    local start = Time.system_clock()
    local resource = Labeler.get_resource()

    reporter:report(resource)

    local elapsed = Time.system_clock() - start
    if elapsed > 0 then
        reporter_cost:inc(elapsed)
        report_times:inc(1)
    end
end

-- 对4种埋点数据分别异步发送到Ingester服务器 由timer触发
function M.report()
    E.LOG.debug(LOGGER, "reporter is invoked.triggered by timer")
    local start = Time.system_clock()
    local resource = Labeler.get_resource()

    for _, reporter in ipairs(reporter_full_list) do
        reporter:report(resource)
    end

    local elapsed = Time.system_clock() - start
    if elapsed > 0 then
        reporter_cost:inc(elapsed)
        report_times:inc(1)
    end
end

return M
