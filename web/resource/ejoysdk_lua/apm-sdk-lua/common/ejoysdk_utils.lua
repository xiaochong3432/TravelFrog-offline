-------------------------------------------------------------------------------
-- Created Date: 2022.06.28
-- Author: 三傻
-- Desc:   ejoysdk 相关工具类
-- Copyright (c) 2022 灵犀互娱
-------------------------------------------------------------------------------
local E = require "ejoysdk_lua.ejoysdk"
local JSONUtils = require "ejoysdk_lua.apm-sdk-lua.common.json_utils"
local FileUtils = require "ejoysdk_lua.apm-sdk-lua.common.file_utils"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"
local ErrUtils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"
local VER_CHECK = require "ejoysdk_lua.ejoysdk_version_check"

local M = {}
M.__index = M

M.ERROR = {
    CODE_NOT_SUPPORT = 7014100,
    CODE_ERROR_PARAMS = 7014101
}

local LOGGER = "apm_ejoysdkutils"

-- 是否已经升级了文件上传所需的native代码
function M.has_upgrade_log_file_native()
    -- ejoysdk 从日志结构化 版本 开始用到cjson
    -- 以_ejoysdk_lua_cjson 这个变量判断客户端是否升级了结构化日志依赖的native代码
    -- 只有升级了native代码 才走文件上传的渠道
    return _ejoysdk_lua_cjson ~= nil -- luacheck: ignore
end

-- 告诉后端这个是未经压缩的文件
-- window端不支持bool, 改成string,兼容多端
local default_http_header = {rawFile = "true"}

-- 默认的可重试的错误码列表
local default_retry_code_list = {
    Global.HTTPStatusCodeEnum.TOO_MANY_REQUEST,
    Global.HTTPStatusCodeEnum.INTERNAL_ERR,
    Global.HTTPStatusCodeEnum.BAD_GATEWAY,
    Global.HTTPStatusCodeEnum.SERVICE_UNAVAILABLE,
    Global.HTTPStatusCodeEnum.GATEWAY_TIMEOUT
}

-- 最大上传失败的重试次数 10
local MAX_RETRY_BUDGET = 10

local function hit_retry_code_list(code, opts)
    local retry_code_list = default_retry_code_list
    if type(opts.retry_code_list) == "table" and next(opts.retry_code_list) ~= nil then
        retry_code_list = opts.retry_code_list
    end
    for _, retry_code in ipairs(retry_code_list) do
        if type(retry_code) == "number" and code == retry_code then
            return true
        end
    end
    return false
end

-- 是否需要重试上传文件
-- @param code: number http response code
-- @param opts: table 可选项
-- return (ok, interval)
--    ok bool 代表是否重试
--    interval number 重试的间隔时间
local function should_retry(code, opts)
    if not opts then
        return false
    end
    if type(opts.retry_budget) ~= "number" or type(opts.retried_count) ~= "number" then
        return false
    end
    -- retry_budget 不能超过MAX_RETRY_BUDGET
    if opts.retry_budget > MAX_RETRY_BUDGET then
        opts.retry_budget = MAX_RETRY_BUDGET
    end
    if opts.retry_budget < 1 then
        return false
    end
    if opts.retried_count > MAX_RETRY_BUDGET then
        return false
    end
    if not hit_retry_code_list(code, opts) then
        return false
    end
    -- 重试间隔时间采用指数退避方式 减轻服务器压力
    return true, 2 ^ opts.retried_count
end

-- 文件上传封装
--[[
    1）目前只有Android, iOS支持上传结构化日志文件
    2）支持结构化版本ejoysdk 2.6.0
    url : string, 请求地址
    params : table, 请求头
        http_header, 请求header
        form_header, 写入到add_part
    file_full_path : string, 文件完整路径名
    opts: table 可选项
        retry_budget: number 可重试次数，最大值可配,上限为MAX_RETRY_BUDGET(hardcode)
        retried_count: number 当前已重试的次数 默认为0 [重试间隔时间=2^retried_count]
        retry_code_list: table 可重试的错误码列表 默认是default_retry_code_list
    cb: 回调函数
 ]]
local function upload_file_to_apus(url, params, file_full_path, opts, cb)
    opts.retried_count = opts.retried_count or 0
    -- 旧版本不支持文件上传
    if not M.has_upgrade_log_file_native() then
        cb(false, M.ERROR.CODE_NOT_SUPPORT, "sdk(native) version not support")
        return
    end
    if type(cb) ~= "function" then
        return
    end
    -- TODO 后续有LUA API计算文件大小的时候，需要加个文件大小的限制

    local file_name = FileUtils.get_file_name(file_full_path)

    if not file_name or string.len(file_name) == 0 then
        cb(false, M.ERROR.CODE_ERROR_PARAMS, "file_name should not be nil")
        return
    end

    if type(params.form_header) ~= "table" then
        cb(false, M.ERROR.CODE_ERROR_PARAMS, "miss form_header or form_header is invalid,won't upload file.")
        return
    end

    local formdata = E.HTTP.NativeBuildFormData.New()
    formdata:add_file("file", file_full_path, "application/octet-stream", file_name)
    formdata:add_part("resource", JSONUtils.encode(params.form_header))

    local http_post_cb = function(resp)
        E.LOG.debug(LOGGER, "upload_file_to_apus resp:")
        E.LOG.debug(LOGGER, resp)
        if resp and resp.status == 200 then
            cb(true, {file_path = file_full_path, file_name = file_name})
            return
        end
        -- 处理上传失败的逻辑
        local code = resp and resp.status or -1
        local msg = resp and resp.body or ""

        local ok, interval = should_retry(code, opts)
        if not ok then
            E.LOG.debug(LOGGER, "upload_file_to_apus fail,stop retry.")
            cb(false, code, tostring(msg))
            return
        end
        local retry_log_msg =
            string.format(
            "upload_file_to_apus fail,try to retry,remaining retry_budget:%d,retried_count:%d,interval:%d,file:%s",
            opts.retry_budget,
            opts.retried_count,
            interval,
            file_full_path
        )
        E.LOG.debug(LOGGER, retry_log_msg)
        local retry_upload_file_to_apus = function()
            opts.retry_budget = opts.retry_budget - 1
            opts.retried_count = opts.retried_count + 1
            M.upload_file_to_apus(url, params, file_full_path, opts, cb)
        end
        E.Timer.once(interval, retry_upload_file_to_apus)
    end

    E.HTTP.post(
        url,
        {safe_formdata = formdata:get_part(), headers = params.http_header or default_http_header},
        formdata:content_type(),
        formdata:empty_body(),
        http_post_cb
    )
