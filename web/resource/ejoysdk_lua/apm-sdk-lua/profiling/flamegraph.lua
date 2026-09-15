-------------------------------------------------------------------------------
-- flamegraph 火焰图采集模块
-- Created Date: 2022.08.02
-- Author: 三傻
-- Doc: https://yuque.antfin.com/gserver/evpg3z/qhn6og
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------

local E = require "ejoysdk_lua.ejoysdk"
local Time = require "ejoysdk_lua.apm-sdk-lua.common.time.init"
local FgCfg = require "ejoysdk_lua.apm-sdk-lua.config.flamegraph_config"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local EU = require "ejoysdk_lua.apm-sdk-lua.common.ejoysdk_utils"
local Utils = require "ejoysdk_lua.apm-sdk-lua.common.utils"
local Labeler = require "ejoysdk_lua.apm-sdk-lua.label.labeler"
local Event = require "ejoysdk_lua.apm-sdk-lua.event.event"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local E_UTILS = require "ejoysdk_lua.ejoysdk_utils"

local LOGGER = "apm_flamegraph"

local M = {
    -- 生成火焰图的函数，由游戏注册进来
    flamegraph_fn = nil,
    -- 删除文件的函数，由游戏注册进来
    remove_file_fn = nil,
    enabled = true,
    -- 最大的火焰图生成时间 单位秒
    max_duration = 300,
    -- 配置项-任务的最大生效时间 单位毫秒
    ttl = 300 * 1000,
    -- 最大的可接收的下发的任务数
    max_concurrent_tasks = 10,
    -- 限流器
    ratelimiter = nil,
    -- 重试参数配置
    retry_opts = {}
}

M.__index = M

M.TaskActionModeEnum = {
    IMMEDIATE = 0, --  立即执行
    DEFERRED = 1 --  延迟执行
}

-- 默认的最大生成火焰图的时间 防止配错 这里多个兜底 单位秒
local DEFAULT_MAX_DURATION = 300

local CFG_TASKS = "tasks"
local CFG_ENABLED = "enabled"
local CFG_MAX_DURATION = "max_duration"
local CFG_MAX_CONCURRENT_TASKS = "max_concurrent_tasks"
local CFG_TTL = "ttl"
local CFG_RETRY_BUDGET = "retry_budget"
local CFG_RETRY_CODE_LIST = "retry_code_list"

-- 约束task的一些必填字段及其类型
local task_constraint = {
    duration = {type = "number"},
    createTime = {type = "number"},
    actionMode = {type = "number"},
    actionTimestamp = {type = "number"},
    id = {type = "string"}
}

-- 是否正在执行生成火焰图的任务 用于防止并发地执行火焰图任务
local is_running_flamegraph = false

local event_name = "apus_flamegraph"
local trace_id = ""
-- 火焰图生成失败或上报火焰图成功，上报一个事件，为了追踪火焰图在各个环节的执行情况
-- code 错误码
-- err_msg 错误的消息
-- task 错误的火焰图任务信息
local function submit_event(code, err_msg, task)
    local labels = {code = code}
    if type(task) == "table" and task.id then
        labels.task_id = task.id
    end
    E.LOG.debug(LOGGER, "recv an event,code:" .. tostring(code) .. " err_msg:" .. tostring(err_msg))
    Event.post(event_name, labels, trace_id, err_msg)
end

local function get_file_server_url()
    local domain = Cfg.get_ingester_server()
    local env = Labeler.get_resource("env")
    if not domain or not env then
        return nil
    end
    return tostring(domain) .. "/" .. tostring(env) .. "/v1/files/flamegraph"
end

-- 删除文件
local function remove_file(file_full_path)
    if file_full_path and M.remove_file_fn then
        E.LOG.debug(LOGGER, "ready to rm file:" .. file_full_path)
        M.remove_file_fn(file_full_path)
    end
end

