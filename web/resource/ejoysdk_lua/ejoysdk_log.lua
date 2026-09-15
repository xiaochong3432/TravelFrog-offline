-------------------------------------------------------------------------------
-- 日志模块
-- 第二部分LOG API仅供ejoysdk.lua require，统一日志入口。
-- Created Date: 2021.11.23
-- Author: 四境
--
-- Copyright (c) 2021 灵犀互娱
-------------------------------------------------------------------------------
local E_UTILS = require 'ejoysdk_lua.ejoysdk_utils'
local JSON_UTILS = require 'ejoysdk_lua.ejoysdk_json'
local EM = require "ejoysdk_lua.ejoysdk_module"
local CJSON = require "ejoysdk_lua.ejoysdk_cjson"

local TAG = EM.MODULE.EJOYSDK_BASE_MODULE .. 'log'

-- ======================== 1.Config ========================
local M = {}

local _compat_log_args = false
if _ejoysdk.os() == "android" then
    -- NOTICE: log2 参数向前兼容，log_compat才能支持扩展参数，以及兼容非utf8的crash防护
    if _ejoysdk.log_compat then
        _ejoysdk.log2 = _ejoysdk.log_compat
        _compat_log_args = true
    end
else 
    _compat_log_args = true
end

local IVK_OPEN_LOG = 'OPEN_LOG'
local IVK_OPEN_LOG_WITH_CONFIG = 'OPEN_LOG_WITH_CONFIG'
-- local IVK_SET_LOG_LEVEL = 'SET_LOG_LEVEL'

local CONST_LEVEL = {
    ['none'] = 0,
    ['error'] = 1,
    ['warn'] = 2,
    ['info'] = 3,
    ['debug'] = 4
}

-- 直接对需要pass的level
local CONST_PASS_LEVEL = 99

local CONST_LEVEL_STR = {
    [CONST_LEVEL.none] = 'none',
    [CONST_LEVEL.error] = 'error',
    [CONST_LEVEL.warn] = 'warn',
    [CONST_LEVEL.info] = 'info',
    [CONST_LEVEL.debug] = 'debug',
    [CONST_PASS_LEVEL] = 'p'
}

local CONST_APUS_LEVEL_STR = {
    [CONST_LEVEL.none] = 'NON',
    [CONST_LEVEL.error] = 'ERR',
    [CONST_LEVEL.warn] = 'WAR',
    [CONST_LEVEL.info] = 'INF',
    [CONST_LEVEL.debug] = 'DBG'
}

local CONST_STYLE = {
    DEFAULT = 'default',
    JSON = 'json'
}

M.CONFIG_PRIORTY = {
    HIGH = 1,
    DEFAULT = 2,
    LOW = 3
}

local block_tag_enable = false
local block_tags = {}
local white_modules = {}
local white_modules_enable = false

-- ======================== 2.LOG ========================
M.LOG_LEVEL = CONST_LEVEL
M.LOG_STYLE = CONST_STYLE
M.LOG_MAX_LENGTH = 16 * 1024 -- 结构化上报的单条日志限制16k, 限制最终是sls单字段的，超过会截断

M.CONSOLE_LOG_MAX_LENGTH = 16 * 1024 -- 控制台打印日志长度限制，默认16k
M.ENABLE_CONSOLE_LOG_LIMIT = true -- 长度限制开关

local s_log_level
local is_log_open = false

local elog_config
local is_log_open_from_cl = false -- 配置中心控制

-- debug file 
local ej_debugable = false
function M.setup_ej_debugable(debugable)
    ej_debugable = debugable or false
end

-- 设置是否是native sdk，用于区分文档链接
local is_native = false
function M.set_native(native)
    is_native = native
end

-- 日志开关，旧版本兼容
--[[
    开关控制优先级：
    1.open_log，兼容旧接口
        true: 开启打印，开启存储，level如果没设置则是debug
        false: 以配置中心下发配置为准，如没有配置则都关闭
    2.open_log_with_config
        is_save: 控制存储
        is_console: 控制打印
]] 

