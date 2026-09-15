local Logger = require "ejoysdk_lua.apm-sdk-lua.log.logger"
local Vconfig = require "ejoysdk_lua.apm-sdk-lua.log.vconfig"
local Cfg = require "ejoysdk_lua.apm-sdk-lua.config.configurator"
local ErrUtils = require "ejoysdk_lua.apm-sdk-lua.common.err_utils"
local Global = require "ejoysdk_lua.apm-sdk-lua.global"

-- export default logger for easy use
local logger = Logger.new()

local mt_v = {}

-- luacheck: ignore
function mt_v:__call(verbose)
    return verbose <= logger.verbose
end

-- luacheck: ignore
function mt_v:__index(verbose)
    error(verbose)
end

local V = setmetatable({}, mt_v)

local pack_fn = table.pack or function(...)
        local ret = {...}
        -- lua5.1 没有.n 属性， 需要加上
        ret.n = select("#", ...)
        return ret
    end
local unpack_fn = table.unpack or unpack

local function index_log(t, k)
    local v = logger[k]
    if type(v) == "function" then
        local f = v
        v = function(...)
            local args = pack_fn(...)
            local action = function()
                -- table.unpack | unpack 这俩函数都会丢掉末尾nil的元素，需要加上开始、结尾位置
                return f(logger, unpack_fn(args, 1, args.n))
            end
            local ok, result = xpcall(action, ErrUtils.handle_err)
            if ok then
                return result
            end
            return
        end
        t[k] = v
    end
    return v
end

local Log = setmetatable({V = V}, {__index = index_log})

local empty_function = function()
end
local vlt, eft = {}, {}
for fname in pairs(Vconfig.available_fnames) do
    vlt[fname] = Log[fname]
    eft[fname] = empty_function
end

local function reset_verbose()
    for i = 1, Vconfig.max_level do
        if i <= logger.verbose then
            V[i] = vlt
        else
            V[i] = eft
        end
    end
    -- 以下这行代码有可能会重载游戏的log函数，最好不要有这种全局的函数
    -- log = Log.InfoS
end
reset_verbose()

function Log.config(...)
    local res = logger:config(...)
    reset_verbose()
    return res
end

function Log.set_bucket(bucket)
    return logger.set_bucket(bucket)
end

function Log.get_bucket()
    return logger.get_bucket()
end

function Log.set_module(module_name)
    return logger:set_module(module_name)
end

function Log.set_log_level(log_level)
    return logger:set_log_level(log_level)
end

local function handle_config_update(key, value)
    if key == "level" then
        if
            value == Logger.DEBUG or value == Logger.INFO or value == Logger.WARNING or value == Logger.ERROR or
                value == Logger.CRITICAL
         then
            logger:set_log_level(value)
        end
    end
    if key == "disable_debug_stack" then
        if type(value) == "boolean" then
            Global.set_disable_debug_stack(value)
        end
    end
end

function Log.init()
    Cfg.set_update_callback(Cfg.CATEGORY_LOG, handle_config_update)
end

return Log