-- 生成火焰图的回调函数
-- task_id 任务id
-- is_succ 生成火焰图是否成功 bool类型
-- file_path 火焰图文件绝对路径
-- extra_labels 额外的标签信息 游戏可以给这个火焰图打一些自定义的标签信息
local generate_flamegraph_cb = function(task_id, is_succ, file_path, extra_labels)
    -- 火焰图回调函数得到执行，更改is_running_flamegraph状态
    is_running_flamegraph = false

    E.LOG.debug(LOGGER, "generate_flamegraph_cb is called,is_succ:" .. tostring(is_succ))
    if not is_succ then
        submit_event(Global.HTTPStatusCodeEnum.INTERNAL_ERR, "generate flamegraph file failed")
        return
    end
    local resource = Utils.merge_table(Labeler.get_resource(), extra_labels)
    resource.task_id = task_id

    local upload_file_cb = function(succ, ...)
        if succ then
            submit_event(Global.HTTPStatusCodeEnum.SUCC, "upload flamegraph succ")
        else
            local code, msg = ...
            submit_event(code, msg)
        end
        -- 回调回来后，不管上传成功与否，都删除掉该火焰图文件
        remove_file(file_path)
    end
    local file_server_url = get_file_server_url()
    local retry_opts = E_UTILS.deepcopy(M.retry_opts)
    E.LOG.debug(LOGGER, "ready to call upload_file_to_apus,url:" .. tostring(file_server_url))
    EU.upload_file_to_apus(file_server_url, {form_header = resource}, file_path, retry_opts, upload_file_cb)
end

local function get_max_duration()
    local max_duration = M.max_duration
    if M.max_duration > DEFAULT_MAX_DURATION then
        max_duration = DEFAULT_MAX_DURATION
    end
    return max_duration
end

local function is_task_fields_valid(task)
    if type(task) ~= "table" or next(task) == nil then
        return false
    end
    for k, v in pairs(task_constraint) do
        local field = task[k]
        if field == nil then
            E.LOG.error(LOGGER, k .. " missed, ignore!")
            return false
        end
        if type(field) ~= v.type then
            E.LOG.error(LOGGER, k .. " mismatch type, ignore! field:" .. tostring(field))
            return false
        end
    end
    if task.duration < 0 or task.duration > get_max_duration() then
        E.LOG.error(LOGGER, "duration:" .. task.duration .. " is invalid, ignore!")
        return false
    end
    return true
end

local function exec_task_immediately(task)
    -- 并发检测
    if is_running_flamegraph then
        submit_event(
            Global.HTTPStatusCodeEnum.TOO_MANY_REQUEST,
            "another flamegraph task is still running, drop this task.",
            task
        )
        return
    end

    E.LOG.debug(LOGGER, "ready to call flamegraph generate function,taskID:" .. task.id)
    local file_name = string.format("%s.txt", task.id)
    local ok = M.generate_flamegraph(task.id, task.duration, file_name, generate_flamegraph_cb)
    if not ok then
        submit_event(Global.HTTPStatusCodeEnum.INTERNAL_ERR, "generate flamegraph failed", task)
        return
    end
    -- 来到这里说明任务被执行了
    is_running_flamegraph = true

    -- 为了防止generate_flamegraph_cb一直没有回调成功 这里起个兜底定时器更改is_running_flamegraph的状态
    local update_running_flamegraph_status = function()
        is_running_flamegraph = false
    end
    E.Timer.once(task.duration, update_running_flamegraph_status)
end

local function exec_deferred_task(task)
    local exec_task_func = function()
        return exec_task_immediately(task)
    end
    local interval = task.actionTimestamp - Time.now_utc()
    E.LOG.debug(LOGGER, "launch a timer to exec deferred task. interval:" .. interval .. " taskID:" .. task.id)
    E.Timer.once(interval, exec_task_func)
end

local function exec_task(task)
    E.LOG.debug(LOGGER, "ready to exec task")
    E.LOG.debug(LOGGER, task)
    if task.actionMode == M.TaskActionModeEnum.IMMEDIATE then
        return exec_task_immediately(task)
    end
    return exec_deferred_task(task)
end

-- 存储已经执行过的task
local executed_tasks = {}