-- 统一开关控制入口，减少多次调用
local function _open_log_inside(_is_open, _config)
    
    -- 新版本接口调用，支持存储和打印模块控制
    local final_config = _config or {}
    final_config.priority = _config.priority or M.CONFIG_PRIORTY.DEFAULT

    if elog_config and elog_config.priority < final_config.priority then
        _ejoysdk.log(TAG .. '#open_log_with_config ignore: current log priority is higher:' .. tostring(elog_config.priority))
        return
    end

    is_log_open = _is_open

    -- 记录日志配置
    elog_config = final_config

    local is_save = final_config.is_save or false
    local is_console = final_config.is_console or false

    -- 根据配置中心下发，更新日志等级
    if _config and _config.level and type(_config.level) == "string" then
        if CONST_LEVEL[_config.level] ~= nil then
            M.set_log_level(CONST_LEVEL[_config.level])
        end
    end

    -- 根据配置中心下发，更新白名单
    if _config and _config.white_modules then
        white_modules = {}
        white_modules_enable = false
        if #_config.white_modules > 0 then
            M.set_white_modules(_config.white_modules)
            white_modules_enable = true
        end
    end

    -- ej_debugable 打开则这里确保native层日志开关开启
    local c_params = {
        is_save = is_save,
        is_console = is_console or ej_debugable
    }
    if _config.level then
        c_params.level = _config.level
    end

    local optStr = JSON_UTILS.encode(c_params)

    local E = require 'ejoysdk_lua.ejoysdk'
    if _ejoysdk.os and _ejoysdk.os() == 'android' then
        
        if _ejoysdk.log2 then
            E.invoke(IVK_OPEN_LOG, { is_open = _is_open })
        else -- 兼容旧版本调用，控制旧版开关，旧版本只有打印
            E.invoke(IVK_OPEN_LOG, { is_open = is_console })
        end

        E.async_call(IVK_OPEN_LOG_WITH_CONFIG, c_params , '', nil)
    elseif _ejoysdk.os and _ejoysdk.os() == 'ios' then
        -- iOS旧版本没有open_log接口
        E.async_call("open_log_with_config", nil, optStr)
    elseif _ejoysdk.os and _ejoysdk.os() == 'windows' then
        -- 兼容旧版本调用，控制旧版开关，windows暂无存储版本
        _ejoysdk.open_log(is_console)
    end

    if _config then
        _ejoysdk.log(TAG .. '#open_log_with_config#is_save=' .. tostring(_config.is_save) .. ', is_console=' .. tostring(_config.is_console) .. ', level=' .. tostring(_config.level) .. ', priority=' .. tostring(final_config.priority))
    end
end

function M.open_log(is_open)
    -- 2022-11-11 修改：open_log不再对is_save生效，避免独代等旧版本直接打开存储
    local last_is_save = (elog_config and elog_config.is_save) or false
    _open_log_inside(is_open, {is_console = is_open, is_save = last_is_save})
    
end

-- 日志开关，旧版本兼容
function M.is_log_open()
    return is_log_open
end

function M.log_config()
    return elog_config or {}
end

-- 配置中心下发；外部不需要关心开关的来源
function M.open_log_from_cc(_config)
    if _config then
        _config['is_from_cc'] = true

        -- 配置中心配置
        is_log_open_from_cl = (_config.is_save or _config.is_console) or false
        _open_log_inside(_config.is_console or _config.is_save or false, _config)

        -- 打印一下配置中心的配置
        -- _ejoysdk.log(TAG .. '#open_log_from_cc >> ')
        -- _ejoysdk.log(TAG .. '#is_save=' .. tostring(_config.is_save) .. ', is_console=' .. tostring(_config.is_console) .. ', is_open=' .. tostring(_config.is_open) .. ', level=' .. tostring(_config.level) .. ';')
        local white_modules_str = ''
        for i,v in pairs(_config.white_modules or {}) do
            if i == #(_config.white_modules) then
                white_modules_str = white_modules_str .. tostring(v) .. ';'
            else
                white_modules_str = white_modules_str .. tostring(v) .. ', '
            end
        end
        _ejoysdk.log(TAG .. '#white_modules=' .. tostring(white_modules_str))

        -- 上传到JF
        local ESTAT = require 'ejoysdk_lua.ejoysdk_stat'
        local params = E_UTILS.deepcopy(_config)
        params['is_priority_high'] = true
        ESTAT.stat_action_with_limit(TAG, 'open_log_from_cc', 'open_log_from_cc', 'open_log_from_cc', params)
    end
end

-- 新的配置接口
function M.open_log_with_config(_config)
    if _config then
        _open_log_inside(_config.is_console or _config.is_save or false, _config)
    end
end

-- 日志等级开关
function M.set_log_level(_level)
    s_log_level = _level
end

function M.get_log_level()
    return s_log_level or M.LOG_LEVEL.none
end

local function level_pass(level, tag)

    -- 有日志模块 等级白名单
    if white_modules_enable and tag then
        local E = require 'ejoysdk_lua.ejoysdk'
        local split_module = E.Utils.split_string(tag, '##')
        if #split_module >= 1 then
            local temp_module = split_module[1]
            if white_modules[temp_module] then
                return true
            end
        end
    end

    return M.get_log_level() >= level or s_log_level == nil or level == CONST_PASS_LEVEL
end