end

local function check_upload_file_for_window(params, file_full_path, cb)
    if type(cb) ~= "function" then
        return "", false
    end
    -- TODO 后续有LUA API计算文件大小的时候，需要加个文件大小的限制

    local file_name = FileUtils.get_file_name(file_full_path)

    if not file_name or string.len(file_name) == 0 then
        cb(false, M.ERROR.CODE_ERROR_PARAMS, "file_name should not be nil")
        return "", false
    end

    if type(params.form_header) ~= "table" then
        cb(false, M.ERROR.CODE_ERROR_PARAMS, "miss form_header or form_header is invalid,won't upload file.")
        return "", false
    end

    local ejoysdk_ver = E.get_sdk_version_name("EJOYSDK") or ""
    if ejoysdk_ver ~= "" and VER_CHECK.compare_versions(ejoysdk_ver, "2.2.4") < 0 then
        cb(false, M.ERROR.CODE_NOT_SUPPORT, "expect ejoysdk_ver above v2.2.4 but got" .. tostring(ejoysdk_ver))
        return "", false
    end
    return file_name, true
end

-- 文件上传封装
--[[
    1）支持windows上传结构化日志文件 使用lua接口
    2）支持结构化版本ejoysdk 2.6.0
    url : string, 请求地址
    params : table, 请求头
        http_header, 请求header
        form_header, 写入到add_part
    file_full_path : string, 文件完整路径名
    opts: table 可选项
        retry_budget: number 可重试次数，最大值可配,上限为MAX_RETRY_BUDGET(hardcode)
        retried_count: number 当前已重试的次数 默认为0 [重试间隔时间=2^retried_count]
        retry_code_list: table 可重试的错误码列表 默认是default_retry_code_list
    cb: 回调函数
 ]]
local function upload_file_to_apus_for_windows(url, params, file_full_path, opts, cb)
    opts.retried_count = opts.retried_count or 0
    local file_name, valid = check_upload_file_for_window(params, file_full_path, cb)
    if not valid then
        return
    end

    local formdata = E.HTTP.FormData.New()
    formdata:add_simple_part("resource", JSONUtils.encode(params.form_header))

    local data = E.File.readfile(file_full_path)
    if data == nil or data == 0 or #data == 0 then
        cb(false, M.ERROR.CODE_ERROR_PARAMS, "no file data to send,won't upload file.")
        return
    end
    formdata:add_part("file", data, false, false, file_name)

    local http_post_cb = function(resp)
        E.LOG.debug(LOGGER, "upload_file_to_apus_for_windows resp:")
        E.LOG.debug(LOGGER, resp)
        if resp and resp.status == 200 then
            cb(true, {file_path = file_full_path, file_name = file_name})
            return
        end
        -- 处理上传失败的逻辑
        local code = resp and resp.status or -1
        local msg = resp and resp.body or ""

        local ok, interval = should_retry(code, opts)
        if not ok then
            E.LOG.debug(LOGGER, "upload_file_to_apus_for_windows fail,stop retry.")
            cb(false, code, tostring(msg))
            return
        end
        local retry_log_msg =
            string.format(
            "upload_file_to_apus_for_w fail,try to retry,remain retry_budget:%d,retried_count:%d,interval:%d,file:%s",
            opts.retry_budget,
            opts.retried_count,
            interval,
            file_full_path
        )
        E.LOG.debug(LOGGER, retry_log_msg)
        local retry_upload_file_to_apus_for_windows = function()
            opts.retry_budget = opts.retry_budget - 1
            opts.retried_count = opts.retried_count + 1
            M.upload_file_to_apus(url, params, file_full_path, opts, cb)
        end
        E.Timer.once(interval, retry_upload_file_to_apus_for_windows)
    end

    E.HTTP.post(
        url,
        {acceptable = E.HTTP.CT_JSON, headers = params.http_header or default_http_header},
        formdata:content_type(),
        formdata:build(),
        http_post_cb
    )
end

function M.is_windows_os()
    return E.Sysinfo.os() == "windows"
end

local is_windows_os = M.is_windows_os()

-- wrap xpcall
M.upload_file_to_apus = function(url, params, file_full_path, opts, cb)
    local upload_file_to_apus_fn = function()
        if is_windows_os then
            -- windows系统使用lua接口上传文件
            return upload_file_to_apus_for_windows(url, params, file_full_path, opts, cb)
        else
            -- android ios使用native接口上传文件
            return upload_file_to_apus(url, params, file_full_path, opts, cb)
        end
    end
    xpcall(upload_file_to_apus_fn, ErrUtils.handle_err)
end

return M