local function should_exec_task(task)
    -- 必填字段和相应的类型校验
    if not is_task_fields_valid(task) then
        return false, "task fields is invalid"
    end
    -- 对于创建时间太久的任务 直接丢弃 防止任务重做
    local inflight_time = Time.now_ms() - task.createTime
    if inflight_time > M.ttl then
        return false, "task exceeds ttl"
    end
    --actionMode枚举值错误的 不再执行
    if task.actionMode ~= M.TaskActionModeEnum.DEFERRED and task.actionMode ~= M.TaskActionModeEnum.IMMEDIATE then
        return false, "unsupported actionMode :" .. tostring(task.actionMode)
    end
    -- 延迟任务执行时间早于当前时间的 不再执行
    if task.actionMode == M.TaskActionModeEnum.DEFERRED and task.actionTimestamp < Time.now_utc() then
        return false, "actionTimestamp is is too early"
    end
    -- 对于已经执行过的task 不再执行
    if executed_tasks[task.id] then
        return false, "task is already executed"
    end
    return true, ""
end

-- 任务列表变更 触发生成火焰图的逻辑
-- cfg是一个task数组的table
-- task的数据结构如下:
-- {
--     "duration": 10,
--     "createTime": 1659423461234,
--     "actionMode": 0, //执行模式：0立刻执行 1等到指定时间执行
--     "actionTimestamp": 1659423461, //执行时间 UTC时间戳
--     "remark": "S3火焰图任务1",
--     "id": 112
-- },
--
local function handle_tasks_update(cfg)
    E.LOG.debug(LOGGER, "handle_tasks_update")
    E.LOG.debug(LOGGER, cfg)

    if type(cfg) ~= "table" or next(cfg) == nil then
        submit_event(Global.HTTPStatusCodeEnum.BAD_REQUST, "flamegraph' tasks empty")
        return
    end
    if #cfg > M.max_concurrent_tasks then
        local err_msg =
            string.format("the number[%d] of tasks exceed max_concurrent_tasks[%s]", #cfg, M.max_concurrent_tasks)
        submit_event(Global.HTTPStatusCodeEnum.TOO_MANY_REQUEST, err_msg)
        return
    end
    for _, task in ipairs(cfg) do
        local ok, reason = should_exec_task(task)
        if ok then
            executed_tasks[task.id] = true
            exec_task(task)
        else
            submit_event(Global.HTTPStatusCodeEnum.BAD_REQUST, reason, task)
        end
    end
end

local function assert_greater_than(value, key, boundary)
    if type(value) == "number" and type(boundary) == "number" and value > boundary then
        E.LOG.debug(LOGGER, string.format("flamegraph_tasks.%s is changed to %.2f", key, value))
        return true
    end
    E.LOG.error(LOGGER, string.format("invalid %s ,type:%s,value:%s", key, type(value), tostring(value)))
    return false
end

local key_changes_handlers = {
    [CFG_ENABLED] = function(value)
        M.enabled = value
        E.LOG.debug(LOGGER, "flamegraph collector is " .. (value and "enabled" or "disabled"))
    end,
    [CFG_MAX_DURATION] = function(value)
        if assert_greater_than(value, CFG_MAX_DURATION, 0) then
            M.max_duration = value
        end
    end,
    [CFG_MAX_CONCURRENT_TASKS] = function(value)
        if assert_greater_than(value, CFG_MAX_CONCURRENT_TASKS, 0) then
            M.max_concurrent_tasks = value
        end
    end,
    [CFG_TTL] = function(value)
        if assert_greater_than(value, CFG_TTL, 0) then
            M.ttl = value
        end
    end,
    [CFG_TASKS] = function(value)
        if not M.enabled then
            E.LOG.warn(LOGGER, "flamegraph collector is disabled, ignore cfg update")
            return
        end
        handle_tasks_update(value)
    end,
    [CFG_RETRY_BUDGET] = function(value)
        if assert_greater_than(value, CFG_RETRY_BUDGET, 0) then
            M.retry_opts.retry_budget = value
        end
    end,
    [CFG_RETRY_CODE_LIST] = function(value)
        if type(value) == "table" then
            M.retry_opts.retry_code_list = value
        end
    end
}

local function handle_config_update(key, value)
    if type(key) ~= "string" or key == "" then
        return
    end
    local handler = key_changes_handlers[key]
    if handler ~= nil then
        handler(value)
    else
        E.LOG.warn(LOGGER, key .. " has not registered hanlder, ignored! ")
    end
end

function M.init()
    local cat = FgCfg.CATEGORY_FRAMRGRAPH_TASKS
    M.enabled = FgCfg.get(cat, CFG_ENABLED, true)
    M.max_duration = FgCfg.get(cat, CFG_MAX_DURATION, 300)
    M.max_concurrent_tasks = FgCfg.get(cat, CFG_MAX_CONCURRENT_TASKS, 10)
    M.ttl = FgCfg.get(cat, CFG_TTL, 300 * 1000)
    M.retry_opts = {
        retry_budget = FgCfg.get(cat, CFG_RETRY_BUDGET, 3),
        retry_code_list = FgCfg.get(cat, CFG_RETRY_CODE_LIST, {})
    }
    FgCfg.set_update_callback(cat, handle_config_update)
end

-- just for ut
M.handle_config_update = handle_config_update

-- 注册火焰图的相关函数
--  flamegraph_fn function类型 声明:(task_id, duration, file_name, callback)各个参数解释如下
--      task_id :string 任务ID
--      duration :number 抓取火焰图的持续时间 单位是秒 有效值范围是 0 ~ 300
--      file_name :string 文件名
--      callback :function 回调函数，详见下面的回调函数的声明
--  remove_file_fn function类型 声明:(file_full_path)各个参数解释如下
--      file_full_path :string 完整文件路径
function M.register_flamegraph_fns(flamegraph_fn, remove_file_fn)
    local param_type = type(flamegraph_fn)
    if param_type ~= "function" then
        E.LOG.error(
            LOGGER,
            "register_flamegraph_fns failed,flamegraph_fn expects a param of function, but got a param of " ..
                param_type
        )
        return
    end
    param_type = type(remove_file_fn)
    if param_type ~= "function" then
        E.LOG.error(
            LOGGER,
            "register_flamegraph_fns failed,remove_file_fn expects a param of function, but got a param of " ..
                param_type
        )
        return
    end
    M.flamegraph_fn = flamegraph_fn
    M.remove_file_fn = remove_file_fn
end

-- 火焰图的默认文件名
local default_file_name = "apus_flamegraph%d.txt"

local file_name_counter = 1

local function gen_file_name(file_name)
    if type(file_name) ~= "string" or file_name == "" then
        file_name = string.format(default_file_name, file_name_counter)
        file_name_counter = file_name_counter + 1
    end
    return file_name
end

-- 执行生成火焰图
-- task_id 任务ID string类型
-- duration 抓取火焰图的持续时间 number类型 单位是秒 有效值范围是 0 ~ 3600
-- file_name 文件名 string 类型
-- callback 回调函数 function callback(is_succ, file_path, extra_labels)各个参数解释如下
--     is_succ 生成火焰图是否成功 bool类型
--     file_path 火焰图文件绝对路径
--     extra_labels 额外的标签信息 游戏可以给这个火焰图打一些自定义的标签信息
function M.generate_flamegraph(task_id, duration, file_name, callback)
    if M.flamegraph_fn == nil then
        E.LOG.error(LOGGER, "generate flamegraph failed,flamegraph_fn is nil, need to register flamegraph_fns first ")
        return false
    end
    if M.remove_file_fn == nil then
        E.LOG.error(LOGGER, "generate flamegraph failed,remove_file_fn is nil, need to register flamegraph_fns first ")
        return false
    end
    if type(callback) ~= "function" then
        E.LOG.error(LOGGER, "generate flamegraph failed,callback is not a funtion ,unexpected! ")
        return false
    end
    if type(duration) ~= "number" then
        E.LOG.error(LOGGER, "generate flamegraph failed,duration is not a number ,unexpected! ")
        return false
    end
    if type(task_id) ~= "string" or task_id == "" then
        E.LOG.error(LOGGER, "task_id is invalid!")
        return false
    end
    if duration < 0 or duration > get_max_duration() then
        E.LOG.error(LOGGER, "generate flamegraph failed,duration:" .. duration .. " is unacceptable!")
        return false
    end
    M.flamegraph_fn(task_id, duration, gen_file_name(file_name), callback)
    return true
end

return M