-- 使用日志Tag开关
function M.open_log_block(_enable)
    block_tag_enable = _enable
end

-- 增加剔除掉的tag
-- 格式 { "tag1", "tag2" }
function M.add_block_tags(f_tags)
    for _, v in pairs(f_tags) do
        if v then 
            block_tags[v] = true
        end
    end
end

-- 删除剔除掉的tag
-- 格式 { "tag1", "tag2" }
function M.del_block_tags(f_tags)
    for _, v in pairs(f_tags) do
        if v then 
            block_tags[v] = false
        end
    end
end

-- 剔除掉的tag
function M.get_block_tags()
    return E_UTILS.deepcopy(block_tags)
end

-- 获取剔除掉的tag
function M.is_block_tag()
    return block_tag_enable
end

-- 增加日志全等级白名单的tag
-- 在白名单内的tag，日志等级按最低（debug）, 这个接口可暴露便于外部使用
-- 格式 { "tag1", "tag2" }
function  M.set_white_modules(f_modules)
    for _, v in pairs(f_modules) do
        if v then 
            white_modules[v] = true
        end
    end
end

function  M.get_white_modules()
    return E_UTILS.deepcopy(white_modules)
end

local function log_time()
    if _ejoysdk.system_ms then 
        return math.floor(_ejoysdk.system_ms())
    else 
        return os.time() * 1000
    end
end

local _enable_sdk_struct_log = true
-- 结构化日志数据以p_struct为准
-- 非结构化日志入口支持构造p_struct，包含 msg, level, p_header（string）
local function get_struct_str(msg, level, p_header_str, p_struct)
    -- 结构化日志处理，结构化日志的版本才包含_ejoysdk_lua_cjson
    local p_struct_str
    if _ejoysdk_lua_cjson then -- luacheck: ignore
        if p_struct == nil and _enable_sdk_struct_log then
            p_struct = {
                m = msg or '', -- message
                lv = CONST_APUS_LEVEL_STR[level], -- level
                mo = 'app', -- module
                e = 'ejoysdk', -- event_name
                ti = log_time(),
                ext = p_header_str -- 自定义公参，如果是结构化入口以天燕的ext为准
            }
        end
        if type(p_struct) == 'table' then
            -- 统计耗时 p_struct_str = (tostring(st2 - st1) * 1000) .. 'ms, ' .. ret_str
            -- 日志截短，限制大长度
            if p_struct.m ~= nil and #p_struct.m > M.LOG_MAX_LENGTH then
                p_struct.m = string.sub(p_struct.m, 1, M.LOG_MAX_LENGTH)
            end
            p_struct_str = CJSON.safe_encode(p_struct)
        end
    end

    return p_struct_str
end

-- 日志调用
local log = {}
M.LOG = log

-- 上传sdk日志到sls的开关
function log.enable_sdk_struct_log(is_enable)
    _enable_sdk_struct_log = is_enable
end

local _log_compat_v
_log_compat_v = function(msg, level, tag, p_header, p_struct)

    local append_p_header_str = '' -- 结构化则是ext字段
    if p_header and type(p_header) == 'string' and #p_header > 0 then
        append_p_header_str = '\n' .. tostring(p_header).. '\n'
    end

    if _ejoysdk.log2 then
        if _compat_log_args then

            -- 对于不需要打印且关闭上报到sls的sdk的log，可以直接忽略掉， p_struct == nil 为sdk内部的非结构化的日志
            if _enable_sdk_struct_log == false and p_struct == nil and M.log_config()['is_console'] == false and ej_debugable == false then
                return
            end

            local struct_msg = get_struct_str(msg, level, append_p_header_str, p_struct)

            if M.ENABLE_CONSOLE_LOG_LIMIT and msg ~= nil and #msg > M.CONSOLE_LOG_MAX_LENGTH and ej_debugable == false then
                -- 日志截短，背景：https://aone.alibaba-inc.com/v2/project/770618/req/47236680
                msg = string.sub(msg, 1, M.CONSOLE_LOG_MAX_LENGTH)
            end

            _ejoysdk.log2('[l][' .. CONST_LEVEL_STR[level] .. ']' ..tostring(tag) .. append_p_header_str .. msg, CONST_LEVEL_STR[level], tag, struct_msg)
        else
            -- 旧版本的Android JNI兼容，就不需要去struct的传递和处理了
            _ejoysdk.log2('[' .. CONST_LEVEL_STR[level] .. ']' ..tostring(tag) .. append_p_header_str .. msg, CONST_LEVEL_STR[level], tag)
        end
    elseif M.log_config()['is_console'] or ej_debugable then -- 旧版本native兼容
        _ejoysdk.log('[' .. CONST_LEVEL_STR[level] .. ']' ..tostring(tag) .. append_p_header_str .. msg)
    end
