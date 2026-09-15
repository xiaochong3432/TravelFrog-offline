local E = require "ejoysdk_lua.ejoysdk"
local ET = require "ejoysdk_lua.ejoysdk_topic"
--local EG = require "ejoysdk_lua.ejoysdk_gangplank"
local UNI = require "ejoysdk_lua.vendors.unisdk"
local Vendor = require "ejoysdk_lua.vendors.vendor"
local EM = require "ejoysdk_lua.ejoysdk_module"
--local EI = require 'ejoysdk_lua.ejoysdk_init'
local EU = require 'ejoysdk_lua.ejoysdk_utils'

--经分SDK
local CHANNEL = "CRASH_SDK"
local M = Vendor:Inherit(CHANNEL)
--初始化crashsdk
local CAST_INIT_CRASH_SDK = "CAST_INIT_CRASH_SDK"
--crashsdk 更新数据
local CAST_CRASH_SDK_UPDATE_DATA = "CAST_CRASH_SDK_UPDATE_DATA"
--上传自定义日志
local CAST_CREATE_CUSTOM_LOG = "CAST_CREATE_CUSTOM_LOG"
--增加啄木鸟的自定义头信息
local CAST_ADD_HEADER_INFO = "CAST_ADD_HEADER_INFO"

--增加啄木鸟崩溃日志的自定义信息，方便崩溃时排查问题
local CAST_ADD_CACHED_INFO = "CAST_ADD_CACHED_INFO"

local TAG = EM.MODULE.VENDORS.CRASH_SDK

--自定义崩溃日志上传
--@param err_msg 错误信息
--@param stack_trace 异常堆栈
--@param stack_hash  异常的Hash，非必传，默认取stacktrace前3行计算
--@param extra   附加信息，可选
function M.create_custom_log(log_level, err_msg, stack_trace, stack_hash, extra)
    if _ejoysdk.os() == "windows" then
        -- 这个还是要保留
        _ejoysdk.error_report('lua', log_level, err_msg, stack_trace, stack_hash, extra)
        return
    end

    local log_params = {
        logType = 'lua',
        logLevel = log_level,
        errMsg = err_msg,
        stackTrace = stack_trace,
        stackHash = stack_hash,
        extra = extra
    }
    UNI.cast(CHANNEL, CAST_CREATE_CUSTOM_LOG, log_params)
end

--自定义崩溃日志上传
--在create_custom_log的基础之上，对err_msg、stack_trace、extra进行utf-8检查，非法字符替换成?
function M.create_custom_log_with_checkutf8(log_level, err_msg, stack_trace, stack_hash, extra)
    stack_trace = EU.verify_utf_char(stack_trace)
    err_msg = EU.verify_utf_char(err_msg)
    extra = EU.verify_utf_char(extra)
    M.create_custom_log(log_level, err_msg, stack_trace, stack_hash, extra)
end


--增加自定义的啄木鸟头信息
--对应的 android 文档：https://yuque.antfin-inc.com/wpk/help/api#3dd4baff
function M.add_header_info(key, value)
    assert(type(key) == "string", "key must be string")
    assert(type(value) == "string", "value must be string")
    local header = {
        key = key,
        value = value
    }
    UNI.cast(CHANNEL, CAST_ADD_HEADER_INFO, header)
end

function M.add_cached_info(key, value)
    assert(type(key) == "string", "key must be string")
    assert(type(value) == "string", "value must be string")

    local param = {
        key = key,
        value = value
    }
    UNI.cast(CHANNEL, CAST_ADD_CACHED_INFO, param)
end

--初始化crashsdk
local function init_crash_sdk()
    local ch = E.get_channel()
    local game_id = E.get_game_id()
    local init_param = {
        channel_id = ch,
        game_id = game_id
    }
    UNI.cast(CHANNEL, CAST_INIT_CRASH_SDK, init_param)
end

-- 更新经分参数
local function update_data(params)
    UNI.cast(CHANNEL, CAST_CRASH_SDK_UPDATE_DATA, params)
end

local login_handler = function(user_info)
    --登录成功
    -- update stat account param
    local params = {
        uid = user_info.uid
    }
    update_data(params)
end

local function gangplank_logout_handler()
    --登出成功，更新数据
    -- update stat account param
    local params = {
        uid = ''
    }
    update_data(params)
end

local function gangplank_exit_handler()
    M.exit()
end

function M.exit()
    -- update stat account param
    local params = {
        uid = ''
    }
    update_data(params)

    --退出崩溃SDK
    E.LOG.debug(TAG, "接收到gangplank exit事件，退出崩溃SDK")
    UNI.exit(CHANNEL)
end

function M.init(opt, cb)
    E.LOG.debug(TAG, 'crashsdk start init!')

    -- 初始化经分sdk
    init_crash_sdk()

    -- 账号级的状态，用ET.gangplank.LOGIN、ET.gangplank.LOGOUT、ET.gangplank.EXIT就行了。
    ET.subscribe(ET.gangplank.LOGIN, login_handler)
    ET.subscribe(ET.gangplank.LOGOUT, gangplank_logout_handler)
    ET.subscribe(ET.gangplank.EXIT, gangplank_exit_handler)

    -- callback init success
    cb(true)
end

return M