end

local _log
-- p_struct 结构化参数
_log = function(level, tag, msg, p_header, style, p_struct)
    level = level or CONST_LEVEL.debug
    style = style or CONST_STYLE.DEFAULT

    if block_tag_enable and tag and not is_log_open_from_cl and not ej_debugable then 
        if block_tags[tag] then 
            return
        end
    end
    
    if tag and type(tag) ~= 'string' then
        return
    end

    tag = tag and (tag .. '#') or ''

    --  ej_debugable 这里确保lua层日志可以透传
    if ((M.is_log_open() or is_log_open_from_cl) and level_pass(level, tag)) or ej_debugable then

        if type(msg) == 'table' then
            local msg_str
            if style == CONST_STYLE.JSON then
                msg_str = E_UTILS.log_util.table_tojson(msg) or ''
            else
                msg_str = E_UTILS.log_util.table_tostring(msg) or ''
            end

            _log_compat_v(msg_str, level, tag, p_header, p_struct)
        else
            _log_compat_v(tostring(msg), level, tag, p_header, p_struct)
        end
    end
end

-- debug 日志打印
-- p_header: 日志公参
function log.debug(tag, msg, p_header, style)
    _log(CONST_LEVEL.debug, tag, msg, p_header, style)
end

-- info 日志打印
-- p_header: 日志公参
function log.info(tag, msg, p_header, style)
    _log(CONST_LEVEL.info, tag, msg, p_header, style)
end

-- warn 日志打印
-- p_header: 日志公参
function log.warn(tag, msg, p_header, style)
    _log(CONST_LEVEL.warn, tag, msg, p_header, style)
end

-- err 日志打印
function log.error(tag, msg, p_header, style)
    --string类型才处理，增加文档提示信息
    if type(msg) == 'string' then
        local ej_module_tips_url = EM.MODULE_USER_TIPS_URL[tag]
        if is_native then
            ej_module_tips_url = EM.MODULE_EXTERNAL_USER_TIPS_URL[tag]
        end
        if ej_module_tips_url then
            msg = msg .. ', you can try to find a solution on the documentation: ' .. tostring(ej_module_tips_url)
        end
    end
    _log(CONST_LEVEL.error, tag, msg, p_header, style)
end

function log.tips(tag, msg)
    local ej_module_tips_url = EM.MODULE_USER_TIPS_URL[tag]
    if is_native then
        ej_module_tips_url = EM.MODULE_EXTERNAL_USER_TIPS_URL[tag]
    end
    if ej_module_tips_url then
        msg = msg .. ', you can try to find a solution on the documentation: ' .. tostring(ej_module_tips_url)
        _log(CONST_LEVEL.error, tag, msg)
    end
end

-- 结构化日志入口
-- https://yuque.antfin-inc.com/gserver/evpg3z/arwxsl
--[[
    local log_info = {
        e = '', -- 必填event_name
        m = '', -- 必填message
        ln = 0,
        ti = ti,
        mo = 'app', -- 必填
        tags = {},
        args = {},
        lv = '', -- 必填level
        ext = ''
    }
]]
function log.debugt(p_struct)
    if p_struct and p_struct.m and p_struct.e then
        _log(CONST_LEVEL.debug, '', p_struct.m, nil, nil, p_struct)
    end
end

function log.infot(p_struct)
    if p_struct and p_struct.m and p_struct.e then
        _log(CONST_LEVEL.info, '', p_struct.m, nil, nil, p_struct)
    end
end

function log.warnt(p_struct)
    if p_struct and p_struct.m and p_struct.e then
        _log(CONST_LEVEL.warn, '', p_struct.m, nil, nil, p_struct)
    end
end

function log.errort(p_struct)
    if p_struct and p_struct.m and p_struct.e then
        _log(CONST_LEVEL.error, '', p_struct.m, nil, nil, p_struct)
    end
end

-- p_struct: table, 结构化参数
function log.ignore_level(p_struct)
    if p_struct and p_struct.m and p_struct.e then
        _log(CONST_PASS_LEVEL, '', p_struct.m, nil, nil, p_struct)
    end
end

-- 缩写
log.e = log.error
log.w = log.warn
log.i = log.info
log.d = log.debug


-- 兼容旧调用方
function M.log(params)
    M.LOG.debug(nil, params)
end

-- 设置长度，默认是16KB = 16 * 1024
function M.set_log_max_length(log_length)
    M.CONSOLE_LOG_MAX_LENGTH = log_length
end

function M.set_log_length_limit(enable)
    M.ENABLE_CONSOLE_LOG_LIMIT = enable
end

return M
